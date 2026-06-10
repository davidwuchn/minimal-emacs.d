;;; test-self-heal-semantic.el --- Tests for semantic self-heal -*- lexical-binding: t; -*-

;; Tests that verify the semantic self-heal module can detect the kinds
;; of bugs we've been fixing manually:
;; 1. Regex string literals with embedded newlines
;; 2. (let ...) used to bind functions (should be cl-letf)
;; 3. Hardcoded resource limits (1.5GB watchdog threshold)
;; 4. score=0 logic that confuses legitimate grades with broken graders

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load the module under test
(unless (featurep 'gptel-auto-workflow-self-heal-semantic)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                          default-directory)))

;; ── Helper: create a temp file with given content ──

(defun test-self-heal-semantic--tmp-file (content)
  "Create a temp file with CONTENT (a string), return file path.
File name starts with `test-` so the let-binding check applies."
  (let ((file (make-temp-file "ov5-test-" nil ".el")))
    (with-temp-file file
      (insert content))
    file))

(defun test-self-heal-semantic--cleanup (file)
  "Delete FILE if it exists."
  (when (and file (file-exists-p file))
    (delete-file file)))

;; ── Test 1: Regex embedded newlines detection (skipped - complex parser) ──
;; The regex-string detection is complex to implement correctly without
;; false positives. The kibcm-patterns bug was caught and fixed manually
;; when the patterns broke test cases. For now, the other 3 checks provide
;; good coverage.

;; ── Test 2: (let ...) binding functions detection ──

(ert-deftest test-self-heal-semantic/detects-let-binding-function ()
  "Detects (let ((fn-name (lambda ...)))) which should be cl-letf."
  (let* ((content
          "(defun test-foo ()
  (let ((gptel-auto-workflow--some-fn (lambda () nil)))
    (funcall #'gptel-auto-workflow--some-fn)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-let-binding-functions file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-let-no-binding ()
  "Regular (let ((var value))) bindings are clean."
  (let* ((content
          "(defun test-foo ()
  (let ((my-var 42))
    (+ my-var 1)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-let-binding-functions file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 3: Hardcoded resource limits detection ──

(ert-deftest test-self-heal-semantic/detects-hardcoded-1.5gb ()
  "Detects hardcoded 1.5GB watchdog threshold."
  (let* ((content
          "(defun watchdog-check ()
  (when (> rss 1572864)  ; 1.5GB
    (force-stop)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-hardcoded-limits file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/hardcoded-limit-line-number ()
  "Hardcoded limit detection reports correct line numbers."
  (let* ((content
          "(defun foo ()
  (+ 1 2))
(defun watchdog-check ()
  (when (> rss 1572864)
    (force-stop)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (gptel-auto-workflow--audit-hardcoded-limits file)
          (let ((log gptel-auto-workflow--semantic-audit-log))
            (should (= (length log) 1))
            ;; The hardcoded limit is on line 4 (1-indexed, blank lines stripped)
            (should (= (plist-get (car log) :line) 4))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/hardcoded-limit-line-number-with-blanks ()
  "Hardcoded limit detection reports correct line numbers even with blank lines.
Regression: split-string with t omits empty strings, breaking line counting."
  (let* ((content
          "(defun foo ()
  (+ 1 2))

(defun watchdog-check ()
  (when (> rss 1572864)
    (force-stop)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (gptel-auto-workflow--audit-hardcoded-limits file)
          (let ((log gptel-auto-workflow--semantic-audit-log))
            (should (= (length log) 1))
            ;; The hardcoded limit is on line 5 (with blank line on line 3)
            (should (= (plist-get (car log) :line) 5))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-no-hardcoded ()
  "Files without 1.5GB are clean."
  (let* ((content
          "(defun clean ()
  (let ((threshold 4194304))  ; 4GB
    (when (> rss threshold) (force-stop))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-hardcoded-limits file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/hardcoded-limit-skip-docstring ()
  "Hardcoded limit detection skips mentions inside docstrings.
Regression: 1572864 mentioned in a docstring describing the OLD threshold
should not be flagged. The check uses syntax-ppss to detect string context."
  (let* ((content
          "(defvar foo 4194304
  \"RSS threshold in KB. The old 1.5GB threshold (1572864) killed
legitimate subagent work. Set to nil to disable.\")")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (gptel-auto-workflow--audit-hardcoded-limits file)
          (let ((log gptel-auto-workflow--semantic-audit-log))
            (should (= (length log) 0))))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 4: score=0 logic detection ──

(ert-deftest test-self-heal-semantic/detects-score-zero-bug ()
  "Detects (greater-than score 0) used as grader-broken check."
  (let* ((content
          "(defun classify-grade (score)
  (if (and (numberp score) (> score 0))
      'healthy
    'broken))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-score-zero-bug file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-no-score-zero-bug ()
  "Files without (greater-than score 0) are clean."
  (let* ((content
          "(defun classify-grade (score)
  (if (and (numberp score) (>= score 0.5))
      'healthy
    'unknown))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-score-zero-bug file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 5: Audit dispatcher ──

(ert-deftest test-self-heal-semantic/audit-checks-variable-defined ()
  "The audit checks alist is defined with all checks."
  (should (= (length gptel-auto-workflow--semantic-audit-checks) 9))
  (should (assq 'let-binding-function gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'hardcoded-limit gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'score-zero-bug gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'unguarded-external-call gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'excessive-blank-lines gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'unbalanced-parens gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'missing-provide gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'condition-case-unbound-err gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'risk-node gptel-auto-workflow--semantic-audit-checks)))

;; ── Test 10: Missing provide detection ──

(ert-deftest test-self-heal-semantic/detects-missing-provide ()
  "Detects files that don't have a (provide 'foo) statement."
  (let* ((content
          "(defun foo ()\n  1)\n;;; foo.el ends here\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-missing-provide file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-with-provide ()
  "Files with (provide 'foo) are clean."
  (let* ((content
          "(defun foo ()\n  1)\n(provide 'foo)\n;;; foo.el ends here\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-missing-provide file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-adds-missing-provide ()
  "Auto-fixer should add (provide 'feature) before 'ends here' marker."
  (let* ((content
          "(defun foo ()\n  1)\n;;; foo.el ends here\n")
         (file (test-self-heal-semantic--tmp-file content))
         (expected-feature (file-name-sans-extension
                            (file-name-nondirectory file))))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-missing-provide file)))
            (should (= fixed 1))
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (should (re-search-forward
                       (format "^(provide '%s)" expected-feature)
                       nil t)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-no-op-when-present ()
  "Auto-fixer should not modify files that already have provide."
  (let* ((content
          "(defun foo ()\n  1)\n(provide 'foo)\n;;; foo.el ends here\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-missing-provide file)))
          (should (= fixed 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 9: Unbalanced parens detection ──

(ert-deftest test-self-heal-semantic/detects-unbalanced-parens ()
  "Detects files with unbalanced parens/brackets.
Reproduces the memory-schema bug: missing closing paren after fboundp guard."
  (let* ((content
          "(defun foo ()
  (let ((x 1))
    (setq x 2))
  ;; Missing close paren before message
  (message \"x=%d\" x)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unbalanced-parens file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/detects-extra-close-at-eof ()
  "Detects extra close parens at EOF (e.g., ')))' after the form ends).
Regression: ontology-router.el had ')))' at end of file which caused
'End of file during parsing' error. The audit was using condition-case
for user-error only, missing other parse errors like end-of-file.
After fix: catches ALL errors via (error ...)."
  (let* ((content
          "(defun foo ()\n  42)\n\n)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unbalanced-parens file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-balanced-parens ()
  "Files with balanced parens are clean."
  (let* ((content
          "(defun foo ()
  (let ((x 1))
    (setq x 2)))
(message \"ok\")")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unbalanced-parens file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-adds-missing-close-at-eof ()
  "Auto-fixer appends missing close parens at EOF for the common case."
  (let* ((content
          "(defun foo ()\n  (let ((x 1))\n    (setq x 2)\n  (message \"x=%d\" x)\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (should (= 1 (gptel-auto-workflow--audit-unbalanced-parens file)))
          (let ((fixed (gptel-auto-workflow--fix-unbalanced-parens file)))
            (should (= fixed 1)))
          (should (= 0 (gptel-auto-workflow--audit-unbalanced-parens file))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-no-op-when-balanced ()
  "Auto-fixer is no-op when parens are balanced."
  (let* ((content
          "(defun foo ()\n  42)\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-unbalanced-parens file)))
          (should (= fixed 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-skip-when-cannot-fix ()
  "Auto-fixer does not modify file when paren balance cannot be determined
or when closing > opening (would require deletion, not just addition)."
  (let* ((content
          "(defun foo ()\n  42))\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-unbalanced-parens file)))
          (should (= fixed 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/detects-unmatched-brackets ()
  "Detects unmatched brackets in any direction."
  (let* ((content
          "(defun foo ()
  (let (x 1))
(message \"ok\")")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unbalanced-parens file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 8: Excessive blank line detection ──

(ert-deftest test-self-heal-semantic/detects-excessive-blank-lines ()
  "Detects 4+ consecutive blank lines as excessive."
  (let* ((content
          "(defun foo () 1)\n\n\n\n\n(defun bar () 2)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-blank-lines file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-normal-blank-lines ()
  "Single or double blank lines between defuns are normal."
  (let* ((content
          "(defun foo () 1)\n\n(defun bar () 2)\n\n(defun baz () 3)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-blank-lines file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-excessive-blank-lines ()
  "Fixer compresses 4+ blank lines to single separator."
  (let* ((content
          "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-excessive-blank-lines file)))
          (should (>= fixed 1))
          ;; Verify: no 3+ consecutive blank lines remain
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (let ((max-consecutive 0)
                  (current 0))
              (while (not (eobp))
                (if (string-empty-p (buffer-substring-no-properties
                                     (line-beginning-position)
                                     (line-end-position)))
                    (setq current (1+ current))
                  (setq max-consecutive (max max-consecutive current))
                  (setq current 0))
                (forward-line 1))
              (should (<= max-consecutive 2)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fix-blank-lines-idempotent ()
  "Fixer on already-clean file returns 0."
  (let* ((content
          "(defun foo () 1)\n\n(defun bar () 2)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-excessive-blank-lines file)))
          (should (= fixed 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 9: Entry point function ──

(ert-deftest test-self-heal-semantic/detects-unguarded-external-call ()
  "Detects calls to gptel-agent-read-file without fboundp guard.

Reproduces the bug: gptel-auto-workflow--load-skill called
gptel-agent-read-file without a (fboundp 'gptel-agent-read-file) guard,
causing void-function errors when gptel-agent was not loaded."
  (let* ((content
          "(defun load-skill (file)
  (let ((parsed (gptel-agent-read-file file))
        (name (car parsed)))
    name))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unguarded-external-calls file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-with-fboundp-guard ()
  "Function call with (fboundp 'foo) guard is clean."
  (let* ((content
          "(defun load-skill (file)
  (when (fboundp 'gptel-agent-read-file)
    (let ((parsed (gptel-agent-read-file file)))
      parsed)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unguarded-external-calls file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-with-condition-case ()
  "Function call wrapped in condition-case is also safe."
  (let* ((content
          "(defun load-skill (file)
  (condition-case nil
      (gptel-agent-read-file file)
    (error nil)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-unguarded-external-calls file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fixes-unguarded-external-call ()
  "Auto-fixer adds fboundp guard to unguarded external calls."
  (let* ((content
          "(defun load-skill (file)
  (let ((parsed (gptel-agent-read-file file))
        (name (car parsed)))
    name))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          ;; First verify it's detected as unguarded
          (let ((issues-before (gptel-auto-workflow--audit-unguarded-external-calls file)))
            (should (>= issues-before 1)))
          ;; Run the fixer
          (let ((fixed (gptel-auto-workflow--fix-unguarded-external-calls file)))
            (should (= fixed 1)))
          ;; Verify it's now guarded
          (let ((issues-after (gptel-auto-workflow--audit-unguarded-external-calls file)))
            (should (= issues-after 0)))
          ;; Verify the fix is correct
          (let ((fixed-content (with-temp-buffer
                                 (insert-file-contents file)
                                 (buffer-string))))
            (should (string-match-p "fboundp.*gptel-agent-read-file" fixed-content))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fixer-skips-already-guarded ()
  "Auto-fixer doesn't double-guard already guarded calls."
  (let* ((content
          "(defun load-skill (file)
  (when (fboundp 'gptel-agent-read-file)
    (let ((parsed (gptel-agent-read-file file)))
      parsed)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-unguarded-external-calls file)))
          (should (= fixed 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 6: Entry point function ──

(ert-deftest test-self-heal-semantic/entry-point-runs ()
  "gptel-auto-workflow--self-heal-semantic can be called as entry point."
  (let ((result (gptel-auto-workflow--self-heal-semantic)))
    (should result)
    (should (plist-get result :total-issues))
    (should (numberp (plist-get result :files-checked)))))

;; ── Test 12: Fixer registry data-driven dispatch ──

(ert-deftest test-self-heal-semantic/fixer-registry-defined ()
  "The fixer registry is defined with all auto-fixable issue types."
  (should (assq 'excessive-blank-lines gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'unguarded-external-call gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'missing-provide gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'unbalanced-parens gptel-auto-workflow--semantic-fixer-alist)))

(ert-deftest test-self-heal-semantic/fixer-entries-are-functions ()
  "Each fixer in the registry must be a function symbol."
  (dolist (entry gptel-auto-workflow--semantic-fixer-alist)
    (let ((fixer (cdr entry)))
      (should (symbolp fixer))
      (should (fboundp fixer)))))

;; ── Test 13: condition-case unbound err detection ──

(ert-deftest test-self-heal-semantic/detects-condition-case-unbound-err ()
  "Detects condition-case handlers that reference err without binding it.
Bug: '(error) (uses err)' — handler doesn't bind err, so reference is void."
  (let* ((content
          "(defun foo ()\n  (condition-case nil\n      (do-something)\n    (error\n      (message \"failed: %s\" (error-message-string err)))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-condition-case-bound-err ()
  "Files with properly bound err are clean."
  (let* ((content
          "(defun foo ()\n  (condition-case nil\n      (do-something)\n    (error err\n      (message \"failed: %s\" (error-message-string err)))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-condition-case-no-err-ref ()
  "Files with no err reference in handler are clean."
  (let* ((content
          "(defun foo ()\n  (condition-case nil\n      (do-something)\n    (error\n      (message \"failed\"))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 13b: Real-world patterns from recovery.el ──

(ert-deftest test-self-heal-semantic/detects-recovery-condition-case-nil-err ()
  "Detects the exact pattern found in gptel-auto-workflow-recovery.el:
condition-case nil with (error-message-string err) in handler."
  (let* ((content
          "(defun gptel-recovery-clean ()\n  (condition-case nil\n      (delete-directory dir 'recursive)\n    (error\n     (message \"[recovery] Failed: %s\" (error-message-string err)))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/detects-circuit-breaker-condition-case-nil-err ()
  "Detects the exact pattern found in gptel-ext-circuit-breaker.el:
condition-case nil with err reference in handler."
  (let* ((content
          "(defun gptel-circuit-load ()\n  (condition-case nil\n      (json-read)\n    (error\n     (message \"[circuit-breaker] Failed: %s\" err))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 13c: Auto-fixer for condition-case-unbound-err ──

(ert-deftest test-self-heal-semantic/fixes-condition-case-unbound-err ()
  "Auto-fixer changes condition-case nil → err when handler references err."
  (let* ((content
          "(defun foo ()\n  (condition-case nil\n      (do-something)\n    (error\n      (message \"failed: %s\" err))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-condition-case-unbound-err file)))
            (should (= fixed 1)))
          ;; Verify the fix was applied
          (let ((fixed-content (with-temp-buffer
                                 (insert-file-contents file)
                                 (buffer-string))))
            (should (string-match-p "condition-case err" fixed-content))
            (should-not (string-match-p "condition-case nil" fixed-content)))
          ;; Verify audit no longer flags it
          (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
            (should (= issues 0))))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 14: Risk node detection (TSP-inspired) ──

(ert-deftest test-self-heal-semantic/detects-risk-node-resource ()
  "Detects resource allocation without cleanup (risk node).
Inspired by TSP paper: fine-grained risk nodes where failures emerge."
  (let* ((content
          "(defun foo ()\n  (let ((f (make-temp-file \"test-\")))\n    (message \"Created: %s\" f)\n    f))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/detects-risk-node-api ()
  "Detects external API calls without error handling (risk node)."
  (let* ((content
          "(defun foo ()\n  (shell-command-to-string \"ls -la\"))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-risk-node-with-cleanup ()
  "Files with proper cleanup are clean (no risk node)."
  (let* ((content
          "(defun foo ()\n  (let ((f (make-temp-file \"test-\")))\n    (unwind-protect\n        (message \"Using: %s\" f)\n      (delete-file f))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/clean-risk-node-with-error-handling ()
  "Files with proper error handling are clean (no risk node)."
  (let* ((content
          "(defun foo ()\n  (condition-case err\n      (shell-command-to-string \"ls -la\")\n    (error (message \"failed: %s\" err))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/skip-top-level-defvar-risk-node ()
  "Top-level defvar with hash-table should NOT be flagged as risk node.
Top-level forms are persistent caches, not temporary resources.
Regression: the check was finding 331 false positives on top-level defvars."
  (let* ((content
          "(defvar my-cache (make-hash-table :test 'equal)\n  \"Persistent cache for X.\")\n\n(defun foo ()\n  (gethash 'key my-cache))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (gptel-auto-workflow--audit-risk-nodes file)
          ;; Check that no issue was actually recorded in the log
          (should (= (length gptel-auto-workflow--semantic-audit-log) 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 15: Condition-case unbound err audit ──

(ert-deftest test-self-heal-semantic/condition-case-unbound-err-audit-positive ()
  "Audit finds condition-case with nil binding that references err."
  (let* ((content "(defun foo () (condition-case nil (risky-op) (error (message \"X: %s\" (error-message-string err)))))"
)
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
            (should (= issues 1))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/condition-case-unbound-err-audit-negative ()
  "Audit does NOT flag condition-case that already binds err."
  (let* ((content "(defun foo () (condition-case err (risky-op) (error (message \"X: %s\" (error-message-string err)))))"
)
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-condition-case-unbound-err file)))
            (should (= issues 0))))
      (test-self-heal-semantic--cleanup file))))



(ert-deftest test-self-heal-semantic/no-fix-when-already-binds-err ()
  "Fixer is idempotent: does not change condition-case that already binds err."
  (let* ((content "(defun foo () (condition-case err (risky-op) (error (message \"X: %s\" (error-message-string err)))))"
)
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (should (= (gptel-auto-workflow--fix-condition-case-unbound-err file) 0))
          (let ((unchanged (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))))
            (should (string= unchanged content))))
      (test-self-heal-semantic--cleanup file))))

(provide 'test-self-heal-semantic)
;;; test-self-heal-semantic.el ends here

(provide 'test-self-heal-semantic)
;;; test-self-heal-semantic.el ends here
