;;; gptel-ext-daemon-repl.el --- Daemon REPL for Elisp (OV5) -*- no-byte-compile: t; lexical-binding: t; -*-

;; Inspired by https://github.com/licht1stein/brepl (Clojure bracket-fixing REPL)
;; This module adapts brepl concepts to Emacs Lisp for OV5:
;; NOT the Clojure `brepl` CLI — this is the Elisp daemon REPL.
;;   1. Bracket fixing before file edits (via self-heal-semantic)
;;   2. Auto-evaluation of .el files after save
;;   3. Emacs daemon socket discovery
;;   4. Project-aware evaluation context

(require 'cl-lib)
(require 'subr-x)
(require 'server nil t)
(require 'filenotify nil t)

;;; Customization

(defcustom gptel-daemon-repl-enabled t
  "When non-nil, enable daemon-repl features (auto-eval, bracket validation)."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-daemon-repl-eval-on-save t
  "When non-nil, evaluate .el files in REPL after saving."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-daemon-repl-validate-brackets t
  "When non-nil, validate/fix brackets before writing .el files."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-daemon-repl-socket-dir nil
  "Directory containing Emacs server sockets.
If nil, auto-detect from standard locations:
- /tmp/emacs$(id -u)/ (macOS/Linux)
- ${TMPDIR}/emacs$(id -u)/ (macOS with TMPDIR)
- ~/.emacs.d/server/ (fallback)")

(defcustom gptel-daemon-repl-default-server "server"
  "Default Emacs server name to connect to.
Used with emacsclient -s SERVER_NAME.")

;;; ── Server Discovery ──

(defun gptel-daemon-repl--socket-dir ()
  "Return the Emacs server socket directory.
Checks standard locations in order of preference:
1. `server-socket-dir' (Emacs 29+)
2. /run/user/$UID/emacs/ (Linux)
3. /tmp/emacs$UID/ (macOS/Linux fallback)
4. ${TMPDIR}/emacs$UID/ (macOS with TMPDIR)
5. ~/.emacs.d/server/ (final fallback)"
  (or gptel-daemon-repl-socket-dir
      (let* ((uid (number-to-string (user-uid)))
             (sd (when (fboundp 'server-socket-dir) (server-socket-dir)))
             (dirs (delq nil (list
                              sd
                              (format "/run/user/%s/emacs" uid)
                              (format "/tmp/emacs%s" uid)
                              (when (getenv "TMPDIR")
                                (format "%semacs%s" (file-name-as-directory (getenv "TMPDIR")) uid))
                              (expand-file-name "server" user-emacs-directory)))))
        (cl-dolist (dir dirs)
          (when (and dir (file-directory-p dir))
            (cl-return dir))))))

(defun gptel-daemon-repl--socket-file-p (path)
  "Check if PATH is a Unix domain socket.
Fallback for Emacs < 29 where `file-socket-p' is unavailable."
  (if (fboundp 'file-socket-p)
      (file-socket-p path)
    ;; Fallback: check file-attributes type is nil (socket files show nil type in some Emacs versions)
    (and (file-exists-p path)
         (not (file-directory-p path))
         (not (file-regular-p path))
         (not (file-symlink-p path)))))

(defun gptel-daemon-repl--discover-servers ()
  "Discover available Emacs daemon servers.
Returns alist of (name . socket-path)."
  (let ((socket-dir (gptel-daemon-repl--socket-dir))
        (servers nil))
    (when socket-dir
      (dolist (file (directory-files socket-dir t))
        (when (and (not (string-match-p "/\\.\\.?\\'" file))
                   (gptel-daemon-repl--socket-file-p file))
          (push (cons (file-name-nondirectory file) file) servers))))
    (nreverse servers)))

(defun gptel-daemon-repl--default-server-socket ()
  "Return path to the default Emacs server socket."
  (let ((socket-dir (gptel-daemon-repl--socket-dir)))
    (when socket-dir
      (expand-file-name gptel-daemon-repl-default-server socket-dir))))

;;; ── REPL Evaluation ──

(defun gptel-daemon-repl--in-target-daemon-p ()
  "Return non-nil if we are running inside the target daemon.
When true, avoid shelling out to emacsclient to prevent reentry hang."
  (and (daemonp)
       (string= server-name gptel-daemon-repl-default-server)))

(defun gptel-daemon-repl--eval-direct (code)
  "Evaluate CODE string directly in-process.
Returns plist with :success :result :error."
  (condition-case err
      (let* ((form (read code))
             (result (eval form t)))
        (list :success t :result (prin1-to-string result) :error nil))
    (error
     (list :success nil :result nil :error (error-message-string err)))))

(defun gptel-daemon-repl--eval-via-emacsclient (code &optional server-socket)
  "Evaluate CODE via emacsclient.
Returns plist with :success :result :error.
Optional SERVER-SOCKET overrides the default.
If running inside the target daemon, evals directly to avoid reentry hang."
  (if (gptel-daemon-repl--in-target-daemon-p)
      (progn
        (message "[daemon-repl] Running in target daemon — evaluating directly")
        (gptel-daemon-repl--eval-direct code))
    (let* ((socket (or server-socket (gptel-daemon-repl--default-server-socket)))
           (args (append (when socket (list "-s" socket))
                         '("-a" "false" "--eval")
                         (list code)))
           (outbuf (generate-new-buffer " *daemon-repl-emacsclient*")))
      (message "[daemon-repl] Evaluating via emacsclient...")
      (unwind-protect
          (condition-case proc-err
              (let ((exit-code (apply #'call-process "emacsclient" nil outbuf nil args)))
                (with-current-buffer outbuf
                  (let ((output (string-trim (buffer-string))))
                    (cond
                     ((/= exit-code 0)
                      (list :success nil :result nil
                            :error (format "emacsclient exited %d: %s" exit-code output)))
                     ((string= output "")
                      (list :success nil :result nil
                            :error "Empty response — daemon may not be running"))
                     ((string-match-p "\\`Error:" output)
                      (list :success nil :result nil :error output))
                     (t
                      (list :success t :result output :error nil))))))
            (file-error
             (list :success nil :result nil
                   :error (format "emacsclient not found: %s" (error-message-string proc-err)))))
        (kill-buffer outbuf)))))

(defun gptel-daemon-repl-eval-expression (expr &optional server)
  "Evaluate Elisp expression EXPR in the running Emacs daemon.
EXPR is a string of Elisp code.
Optional SERVER is the server socket path.
Returns the result string or signals an error."
  (unless gptel-daemon-repl-enabled
    (error "daemon-repl is disabled (gptel-daemon-repl-enabled is nil)"))
  (let ((result (gptel-daemon-repl--eval-via-emacsclient expr server)))
    (if (plist-get result :success)
        (plist-get result :result)
      (error "daemon-repl evaluation failed: %s" (plist-get result :error)))))

(defun gptel-daemon-repl-eval-file (file &optional server)
  "Evaluate FILE in the running Emacs daemon.
Uses emacsclient to load the file.
Optional SERVER overrides socket path."
  (unless gptel-daemon-repl-enabled
    (error "daemon-repl is disabled"))
  (let* ((abs-file (expand-file-name file))
         (code (format "(load-file %S)" abs-file))
         (result (gptel-daemon-repl--eval-via-emacsclient code server)))
    (if (plist-get result :success)
        (progn
          (message "[daemon-repl] ✓ Evaluated %s" (file-name-nondirectory abs-file))
          (plist-get result :result))
      (error "daemon-repl file eval failed: %s" (plist-get result :error)))))

;;; ── Bracket Validation (pre-edit) ──

(defun gptel-daemon-repl-validate-brackets (file-content)
  "Validate brackets in FILE-CONTENT string.
Returns plist:
  :valid t/nil
  :fixed-content string (if auto-fixed)
  :error string (if invalid and unfixable)"
  (let ((temp-file (make-temp-file "daemon-repl-validate-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert file-content))
          ;; Try to byte-compile to check syntax
          (condition-case compile-err
              (progn
                (with-temp-buffer
                  (emacs-lisp-mode)
                  (insert file-content)
                  (check-parens))
                (list :valid t :fixed-content file-content :error nil))
            (error
             ;; Try auto-fix via self-heal-semantic if available
             (if (and gptel-daemon-repl-validate-brackets
                      (fboundp 'gptel-auto-workflow--fix-unbalanced-parens))
                 (progn
                   (gptel-auto-workflow--fix-unbalanced-parens temp-file)
                   (let ((fixed (with-temp-buffer
                                  (insert-file-contents temp-file)
                                  (buffer-string))))
                     (if (string= fixed file-content)
                         ;; Couldn't fix
                         (list :valid nil :fixed-content nil
                               :error (error-message-string compile-err))
                       ;; Fixed!
                       (list :valid t :fixed-content fixed :error nil))))
               ;; No fixer available
               (list :valid nil :fixed-content nil
                     :error (error-message-string compile-err))))))
      (delete-file temp-file))))

;;; ── File Watch + Auto-Eval ──

(defvar gptel-daemon-repl--watch-descriptors nil
  "List of file watch descriptors for auto-evaluation.")

(defun gptel-daemon-repl--on-file-change (event)
  "Handle file change EVENT for auto-evaluation.
EVENT is a file-notify event."
  (when gptel-daemon-repl-eval-on-save
    (let* ((action (cadr event))
           (file (nth 2 event)))
      (when (and (eq action 'changed)
                 (string-suffix-p ".el" file)
                 (not (string-match-p "/\\." file))     ; skip dotfiles
                 (not (string-match-p "-autoloads\\.el\\'" file))
                 (not (string-match-p "test-.*\\.el\\'" file)))
        (message "[daemon-repl] File changed: %s — evaluating..." (file-name-nondirectory file))
        (condition-case err
            (gptel-daemon-repl-eval-file file)
          (error
           (message "[daemon-repl] ✗ Eval error in %s: %s"
                    (file-name-nondirectory file)
                    (error-message-string err))))))))

(defun gptel-daemon-repl-watch-directory (dir)
  "Watch DIR for .el file changes and auto-evaluate.
Returns the watch descriptor."
  (if (fboundp 'file-notify-add-watch)
      (condition-case err
          (let ((desc (file-notify-add-watch
                       dir '(change attribute-change)
                       #'gptel-daemon-repl--on-file-change)))
            (push desc gptel-daemon-repl--watch-descriptors)
            (message "[daemon-repl] Watching %s for .el changes" dir)
            desc)
        (error
         (message "[daemon-repl] Error watching %s: %s" dir (error-message-string err))
         nil))
    (message "[daemon-repl] Warning: file-notify not available — auto-eval disabled")))

(defun gptel-daemon-repl-unwatch-all ()
  "Remove all file watches."
  (dolist (desc gptel-daemon-repl--watch-descriptors)
    (file-notify-rm-watch desc))
  (setq gptel-daemon-repl--watch-descriptors nil)
  (message "[daemon-repl] Stopped watching all directories"))

;;; ── Hook Integration ──

(defun gptel-daemon-repl--should-auto-eval-p ()
  "Return t if current buffer should be auto-evaluated.
Only evaluates .el files in the project (not tests, not generated files)."
  (and gptel-daemon-repl-enabled
       gptel-daemon-repl-eval-on-save
       (derived-mode-p 'emacs-lisp-mode)
       (buffer-file-name)
       (string-suffix-p ".el" (buffer-file-name))
       (not (string-match-p "\\`\\." (file-name-nondirectory (buffer-file-name)))) ; skip dotfiles
       (not (string-match-p "-autoloads\\.el\\'" (buffer-file-name)))
        (not (string-match-p "\\`test-" (file-name-nondirectory (buffer-file-name))))
       (not (string-match-p "/tests?/" (buffer-file-name)))
       (not (string-match-p "/var/" (buffer-file-name)))))       ; skip package files

(defun gptel-daemon-repl--after-save-eval ()
  "Evaluate current .el file via daemon-repl after saving.
Installed in `after-save-hook'."
  (when (gptel-daemon-repl--should-auto-eval-p)
    (let ((file (buffer-file-name)))
      (message "[daemon-repl] Auto-evaluating %s..." (file-name-nondirectory file))
      (condition-case err
          (gptel-daemon-repl-eval-file file)
        (error
         (message "[daemon-repl] ✗ Auto-eval failed for %s: %s"
                  (file-name-nondirectory file)
                  (error-message-string err))
         ;; Trigger self-heal if available
         (when (fboundp 'gptel-auto-workflow--self-heal-semantic)
           (message "[daemon-repl] Triggering self-heal for %s" file)
           (condition-case nil
               (funcall 'gptel-auto-workflow--self-heal-semantic)
             (error nil))))))))

(defun gptel-daemon-repl-install-save-hooks ()
  "Install before-save and after-save hooks for brepl."
  (when gptel-daemon-repl-validate-brackets
    (add-hook 'before-save-hook
              (lambda ()
                (when (and (derived-mode-p 'emacs-lisp-mode)
                           gptel-daemon-repl-enabled)
                  (let ((validation (gptel-daemon-repl-validate-brackets
                                     (buffer-string))))
                    (when (and (plist-get validation :fixed-content)
                               (not (string= (plist-get validation :fixed-content)
                                             (buffer-string))))
                      ;; Auto-fix brackets before save
                      (let ((fixed (plist-get validation :fixed-content)))
                        (erase-buffer)
                        (insert fixed)
                        (message "[daemon-repl] Auto-fixed brackets before save"))))))
              nil t))
  (when gptel-daemon-repl-eval-on-save
    (add-hook 'after-save-hook #'gptel-daemon-repl--after-save-eval nil t)))

;;; ── Status ──

(defun gptel-daemon-repl-status ()
  "Return brepl status as a plist."
  (let ((socket (gptel-daemon-repl--default-server-socket)))
    (list :enabled gptel-daemon-repl-enabled
          :eval-on-save gptel-daemon-repl-eval-on-save
          :validate-brackets gptel-daemon-repl-validate-brackets
          :socket-dir (gptel-daemon-repl--socket-dir)
          :default-server gptel-daemon-repl-default-server
          :server-socket socket
          :server-accessible (and socket (gptel-daemon-repl--socket-file-p socket))
          :watches (length gptel-daemon-repl--watch-descriptors))))

(defun gptel-daemon-repl-show-status ()
  "Display brepl status in a buffer."
  (interactive)
  (let ((status (gptel-daemon-repl-status)))
    (with-current-buffer (get-buffer-create "*brepl-status*")
      (erase-buffer)
      (insert "=== brepl Status (OV5 Elisp REPL) ===\n\n")
      (insert (format "Enabled:         %s\n" (if (plist-get status :enabled) "✓" "✗")))
      (insert (format "Eval on save:    %s\n" (if (plist-get status :eval-on-save) "✓" "✗")))
      (insert (format "Validate brackets: %s\n" (if (plist-get status :validate-brackets) "✓" "✗")))
      (insert (format "Socket dir:      %s\n" (or (plist-get status :socket-dir) "Not found")))
      (insert (format "Server socket:   %s\n" (or (plist-get status :server-socket) "Not found")))
      (insert (format "Server ready:    %s\n" (if (plist-get status :server-accessible) "✓" "✗")))
      (insert (format "Active watches:  %d\n" (plist-get status :watches)))
      (insert "\nAvailable servers:\n")
      (dolist (server (gptel-daemon-repl--discover-servers))
        (insert (format "  %s → %s\n" (car server) (cdr server))))
      (pop-to-buffer (current-buffer)))))

;;; ── Init ──

(defun gptel-daemon-repl-init ()
  "Initialize brepl: start watching lisp/modules/ for auto-eval.
Call this on daemon startup."
  (when gptel-daemon-repl-enabled
    (let ((modules-dir (expand-file-name "lisp/modules" (or (and (boundp 'gptel-auto-workflow--worktree-base-root)
                                                                  (gptel-auto-workflow--worktree-base-root))
                                                             default-directory))))
      (when (file-directory-p modules-dir)
        (gptel-daemon-repl-watch-directory modules-dir)))
    ;; Install hooks globally for all emacs-lisp-mode buffers
    (add-hook 'emacs-lisp-mode-hook #'gptel-daemon-repl-install-save-hooks)
    (message "[daemon-repl] Initialized — watching for .el changes")))

(provide 'gptel-ext-daemon-repl)
;;; gptel-ext-daemon-repl.el ends here
