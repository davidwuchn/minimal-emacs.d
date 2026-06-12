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
  ;; Guard against nil/non-string input — (insert nil) throws
  ;; wrong-type-argument char-or-string-p nil.
  (if (not (stringp file-content))
      (list :valid nil :fixed-content nil
            :error (format "Expected string file-content, got %S" file-content))
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
        (delete-file temp-file)))))

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

;;; ── Test Runner ──

(defun gptel-brepl-run-tests (namespace)
  "Run clojure.test tests for NAMESPACE via brepl.
Returns plist (:success t/nil :tests N :failures N :errors N :error string
:raw string)."
  (let ((binary (executable-find gptel-brepl-binary)))
    (if (not binary)
        (list :success nil :tests 0 :failures 0 :errors 0
              :error (format "[brepl] Binary not found: %s" gptel-brepl-binary)
              :raw "")
      (let* ((code (format "(require 'clojure.test) (clojure.test/run-tests '%s)" namespace))
             (result (gptel-brepl--call (list "-e" code)))
             (raw (or (plist-get result :result) "")))
        (if (plist-get result :success)
            (let ((parsed (gptel-brepl--parse-test-output raw)))
              (append (list :success t :raw raw) parsed))
          (let ((parsed (gptel-brepl--parse-test-output raw)))
            (append (list :success nil :raw raw :error
                          (or (plist-get result :error) "Tests failed"))
                    parsed)))))))

(defun gptel-brepl--parse-test-output (output)
  "Parse clojure.test output string into plist (:tests N :failures N :errors N)."
  (let ((tests 0) (failures 0) (errors 0))
    (when (string-match "Ran \\([0-9]+\\) tests" output)
      (setq tests (string-to-number (match-string 1 output))))
    (when (string-match "\\([0-9]+\\) failures" output)
      (setq failures (string-to-number (match-string 1 output))))
    (when (string-match "\\([0-9]+\\) errors" output)
      (setq errors (string-to-number (match-string 1 output))))
    (list :tests tests :failures failures :errors errors)))

;;; ── Lint ──

(defun gptel-brepl-lint-file (file)
  "Run clj-kondo on FILE and return findings.
Returns plist (:success t/nil :findings list :error string).
Each finding is (:file :line :level :message)."
  (let ((kondo (executable-find "clj-kondo")))
    (if (not kondo)
        (list :success nil :findings nil
              :error "clj-kondo not found in PATH")
      (let* ((outbuf (generate-new-buffer " *clj-kondo-out*"))
             (exit-code (condition-case nil
                            (call-process kondo nil outbuf nil
                                          "--lint" (expand-file-name file)
                                          "--config" "{:output {:format :text}}")
                          (error -1)))
             (output (with-current-buffer outbuf (string-trim (buffer-string))))
             (findings (gptel-brepl--parse-kondo-output output)))
        (kill-buffer outbuf)
        (if (zerop exit-code)
            (list :success t :findings findings :error nil)
          (list :success nil :findings findings
                :error (if (string-empty-p output)
                           (format "clj-kondo exited %d" exit-code)
                         output)))))))

(defun gptel-brepl--parse-kondo-output (output)
  "Parse clj-kondo text output into findings list.
Each finding: (:file string :line integer :level string :message string)."
  (let ((findings nil))
    (dolist (line (split-string output "\n" t))
      (when (string-match
             "\\`\\(.+?\\):\\([0-9]+\\):\\([0-9]+\\)?:?\\s-+\\([a-z]+\\):\\s-+\\(.+\\)\\'"
             line)
        (push (list :file (match-string 1 line)
                    :line (string-to-number (match-string 2 line))
                    :level (match-string 4 line)
                    :message (match-string 5 line))
              findings)))
    (nreverse findings)))

;;; ── Self-Heal Fixers ──

(defun gptel-brepl-fix-ns-ordering (file-content)
  "Fix ns form ordering in Clojure FILE-CONTENT.
Reorders sub-forms of each (ns ...) form to canonical Clojure order:
  1. (:require ...)
  2. (:import ...)
  3. (:gen-class) and other sub-forms
Returns (:valid t/nil :fixed-content string :error nil/string)."
  (if (not (stringp file-content))
      (list :valid nil :fixed-content nil :error "Expected string file-content")
    (let ((reordered file-content))
      (with-temp-buffer
        (insert file-content)
        (goto-char (point-min))
        (condition-case nil
            (progn
              (while (re-search-forward "(ns[[:space:]\n\r]+" nil t)
                (let* ((ns-start (match-beginning 0))
                       (ns-end (condition-case nil
                                   (save-excursion
                                     (goto-char ns-start)
                                     (forward-list)
                                     (point))
                                 (error nil))))
                  (when ns-end
                    (let* ((ns-text (buffer-substring ns-start ns-end))
                           (reordered-ns (gptel-brepl--reorder-ns-form ns-text)))
                      (unless (string= ns-text reordered-ns)
                        (delete-region ns-start ns-end)
                        (insert reordered-ns))))
                    (goto-char ns-end))))
          (error nil))
        (setq reordered (buffer-string)))
      (if (string= reordered file-content)
          (list :valid t :fixed-content file-content :error nil)
        (list :valid t :fixed-content reordered :error nil)))))

(defun gptel-brepl--reorder-ns-form (ns-text)
  "Reorder sub-forms of NS-TEXT (a string starting with (ns ...)).
Returns reordered ns text."
  (condition-case nil
      (let* ((prefix-match (string-match "^(ns[[:space:]\n\r]+\\([^[:space:]\n\r]+\\)" ns-text))
             (nspace (and prefix-match (match-string 1 ns-text)))
             (prefix-end (or (and prefix-match (match-end 0)) 0))
             (body-start prefix-end)
             (body-end (1- (length ns-text)))
             (body (substring ns-text body-start body-end))
             (subforms (gptel-brepl--extract-ns-subforms body))
             (reordered (gptel-brepl--reorder-ns-subforms subforms))
             (result (concat "(ns " nspace reordered ")")))
        result)
    (error ns-text)))

(defun gptel-brepl--extract-ns-subforms (body)
  "Extract balanced sub-forms from BODY (a string). Returns list of (WS . FORM) cons cells."
  (let ((subforms nil))
    (with-temp-buffer
      (insert body)
      (goto-char (point-min))
      (let ((current-pos (point)))
        (while (not (eobp))
          (let* ((ws-start current-pos)
                 (form-start (progn
                               (skip-syntax-forward " \t\n\r")
                               (point)))
                 (ws (and (< ws-start form-start)
                          (buffer-substring ws-start form-start)))
                 (form-end (gptel-brepl--find-form-end form-start)))
            (if (and form-end (> form-end form-start))
                (progn
                  (let ((form-text (buffer-substring form-start form-end)))
                    (push (cons ws form-text) subforms))
                  (setq current-pos form-end)
                  (goto-char form-end))
              (goto-char (point-max))))))
      (nreverse subforms))))

(defun gptel-brepl--find-form-end (start)
  "Find the end position of the form starting at START in current buffer.
Returns point after the form, or nil if not found."
  (if (eq (char-after start) ?\()
      (condition-case nil
          (progn
            (goto-char start)
            (forward-list)
            (point))
        (error nil))
    (progn
      (goto-char start)
      (re-search-forward "[\s\t\n\r()\";,]" nil t)
      (or (match-beginning 0) (point-max)))))

(defun gptel-brepl--reorder-ns-subforms (subforms)
  "Reorder SUBFORMS to put :require/:import first, others after.
Returns the reordered subforms concatenated with their leading whitespace."
  (let ((require-imports nil)
        (others nil))
    (dolist (sf subforms)
      (let* ((form (cdr sf))
             (raw-key (and (string-prefix-p "(" form)
                           (string-match "(\\([^ )]+\\)" form)
                           (match-string 1 form)))
             (key (and raw-key
                       (if (string-prefix-p ":" raw-key)
                           (substring raw-key 1)
                         raw-key))))
        (if (member key '("require" "import"))
            (push sf require-imports)
          (push sf others))))
    (setq require-imports (nreverse require-imports))
    (setq others (nreverse others))
    (let ((reordered (append require-imports others))
          (result "")
          (first t))
      (dolist (sf reordered)
        (let* ((ws (car sf))
               (form (cdr sf)))
          (when first
            (when ws (setq result (concat result ws)))
            (setq first nil))
          (setq result (concat result form)))
        (when first
          (setq first nil)))
      result)))

;;; ── Formatter ──

(defun gptel-brepl-format (file-content)
  "Format Clojure FILE-CONTENT using zprint.
Returns plist (:valid t/nil :fixed-content string :error nil/string)."
  (if (not (stringp file-content))
      (list :valid nil :fixed-content nil :error "Expected string file-content")
    (let ((zprint (executable-find "zprint")))
      (if (not zprint)
          (list :valid t :fixed-content file-content :error nil
                :note "zprint not found — skipping format")
        (let* ((temp-file (make-temp-file "brepl-format-" nil ".clj"))
               (outbuf (generate-new-buffer " *zprint-out*")))
          (unwind-protect
              (progn
                (with-temp-file temp-file
                  (insert file-content))
                (let ((exit-code (call-process zprint nil outbuf nil temp-file)))
                  (if (zerop exit-code)
                      (let ((formatted (with-temp-buffer
                                         (insert-file-contents temp-file)
                                         (buffer-string))))
                        (list :valid t :fixed-content formatted :error nil))
                    (let ((err (with-current-buffer outbuf (string-trim (buffer-string)))))
                      (list :valid nil :fixed-content file-content
                            :error (if (string-empty-p err)
                                       (format "zprint exited %d" exit-code)
                                     err))))))
            (delete-file temp-file)
            (kill-buffer outbuf)))))))

;;; ── Self-Heal: unused require removal ──

(defun gptel-brepl-fix-unused-require (file-content)
  "Remove unused :require clauses from Clojure FILE-CONTENT.
Uses clj-kondo analysis to detect unused requires.
Returns (:valid t/nil :fixed-content string :error nil/string)."
  (if (not (stringp file-content))
      (list :valid nil :fixed-content nil :error "Expected string file-content")
    (let ((kondo (executable-find "clj-kondo")))
      (if (not kondo)
          (list :valid t :fixed-content file-content :error nil
                :note "clj-kondo not found — skipping unused-require check")
        (let* ((temp-file (make-temp-file "brepl-unused-" nil ".clj"))
               (outbuf (generate-new-buffer " *kondo-out*"))
               (unused-reqs nil))
          (unwind-protect
              (progn
                (with-temp-file temp-file
                  (insert file-content))
                ;; Run clj-kondo to find unused requires
                (call-process kondo nil outbuf nil
                              "--lint" temp-file
                              "--config" "{:output {:format :text}}")
                (let ((output (with-current-buffer outbuf (buffer-string))))
                  (setq unused-reqs
                        (gptel-brepl--parse-kondo-unused-requires output)))
                (if unused-reqs
                    (let ((fixed (gptel-brepl--remove-requires
                                  file-content unused-reqs)))
                      (list :valid t :fixed-content fixed :error nil))
                  (list :valid t :fixed-content file-content :error nil)))
            (delete-file temp-file)
            (kill-buffer outbuf)))))))

(defun gptel-brepl--parse-kondo-unused-requires (output)
  "Parse clj-kondo text output for unused namespace requires.
Returns list of (namespace . alias-or-nil) pairs to remove."
  (let ((unused nil))
    (dolist (line (split-string output "\n" t))
      (when (string-match
             "namespace \\([^ ]+\\) is required but never used"
             line)
        (let ((ns-name (match-string 1 line)))
          (push (cons ns-name nil) unused))))
    (let ((result nil))
      (dolist (entry unused)
        (unless (assoc (car entry) result)
          (push entry result)))
      result)))

(defun gptel-brepl--remove-requires (file-content unused-reqs)
  "Remove unused :require clauses from FILE-CONTENT.
UNUSED-REQS is a list of namespace strings to remove.
Also removes empty (:require) forms."
  (with-temp-buffer
    (insert file-content)
    (goto-char (point-min))
    (dolist (ns-name (mapcar 'car unused-reqs))
      (goto-char (point-min))
      (while (re-search-forward
              (concat "\\["
                      (regexp-quote ns-name)
                      "\\b[^]]*\\]")
              nil t)
        (let ((start (match-beginning 0)))
          (goto-char start)
          (skip-chars-backward " \t\n\r")
          (delete-region (point)
                         (progn
                           (goto-char (match-end 0))
                           (skip-chars-forward " \t\n\r")
                           (point))))))
    ;; Clean up empty (:require) forms
    (goto-char (point-min))
    (while (re-search-forward "(\\(\\s-*\\):require\\s-*)" nil t)
      (replace-match ""))
    (buffer-string)))

(provide 'gptel-ext-brepl)
;;; gptel-ext-brepl.el ends here
