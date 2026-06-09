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

(defun gptel-auto-workflow--semantic-audit-record (file line type message)
  "Record a semantic audit issue at FILE:LINE of TYPE with MESSAGE."
  (push (list :file file :line line :type type :message message)
        gptel-auto-workflow--semantic-audit-log))

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
                    (goto-line call-line)
                    ;; Search backward for the enclosing (defun
                    (when (re-search-backward "^(defun\\b" nil t)
                      (setq defun-start-line (line-number-at-pos (point)))))
                  ;; Check for guard anywhere within the defun (after defun-start-line)
                  (let ((check-line (max 1 (- call-line 1)))
                        (end-of-lookback defun-start-line))
                    (while (and (>= check-line end-of-lookback)
                                (not found-guard))
                      (save-excursion
                        (goto-line check-line)
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
        (let ((line-start (point))
              (line (buffer-substring-no-properties
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
Catches the 'End of file during parsing' class of bugs where editing
introduces a missing close paren. Uses Emacs's built-in check-parens
after loading the file as emacs-lisp.
Returns 1 if unbalanced, 0 if balanced."
  (let ((issues 0))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          ;; check-parens raises user-error if unbalanced
          (check-parens))
      (user-error
       (setq issues 1)
       (gptel-auto-workflow--semantic-audit-record
        file 1
        'unbalanced-parens
        "Unbalanced parens/brackets — Emacs cannot parse this file")))
    issues))

;; ── Check 7: Missing provide statement ──

(defun gptel-auto-workflow--audit-missing-provide (file)
  "Audit FILE for missing (provide 'feature) statement.
Modules without provide cannot be required by other modules.
Returns 1 if missing, 0 if present."
  (let ((issues 0)
        (has-provide nil)
        (feature-name nil))
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    ;; Look for (provide 'feature) form
    (when (re-search-forward "^(provide\\s-+'\\([^)]+\\))" nil t)
      (setq has-provide t)
      (setq feature-name (match-string 1)))
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
    (missing-provide . gptel-auto-workflow--audit-missing-provide))
  "Alist of audit check name (symbol) to audit function.")

;; ── Auto-fixers (Layer 2+3: detect AND fix) ──

(defun gptel-auto-workflow--fix-unguarded-external-calls (file)
  "Fix unguarded calls to external functions in FILE.
Wraps calls like (fn ...) with (and (fboundp 'fn) (fn ...)).
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
                    (goto-line call-line)
                    (when (re-search-backward "^(defun\\b" nil t)
                      (setq defun-start-line (line-number-at-pos (point)))))
                  ;; Check for guard within the defun
                  (let ((check-line (max 1 (- call-line 1)))
                        (end-of-lookback defun-start-line))
                    (while (and (>= check-line end-of-lookback)
                                (not found-guard))
                      (save-excursion
                        (goto-line check-line)
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
                      (goto-line call-line)
                      (beginning-of-line)
                      ;; Find the opening paren of the call
                      (when (re-search-forward (format "(%s" (symbol-name fn)) (line-end-position) t)
                        (let ((call-start (match-beginning 0)))
                          ;; Insert guard: (and (fboundp 'fn) (fn ...))
                          (goto-char call-start)
                          (insert "(and (fboundp '")
                          (insert (symbol-name fn))
                          (insert ") ")
                          ;; Find the matching close paren and insert another close paren
                          (forward-char 1)  ; move past the opening paren
                          (forward-sexp 1)  ; move to the matching close paren
                          (insert ")")
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
  "Add (provide 'feature) statement to FILE if missing.
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

(cl-defun gptel-auto-workflow--semantic-audit-file (file &key (_auto-fix nil))
  "Run all semantic audit checks on FILE."
  (gptel-auto-workflow--semantic-audit-reset)
  (let ((total-issues 0))
    (dolist (check gptel-auto-workflow--semantic-audit-checks)
      (let ((issues (funcall (cdr check) file)))
        (setq total-issues (+ total-issues issues))))
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
    ;; ── Auto-fix phase: apply safe fixers ──
    ;; These fixers are structural-only (no logic changes) and safe
    ;; to run without rollback:
    (dolist (entry (plist-get result :report))
      (let* ((file (plist-get entry :file))
             (log (plist-get entry :log)))
        ;; Fix excessive blank lines
        (when (cl-some (lambda (r) (eq (plist-get r :type) 'excessive-blank-lines))
                       log)
          (let ((fixed (gptel-auto-workflow--fix-excessive-blank-lines file)))
            (when (> fixed 0)
              (cl-incf total-fixed fixed))))
        ;; Fix unguarded external calls
        (when (cl-some (lambda (r) (eq (plist-get r :type) 'unguarded-external-call))
                       log)
          (let ((fixed (gptel-auto-workflow--fix-unguarded-external-calls file)))
            (when (> fixed 0)
              (cl-incf total-fixed fixed))))
        ;; Fix missing provide
        (when (cl-some (lambda (r) (eq (plist-get r :type) 'missing-provide))
                       log)
          (let ((fixed (gptel-auto-workflow--fix-missing-provide file)))
            (when (> fixed 0)
              (cl-incf total-fixed fixed))))))
    (when (> total-fixed 0)
      (message "[self-heal-semantic] Auto-fixed %d issue(s)" total-fixed))
    (plist-put result :auto-fixed total-fixed)
    result))

(provide 'gptel-auto-workflow-self-heal-semantic)
;;; gptel-auto-workflow-self-heal-semantic.el ends here
