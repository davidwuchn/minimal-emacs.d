;;; gptel-ext-brepl.el --- Bracket-fixing REPL for Elisp (brepl for OV5) -*- no-byte-compile: t; lexical-binding: t; -*-

;; Inspired by https://github.com/licht1stein/brepl
;; brepl: Bracket-fixing REPL for AI-assisted Clojure development
;; This module brings brepl concepts to Emacs Lisp in OV5:
;;   1. Bracket fixing before file edits (via self-heal-semantic)
;;   2. Auto-evaluation of .el files after save
;;   3. Emacs daemon socket discovery
;;   4. Project-aware evaluation context

(require 'cl-lib)
(require 'subr-x)

;;; Customization

(defcustom gptel-brepl-enabled t
  "When non-nil, enable brepl features (auto-eval, bracket validation)."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-brepl-eval-on-save t
  "When non-nil, evaluate .el files in REPL after saving."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-brepl-validate-brackets t
  "When non-nil, validate/fix brackets before writing .el files."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-brepl-socket-dir nil
  "Directory containing Emacs server sockets.
If nil, auto-detect from standard locations:
- /tmp/emacs$(id -u)/ (macOS/Linux)
- ${TMPDIR}/emacs$(id -u)/ (macOS with TMPDIR)
- ~/.emacs.d/server/ (fallback)")

(defcustom gptel-brepl-default-server "server"
  "Default Emacs server name to connect to.
Used with emacsclient -s SERVER_NAME.")

;;; ── Server Discovery ──

(defun gptel-brepl--socket-dir ()
  "Return the Emacs server socket directory.
Checks standard locations in order of preference."
  (or gptel-brepl-socket-dir
      (let ((uid (number-to-string (user-uid))))
        (cl-dolist (dir (list
                         (format "/tmp/emacs%s" uid)
                         (when (getenv "TMPDIR")
                           (format "%semacs%s" (file-name-as-directory (getenv "TMPDIR")) uid))
                         (expand-file-name "server" user-emacs-directory)))
          (when (and dir (file-directory-p dir))
            (cl-return dir))))))

(defun gptel-brepl--socket-file-p (path)
  "Check if PATH is a Unix domain socket.
Fallback for Emacs < 29 where `file-socket-p' is unavailable."
  (if (fboundp 'file-socket-p)
      (file-socket-p path)
    ;; Fallback: check file-attributes type is nil (socket files show nil type in some Emacs versions)
    (and (file-exists-p path)
         (not (file-directory-p path))
         (not (file-regular-p path))
         (not (file-symlink-p path)))))

(defun gptel-brepl--discover-servers ()
  "Discover available Emacs daemon servers.
Returns alist of (name . socket-path)."
  (let ((socket-dir (gptel-brepl--socket-dir))
        (servers nil))
    (when socket-dir
      (dolist (file (directory-files socket-dir t))
        (when (and (not (string-match-p "/\\.\\.?\\'" file))
                   (gptel-brepl--socket-file-p file))
          (push (cons (file-name-nondirectory file) file) servers))))
    (nreverse servers)))

(defun gptel-brepl--default-server-socket ()
  "Return path to the default Emacs server socket."
  (let ((socket-dir (gptel-brepl--socket-dir)))
    (when socket-dir
      (expand-file-name gptel-brepl-default-server socket-dir))))

;;; ── REPL Evaluation ──

(defun gptel-brepl--eval-via-emacsclient (code &optional server-socket)
  "Evaluate CODE via emacsclient.
Returns plist with :success :result :error.
Optional SERVER-SOCKET overrides the default."
  (let* ((socket (or server-socket (gptel-brepl--default-server-socket)))
         (socket-arg (when socket (format "-s %s" (shell-quote-argument socket))))
         (cmd (format "emacsclient %s -a false --eval %s 2>&1"
                      (or socket-arg "")
                      (shell-quote-argument code))))
    (message "[brepl] Evaluating via emacsclient...")
    (let ((output (string-trim (shell-command-to-string cmd))))
      (cond
       ((string-match-p "^Error:" output)
        (list :success nil :result nil :error output))
       ((string= output "")
        (list :success nil :result nil :error "Empty response — daemon may not be running"))
       (t
        (list :success t :result output :error nil))))))

(defun gptel-brepl-eval-expression (expr &optional server)
  "Evaluate Elisp expression EXPR in the running Emacs daemon.
EXPR is a string of Elisp code.
Optional SERVER is the server socket path.
Returns the result string or signals an error."
  (unless gptel-brepl-enabled
    (error "brepl is disabled (gptel-brepl-enabled is nil)"))
  (let ((result (gptel-brepl--eval-via-emacsclient expr server)))
    (if (plist-get result :success)
        (plist-get result :result)
      (error "brepl evaluation failed: %s" (plist-get result :error)))))

(defun gptel-brepl-eval-file (file &optional server)
  "Evaluate FILE in the running Emacs daemon.
Uses emacsclient to load the file.
Optional SERVER overrides socket path."
  (unless gptel-brepl-enabled
    (error "brepl is disabled"))
  (let* ((abs-file (expand-file-name file))
         (code (format "(load-file %S)" abs-file))
         (result (gptel-brepl--eval-via-emacsclient code server)))
    (if (plist-get result :success)
        (progn
          (message "[brepl] ✓ Evaluated %s" (file-name-nondirectory abs-file))
          (plist-get result :result))
      (error "brepl file eval failed: %s" (plist-get result :error)))))

;;; ── Bracket Validation (pre-edit) ──

(defun gptel-brepl-validate-brackets (file-content)
  "Validate brackets in FILE-CONTENT string.
Returns plist:
  :valid t/nil
  :fixed-content string (if auto-fixed)
  :error string (if invalid and unfixable)"
  (let ((temp-file (make-temp-file "brepl-validate-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert file-content))
          ;; Try to byte-compile to check syntax
          (condition-case compile-err
              (progn
                (emacs-lisp-mode)
                (with-temp-buffer
                  (insert file-content)
                  (check-parens))
                (list :valid t :fixed-content file-content :error nil))
            (error
             ;; Try auto-fix via self-heal-semantic if available
             (if (and gptel-brepl-validate-brackets
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

(defvar gptel-brepl--watch-descriptors nil
  "List of file watch descriptors for auto-evaluation.")

(defun gptel-brepl--on-file-change (event)
  "Handle file change EVENT for auto-evaluation.
EVENT is a file-notify event."
  (when gptel-brepl-eval-on-save
    (let* ((file (car (last event)))
           (action (car event)))
      (when (and (eq action 'changed)
                 (string-suffix-p ".el" file)
                 (not (string-match-p "/\\." file))     ; skip dotfiles
                 (not (string-match-p "-autoloads\\.el\\'" file))
                 (not (string-match-p "test-.*\\.el\\'" file)))
        (message "[brepl] File changed: %s — evaluating..." (file-name-nondirectory file))
        (condition-case err
            (gptel-brepl-eval-file file)
          (error
           (message "[brepl] ✗ Eval error in %s: %s"
                    (file-name-nondirectory file)
                    (error-message-string err))))))))

(defun gptel-brepl-watch-directory (dir)
  "Watch DIR for .el file changes and auto-evaluate.
Returns the watch descriptor."
  (if (fboundp 'file-notify-add-watch)
      (let ((desc (file-notify-add-watch
                   dir '(change attribute)
                   #'gptel-brepl--on-file-change)))
        (push desc gptel-brepl--watch-descriptors)
        (message "[brepl] Watching %s for .el changes" dir)
        desc)
    (message "[brepl] Warning: file-notify not available — auto-eval disabled")))

(defun gptel-brepl-unwatch-all ()
  "Remove all file watches."
  (dolist (desc gptel-brepl--watch-descriptors)
    (file-notify-rm-watch desc))
  (setq gptel-brepl--watch-descriptors nil)
  (message "[brepl] Stopped watching all directories"))

;;; ── Hook Integration ──

(defun gptel-brepl--should-auto-eval-p ()
  "Return t if current buffer should be auto-evaluated.
Only evaluates .el files in the project (not tests, not generated files)."
  (and gptel-brepl-enabled
       gptel-brepl-eval-on-save
       (derived-mode-p 'emacs-lisp-mode)
       (buffer-file-name)
       (string-suffix-p ".el" (buffer-file-name))
       (not (string-match-p "/\\." (buffer-file-name)))           ; skip dotfiles
       (not (string-match-p "-autoloads\\.el\\'" (buffer-file-name)))
        (not (string-match-p "\\`test-" (file-name-nondirectory (buffer-file-name))))
       (not (string-match-p "/tests?/" (buffer-file-name)))
       (not (string-match-p "/var/" (buffer-file-name)))))       ; skip package files

(defun gptel-brepl--after-save-eval ()
  "Evaluate current .el file via brepl after saving.
Installed in `after-save-hook'."
  (when (gptel-brepl--should-auto-eval-p)
    (let ((file (buffer-file-name)))
      (message "[brepl] Auto-evaluating %s..." (file-name-nondirectory file))
      (condition-case err
          (gptel-brepl-eval-file file)
        (error
         (message "[brepl] ✗ Auto-eval failed for %s: %s"
                  (file-name-nondirectory file)
                  (error-message-string err))
         ;; Trigger self-heal if available
         (when (fboundp 'gptel-auto-workflow--self-heal-semantic)
           (message "[brepl] Triggering self-heal for %s" file)
           (gptel-auto-workflow--self-heal-semantic file)))))))

(defun gptel-brepl-install-save-hooks ()
  "Install before-save and after-save hooks for brepl."
  (when gptel-brepl-validate-brackets
    (add-hook 'before-save-hook
              (lambda ()
                (when (and (derived-mode-p 'emacs-lisp-mode)
                           gptel-brepl-enabled)
                  (let ((validation (gptel-brepl-validate-brackets
                                     (buffer-string))))
                    (when (and (not (plist-get validation :valid))
                               (plist-get validation :fixed-content))
                      ;; Auto-fix brackets before save
                      (let ((fixed (plist-get validation :fixed-content)))
                        (erase-buffer)
                        (insert fixed)
                        (message "[brepl] Auto-fixed brackets before save"))))))
              nil t))
  (when gptel-brepl-eval-on-save
    (add-hook 'after-save-hook #'gptel-brepl--after-save-eval nil t)))

;;; ── Status ──

(defun gptel-brepl-status ()
  "Return brepl status as a plist."
  (let ((socket (gptel-brepl--default-server-socket)))
    (list :enabled gptel-brepl-enabled
          :eval-on-save gptel-brepl-eval-on-save
          :validate-brackets gptel-brepl-validate-brackets
          :socket-dir (gptel-brepl--socket-dir)
          :default-server gptel-brepl-default-server
          :server-socket socket
          :server-accessible (and socket (gptel-brepl--socket-file-p socket))
          :watches (length gptel-brepl--watch-descriptors))))

(defun gptel-brepl-show-status ()
  "Display brepl status in a buffer."
  (interactive)
  (let ((status (gptel-brepl-status)))
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
      (dolist (server (gptel-brepl--discover-servers))
        (insert (format "  %s → %s\n" (car server) (cdr server))))
      (pop-to-buffer (current-buffer)))))

;;; ── Init ──

(defun gptel-brepl-init ()
  "Initialize brepl: start watching lisp/modules/ for auto-eval.
Call this on daemon startup."
  (when gptel-brepl-enabled
    (let ((modules-dir (expand-file-name "lisp/modules" (or (and (boundp 'gptel-auto-workflow--worktree-base-root)
                                                                  (gptel-auto-workflow--worktree-base-root))
                                                             default-directory))))
      (when (file-directory-p modules-dir)
        (gptel-brepl-watch-directory modules-dir)))
    ;; Install hooks globally for all emacs-lisp-mode buffers
    (add-hook 'emacs-lisp-mode-hook #'gptel-brepl-install-save-hooks)
    (message "[brepl] Initialized — watching for .el changes")))

(provide 'gptel-ext-brepl)
;;; gptel-ext-brepl.el ends here
