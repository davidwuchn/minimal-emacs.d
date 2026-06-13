;;; gptel-auto-workflow-self-heal-semantic.el --- Layer 2+3 self-heal -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; Layer 1 (byte-compile) catches syntax/void-function/arity issues.
;; This module is Layer 2 (semantic assertions) + Layer 3 (operational
;; guards). It catches bugs that compile fine but misbehave at runtime.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'gptel-auto-workflow-audit-provide-inside-defun)

(declare-function gptel-auto-workflow--with-temporary-worktree
                  "gptel-tools-agent-staging-baseline" (slug ref fn))

;; ── Dirty-tree gate helper ──

(defcustom gptel-auto-workflow--self-heal-dirty-tree-gate t
  "When non-nil, refuse to self-heal when the working tree has uncommitted changes."
  :type 'boolean
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--git-status-porcelain ()
  "Return output of `git status --porcelain', or empty string on error.
Uses a 10-second timeout via `with-timeout'.  If git is unavailable
or the command times out, returns \"\" so callers can proceed."
  (condition-case nil
      (with-timeout (10 "")
        (replace-regexp-in-string
         "[ \t\n\r]+\\'" ""
         (shell-command-to-string "git status --porcelain")))
    (error "")))

;; ── Fixer rate limiting ──

(defcustom gptel-auto-workflow--fixer-rate-limit-minutes 60
  "Minutes before re-attempting the same fixer on the same file.
Set to 0 to disable rate limiting."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--fix-attempt-history
  (make-hash-table :test 'equal)
  "Hash table mapping (FILE . FIXER-NAME) → float-time of last attempt.
Reset at the start of each self-heal cycle.")

(defun gptel-auto-workflow--fixer-rate-limit-p (file fixer-name)
  "Return t if FIXER-NAME was attempted on FILE too recently.
Returns nil (allow) if rate limiting is disabled or no history exists."
  (when (and gptel-auto-workflow--fix-attempt-history
             (> gptel-auto-workflow--fixer-rate-limit-minutes 0))
    (let* ((key (cons file fixer-name))
           (last-time (gethash key gptel-auto-workflow--fix-attempt-history))
           (cutoff (- (float-time)
                      (* 60 gptel-auto-workflow--fixer-rate-limit-minutes))))
      (and last-time (> last-time cutoff)))))

(defun gptel-auto-workflow--fixer-rate-limit-record (file fixer-name)
  "Record that FIXER-NAME was attempted on FILE at the current time."
  (when (and gptel-auto-workflow--fix-attempt-history
             (> gptel-auto-workflow--fixer-rate-limit-minutes 0))
    (puthash (cons file fixer-name) (float-time)
             gptel-auto-workflow--fix-attempt-history)))

;; ── Issue accumulator ──

(defvar gptel-auto-workflow--semantic-audit-log nil
  "List of semantic audit issues found.")

(defvar gptel-auto-workflow--daemon-hang-done nil
  "Set to t after daemon-hang check runs to skip per-file re-check.")

(defun gptel-auto-workflow--semantic-audit-reset ()
  "Clear the semantic audit log."
  (setq gptel-auto-workflow--semantic-audit-log nil
        gptel-auto-workflow--daemon-hang-done nil))

(defvar gptel-auto-workflow--semantic--top-level-cache
  (make-hash-table :test 'equal)
  "Cache of (file . first-defun-line) -> first-defun-line.
Used to determine if a line is before the first defun (i.e., top-level).")

(defun gptel-auto-workflow--semantic--top-level-line-p (file line)
  "Return t if LINE in FILE is before the first defun (top-level form).
Top-level forms (defvar/defcustom) hold persistent state, not temp resources."
  (let* ((key (cons file nil))
         (cached (gethash key gptel-auto-workflow--semantic--top-level-cache))
         (first-defun-line
          (or cached
              (with-temp-buffer
                (insert-file-contents file)
                (goto-char (point-min))
                (let ((pos (re-search-forward "^(defun\\b" nil t)))
                  (prog1 (and pos (line-number-at-pos pos))
                    (puthash key (and pos (line-number-at-pos pos))
                             gptel-auto-workflow--semantic--top-level-cache)))))))
    (or (null first-defun-line)
        (< line first-defun-line))))

(defun gptel-auto-workflow--semantic-audit-record (file line type message)
  "Record a semantic audit issue at FILE:LINE of TYPE with MESSAGE.
Top-level risk-node issues are filtered out (they are persistent caches,
not temporary resources). For other issue types, all issues are recorded."
  ;; Skip top-level risk-node issues (false positives on persistent caches)
  (unless (and (memq type '(risk-node-resource risk-node-api))
               (gptel-auto-workflow--semantic--top-level-line-p file line))
    (push (list :file file :line line :type type :message message)
          gptel-auto-workflow--semantic-audit-log)))

;; ── Check 1: (let ...) used to bind functions (should be cl-letf) ──

(defun gptel-auto-workflow--audit-let-binding-functions (file)
  "Audit FILE for `(let ((some-fn ...)))` patterns."
  (let ((issues 0))
    (progn
      (when (string-match-p "test-" (file-name-nondirectory file))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "let.*gptel-auto-workflow--.*lambda"
                  nil t)
            (setq issues (1+ issues))
            (gptel-auto-workflow--semantic-audit-record
             file (line-number-at-pos (match-beginning 0))
             'let-binding-function
             "Use cl-letf to mock functions"))))
      issues)))

;; ── Check 2: Hardcoded resource limits ──

(defun gptel-auto-workflow--audit-hardcoded-limits (file)
  "Audit FILE for hardcoded resource limits.
Skips lines that are comments, docstrings, or string literals."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((case-fold-search nil))
        (while (re-search-forward "\\b1572864\\b" nil t)
          (let* ((match-line (line-number-at-pos (match-beginning 0)))
                 (match-pos (point))
                 (line-text
                  (save-excursion
                    (beginning-of-line)
                    (buffer-substring (point) (line-end-position)))))
            ;; Skip if match is inside a string literal (e.g., docstring).
            (save-excursion
              (emacs-lisp-mode)
              (let ((state (syntax-ppss match-pos)))
                (when (nth 3 state)  ; inside a string
                  (setq line-text ""))))  ; force skip
            ;; Skip: comment lines, docstring/section comments, or lines
            ;; with descriptive text (not actual code with hardcoded limit).
            (unless (or (string-prefix-p ";" line-text)
                        (string-match-p "^\".*1572864.*\"$" line-text)
                        (string-match-p "^\\s-*\\w.*\\(threshold\\|limit\\|memory\\)"
                                        line-text)
                        (string= "" line-text))  ; skipped due to string context
              (setq issues (1+ issues))
              (gptel-auto-workflow--semantic-audit-record
               file match-line
               'hardcoded-limit
               "Hardcoded 1.5GB limit - should be configurable"))))))
    issues))

;; ── Check 3: score=0 logic ──

(defun gptel-auto-workflow--audit-score-zero-bug (file)
  "Audit FILE for the bug pattern (greater-than score 0) as grader-broken.
Flags only when the check is part of a wider `if`/`cond` form where
the alternative branch classifies as \='broken\=' or \='error\='.
Filters out legitimate uses like `(when (> score 0) (push ...))`."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((case-fold-search nil))
        (while (re-search-forward "(>\\s-+score\\s-+0)" nil t)
          (let* ((match-line (line-number-at-pos (match-beginning 0)))
                 ;; Look at 500 chars around the match for context
                 (context-start (max (point-min) (- (match-beginning 0) 500)))
                 (context-end (min (point-max) (+ (point) 500)))
                 (context
                  (buffer-substring context-start context-end))
                 (is-buggy
                  (and
                   ;; Has 'broken' or 'error' classification in context
                   (or (string-match-p "'broken\\b" context)
                       (string-match-p "BROKEN" context)
                       (string-match-p "broken" context)
                       (string-match-p "grader.*broken" context))
                   ;; Is in an if/cond form
                   (or (string-match-p "(if\\b" context)
                       (string-match-p "(cond\\b" context)))))
            (when is-buggy
              (setq issues (1+ issues))
              (gptel-auto-workflow--semantic-audit-record
               file match-line
               'score-zero-bug
               "(> score 0) as grader-broken is wrong - score=0 can be legitimate"))))))
    issues))

;; ── Check 4: Unguarded external function calls ──

(defvar gptel-auto-workflow--semantic-external-fns
  '(gptel-agent-read-file
    gptel-auto-workflow-self-audit--root)
  "List of external functions that require fboundp guards.
When code calls these without (fboundp '...) or condition-case,
the function is brittle in test environments where the package
providing these functions is not loaded.")

(defun gptel-auto-workflow--audit-unguarded-external-calls (file)
  "Audit FILE for unguarded calls to external functions.
Reports calls to gptel-agent-read-file (or other registered external
functions) that are NOT preceded by a (fboundp '...) check or wrapped
in a condition-case. Such calls are brittle in test environments.
The check is function-local: it looks for a guard within the same
defun as the call, not just the immediately preceding lines."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (dolist (fn gptel-auto-workflow--semantic-external-fns)
        (let ((pattern (format "(%s\\s-" (symbol-name fn))))
          (goto-char (point-min))
          (while (re-search-forward pattern nil t)
            (let* ((call-line (line-number-at-pos (match-beginning 0)))
                   (line-text
                    (save-excursion
                      (beginning-of-line)
                      (buffer-substring (point) (line-end-position)))))
              (unless (or (string-match-p "(defun\\s-+" line-text)
                         (string-match-p "(declare-function\\s-+" line-text))
                ;; Find the start of the enclosing defun
                (let ((defun-start-line 1)
                      (found-guard nil))
                  (save-excursion
                    (goto-char (point-min))
                    (forward-line (1- call-line))
                    ;; Search backward for the enclosing (defun
                    (when (re-search-backward "^(defun\\b" nil t)
                      (setq defun-start-line (line-number-at-pos (point)))))
                  ;; Check for guard anywhere within the defun (including current line)
                  (let ((check-line call-line)
                        (end-of-lookback defun-start-line))
                     (while (and (>= check-line end-of-lookback)
                                 (not found-guard))
                       (save-excursion
                         (goto-char (point-min))
                         (forward-line (1- check-line))
                         (beginning-of-line)
                         (when (re-search-forward
                                (format "fboundp.*'%s" (symbol-name fn))
                                (line-end-position) t)
                           (setq found-guard t))
                         (when (re-search-forward
                                "condition-case"
                                (line-end-position) t)
                           (setq found-guard t)))
                       (setq check-line (1- check-line)))
                     (unless found-guard
                       (setq issues (1+ issues))
                       (gptel-auto-workflow--semantic-audit-record
                        file call-line
                        'unguarded-external-call
                        (format "Call to %s without (fboundp '%s) or condition-case guard"
                                (symbol-name fn) (symbol-name fn))))))))))))
     issues))

;; ── Check 5: Excessive blank lines ──

(defun gptel-auto-workflow--audit-blank-lines (file)
  "Audit FILE for excessive blank lines (3+ consecutive).
Blank-line accumulation is a common artifact of auto-merge/auto-generated
code. More than 2 consecutive blank lines indicate cruft.
Returns number of blocks found."
  (let ((issues 0)
        (consecutive 0)
        (start-line 0))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      (while (not (eobp))
        (let* ((line-start (line-beginning-position))
               (line (buffer-substring-no-properties
                      line-start (line-end-position)))
               (inside-string-or-comment
                (let ((state (syntax-ppss line-start)))
                  (or (nth 3 state) (nth 4 state)))))
          (if (and (string-empty-p (string-trim line))
                   (not inside-string-or-comment))
              (progn
                (when (= consecutive 0)
                  (setq start-line (line-number-at-pos)))
                (setq consecutive (1+ consecutive)))
            (when (>= consecutive 3)
              (setq issues (1+ issues))
              (gptel-auto-workflow--semantic-audit-record
               file start-line
               'excessive-blank-lines
               (format "%d consecutive blank lines — compress to 1 separator" consecutive)))
            (setq consecutive 0))
          (forward-line 1)))
      (when (>= consecutive 3)
        (setq issues (1+ issues))
        (gptel-auto-workflow--semantic-audit-record
         file start-line
         'excessive-blank-lines
         (format "%d consecutive blank lines at end of file" consecutive))))
    issues))

;; ── Audit dispatcher ──

;; ── Check 6: Unbalanced parens/brackets ──

(defun gptel-auto-workflow--audit-unbalanced-parens (file)
  "Audit FILE for unbalanced parens/brackets.
Catches the `End of file during parsing' class of bugs where editing
introduces a missing or extra close paren. Uses Emacs's built-in
check-parens after loading the file as emacs-lisp.
Returns 1 if unbalanced, 0 if balanced. Catches ALL parse errors
(not just user-error) so that `end-of-file' and other balance errors
are also reported."
  (let ((issues 0)
        (error-line 1))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          (check-parens))
      (error
       (setq issues 1)
       (setq error-line
             (or (gptel-auto-workflow--find-paren-balance-line file)
                 1))
       (gptel-auto-workflow--semantic-audit-record
        file error-line
        'unbalanced-parens
        (format "Unbalanced parens — %s"
                (error-message-string err)))))
    issues))

(defun gptel-auto-workflow--find-paren-balance-line (file)
  "Find the line where paren balance goes negative in FILE.
Returns line number, or nil if file is balanced."
  (cl-block nil
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((balance 0)
            (in-string nil)
            (in-comment nil))
        (while (not (eobp))
          (let ((ch (char-after)))
            (cond
             ((and (not in-string) (eq ch 59))
              (setq in-comment t))
             ((and in-comment (eq ch 10))
              (setq in-comment nil))
             ((and (not in-comment) (eq ch 34))
              (setq in-string (not in-string)))
             ((and (not in-string) (not in-comment))
              (cond ((eq ch 40) (setq balance (1+ balance)))
                    ((eq ch 41)
                     (setq balance (1- balance))
                     (when (< balance 0)
                        (cl-return (line-number-at-pos)))))))
          (forward-char 1)))))))


;; ── Check 7: Missing provide statement ──

(defun gptel-auto-workflow--audit-missing-provide (file)
  "Audit FILE for missing (provide \='feature) statement.
Modules without provide cannot be required by other modules.
Returns 1 if missing, 0 if present."
  (let ((issues 0)
        (has-provide nil))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    ;; Look for (provide 'feature) form
    (when (re-search-forward "^(provide\\s-+'\\([^)]+\\))" nil t)
      (setq has-provide t))
    (unless has-provide
      (setq issues 1)
      (let ((suggested (file-name-sans-extension
                        (file-name-nondirectory file))))
        (gptel-auto-workflow--semantic-audit-record
         file 1
         'missing-provide
         (format "Missing (provide '%s) — module cannot be required"
                 suggested)))))
  issues))

;; ── Check 10: Bare (defvar FOO) without initial value ──

(defun gptel-auto-workflow--audit-void-defvars (file)
  "Audit FILE for bare (defvar SYMBOL) without an initial value.
Bare defvars do not make the variable special under lexical-binding,
causing void-variable errors at runtime.  Returns count of bare defvars."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      (while (re-search-forward "^(defvar[ \t]+\\([a-z][a-z0-9-]*\\)" nil t)
        (let ((var-name (match-string 1))
              (line-no (line-number-at-pos))
              (is-bare nil))
          ;; Skip whitespace after the var name
          (skip-syntax-forward " ")
          ;; Check if the close paren follows immediately (same line) or
          ;; on the next line with only whitespace between.
          (cond
            ((eq (char-after) ?\))
             (setq is-bare t))
            ((eq (char-after) ?\n)
             (forward-line 1)
             (skip-syntax-forward " ")
             (when (eq (char-after) ?\))
               (setq is-bare t))))
          (when is-bare
            ;; Skip bare defvars that are forward declarations for hash
            ;; tables defined in another file.  These are expected: the
            ;; real definition initializes the hash table; the bare
            ;; defvar here suppresses compiler warnings.
            (unless (gptel-auto-workflow--var-used-as-hash-table-p
                     var-name nil (current-buffer))
              (setq issues (1+ issues))
              (gptel-auto-workflow--semantic-audit-record
               file line-no
               'void-defvar
               (format "Bare (defvar %s) — add nil to prevent void-variable errors"
                       var-name))))
          ;; Move past this form to avoid re-matching the same defvar.
          ;; If bare, we advanced to the close paren during detection;
          ;; otherwise, move to the next line.
          (if is-bare
              (when (eq (char-after) ?\))
                (forward-char 1))
            (forward-line 1)))))
    issues))

;; ── Check 11: Daemon subprocess hang ──

(defun gptel-auto-workflow--audit-daemon-hang--impl ()
  "Check if pmf-value-stream daemon is hung on orphaned subprocesses."
  (condition-case nil
      (let ((uid (user-uid))
            (daemon-pid nil)
            (sock (format "/tmp/emacs%d/pmf-value-stream" (user-uid))))
        (with-temp-buffer
          (when (eq 0 (call-process "pgrep" nil t nil
                                     "-f" "pmf-value-stream"))
            (setq daemon-pid (string-trim (buffer-string)))))
        (unless daemon-pid (cl-return-from gptel-auto-workflow--audit-daemon-hang--impl 0))
        (when (eq 0 (call-process "timeout" nil nil nil "2"
                                   "emacsclient" "-s" sock "-e" "t"))
          (cl-return-from gptel-auto-workflow--audit-daemon-hang--impl 0))
        (with-temp-buffer
          (unless (eq 0 (call-process "pgrep" nil t nil
                                       "-P" daemon-pid "curl"))
            (cl-return-from gptel-auto-workflow--audit-daemon-hang--impl 0))
          (when (string-empty-p (string-trim (buffer-string)))
            (cl-return-from gptel-auto-workflow--audit-daemon-hang--impl 0)))
        (message "[self-heal] Daemon %s unresponsive with orphaned curl — subprocess hang"
                 daemon-pid)
        1)
    (error 0)))

(defun gptel-auto-workflow--audit-daemon-hang (file)
  "Audit for daemon subprocess hang. FILE accepted for dispatch, ignored."
  (when gptel-auto-workflow--daemon-hang-done (cl-return-from gptel-auto-workflow--audit-daemon-hang 0))
  (setq gptel-auto-workflow--daemon-hang-done t)
  (gptel-auto-workflow--audit-daemon-hang--impl))

;; ── Check 13: nil-initialized hash tables ──

(defun gptel-auto-workflow--var-used-as-hash-table-p (var-name _file-content buffer)
  "Check if VAR-NAME is used as the TABLE argument in hash-table calls.
Matches VAR-NAME only when it appears as the table argument (not as a
key, value, or inside a nested expression) in calls to gethash, puthash,
maphash, or clrhash.  `hash-table-p' is excluded because it is a common
guard predicate on alist-backed caches.
BUFFER must be a buffer visiting the file content in `emacs-lisp-mode'.
Uses `forward-sexp' to navigate to the exact table-argument position,
then compares the symbol found there to VAR-NAME."
  ;; (fn . table-arg-position) — number of sexps to skip past the
  ;; opening paren before reaching the table argument (count includes
  ;; the function name itself, so we skip fn-name + preceding args).
  (let ((fn-positions '(("gethash" . 2)    ; gethash key TABLE
                        ("puthash" . 3)    ; puthash key value TABLE
                        ("clrhash"  . 1)   ; clrhash TABLE
                        ("maphash"  . 2))) ; maphash function TABLE
        (var-sym (intern var-name)))
    (catch 'found
      (with-current-buffer buffer
        (save-excursion
          (emacs-lisp-mode)
          (dolist (entry fn-positions)
            (let ((fn (car entry))
                  (table-pos (cdr entry)))
              (goto-char (point-min))
              (while (re-search-forward (format "(%s\\b" fn) nil t)
                (let ((call-start (match-beginning 0))
                      (state (save-excursion
                               (syntax-ppss (match-beginning 0)))))
                  (unless (or (nth 3 state) (nth 4 state))
                    ;; Navigate to the table argument via forward-sexp
                    (condition-case nil
                        (save-excursion
                          (goto-char (1+ call-start)) ; skip opening paren
                          (dotimes (_ table-pos)
                            (forward-sexp 1))          ; skip to table arg
                          (skip-syntax-forward " ")
                          (when (eq (read (current-buffer)) var-sym)
                            (throw 'found t)))
                      (error nil))))))))
        nil))))

(defun gptel-auto-workflow--var-has-hash-table-p-guard-p (var-name file-content)
  "Return t if (hash-table-p VAR-NAME) appears in FILE-CONTENT.
Indicates the variable is conditionally a hash table (may be alist-backed
by default) and should not be auto-fixed."
  (string-match-p
   (format "(hash-table-p\\b[^)]*\\b%s\\b" (regexp-quote var-name))
   file-content))

(defun gptel-auto-workflow--var-has-lazy-init-setq-p (var-name _file-content buffer)
  "Return t if a setq of VAR-NAME to a hash-table constructor appears in BUFFER.
Walks setq forms with `read' to correctly handle multi-binding
forms like (setq a (ns-make-schemas) b (ns-make-entities) ...) that the
old regex [^)]* could not parse through nested parens.
A constructor is either the symbol `make-hash-table', or a list whose
car is a symbol whose name contains `make-'.
BUFFER must be visiting the file content in `emacs-lisp-mode'."
  (let ((var-sym (intern var-name))
        (case-fold-search nil))
    (catch 'found
      (with-current-buffer buffer
        (save-excursion
          (emacs-lisp-mode)
          (goto-char (point-min))
          (while (re-search-forward "(setq\\b" nil t)
            (let ((start (match-beginning 0))
                  (state (save-excursion
                           (syntax-ppss (match-beginning 0)))))
              (unless (or (nth 3 state) (nth 4 state))
                (condition-case nil
                    (save-excursion
                      (goto-char (1+ start))  ; skip opening paren
                      (while (progn (skip-syntax-forward " ")
                                    (and (not (eobp))
                                         (not (eq (char-after) ?\)))))
                        (let ((sym (read (current-buffer))))
                          (skip-syntax-forward " ")
                          (when (eq sym var-sym)
                            (let ((val (read (current-buffer))))
                              (when (or (eq val 'make-hash-table)
                                        (and (consp val)
                                             (symbolp (car val))
                                             (string-match-p
                                              "make-"
                                              (symbol-name (car val)))))
                                (throw 'found t)))))))
                  (error nil))))))
        nil))))

(defun gptel-auto-workflow--audit-nil-hash-tables (file)
  "Audit FILE for hash tables initialized to nil.
Detects (defvar NAME nil) where NAME is used with hash-table
functions (gethash, puthash, maphash, clrhash) in the same file.
Skips variables guarded by (hash-table-p VAR), lazy-init setq
patterns, and matches inside strings/comments.
Returns count of issues found."
  (let ((issues 0)
        (file-content nil))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (setq file-content (buffer-string))
      (goto-char (point-min))
      (while (re-search-forward
              "^(defvar[ \t]+\\([a-z][a-z0-9-]*\\)[ \t]+nil\\b" nil t)
        (let ((var-name (match-string 1))
              (line-no (line-number-at-pos))
              (match-pos (match-beginning 0)))
          ;; Skip if the defvar itself is inside a string or comment
          (unless (let ((state (save-excursion (syntax-ppss match-pos))))
                    (or (nth 3 state) (nth 4 state)))
            ;; Skip lazy-init / ensure-loaded sentinels
            (unless (gptel-auto-workflow--var-has-lazy-init-setq-p
                     var-name file-content (current-buffer))
              ;; Skip hash-table-p guarded variables (alist-backed caches)
              (unless (gptel-auto-workflow--var-has-hash-table-p-guard-p
                       var-name file-content)
                (when (gptel-auto-workflow--var-used-as-hash-table-p
                       var-name file-content (current-buffer))
                  (setq issues (1+ issues))
                  (gptel-auto-workflow--semantic-audit-record
                   file line-no
                   'nil-hash-table
                   (format
                    "Hash table %s initialized to nil — use (make-hash-table :test 'equal)"
                    var-name))))))))
      issues)))

(defvar gptel-auto-workflow--semantic-audit-checks
  '((let-binding-function . gptel-auto-workflow--audit-let-binding-functions)
    (hardcoded-limit . gptel-auto-workflow--audit-hardcoded-limits)
    (score-zero-bug . gptel-auto-workflow--audit-score-zero-bug)
    (unguarded-external-call . gptel-auto-workflow--audit-unguarded-external-calls)
    (excessive-blank-lines . gptel-auto-workflow--audit-blank-lines)
    (unbalanced-parens . gptel-auto-workflow--audit-unbalanced-parens)
    (missing-provide . gptel-auto-workflow--audit-missing-provide)
    (condition-case-unbound-err . gptel-auto-workflow--audit-condition-case-unbound-err)
    (risk-node . gptel-auto-workflow--audit-risk-nodes)
    (provide-inside-defun . gptel-auto-workflow--audit-provide-inside-defun)
    (void-defvar . gptel-auto-workflow--audit-void-defvars)
    (daemon-hang . gptel-auto-workflow--audit-daemon-hang)
    (nil-hash-table . gptel-auto-workflow--audit-nil-hash-tables))
  "Alist of audit check name (symbol) to audit function.")

;; ── Check 8: condition-case with unbound err ──

(defun gptel-auto-workflow--audit-condition-case-unbound-err (file)
  "Audit FILE for condition-case handlers that reference err without binding.
Returns count of such bugs."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (emacs-lisp-mode)
      (let ((case-fold-search nil))
        (while (re-search-forward "(error\\b" nil t)
          (let* ((match-end-pos (match-end 0))
                 (next-char (or (char-after match-end-pos) 0))
                 (has-binding t)
                 (case-end nil)
                  (inside-condition-case nil)
                  (case-binds-err nil))
             (cond
             ((= next-char ?\)) (setq has-binding nil))
             ((memq next-char '(?\s ?\t ?\n ?\r))
              (let ((p (1+ match-end-pos))
                    (end (point-max)))
                (while (and (< p end) (memq (char-after p) '(?\s ?\t ?\n ?\r)))
                  (setq p (1+ p)))
                (let ((first-real (or (char-after p) 0)))
                  (when (memq first-real '(?\) ?\( ?\"))
                    (setq has-binding nil)))))
             (t nil))
            (setq case-end (condition-case nil
                              (save-excursion
                                (goto-char (match-beginning 0))
                                (backward-up-list 1)
                                (forward-sexp 1)
                                (1- (point)))
                            (error nil)))
              (when case-end
                (save-excursion
                  ;; Go to the enclosing form to verify it's condition-case
                  (goto-char (match-beginning 0))
                  (backward-up-list 1)
                  (let ((form-start (point)))
                    (forward-char 1)
                    (forward-symbol 1)
                    (when (string= (buffer-substring (1+ form-start) (point))
                                   "condition-case")
                      (setq inside-condition-case t)
                      ;; Check if condition-case binds err
                      (skip-syntax-forward " '")
                      (let ((var-start (point)))
                        (skip-syntax-forward "w_")
                        (when (string= (buffer-substring var-start (point)) "err")
                          (setq case-binds-err t)))))))
             (when (and inside-condition-case (null has-binding) (null case-binds-err))
              (save-excursion
                (goto-char match-end-pos)
                (when (re-search-forward "[^-_[:word:]]err[^-_[:word:]]" case-end t)
                  (setq issues (1+ issues))
                  (gptel-auto-workflow--semantic-audit-record
                   file (line-number-at-pos (match-beginning 0))
                   'condition-case-unbound-err
                   "(error) handler references \='err\=' without binding it"))))))))
    issues))

;; ── Check 9: Risk nodes (TSP-inspired) ──

(defun gptel-auto-workflow--audit-risk-nodes (file)
  "Audit FILE for risk nodes — critical decision points where failures emerge.
Inspired by TSP paper (2606.03489v1): identifies fine-grained risk nodes.
Detects:
- Resource allocation without cleanup (make-hash-table/make-temp-file without
unwind-protect)
- External API calls without error handling (shell-command-to-string without
condition-case)
Returns count of risk nodes found."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (emacs-lisp-mode)
      ;; Check for resource allocation without cleanup
      ;; make-hash-table removed: hash tables are GC'd, not resource leaks.
      ;; Only temp files (make-temp-file/make-temp-name) need cleanup.
      (let ((resource-patterns '(("make-temp-file" . "delete-file")
                                 ("make-temp-name" . "delete-file"))))
         (dolist (pattern resource-patterns)
           (let ((resource-fn (car pattern)))
             (goto-char (point-min))
             (while (re-search-forward (format "(%s\\b" resource-fn) nil t)
              (let* ((match-line (line-number-at-pos (match-beginning 0)))
                     (defun-start (save-excursion
                                    (when (re-search-backward "^(\\(defun\\|cl-defun\\)\\b" nil t)
                                      (point))))
                     (defun-end (when defun-start
                                  (save-excursion
                                    (goto-char defun-start)
                                    (forward-sexp 1)
                                    (point))))
                     (has-cleanup nil)
                     (is-wrapper nil))
                (when (and defun-start defun-end)
                   ;; Check if this is a wrapper/setup function. These return or
                   ;; stash temp paths for paired teardown outside this defun.
                   (save-excursion
                     (goto-char defun-start)
                     (when (looking-at "(\\(defun\\|cl-defun\\)\\s-+\\([^ )]+\\)")
                       (let ((fn-name (match-string 2)))
                         (when (string-match-p "\\(temp-file\\|setup-temp-repo\\)" fn-name)
                           (setq is-wrapper t)))))
                  (unless is-wrapper
                    (save-excursion
                      (goto-char defun-start)
                      ;; Check for delete-file, delete-directory, or unwind-protect
                      (when (or (re-search-forward "(delete-file\\b" defun-end t)
                                (re-search-forward "(delete-directory\\b" defun-end t)
                                (re-search-forward "(unwind-protect\\b" defun-end t))
                        (setq has-cleanup t)))))
                (unless (or has-cleanup is-wrapper)
                  (setq issues (1+ issues))
                  (gptel-auto-workflow--semantic-audit-record
                   file match-line
                   'risk-node-resource
                   (format "%s without cleanup — risk node" resource-fn))))))))
      ;; Check for external API calls without error handling
      (let ((api-patterns '(("shell-command-to-string" . "condition-case")
                            ("call-process" . "condition-case")
                            ("url-retrieve-synchronously" . "condition-case"))))
        (dolist (pattern api-patterns)
          (let ((api-fn (car pattern))
                (error-fn (cdr pattern)))
            (goto-char (point-min))
            (while (re-search-forward (format "(%s\\b" api-fn) nil t)
              (let* ((match-line (line-number-at-pos (match-beginning 0)))
                     (defun-start (save-excursion
                                    (when (re-search-backward "^(\\(defun\\|cl-defun\\)\\b" nil t)
                                      (point))))
                     (defun-end (when defun-start
                                  (save-excursion
                                    (goto-char defun-start)
                                    (forward-sexp 1)
                                    (point))))
                     (has-error-handling nil))
                (when (and defun-start defun-end)
                  (save-excursion
                    (goto-char defun-start)
                    (when (re-search-forward (format "(%s\\b" error-fn) defun-end t)
                      (setq has-error-handling t))))
                (unless has-error-handling
                  (setq issues (1+ issues))
                  (gptel-auto-workflow--semantic-audit-record
                   file match-line
                   'risk-node-api
                    (format "%s without %s — risk node" api-fn error-fn)))))))))
     issues))

;; ── Risk-node helpers (TSP-inspired training pairs) ──

(defvar gptel-auto-workflow--risk-node-training-pairs-file
  (expand-file-name "mementum/risk-node-training-pairs.jsonl"
                    user-emacs-directory)
  "JSONL file storing risk-node training pairs.")

(defun gptel-auto-workflow--risk-node-types-in-file (file)
  "Return list of risk node type symbols found in FILE.
Types: risk-node-resource, risk-node-api.
Returns nil if file doesn't exist or no risk nodes found."
  (when (and file (file-exists-p file))
    (let ((types nil))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (emacs-lisp-mode)
        ;; Check for resource patterns
        (dolist (pattern '(("make-temp-file" . "delete-file")
                           ("make-temp-name" . "delete-file")))
          (let ((resource-fn (car pattern)))
            (goto-char (point-min))
            (while (re-search-forward (format "(%s\\b" resource-fn) nil t)
              (let* ((defun-start (save-excursion
                                    (when (re-search-backward "^(\\(defun\\|cl-defun\\)\\b" nil t)
                                      (point))))
                     (defun-end (when defun-start
                                  (save-excursion
                                    (goto-char defun-start)
                                    (ignore-errors (forward-sexp 1))
                                    (point))))
                     (has-cleanup nil)
                     (is-wrapper nil))
                (when (and defun-start defun-end)
                  (save-excursion
                    (goto-char defun-start)
                    (when (looking-at "(\\(defun\\|cl-defun\\)\\s-+\\([^ )]+\\)")
                      (let ((fn-name (match-string 2)))
                        (when (string-match-p "\\(temp-file\\|setup-temp-repo\\)" fn-name)
                          (setq is-wrapper t)))))
                  (save-excursion
                    (goto-char defun-start)
                    (when (or (re-search-forward "(delete-file\\b" defun-end t)
                              (re-search-forward "(delete-directory\\b" defun-end t)
                              (re-search-forward "(unwind-protect\\b" defun-end t))
                      (setq has-cleanup t))))
                (unless (or has-cleanup is-wrapper)
                  (cl-pushnew 'risk-node-resource types))))))
        ;; Check for API patterns
        (dolist (pattern '(("shell-command-to-string" . "condition-case")
                           ("call-process" . "condition-case")
                           ("url-retrieve-synchronously" . "condition-case")))
          (let ((api-fn (car pattern))
                (error-fn (cdr pattern)))
            (goto-char (point-min))
            (while (re-search-forward (format "(%s\\b" api-fn) nil t)
              (let* ((defun-start (save-excursion
                                    (when (re-search-backward "^(\\(defun\\|cl-defun\\)\\b" nil t)
                                      (point))))
                     (defun-end (when defun-start
                                  (save-excursion
                                    (goto-char defun-start)
                                    (ignore-errors (forward-sexp 1))
                                    (point))))
                     (has-error-handling nil))
                (when (and defun-start defun-end)
                  (save-excursion
                    (goto-char defun-start)
                    (when (re-search-forward (format "(%s\\b" error-fn) defun-end t)
                      (setq has-error-handling t))))
                (unless has-error-handling
                  (cl-pushnew 'risk-node-api types)))))))
      types)))

(defun gptel-auto-workflow--risk-node-report-from-history (results &optional modules-dir)
  "Generate a markdown report correlating risk nodes with experiment outcomes.
RESULTS is a list of plists from `gptel-auto-workflow--parse-all-results'.
MODULES-DIR defaults to `lisp/modules' under the project root.
Returns the report string."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   user-emacs-directory))
         (modules-dir (or modules-dir
                          (expand-file-name "lisp/modules" root)))
         (correlations (make-hash-table :test 'equal))
         (total-with-risk 0)
         (total-success 0)
         (total-failure 0))
    (dolist (r results)
      (let* ((target (plist-get r :target))
             (kept (plist-get r :kept))
             (source (when target
                       (expand-file-name (file-name-nondirectory target)
                                         modules-dir)))
             (risk-types (when (and source (file-exists-p source))
                           (gptel-auto-workflow--risk-node-types-in-file source))))
        (when risk-types
          (cl-incf total-with-risk)
          (if kept
              (cl-incf total-success)
            (cl-incf total-failure))
          (dolist (type risk-types)
            (let ((entry (gethash type correlations (list 0 0))))
              (if kept
                  (cl-incf (car entry))
                (cl-incf (cadr entry)))
              (puthash type entry correlations))))))
    (with-temp-buffer
      (insert "# Risk Node Correlation Report\n\n")
      (insert (format "Generated: %s\n\n" (format-time-string "%Y-%m-%d %H:%M:%S")))
      (insert (format "- Experiments with risk nodes: %d\n" total-with-risk))
      (insert (format "- Successes: %d (%.1f%%)\n"
                      total-success
                      (if (> total-with-risk 0)
                          (* 100.0 (/ total-success total-with-risk))
                        0)))
      (insert (format "- Failures: %d (%.1f%%)\n\n"
                      total-failure
                      (if (> total-with-risk 0)
                          (* 100.0 (/ total-failure total-with-risk))
                        0)))
      (when (> (hash-table-count correlations) 0)
        (insert "## By Risk Node Type\n\n")
        (insert "| Type | Success | Failure | Success Rate |\n")
        (insert "|------|---------|---------|-------------|\n")
        (maphash (lambda (type counts)
                   (let ((success (car counts))
                         (failure (cadr counts))
                         (total (+ (car counts) (cadr counts))))
                     (insert (format "| %s | %d | %d | %.1f%% |\n"
                                     type success failure
                                     (if (> total 0)
                                         (* 100.0 (/ success total))
                                       0)))))
                 correlations))
      (buffer-string))))

(defun gptel-auto-workflow--update-risk-node-training-pair-outcomes (results)
  "Update training pair outcomes from enriched RESULTS.
Each result plist should have :risk-nodes appended.
Appends to `gptel-auto-workflow--risk-node-training-pairs-file'.
Returns number of pairs recorded."
  (let ((count 0)
        (file gptel-auto-workflow--risk-node-training-pairs-file))
    (make-directory (file-name-directory file) t)
    (with-temp-buffer
      (dolist (r results)
        (let ((risk-nodes (plist-get r :risk-nodes))
              (kept (plist-get r :kept))
              (target (plist-get r :target))
              (trial-id (plist-get r :trial-id)))
          (when (and risk-nodes target)
            (dolist (type risk-nodes)
              (let ((pair `((type . ,type)
                            (target . ,target)
                            (outcome . ,(if kept 'success 'failure))
                            (trial-id . ,(or trial-id "unknown"))
                            (timestamp . ,(format-time-string "%Y-%m-%dT%H:%M:%S")))))
                (insert (json-encode pair) "\n")
                (cl-incf count))))))
      (when (> count 0)
        (write-region (point-min) (point-max) file 'append)))
    (message "[risk-node-training] Recorded %d training pairs" count)
    count))

(defun gptel-auto-workflow--format-kept-risk-node-pairs (&optional max-pairs)
  "Format kept (successful) risk-node training pairs for prompt inclusion.
MAX-PAIRS limits how many to include (default 10).
Returns a string suitable for insertion into prompts."
  (let* ((file gptel-auto-workflow--risk-node-training-pairs-file)
         (max-pairs (or max-pairs 10))
         (pairs nil))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring (line-beginning-position)
                                        (line-end-position))))
            (when (and (not (string-empty-p line))
                       (string-prefix-p "{" line))
              (condition-case nil
                  (let* ((json-object-type 'plist)
                         (pair (json-read-from-string line)))
                    (when (string= (plist-get pair :outcome) "success")
                      (push pair pairs)))
                (error nil))))
          (forward-line 1))))
    (if pairs
        (let ((selected (cl-subseq pairs 0 (min max-pairs (length pairs)))))
          (with-temp-buffer
            (insert "## Successful Risk-Node Patterns (Learned)\n\n")
            (dolist (p selected)
              (insert (format "- %s in %s → success\n"
                              (plist-get p :type)
                              (plist-get p :target))))
            (buffer-string)))
      "")))

;; ── Auto-fixers (Layer 2+3: detect AND fix) ──

(cl-defun gptel-auto-workflow--fix-validate-and-write
    (buffer file &optional original-content &key no-load-check no-subprocess-check)
  "Validate BUFFER's paren balance via `check-parens', then write to FILE.
BUFFER must contain the proposed new file content in `emacs-lisp-mode'.
If `check-parens' passes, write BUFFER to FILE.

After writing, unless NO-LOAD-CHECK is non-nil, attempt to `load-file'
the written file.  If loading fails, restore FILE to ORIGINAL-CONTENT
and return nil.

After load-file check, unless NO-SUBPROCESS-CHECK is non-nil, spawn a
batch Emacs subprocess to load the file in a sandbox.  If the subprocess
exits non-zero, restore FILE to ORIGINAL-CONTENT and return nil.

In all failure cases, log a warning and return nil."
  (with-current-buffer buffer
    (condition-case err
        (progn
          (check-parens)
          (write-region (point-min) (point-max) file)
          ;; Post-write: load-file validation (in-process)
          (unless no-load-check
            (condition-case load-err
                (progn
                  (load-file file)
                  t)
              (error
               (message "[self-heal-semantic] Load-file validation FAILED for %s: %s -- discarding fix"
                        (file-name-nondirectory file) (error-message-string load-err))
               (when original-content
                 (with-temp-file file
                   (insert original-content)))
               (cl-return-from gptel-auto-workflow--fix-validate-and-write nil))))
          ;; Post-write: subprocess sandbox validation
          (unless no-subprocess-check
            (let ((exit-code
                   (condition-case nil
                       (call-process
                        "emacs" nil nil nil
                        "--batch" "-Q"
                        "--eval"
                        (format "(condition-case err (progn (load-file %S) (kill-emacs 0)) (error (kill-emacs 1)))" file))
                     (error -1))))
              (unless (zerop exit-code)
                (message "[self-heal-semantic] Subprocess load FAILED for %s (exit=%d) -- discarding fix"
                         (file-name-nondirectory file) exit-code)
                (when original-content
                  (with-temp-file file
                    (insert original-content)))
                (cl-return-from gptel-auto-workflow--fix-validate-and-write nil))))
          t)
      (error
       (message "[self-heal-semantic] Fix validation FAILED for %s: %s -- discarding fix"
                (file-name-nondirectory file) (error-message-string err))
       (when original-content
         (with-temp-file file
           (insert original-content)))
        nil))))

(defun gptel-auto-workflow--fix-validate-after-write (file original-content)
  "Validate FILE after a fix write.
If `check-parens' fails, restore ORIGINAL-CONTENT.
Returns t if valid, nil if restored."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (condition-case nil
        (progn (check-parens) t)
      (error
       (message "[self-heal-semantic] Fix validation FAILED for %s -- restoring original"
                (file-name-nondirectory file))
       (when original-content
         (with-temp-file file
           (insert original-content)))
       nil))))

(defun gptel-auto-workflow--fix-unguarded-external-calls (file)
  "Fix unguarded calls to external functions in FILE.
Wraps calls like (fn ...) with (and (fboundp \='fn) (fn ...)).
Returns number of calls fixed.  Safe: only adds guards, never changes logic."
  (let ((fixed 0)
        (original-content nil))
    (with-temp-buffer
      (insert-file-contents file)
      (setq original-content (buffer-string))
      (goto-char (point-min))
      (dolist (fn gptel-auto-workflow--semantic-external-fns)
        (let ((pattern (format "(%s\\s-" (symbol-name fn))))
          (goto-char (point-min))
          (while (re-search-forward pattern nil t)
            (let* ((call-line (line-number-at-pos (match-beginning 0)))
                   (line-text
                    (save-excursion
                      (beginning-of-line)
                      (buffer-substring (point) (line-end-position)))))
              ;; Skip defun/declare-function lines
              (unless (or (string-match-p "(defun\\s-+" line-text)
                          (string-match-p "(declare-function\\s-+" line-text))
                ;; Find the enclosing defun
                (let ((defun-start-line 1)
                      (found-guard nil))
                  (save-excursion
                    (goto-char (point-min))
                    (forward-line (1- call-line))
                    (when (re-search-backward "^(defun\\b" nil t)
                      (setq defun-start-line (line-number-at-pos (point)))))
                  ;; Check for guard within the defun
                  (let ((check-line (max 1 (- call-line 1)))
                        (end-of-lookback defun-start-line))
                    (while (and (>= check-line end-of-lookback)
                                (not found-guard))
                      (save-excursion
                        (goto-char (point-min))
                        (forward-line (1- check-line))
                        (beginning-of-line)
                        (when (re-search-forward
                               (format "fboundp.*'%s" (symbol-name fn))
                               (line-end-position) t)
                          (setq found-guard t))
                        (when (re-search-forward
                               "condition-case"
                               (line-end-position) t)
                          (setq found-guard t)))
                      (setq check-line (1- check-line))))
                  ;; No guard found: add one
                  (unless found-guard
                    (save-excursion
                      (goto-char (point-min))
                      (forward-line (1- call-line))
                      (beginning-of-line)
                      ;; Find the opening paren of the call
                      (when (re-search-forward (format "(%s" (symbol-name fn)) (line-end-position) t)
                        (let ((call-start (match-beginning 0)))
                          ;; Find the matching closing paren BEFORE modifying buffer
                          (goto-char call-start)
                          (forward-sexp 1)  ; move to the matching close paren
                          ;; Now insert the closing paren for the (and ...) wrapper
                          (insert ")")
                          ;; Insert the opening part: (and (fboundp 'fn)
                          (goto-char call-start)
                          (insert "(and (fboundp '")
                          (insert (symbol-name fn))
                          (insert ") ")
                          (cl-incf fixed)))))))))))
      ;; Write back if we fixed anything (INSIDE with-temp-buffer)
      (when (> fixed 0)
        (when (gptel-auto-workflow--fix-validate-and-write
               (current-buffer) file original-content)
          (message "[self-heal-semantic] Added fboundp guards to %d call(s) in %s"
                   fixed (file-name-nondirectory file)))))
    fixed))

(defun gptel-auto-workflow--fix-excessive-blank-lines (file)
  "Fix excessive blank lines in FILE: compress 3+ to 1 separator.
Returns number of blocks fixed.  Safe: only modifies blank lines,
never touches code structure."
  (let ((fixed 0)
        (content nil)
        (in-blank-run nil)
        (blank-count 0))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      ;; Collect lines, compressing blank runs
      (while (not (eobp))
        (let* ((line-start (line-beginning-position))
               (line (buffer-substring-no-properties
                      line-start (line-end-position)))
               (inside-string-or-comment
                (let ((state (syntax-ppss line-start)))
                  (or (nth 3 state) (nth 4 state)))))
          (if (and (string-empty-p (string-trim line))
                   (not inside-string-or-comment))
              (progn
                (setq blank-count (1+ blank-count))
                (setq in-blank-run t))
            ;; Non-blank line: flush compressed blanks
            (when in-blank-run
              (if (>= blank-count 3)
                  (progn
                    (setq fixed (1+ fixed))
                    (push "" content)       ; single separator
                    (push "" content))      ; single separator
                ;; 1-2 blanks: keep as-is
                (dotimes (_ blank-count)
                  (push "" content)))
              (setq blank-count 0)
              (setq in-blank-run nil))
            (push line content))
          (forward-line 1)))
      ;; Trailing blank run
      (when in-blank-run
        (if (>= blank-count 3)
            (progn
              (setq fixed (1+ fixed))
              (push "" content))
          (dotimes (_ blank-count)
            (push "" content)))))
    ;; Write back if we fixed anything
    (when (> fixed 0)
      (let ((original (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-string))))
        (with-temp-buffer
          (emacs-lisp-mode)
          (dolist (l (nreverse content))
            (insert l "\n"))
          (when (gptel-auto-workflow--fix-validate-and-write
                 (current-buffer) file original)
            (message "[self-heal-semantic] Compressed %d blank-run(s) in %s"
                     fixed (file-name-nondirectory file))))))
    fixed))

(defun gptel-auto-workflow--fix-missing-provide (file)
  "Add (provide \='feature) statement to FILE if missing.
Feature name is derived from filename (e.g., gptel-foo.el -> gptel-foo).
Idempotent: returns 0 if file already has provide statement.
Returns 1 if fixed, 0 if no change needed."
  (let ((fixed 0)
        (feature (file-name-sans-extension (file-name-nondirectory file)))
        (has-provide nil)
        (new-content nil))
    ;; Read file content
    (with-temp-buffer
      (insert-file-contents file)
      (setq new-content (buffer-string)))
    ;; Check if provide already exists
    (when (string-match "^(provide\\s-+'[^)]+)" new-content)
      (setq has-provide t))
    (unless has-provide
      ;; Find the ';;; foo.el ends here' marker and insert provide before it
      (if (string-match "^;;; .*ends here$" new-content)
          (let ((marker-start (match-beginning 0)))
            (setq new-content
                  (concat (substring new-content 0 marker-start)
                          (format "(provide '%s)\n" feature)
                          (substring new-content marker-start)))
            (setq fixed 1))
        ;; No ends-here marker: append at end
        (unless (string= (substring new-content -1) "\n")
          (setq new-content (concat new-content "\n")))
        (setq new-content (concat new-content
                                 (format "(provide '%s)\n" feature)))
        (setq fixed 1))
      (let ((original (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-string))))
         (with-temp-buffer
          (emacs-lisp-mode)
          (insert new-content)
          (when (gptel-auto-workflow--fix-validate-and-write
                 (current-buffer) file original
                 :no-load-check t :no-subprocess-check t)
            (message "[self-heal-semantic] Added (provide '%s) to %s"
                     feature (file-name-nondirectory file))))))
    fixed))

(defun gptel-auto-workflow--fix-unbalanced-parens (file)
  "Fix unbalanced parens in FILE using Emacs built-in sexp scanning.
Uses `scan-sexps' to find the exact imbalance position, then deletes
excess close parens at the error position or inserts missing close
parens iteratively until the buffer is balanced.
Inserts before provide/end markers to keep them top-level.
Returns 1 if fixed, 0 if already balanced or unfixable."
  (let ((made-change nil)
        (max-attempts 50)
        (original-content
         (with-temp-buffer
           (insert-file-contents file)
           (buffer-string))))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      ;; Quick check: already balanced?
      (unless (condition-case nil
                  (progn (scan-sexps (point-min) (point-max)) t)
                (scan-error nil))
        ;; Iterate: fix one imbalance per loop, re-check, repeat
        (let ((attempt 0))
          (while (and (< attempt max-attempts)
                      (condition-case err
                          (progn (scan-sexps (point-min) (point-max)) nil)
                        (scan-error
                         (let ((err-pos (nth 2 err)))
                           (when err-pos
                             (goto-char err-pos)
                             ;; Skip if inside a string (can't fix string parens)
                             (unless (nth 3 (syntax-ppss))
                               (if (and (not (eobp))
                                        (eq (char-after) 41))
                                   ;; Excess close paren at point: delete it
                                   (progn
                                     (delete-char 1)
                                     (setq made-change t))
                                 ;; Missing close: insert before provide or
                                 ;; end marker to keep them top-level;
                                 ;; iterative re-scan handles nested misses.
                                 (goto-char (point-max))
                                 (if (or (re-search-backward
                                          "^\\s-*(provide\\s-+'" nil t)
                                         (re-search-backward
                                          ";;; .*ends here" nil t))
                                     (progn
                                       (beginning-of-line)
                                       (insert ")\n")
                                       (setq made-change t))
                                   ;; No marker found: insert at EOF
                                   (goto-char (point-max))
                                   (insert ")\n")
                                   (setq made-change t))))))
                         t)))
            (setq attempt (1+ attempt))))
        ;; Validate and write only if we made fixes
        (when made-change
          (if (gptel-auto-workflow--fix-validate-and-write
               (current-buffer) file original-content)
              (message
               "[self-heal-semantic] Fixed unbalanced parens in %s"
               (file-name-nondirectory file))
            (setq made-change nil)))))
    (if made-change 1 0)))


(defun gptel-auto-workflow--fix-condition-case-unbound-err (file)
  "Fix condition-case nil handlers that reference err without binding.
Changes (condition-case nil ... (error ... err ...))
to (condition-case err ... (error ... err ...)).
Returns number of fixes applied. Safe: only adds binding, never
removes or changes logic."
  (let ((fixed 0)
        (original-content nil))
    (with-temp-buffer
      (insert-file-contents file)
      (setq original-content (buffer-string))
      (goto-char (point-min))
      (while (re-search-forward "(condition-case\\s-+\\(nil\\)\\b" nil t)
        (let* ((match-start (match-beginning 0))
               (nil-start (match-beginning 1))
               (nil-end (match-end 1))
               (case-end (condition-case nil
                             (save-excursion
                               (goto-char match-start)
                               (forward-sexp 1)
                               (point))
                           (error nil))))
           (when case-end
             ;; Check if any (error ...) handler references err
             (save-excursion
               (goto-char nil-end)
               (when (re-search-forward "(error\\b" case-end t)
                 (let ((handler-end (condition-case nil
                                        (save-excursion
                                          (goto-char (match-beginning 0))
                                          (forward-sexp 1)
                                          (point))
                                      (error nil))))
                   (when handler-end
                     (goto-char (match-end 0))
                     (when (re-search-forward "[^-_[:word:]]err[^-_[:word:]]" handler-end t)
                       ;; Found: condition-case nil with err reference
                       ;; Fix: change "nil" to "err"
                       (delete-region nil-start nil-end)
                       (goto-char nil-start)
                       (insert "err")
                       (cl-incf fixed)
                       (message "[self-heal-semantic] Fixed condition-case nil → err in %s"
                                (file-name-nondirectory file))))))))))
      (when (> fixed 0)
        (gptel-auto-workflow--fix-validate-and-write
         (current-buffer) file original-content)))
    fixed))

;; ── Fix: nil-initialized hash tables ──

(defun gptel-auto-workflow--fix-nil-hash-tables (file)
  "Fix nil-initialized hash table defvars in FILE.
Changes (defvar NAME nil ...) to (defvar NAME (make-hash-table :test 'equal)
...)
where NAME is used with hash-table functions in the same file.
Skips variables guarded by (hash-table-p VAR) or lazy-init setq patterns.
Returns number of fixes applied."
  (let ((fixed 0)
        (original-content nil)
        (fixes-list nil))
    (with-temp-buffer
      (insert-file-contents file)
      (setq original-content (buffer-string))
      (goto-char (point-min))
      (let ((file-content (buffer-string)))
        (while (re-search-forward
                "^(defvar[ \t]+\\([a-z][a-z0-9-]*\\)[ \t]+nil\\b" nil t)
          (let ((var-name (match-string 1)))
            (unless (gptel-auto-workflow--var-has-lazy-init-setq-p
                     var-name file-content (current-buffer))
              (unless (gptel-auto-workflow--var-has-hash-table-p-guard-p
                       var-name file-content)
                (when (gptel-auto-workflow--var-used-as-hash-table-p
                       var-name file-content (current-buffer))
                  ;; Record the position of "nil" for replacement
                  (save-excursion
                    (re-search-backward "nil" (line-beginning-position) t)
                    (push (cons (point) var-name) fixes-list))))))))
      ;; Apply fixes from bottom to top to preserve positions
      (dolist (fix (sort fixes-list (lambda (a b) (> (car a) (car b)))))
        (let ((pos (car fix)))
          (goto-char pos)
          (delete-region pos (+ pos 3))
          (insert "(make-hash-table :test 'equal)")
          (cl-incf fixed)))
      (when (> fixed 0)
        (gptel-auto-workflow--fix-validate-and-write
         (current-buffer) file original-content
         :no-load-check t :no-subprocess-check t)))
    (when (> fixed 0)
      (message "[self-heal] nil-hash-table: %d fix(es) in %s"
               fixed (file-name-nondirectory file)))
    fixed))

(cl-defun gptel-auto-workflow--semantic-audit-file (file &key (_auto-fix nil))
  "Run all semantic audit checks on FILE.
Wraps each check in condition-case so a buggy check doesn't
crash the whole audit (e.g., unbalanced-parens check throwing
end-of-file error on broken files)."
  (gptel-auto-workflow--semantic-audit-reset)
  (let ((total-issues 0))
    (dolist (check gptel-auto-workflow--semantic-audit-checks)
      ;; Wrap each check in condition-case to isolate failures.
      ;; A broken file (e.g., unbalanced parens) shouldn't crash the
      ;; whole audit run.
      (condition-case check-err
          (let ((issues (funcall (cdr check) file)))
            (setq total-issues (+ total-issues issues)))
        (error
         (message "[self-heal-semantic] Check %s failed on %s: %s"
                  (car check) (file-name-nondirectory file) check-err))))
    (list :issues total-issues
          :log (nreverse (copy-sequence gptel-auto-workflow--semantic-audit-log)))))

(cl-defun gptel-auto-workflow--semantic-audit-all (&key (_auto-fix nil))
  "Run semantic audit on all Elisp files in lisp/modules/.
Skips the self-heal-semantic module itself to avoid false positives
from the audit patterns embedded in the code."
  (let* ((modules-dir (or (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
                               (gptel-auto-workflow--expand-workspace-path "lisp/modules"))
                          "lisp/modules"))
         (files (and (file-directory-p modules-dir)
                     (directory-files modules-dir t "\\.el\\'")))
         (total-issues 0)
         (report nil))
    (when files
      (dolist (file files)
        ;; Skip our own module (contains audit patterns)
        (unless (string-match-p "self-heal-semantic" (file-name-nondirectory file))
          (let* ((result (gptel-auto-workflow--semantic-audit-file file))
                 (issues (plist-get result :issues)))
            (setq total-issues (+ total-issues issues))
            (when (> issues 0)
              (push (list :file file :issues issues
                          :log (plist-get result :log))
                    report))))))
     (list :total-issues total-issues
           :files-checked (length files)
           :report (nreverse report))))

;; ── Batch Anchoring (MOSS insight) ──

(defun gptel-auto-workflow--batch-anchor-audit-results (audit-report)
  "Group AUDIT-REPORT by failure type for batch evolution.
Returns alist: ((TYPE . (issue1 issue2 ...)) ...).
Groups by :type field, preserving original order within groups.
MOSS paper insight: curate failure batches before evolution
instead of fixing each failure individually."
  (let ((batches (make-hash-table :test 'eq)))
    (dolist (entry audit-report)
      (dolist (issue (plist-get entry :log))
        (let ((type (plist-get issue :type)))
          (when type
            (puthash type
                     (cons (list :file (plist-get entry :file)
                                :line (plist-get issue :line)
                                :context (plist-get issue :context))
                           (gethash type batches))
                     batches)))))
    (let (result)
      (maphash (lambda (type issues)
                 (push (cons type (nreverse issues)) result))
               batches)
      (sort result (lambda (a b) (> (length (cdr a)) (length (cdr b))))))))

(defun gptel-auto-workflow--batch-anchor-report (batches)
  "Format BATCHES as markdown report for evolution proposals."
  (with-temp-buffer
    (insert "# Batch Anchor Report\n\n")
    (dolist (batch batches)
      (let ((type (car batch))
            (issues (cdr batch)))
        (insert (format "## %s (%d issues)\n\n" type (length issues)))
        (dolist (issue issues)
          (insert (format "- `%s:%d`\n"
                         (file-name-nondirectory (plist-get issue :file))
                         (plist-get issue :line))))
        (insert "\n")))
    (buffer-string)))

;; ── Integration with existing self-heal pipeline ──

(defvar gptel-auto-workflow--semantic-fixer-alist
  '((excessive-blank-lines . gptel-auto-workflow--fix-excessive-blank-lines)
    (unguarded-external-call . gptel-auto-workflow--fix-unguarded-external-calls)
    (missing-provide . gptel-auto-workflow--fix-missing-provide)
    (unbalanced-parens . gptel-auto-workflow--fix-unbalanced-parens)
    (condition-case-unbound-err . gptel-auto-workflow--fix-condition-case-unbound-err)
    (provide-inside-defun . gptel-auto-workflow--fix-provide-inside-defun)
    (void-defvar . gptel-auto-workflow--fix-void-defvars)
    (nil-hash-table . gptel-auto-workflow--fix-nil-hash-tables))
  "Alist mapping audit issue type (symbol) to its auto-fixer function.
Adding a new auto-fixer is now a one-line change to this alist.
Each fixer must take FILE as argument and return fix count (0 = no-op).")

(defvar gptel-auto-workflow--self-heal-ert-selectors
  '(("gptel-auto-workflow-self-heal-semantic.el" . "self-heal-semantic")
    ("gptel-auto-workflow-memory-schema.el" . "memory-schema")
    ("gptel-ext-prefix-cache.el" . "prefix-cache"))
  "Alist mapping file basename (string) to ERT selector (string).
Used by `gptel-auto-workflow--self-heal-file-via-ov5' to target relevant
ERT tests before promoting semantic fixes into the live tree.
Files not listed here fall back to the full `unit' suite.")

(defconst gptel-auto-workflow--self-heal-direct-safe-file-pattern
  "\\`ov5-test-"
  "Files matching this pattern are safe for direct mutation.
Matches temp test fixture files (created by
`test-self-heal-semantic--tmp-file',
which uses `make-temp-file \"ov5-test-\"').  Files outside lisp/modules/
are also direct-safe regardless of name, handled in the route function.")

(defun gptel-auto-workflow--self-heal-route-for-file (file)
  "Return healing route plist for FILE.
:mode is `direct' for temp/test fixture files or files outside lisp/modules/.
Everything else defaults to `ov5-worktree' deferred validation.
The monitor and daemon-repl can use this to decide which file to heal
and how much validation is required."
  (let ((name (file-name-nondirectory file)))
    (if (or (string-match-p gptel-auto-workflow--self-heal-direct-safe-file-pattern name)
            (not (string-match-p "lisp/modules/" file)))
        (list :mode 'direct
              :reason 'direct-safe
              :file file)
      (list :mode 'ov5-worktree
            :reason 'default-deferred
            :file file))))

(defun gptel-auto-workflow--self-heal-route-mode (file)
  "Return only the self-heal route mode for FILE."
  (plist-get (gptel-auto-workflow--self-heal-route-for-file file) :mode))

(defun gptel-auto-workflow--self-heal-file-dispatch (file)
  "Heal FILE using the route selected by `self-heal-route-for-file'.
High-risk repair-engine files are deferred to
`gptel-auto-workflow--self-heal-file-via-ov5' when available; otherwise no
live-tree mutation is performed."
  (let* ((route (gptel-auto-workflow--self-heal-route-for-file file))
         (mode (plist-get route :mode)))
    (pcase mode
      ('direct
       (gptel-auto-workflow--self-heal-file file))
      ('ov5-worktree
       (if (fboundp 'gptel-auto-workflow--self-heal-file-via-ov5)
           (funcall 'gptel-auto-workflow--self-heal-file-via-ov5 file)
         (append route (list :status 'deferred
                             :reason 'ov5-worktree-adapter-missing
                             :auto-fixed 0))))
      (_
       (append route (list :status 'unknown-route
                           :auto-fixed 0))))))

(defun gptel-auto-workflow--run-ert-in-worktree (worktree-dir &optional ert-selector)
  "Run ert test suite from WORKTREE-DIR via scripts/run-tests.sh unit.
Optional ERT-SELECTOR is passed as the second argument for targeted testing.
Returns (PASS-P . OUTPUT-STRING).
When no tests/ directory exists, returns (t . \"no tests directory\").
Uses `call-process' to capture both stdout+stderr AND the exit code,
so the pass/fail decision is based on the script's exit status, not
fragile output parsing."
  (let ((test-dir (expand-file-name "tests" worktree-dir))
        (script (expand-file-name "scripts/run-tests.sh" worktree-dir)))
    (cond
     ((not (file-directory-p test-dir))
      (cons t "no tests directory"))
     ((not (file-executable-p script))
      (cons t "no run-tests.sh in worktree"))
     (t
      (let* ((default-directory worktree-dir)
             (stdout-buf (generate-new-buffer " *ov5-ert-stdout*"))
             (stderr-file (make-temp-file "ov5-ert-stderr-"))
              (exit-code
               (unwind-protect
                   (apply #'call-process "bash" nil (list stdout-buf stderr-file) nil
                          (shell-quote-argument script) "unit"
                          (if ert-selector (list ert-selector) nil))
                 (with-current-buffer stdout-buf
                   (goto-char (point-max))
                   (insert-file-contents stderr-file))
                 (delete-file stderr-file)))
             (output (string-trim
                      (with-current-buffer stdout-buf (buffer-string)))))
        (kill-buffer stdout-buf)
        (cons (zerop exit-code) output))))))

(defun gptel-auto-workflow--self-heal-file-via-ov5 (file)
  "Heal FILE in an OV5 temporary worktree, then promote only if valid.
This is the safe path for repair-engine files.  It refuses dirty target files
because a HEAD worktree cannot faithfully represent uncommitted live edits."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (abs-file (expand-file-name file root))
         (rel-file (file-relative-name abs-file root)))
    (cond
     ((not (fboundp 'gptel-auto-workflow--with-temporary-worktree))
      (list :status 'deferred
            :reason 'ov5-worktree-helper-missing
            :file abs-file
            :auto-fixed 0))
     ((not (file-exists-p abs-file))
      (list :status 'rejected
            :reason 'file-missing
            :file abs-file
            :auto-fixed 0))
     ((not (zerop (let ((default-directory root))
                    (call-process "git" nil nil nil "diff" "--quiet" "--" rel-file))))
      (list :status 'rejected
            :reason 'dirty-target
            :file abs-file
            :auto-fixed 0))
     (t
      (gptel-auto-workflow--with-temporary-worktree
       "self-heal" "HEAD"
       (lambda (worktree)
         (let* ((target (expand-file-name rel-file worktree))
                (result (gptel-auto-workflow--self-heal-file target))
                (fixed (plist-get result :auto-fixed)))
           (if (<= fixed 0)
               (append result (list :status 'no-change
                                    :file abs-file
                                    :worktree worktree))
              (condition-case err
                   (progn
                     (with-temp-buffer
                       (insert-file-contents target)
                       (emacs-lisp-mode)
                       (check-parens))
                      (load-file target)
                      ;; ERT gate: run targeted or full unit tests before promotion.
                      (let* ((fname (file-name-nondirectory file))
                             (selector (cdr (assoc fname gptel-auto-workflow--self-heal-ert-selectors)))
                             (ert-result (gptel-auto-workflow--run-ert-in-worktree worktree selector)))
                        (if (car ert-result)
                            (progn
                              (copy-file target abs-file t)
                              (append result (list :status 'accepted
                                                   :file abs-file
                                                   :worktree worktree)))
                          (message "[self-heal-semantic] ERT gate FAILED for %s: %s"
                                   fname (cdr ert-result))
                          (append result (list :status 'rejected
                                               :reason 'ert-gate-failed
                                               :ert-selector selector
                                               :ert-output (cdr ert-result)
                                               :file abs-file
                                               :worktree worktree)))))
               (error
                (append result (list :status 'rejected
                                     :reason 'validation-failed
                                     :error (error-message-string err)
                                     :file abs-file
                                     :worktree worktree))))))))))))

(defun gptel-auto-workflow--self-heal-file-has-conflict-p (file)
  "Return non-nil if FILE contains an unresolved merge conflict marker.
Matches `<<<<<<<' only at the start of a line (optionally preceded by
whitespace), which is how git produces conflict markers.  This avoids
false positives from string literals containing the same characters.
Self-heal must never modify files with unresolved conflicts."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (re-search-forward "^[ \t]*<<<<<<<" nil t)))

(cl-defun gptel-auto-workflow--self-heal-semantic (&key dry-run no-dirty-check no-git-snapshot)
  "Layer 2+3 self-heal: detect AND fix semantic/operational bugs.
Runs audit checks on all lisp/modules/*.el files, then applies safe
auto-fixers for detected issues (e.g., excessive blank lines).

Keyword arguments:
  :dry-run — When t, run audits only, skip all fixers.
  :no-dirty-check — When t, skip the dirty-tree gate.
  :no-git-snapshot — When t, skip pre-fix git snapshot commits."
  (interactive)
  ;; Reset rate-limit history for each self-heal cycle
  (setq gptel-auto-workflow--fix-attempt-history
        (make-hash-table :test 'equal))
  ;; ── Dirty-tree gate (Step 1 safety layer) ──
  (let ((dirty-result
         (unless no-dirty-check
           (let ((porcelain (gptel-auto-workflow--git-status-porcelain)))
             (when (and gptel-auto-workflow--self-heal-dirty-tree-gate
                        (not (string-empty-p porcelain)))
               (message "[self-heal-semantic] WARNING: dirty working tree — refusing self-heal")
               (list :status 'dirty-tree
                     :reason "uncommitted changes in working tree"
                     :total-issues 0
                     :files-checked 0))))))
    (if dirty-result
        dirty-result
      (let ((result (gptel-auto-workflow--semantic-audit-all))
            (total-fixed 0)
            (skipped-conflict 0)
            (snapshotted-files nil))
        (when (> (plist-get result :total-issues) 0)
          (message "[self-heal-semantic] Found %d issues"
                   (plist-get result :total-issues)))
        ;; ── Pre-fix git snapshot (Step 5 safety layer) ──
        (unless (or dry-run no-git-snapshot)
          (dolist (entry (plist-get result :report))
            (let* ((file (plist-get entry :file))
                   (fname (file-name-nondirectory file)))
              (when (not (member file snapshotted-files))
                ;; Run git from the file's directory so the correct repo is found.
                (condition-case nil
                    (let ((default-directory (file-name-directory file)))
                      (call-process "git" nil nil nil "add" "--" file)
                      (condition-case nil
                          (call-process "git" nil nil nil "commit" "-m"
                                        (format "[self-heal] snapshot before auto-fix: %s"
                                                fname))
                        (error
                         (message "[self-heal-semantic] git commit failed for snapshot of %s"
                                  fname))))
                  (error
                   (message "[self-heal-semantic] git add failed for snapshot of %s"
                            fname)))
                (push file snapshotted-files)))))
        ;; ── Auto-fix phase: data-driven dispatch via fixer-alist ──
        ;; Skip entirely when dry-run is t (Step 4 safety layer)
        (unless dry-run
          (dolist (entry (plist-get result :report))
            (let* ((file (plist-get entry :file))
                   (log (plist-get entry :log))
                   (present-types
                    (delete-dups
                     (delq nil (mapcar (lambda (r) (plist-get r :type)) log)))))
              ;; Guard: never touch files with unresolved git conflicts.
              (if (gptel-auto-workflow--self-heal-file-has-conflict-p file)
                  (progn
                    (message "[self-heal-semantic] Skipping %s: unresolved merge conflict"
                             (file-name-nondirectory file))
                    (cl-incf skipped-conflict))
                (if (eq 'ov5-worktree (gptel-auto-workflow--self-heal-route-mode file))
                    (let ((dispatch-result (gptel-auto-workflow--self-heal-file-dispatch file)))
                      (cl-incf total-fixed (or (plist-get dispatch-result :auto-fixed) 0)))
                  (dolist (issue-type present-types)
                    (let ((fixer (alist-get issue-type gptel-auto-workflow--semantic-fixer-alist)))
                      (when fixer
                        ;; Rate limiting (Step 3 safety layer)
                        (if (gptel-auto-workflow--fixer-rate-limit-p file fixer)
                            (message
                             "[self-heal-semantic] Skipping %s on %s: rate-limited (last attempt < %d min ago)"
                             fixer (file-name-nondirectory file)
                             gptel-auto-workflow--fixer-rate-limit-minutes)
                          (let ((fixed (funcall fixer file)))
                            (when (> fixed 0)
                              (gptel-auto-workflow--fixer-rate-limit-record file fixer)
                              (cl-incf total-fixed fixed))))))))))))
        (when (> total-fixed 0)
          (message "[self-heal-semantic] Auto-fixed %d issue(s)" total-fixed))
        (plist-put result :auto-fixed total-fixed)
        result))))

(defun gptel-auto-workflow--self-heal-file (file)
  "Targeted self-heal: audit and fix FILE only.
Returns plist with :issues, :auto-fixed, :files-checked.
Logs a conversion unit if fixes were applied and the conversion-unit
module is available."
  (let* ((result (gptel-auto-workflow--semantic-audit-file file))
         (issues (plist-get result :issues))
         (log (plist-get result :log))
         (total-fixed 0))
    (when (> issues 0)
      (message "[self-heal-semantic] Found %d issues in %s"
               issues (file-name-nondirectory file))
      (let ((present-types
             (delete-dups
              (delq nil (mapcar (lambda (r) (plist-get r :type)) log)))))
        (dolist (issue-type present-types)
          (let ((fixer (alist-get issue-type gptel-auto-workflow--semantic-fixer-alist)))
            (when fixer
              ;; Rate limiting (Step 3 safety layer)
              (if (gptel-auto-workflow--fixer-rate-limit-p file fixer)
                  (message
                   "[self-heal-semantic] Skipping %s on %s: rate-limited (last attempt < %d min ago)"
                   fixer (file-name-nondirectory file)
                   gptel-auto-workflow--fixer-rate-limit-minutes)
                (let ((fixed (funcall fixer file)))
                  (when (> fixed 0)
                    (gptel-auto-workflow--fixer-rate-limit-record file fixer)
                    (cl-incf total-fixed fixed)))))))))
    (when (> total-fixed 0)
      (message "[self-heal-semantic] Auto-fixed %d issue(s) in %s"
               total-fixed (file-name-nondirectory file))
      ;; Log conversion unit for audit trail
      (when (and (fboundp 'gptel-conversion-unit-add)
                 (boundp 'gptel-conversion-unit-enabled)
                 gptel-conversion-unit-enabled)
        (condition-case nil
            (gptel-conversion-unit-add
             (format "self-heal-%s" (format-time-string "%Y%m%d%H%M%S"))
             'repair
             (list :file file
                   :status 'audit-failed
                   :issues issues)
             (list :file file
                   :status 'auto-fixed
                   :fixes total-fixed))
          (error nil))))
    (list :issues issues
          :auto-fixed total-fixed
          :files-checked 1)))

(defun gptel-auto-workflow--self-heal-semantic-batch-anchor ()
  "Run audit + batch anchoring for evolution proposal.
Groups failures by type and returns a markdown report.
This is the entry point for batch-anchored evolution."
  (interactive)
  (let* ((result (gptel-auto-workflow--semantic-audit-all))
         (batches (gptel-auto-workflow--batch-anchor-audit-results
                   (plist-get result :report)))
         (report (gptel-auto-workflow--batch-anchor-report batches)))
    (message "[batch-anchor] %d issues -> %d batches"
             (plist-get result :total-issues)
             (length batches))
    ;; Return both raw result and batch-anchored report
    (list :audit result
          :batches batches
          :report report)))

(defun gptel-auto-workflow--batch-anchor-read-report (&optional report-file)
  "Read batch anchor report from REPORT-FILE.
Defaults to `mementum/batch-anchor-report.md' under `user-emacs-directory'.
Returns plist with :types (list of failure type symbols) and :top-type
(the most frequent failure type), or nil if no report exists."
  (let ((file (or report-file
                  (expand-file-name "mementum/batch-anchor-report.md"
                                    user-emacs-directory))))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((types nil)
              (top-type nil)
              (top-count 0))
          ;; Parse "## TYPE (N issues)" lines
          (while (re-search-forward "^## \\([^ ]+\\) (\\([0-9]+\\) issues)" nil t)
            (let* ((type-str (match-string 1))
                   (count (string-to-number (match-string 2)))
                   (type-sym (intern type-str)))
              (push type-sym types)
              (when (> count top-count)
                (setq top-count count)
                (setq top-type type-sym))))
          (when types
            (list :types (nreverse types)
                  :top-type top-type
                   :top-count top-count)))))))

(provide 'gptel-auto-workflow-self-heal-semantic)
;;; gptel-auto-workflow-self-heal-semantic.el ends here
