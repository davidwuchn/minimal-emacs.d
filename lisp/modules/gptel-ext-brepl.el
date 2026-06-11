;;; gptel-ext-brepl.el --- Clojure brepl REPL client (OV5) -*- lexical-binding: t; -*-

;; Wraps the ~/.local/bin/brepl CLI (babashka-based nREPL client) for
;; evaluating Clojure code, loading files, and fixing unbalanced brackets
;; from within Emacs.  Follows the pattern of gptel-ext-daemon-repl.el:
;; plist returns, call-process, [brepl] log prefix.

(require 'cl-lib)
(require 'subr-x)

;;; Customization

(defcustom gptel-brepl-binary "~/.local/bin/brepl"
  "Path to the brepl CLI binary (babashka-based nREPL client)."
  :type 'file
  :group 'gptel)

(defcustom gptel-brepl-validate-brackets t
  "When non-nil, auto-fix unbalanced brackets in Clojure files before save.
Requires `clojure-mode' and the brepl CLI."
  :type 'boolean
  :group 'gptel)

;;; ── nREPL Port Discovery ──

(defun gptel-brepl--find-port-file (dir)
  "Walk up from DIR looking for a .nrepl-port file.
Returns the port number as a string, or nil if not found.
NOTE: catch wraps let (not vice-versa) — Emacs 30 lexical-binding
      compiler miscompiles throw-through-catch when let wraps catch."
  (catch 'gptel-brepl--found
    (let ((current (expand-file-name dir)))
      (while current
        (let ((port-file (expand-file-name ".nrepl-port" current)))
          (when (file-readable-p port-file)
            (with-temp-buffer
              (insert-file-contents port-file)
              (throw 'gptel-brepl--found (string-trim (buffer-string))))))
        (let ((parent (file-name-directory (directory-file-name current))))
          (if (string= parent current)
              (setq current nil)
            (setq current parent)))))))

(defun gptel-brepl-nrepl-port ()
  "Discover nREPL port from .nrepl-port file or BREPL_PORT env var.
Returns the port number as a string, or nil if not discoverable."
  (or (getenv "BREPL_PORT")
      (gptel-brepl--find-port-file default-directory)))

(defun gptel-brepl-available-p ()
  "Return non-nil if brepl binary exists and nREPL port is discoverable."
  (and (executable-find gptel-brepl-binary)
       (gptel-brepl-nrepl-port)))

;;; ── Internal: call-process wrapper ──

(defun gptel-brepl--call (args)
  "Run brepl synchronously with ARGS via `call-process'.
Returns plist (:success t/nil :result string :error string).
Log messages use prefix [brepl]."
  (let ((binary (executable-find gptel-brepl-binary)))
    (if (not binary)
        (list :success nil :result nil
              :error (format "[brepl] Binary not found: %s" gptel-brepl-binary))
      (let ((stdout-buf (generate-new-buffer " *brepl-stdout*"))
            (stderr-file (make-temp-file "brepl-stderr-" nil ".log")))
        (unwind-protect
            (condition-case err
                ;; DESTINATION = (stdout-buf stderr-file).  Per call-process
                ;; docs, when DESTINATION is a list, STDERR-FILE must be
                ;; nil, t, or a file-name STRING — NOT a buffer object.
                ;; Pass a temp-file path so we can capture errors without
                ;; binding to a buffer (which call-process rejects).
                (let ((exit-code (apply #'call-process
                                        binary nil
                                        (list stdout-buf stderr-file)
                                        nil args)))
                  (let ((stdout (with-current-buffer stdout-buf (string-trim (buffer-string))))
                        (stderr (with-temp-buffer
                                  (insert-file-contents stderr-file)
                                  (string-trim (buffer-string)))))
                    (message "[brepl] exit=%d args=%S" exit-code args)
                    (if (= exit-code 0)
                        (list :success t :result stdout
                              :error (unless (string-empty-p stderr) stderr))
                      (list :success nil :result stdout
                            :error (if (string-empty-p stderr)
                                       (format "[brepl] Exit code %d" exit-code)
                                     stderr)))))
              (error
               (list :success nil :result nil
                     :error (format "[brepl] call-process error: %s" (error-message-string err)))))
          (kill-buffer stdout-buf)
          (delete-file stderr-file))))))

;;; ── Public API ──

(defun gptel-brepl-eval (expr)
  "Evaluate Clojure expression EXPR via brepl.
EXPR is a string of Clojure code.
Returns plist (:success t/nil :result string :error string)."
  (gptel-brepl--call (list expr)))

(defun gptel-brepl-load-file (file)
  "Load Clojure file FILE into the nREPL via \"brepl -f\".
Returns plist (:success t/nil :result string :error string)."
  (gptel-brepl--call (list "-f" (expand-file-name file))))

(defun gptel-brepl-balance (file &optional dry-run)
  "Fix unbalanced brackets in FILE via \"brepl balance\".
When DRY-RUN is non-nil, preview changes to stdout instead of
modifying the file in place.
Returns plist (:success t/nil :output string :error string).
Note: uses :output key (not :result) to distinguish from eval results."
  (let* ((args (append '("balance")
                       (when dry-run '("--dry-run"))
                       (list (expand-file-name file))))
         (result (gptel-brepl--call args)))
    (list :success (plist-get result :success)
          :output (plist-get result :result)
          :error (plist-get result :error))))

(defun gptel-brepl-status ()
  "Return brepl status as a plist.
Keys: :binary, :binary-exists, :port, :available."
  (list :binary gptel-brepl-binary
        :binary-exists (and (executable-find gptel-brepl-binary) t)
        :port (gptel-brepl-nrepl-port)
        :available (gptel-brepl-available-p)))

(defun gptel-brepl-validate-brackets (file-content)
  "Validate brackets in FILE-CONTENT string of Clojure code.
Writes content to a temp file, runs `brepl balance --dry-run',
and compares output with input.
Returns plist:
  :valid t/nil
  :fixed-content string (if auto-fixed or already balanced)
  :error string (if invalid and unfixable)"
  (let ((temp-file (make-temp-file "brepl-validate-" nil ".clj")))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert file-content))
          (let ((result (gptel-brepl-balance temp-file t)))
            (if (not (plist-get result :success))
                (list :valid nil :fixed-content nil
                      :error (or (plist-get result :error) "brepl balance failed"))
              (let ((output (plist-get result :output)))
                (cond
                 ;; No output produced — brepl success but empty result is
                 ;; suspicious (e.g. CLI bug, stdin closed). Treat as failure.
                 ((null output)
                  (list :valid nil :fixed-content nil
                        :error "brepl returned empty output"))
                 ((string= output file-content)
                  (list :valid t :fixed-content file-content :error nil))
                 ;; Fixed — output differs from input
                 (t (list :valid t :fixed-content output :error nil)))))))
      (delete-file temp-file))))

(defun gptel-brepl-install-save-hooks ()
  "Install before-save hook for Clojure bracket auto-fix.
Only activates in `clojure-mode' buffers when
`gptel-brepl-validate-brackets' is non-nil."
  (when gptel-brepl-validate-brackets
    (add-hook 'before-save-hook
              (lambda ()
                (when (and (derived-mode-p 'clojure-mode)
                           (fboundp 'gptel-brepl-validate-brackets))
                  (let ((validation (gptel-brepl-validate-brackets
                                     (buffer-string))))
                    (when (and (plist-get validation :fixed-content)
                               (not (string= (plist-get validation :fixed-content)
                                             (buffer-string))))
                      (let ((fixed (plist-get validation :fixed-content)))
                        (erase-buffer)
                        (insert fixed)
                        (message "[brepl] Auto-fixed brackets before save"))))))
              nil)))

(provide 'gptel-ext-brepl)
;;; gptel-ext-brepl.el ends here
