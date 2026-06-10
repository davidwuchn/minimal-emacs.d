;;; gptel-auto-workflow-self-heal-semantic.el --- Layer 2+3 self-heal -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; Layer 1 (byte-compile) catches syntax/void-function/arity issues.
;; This module is Layer 2 (semantic assertions) + Layer 3 (operational
;; guards). It catches bugs that compile fine but misbehave at runtime.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; ── Issue accumulator ──

(defvar gptel-auto-workflow--semantic-audit-log nil
  "List of semantic audit issues found.")

(defun gptel-auto-workflow--semantic-audit-reset ()
  "Clear the semantic audit log."
  (setq gptel-auto-workflow--semantic-audit-log nil))

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
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (if (string-empty-p (string-trim line))
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
(not just user-error) so that 'end-of-file' and other balance errors
are also reported."
  (let ((issues 0))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          ;; check-parens raises user-error if unbalanced.
          ;; Other parse errors (e.g., end-of-file) also indicate
          ;; unbalanced parens, so catch all with 'error'.
          (check-parens))
      (error
       (setq issues 1)
       (gptel-auto-workflow--semantic-audit-record
        file 1
        'unbalanced-parens
        (format "Unbalanced parens — %s"
                (error-message-string err)))))
    issues))

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

(defvar gptel-auto-workflow--semantic-audit-checks
  '((let-binding-function . gptel-auto-workflow--audit-let-binding-functions)
    (hardcoded-limit . gptel-auto-workflow--audit-hardcoded-limits)
    (score-zero-bug . gptel-auto-workflow--audit-score-zero-bug)
    (unguarded-external-call . gptel-auto-workflow--audit-unguarded-external-calls)
    (excessive-blank-lines . gptel-auto-workflow--audit-blank-lines)
    (unbalanced-parens . gptel-auto-workflow--audit-unbalanced-parens)
    (missing-provide . gptel-auto-workflow--audit-missing-provide)
    (condition-case-unbound-err . gptel-auto-workflow--audit-condition-case-unbound-err)
    (risk-node . gptel-auto-workflow--audit-risk-nodes))
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
          (let ((resource-fn (car pattern))
                (cleanup-fn (cdr pattern)))
            (goto-char (point-min))
            (while (re-search-forward (format "(%s\\b" resource-fn) nil t)
              (let* ((match-line (line-number-at-pos (match-beginning 0)))
                     (defun-start (save-excursion
                                    (when (re-search-backward "^(defun\\b" nil t)
                                      (point))))
                     (defun-end (when defun-start
                                  (save-excursion
                                    (goto-char defun-start)
                                    (forward-sexp 1)
                                    (point))))
                     (has-cleanup nil))
                (when (and defun-start defun-end)
                  (save-excursion
                    (goto-char defun-start)
                    ;; Check for delete-file, delete-directory, or unwind-protect
                    (when (or (re-search-forward "(delete-file\\b" defun-end t)
                              (re-search-forward "(delete-directory\\b" defun-end t)
                              (re-search-forward "(unwind-protect\\b" defun-end t))
                      (setq has-cleanup t))))
                (unless has-cleanup
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
                                    (when (re-search-backward "^(defun\\b" nil t)
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

;; ── Auto-fixers (Layer 2+3: detect AND fix) ──

(defun gptel-auto-workflow--fix-unguarded-external-calls (file)
  "Fix unguarded calls to external functions in FILE.
Wraps calls like (fn ...) with (and (fboundp \='fn) (fn ...)).
Returns number of calls fixed.  Safe: only adds guards, never changes logic."
  (let ((fixed 0))
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
        (write-region (point-min) (point-max) file)
        (message "[self-heal-semantic] Added fboundp guards to %d call(s) in %s"
                 fixed (file-name-nondirectory file))))
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
      (goto-char (point-min))
      ;; Collect lines, compressing blank runs
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (if (string-empty-p (string-trim line))
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
      (with-temp-file file
        (dolist (l (nreverse content))
          (insert l "\n")))
      (message "[self-heal-semantic] Compressed %d blank-run(s) in %s"
               fixed (file-name-nondirectory file)))
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
      (with-temp-file file
        (insert new-content))
      (message "[self-heal-semantic] Added (provide '%s) to %s"
               feature (file-name-nondirectory file)))
    fixed))

(defun gptel-auto-workflow--fix-unbalanced-parens (file)
  "Append missing close parens at end of FILE if unbalanced.
Handles the common case: more opening than closing parens/brackets
introduced by editing. Returns 1 if fixed, 0 otherwise.
Safe: only appends closes, never deletes code. Does NOT handle the
case of more closes than opens (which requires deletion — too risky)."
  (let ((fixed 0)
        (opens 0)
        (closes 0)
        (new-content nil)
        (in-string nil)
        (in-comment nil)
        (escaped nil))
    (with-temp-buffer
      (insert-file-contents file)
      (setq new-content (buffer-string))
      ;; Walk through content, tracking paren balance while ignoring
      ;; string literals and comments (where parens don't count).
      (dolist (ch (append new-content nil))
        (cond
         (escaped (setq escaped nil))
         ((eq ch 92) (setq escaped t))
         ((and (not in-string) (eq ch 59))
          (setq in-comment t))
         ((and in-comment (eq ch 10))
          (setq in-comment nil))
         ((and (not in-comment) (eq ch 34))
          (setq in-string (not in-string)))
         ((and (not in-string) (not in-comment))
          (cond
           ((eq ch 40) (setq opens (1+ opens)))
           ((eq ch 41) (setq closes (1+ closes))))))))
    ;; Only fix if more opens than closes (append closes)
    (when (> opens closes)
      (let* ((missing (- opens closes))
             (closes-str (make-string missing 41)))
        (setq new-content (concat new-content "\n" closes-str))
        (with-temp-file file
          (insert new-content))
        (message "[self-heal-semantic] Appended %d missing close paren(s) at EOF in %s"
                 missing (file-name-nondirectory file))
        (setq fixed 1)))
    fixed))

(defun gptel-auto-workflow--fix-condition-case-unbound-err (file)
  "Fix condition-case nil handlers that reference err without binding.
Changes (condition-case nil ... (error ... err ...))
to (condition-case err ... (error ... err ...)).
Returns number of fixes applied. Safe: only adds binding, never
removes or changes logic."
  (let ((fixed 0))
    (with-temp-buffer
      (insert-file-contents file)
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
        (write-region (point-min) (point-max) file)))
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

;; ── Integration with existing self-heal pipeline ──

(defvar gptel-auto-workflow--semantic-fixer-alist
  '((excessive-blank-lines . gptel-auto-workflow--fix-excessive-blank-lines)
    (unguarded-external-call . gptel-auto-workflow--fix-unguarded-external-calls)
    (missing-provide . gptel-auto-workflow--fix-missing-provide)
    (unbalanced-parens . gptel-auto-workflow--fix-unbalanced-parens)
    (condition-case-unbound-err . gptel-auto-workflow--fix-condition-case-unbound-err))
  "Alist mapping audit issue type (symbol) to its auto-fixer function.
Adding a new auto-fixer is now a one-line change to this alist.
Each fixer must take FILE as argument and return fix count (0 = no-op).")

(defun gptel-auto-workflow--self-heal-semantic ()
  "Layer 2+3 self-heal: detect AND fix semantic/operational bugs.
Runs audit checks on all lisp/modules/*.el files, then applies safe
auto-fixers for detected issues (e.g., excessive blank lines)."
  (interactive)
  (let ((result (gptel-auto-workflow--semantic-audit-all))
        (total-fixed 0))
    (when (> (plist-get result :total-issues) 0)
      (message "[self-heal-semantic] Found %d issues"
               (plist-get result :total-issues)))
    ;; ── Auto-fix phase: data-driven dispatch via fixer-alist ──
    ;; For each file with issues, find which issue types are present,
    ;; look up their fixers in the alist, and apply them.
    (dolist (entry (plist-get result :report))
      (let* ((file (plist-get entry :file))
             (log (plist-get entry :log))
             (present-types
              (delete-dups
               (delq nil (mapcar (lambda (r) (plist-get r :type)) log)))))
        (dolist (issue-type present-types)
          (let ((fixer (alist-get issue-type gptel-auto-workflow--semantic-fixer-alist)))
            (when fixer
              (let ((fixed (funcall fixer file)))
                (when (> fixed 0)
                  (cl-incf total-fixed fixed))))))))
    (when (> total-fixed 0)
      (message "[self-heal-semantic] Auto-fixed %d issue(s)" total-fixed))
    (plist-put result :auto-fixed total-fixed)
    result))

(provide 'gptel-auto-workflow-self-heal-semantic)
;;; gptel-auto-workflow-self-heal-semantic.el ends here
