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

(declare-function gptel-auto-workflow--with-temporary-worktree
                  "gptel-tools-agent-staging-baseline" (slug ref fn))

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
  "Fix unbalanced parens in FILE.
Handles two cases:
1. Missing close parens (more opens than closes) — appends at EOF
2. Extra close parens (more closes than opens) — removes from error line
Returns 1 if fixed, 0 otherwise."
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
    (cond
      ;; Case 1: more opens than closes — append missing closes at EOF
      ((> opens closes)
       (let* ((missing (- opens closes))
              (closes-str (make-string missing 41))
              (insert-pos (or (string-match "^\\s-*(provide\\s-+'" new-content)
                              (string-match "^;;; .*ends here$" new-content))))
        ;; Prefer inserting before the provide/end marker so provide remains
        ;; top-level. Appending at EOF can make (provide ...) part of an
        ;; unclosed defun body: load succeeds, but require fails.
        (setq new-content
              (if insert-pos
                  (concat (substring new-content 0 insert-pos)
                          closes-str "\n"
                          (substring new-content insert-pos))
                (concat new-content "\n" closes-str)))
        (with-temp-file file
          (insert new-content))
        (message "[self-heal-semantic] Appended %d missing close paren(s) at EOF in %s"
                 missing (file-name-nondirectory file))
        (setq fixed 1)))
     ;; Case 2: more closes than opens — remove excess from error line
     ((< opens closes)
      (let* ((excess (- closes opens))
             (error-line (gptel-auto-workflow--find-paren-balance-line file)))
        (when error-line
          (with-temp-buffer
            (insert new-content)
            (goto-char (point-min))
            (forward-line (1- error-line))
            (end-of-line)
            ;; Remove excess close parens from end of line
            (let ((end-pos (point))
                  (start-pos (save-excursion
                               (let ((count 0))
                                 (while (and (> (point) (line-beginning-position))
                                            (< count excess)
                                            (eq (char-before) 41))
                                   (backward-char 1)
                                   (setq count (1+ count)))
                                 (point)))))
              (when (> (- end-pos start-pos) 0)
                (delete-region start-pos end-pos)
                 (let ((content (buffer-string)))
                   (with-temp-file file
                     (insert content)))
                (message "[self-heal-semantic] Removed %d excess close paren(s) from line %d in %s"
                         (- end-pos start-pos) error-line (file-name-nondirectory file))
                (setq fixed 1))))))))
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
    (condition-case-unbound-err . gptel-auto-workflow--fix-condition-case-unbound-err))
  "Alist mapping audit issue type (symbol) to its auto-fixer function.
Adding a new auto-fixer is now a one-line change to this alist.
Each fixer must take FILE as argument and return fix count (0 = no-op).")

(defconst gptel-auto-workflow--self-heal-high-risk-file-pattern
  (regexp-opt '("gptel-auto-workflow-self-heal-semantic.el"
                "gptel-auto-workflow-monitoring-agent.el"
                "gptel-auto-workflow-ontology-router.el"
                "gptel-auto-workflow-evolution.el"
                "gptel-tools-agent-worktree.el"))
  "Files that should be healed through OV5 worktree/subagent validation.")

(defun gptel-auto-workflow--self-heal-route-for-file (file)
  "Return healing route plist for FILE.
:mode is `direct' for normal files and `ov5-worktree' for high-risk
workflow/self-heal files.  The monitor and daemon-repl can use this to
decide which file to heal and how much validation is required."
  (let ((name (file-name-nondirectory file)))
    (if (string-match-p gptel-auto-workflow--self-heal-high-risk-file-pattern name)
        (list :mode 'ov5-worktree
              :reason 'high-risk-repair-engine
              :file file)
      (list :mode 'direct
            :reason 'targeted-file
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
                   (copy-file target abs-file t)
                   (append result (list :status 'accepted
                                        :file abs-file
                                        :worktree worktree)))
               (error
                (append result (list :status 'rejected
                                     :reason 'validation-failed
                                     :error (error-message-string err)
                                     :file abs-file
                                     :worktree worktree))))))))))))

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
        (if (eq 'ov5-worktree (gptel-auto-workflow--self-heal-route-mode file))
            (let ((dispatch-result (gptel-auto-workflow--self-heal-file-dispatch file)))
              (cl-incf total-fixed (or (plist-get dispatch-result :auto-fixed) 0)))
          (dolist (issue-type present-types)
            (let ((fixer (alist-get issue-type gptel-auto-workflow--semantic-fixer-alist)))
              (when fixer
                (let ((fixed (funcall fixer file)))
                  (when (> fixed 0)
                    (cl-incf total-fixed fixed)))))))))
    (when (> total-fixed 0)
      (message "[self-heal-semantic] Auto-fixed %d issue(s)" total-fixed))
    (plist-put result :auto-fixed total-fixed)
    result))

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
              (let ((fixed (funcall fixer file)))
                (when (> fixed 0)
                  (cl-incf total-fixed fixed))))))))
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
