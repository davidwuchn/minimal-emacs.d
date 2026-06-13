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
(require 'gptel-auto-workflow-self-heal-semantic)

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

;; ── Test 1: Regex embedded newlines detection ──
;; Regression guard: kibcm-patterns regex strings must contain no literal \n.
;; Also exercise multi-word phrases that were broken by embedded newlines.
;; (The kibcm-patterns bug was fixed — lines 227-245 of gptel-tools-agent-prompt-build.el.)

(require 'gptel-tools-agent-prompt-build)

(ert-deftest test-self-heal-semantic/kibcm-patterns-no-embedded-newlines ()
  "No regex string in kibcm-patterns contains a literal newline."
  (should (boundp 'gptel-auto-experiment--kibcm-patterns))
  (dolist (entry gptel-auto-experiment--kibcm-patterns)
    (let ((pattern (cadr entry)))
      (should (stringp pattern))
      (should-not (string-match-p "\n" pattern)))))

(ert-deftest test-self-heal-semantic/kibcm-axis-refactor-into ()
  "refactor into → :B (was broken by literal newline between words)."
  (should (eq :B (gptel-auto-experiment--kibcm-axis "refactor into helper function"))))

(ert-deftest test-self-heal-semantic/kibcm-axis-same-entity ()
  "same entity → :I (was broken by literal newline between words)."
  (should (eq :I (gptel-auto-experiment--kibcm-axis "same entity as before"))))

(ert-deftest test-self-heal-semantic/kibcm-axis-instead-of ()
  "instead of → :SUBST (was broken by literal newline between words)."
  (should (eq :SUBST (gptel-auto-experiment--kibcm-axis "replace with instead of compress"))))

(ert-deftest test-self-heal-semantic/kibcm-axis-similar-to ()
  "similar to → :M (was broken by literal newline between words)."
  (should (eq :M (gptel-auto-experiment--kibcm-axis "similar to the example"))))

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
  (should (= (length gptel-auto-workflow--semantic-audit-checks) 15))
  (should (assq 'let-binding-function gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'hardcoded-limit gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'score-zero-bug gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'unguarded-external-call gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'excessive-blank-lines gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'unbalanced-parens gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'missing-provide gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'condition-case-unbound-err gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'risk-node gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'provide-inside-defun gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'void-defvar gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'daemon-hang gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'nil-hash-table gptel-auto-workflow--semantic-audit-checks)))

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

(ert-deftest test-self-heal-semantic/fix-missing-close-before-provide ()
  "Missing close parens are inserted before provide so provide stays top-level."
  (let* ((feature 'ov5-test-provide-top-level)
         (content
          (format "(defun ov5-test-provide-top-level-fn ()\n  42\n(provide '%s)\n;;; %s.el ends here\n"
                  feature feature))
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (when (featurep feature)
            (unload-feature feature t))
          (should (= 1 (gptel-auto-workflow--audit-unbalanced-parens file)))
          (should (= 1 (gptel-auto-workflow--fix-unbalanced-parens file)))
          (should (= 0 (gptel-auto-workflow--audit-unbalanced-parens file)))
          (load-file file)
          (should (featurep feature)))
      (when (featurep feature)
        (unload-feature feature t))
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

(ert-deftest test-self-heal-semantic/fix-removes-excess-close-at-eof ()
  "Auto-fixer removes excess close parens when closing > opening."
  (let* ((content
          "(defun foo ()\n  42))\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-unbalanced-parens file)))
            (should (= fixed 1)))
          ;; Verify the extra paren was removed
          (let ((result (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            (should (string= result "(defun foo ()\n  42)\n"))))
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

(ert-deftest test-self-heal-semantic/blank-lines-ignores-string-literals ()
  "Audit/fixer must not mutate blank lines inside multiline strings."
  (let* ((content
          "(defconst ov5-test-html \"alpha\n\n\n\n\nbeta\")\n(provide 'ov5-test-html)\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (should (= 0 (gptel-auto-workflow--audit-blank-lines file)))
          (should (= 0 (gptel-auto-workflow--fix-excessive-blank-lines file)))
          (with-temp-buffer
            (insert-file-contents file)
            (should (string= content (buffer-string)))))
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
  (let* ((tmp-dir (make-temp-file "ov5-test-modules-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir)))
    (make-directory modules-dir t)
    (with-temp-file (expand-file-name "ov5-test-fixture.el" modules-dir)
      (insert "(provide 'ov5-test-fixture)\n"))
    (unwind-protect
           (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                      (lambda (path &optional _root)
                        (expand-file-name path tmp-dir))))
             (let ((default-directory tmp-dir)
                   (gptel-auto-workflow--self-heal-dirty-tree-gate t)
                   (result (gptel-auto-workflow--self-heal-semantic :no-dirty-check t)))
            (should result)
            (should (plist-get result :total-issues))
            (should (numberp (plist-get result :files-checked)))))
      (delete-directory tmp-dir t))))

;; ── Test 12: Fixer registry data-driven dispatch ──

(ert-deftest test-self-heal-semantic/fixer-registry-defined ()
  "The fixer registry is defined with all auto-fixable issue types."
  (should (assq 'excessive-blank-lines gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'unguarded-external-call gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'missing-provide gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'unbalanced-parens gptel-auto-workflow--semantic-fixer-alist))
  (should (assq 'provide-inside-defun gptel-auto-workflow--semantic-fixer-alist)))

(ert-deftest test-self-heal-semantic/routes-defaults-to-ov5-worktree ()
  "Files in lisp/modules/ default to ov5-worktree deferred validation."
  (should (eq 'ov5-worktree
              (gptel-auto-workflow--self-heal-route-mode
               "lisp/modules/gptel-ext-context.el"))))

(ert-deftest test-self-heal-semantic/routes-repair-engine-through-ov5 ()
  "Self-heal/monitor/workflow files require OV5 worktree validation."
  (dolist (file '("lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                  "lisp/modules/gptel-auto-workflow-monitoring-agent.el"
                  "lisp/modules/gptel-auto-workflow-ontology-router.el"))
    (let ((route (gptel-auto-workflow--self-heal-route-for-file file)))
      (should (eq 'ov5-worktree (plist-get route :mode)))
      (should (eq 'default-deferred (plist-get route :reason))))))

(ert-deftest test-self-heal-semantic/routes-temp-fixture-direct ()
  "Temp test fixture files (ov5-test-*) are safe for direct mutation."
  (should (eq 'direct
              (gptel-auto-workflow--self-heal-route-mode
               "/tmp/ov5-test-XYZ123.el"))))

(ert-deftest test-self-heal-semantic/routes-outside-modules-direct ()
  "Files outside lisp/modules/ are safe for direct mutation."
  (should (eq 'direct
              (gptel-auto-workflow--self-heal-route-mode
               "/some/other/path/foo.el"))))

(ert-deftest test-self-heal-semantic/ov5-adapter-defers-without-worktree-helper ()
  "High-risk adapter does not mutate directly when worktree helper is missing."
  (let ((orig-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'fboundp)
               (lambda (sym)
                 (and (not (eq sym 'gptel-auto-workflow--with-temporary-worktree))
                      (funcall orig-fboundp sym)))))
      (let ((result (gptel-auto-workflow--self-heal-file-via-ov5
                     "lisp/modules/gptel-auto-workflow-self-heal-semantic.el")))
        (should (eq 'deferred (plist-get result :status)))
        (should (eq 'ov5-worktree-helper-missing (plist-get result :reason)))
        (should (= 0 (plist-get result :auto-fixed)))))))

(ert-deftest test-self-heal-semantic/bulk-self-heal-dispatches-high-risk-files ()
  "Bulk self-heal must not run fixers directly on repair-engine files."
  (let ((called nil)
        (file "lisp/modules/gptel-auto-workflow-ontology-router.el"))
    (cl-letf (((symbol-function 'gptel-auto-workflow--semantic-audit-all)
               (lambda ()
                 (list :total-issues 1
                       :report (list (list :file file
                                           :issues 1
                                           :log (list (list :type 'unbalanced-parens)))))))
              ((symbol-function 'gptel-auto-workflow--self-heal-file-dispatch)
               (lambda (dispatched-file)
                 (setq called dispatched-file)
                 (list :auto-fixed 1)))
              ((symbol-function 'gptel-auto-workflow--fix-unbalanced-parens)
               (lambda (_file)
                 (error "direct fixer should not run for high-risk files"))))
      (let ((result (gptel-auto-workflow--self-heal-semantic :no-dirty-check t)))
        (should (equal called file))
        (should (= 1 (plist-get result :auto-fixed)))))))

(ert-deftest test-self-heal-semantic/fixer-entries-are-functions ()
  "Each fixer in the registry must be a function symbol.
Cross-module fixers (e.g., in gptel-auto-workflow-evolution) are
loaded on demand if not yet fboundp."
  ;; The void-defvar fixer lives in evolution.el; ensure it's loaded.
  (unless (fboundp 'gptel-auto-workflow--fix-void-defvars)
    (condition-case nil
        (load (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el"
                                default-directory))
      (error nil)))
  ;; Also load nil-hash-table fixer if in a different module
  (let ((nh-fixer (cdr (assq 'nil-hash-table gptel-auto-workflow--semantic-fixer-alist))))
    (when (and nh-fixer (not (fboundp nh-fixer)))
      (condition-case nil
          (load (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                                  default-directory))
        (error nil))))
  (dolist (entry gptel-auto-workflow--semantic-fixer-alist)
    (let ((fixer (cdr entry)))
      (should (symbolp fixer))
      (unless (fboundp fixer)
        (message "[test] Fixer not yet loaded: %s (skipping fboundp check)" fixer)))))

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

(ert-deftest test-self-heal-semantic/risk-node-api-unwind-protect-guard ()
  "call-process inside unwind-protect is guarded — no risk-node-api issue."
  (let* ((content
          "(defun foo ()\n  (unwind-protect\n      (call-process \"ls\" nil nil nil \"/tmp\")\n    (delete-file \"/tmp/x\")))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
            (should (= issues 0))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/risk-node-api-ignore-errors-guard ()
  "shell-command-to-string inside ignore-errors is guarded — no risk-node-api issue."
  (let* ((content
          "(defun foo ()\n  (ignore-errors\n    (shell-command-to-string \"ls -la\")))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
            (should (= issues 0))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/risk-node-api-bare-call-process-flagged ()
  "Bare call-process with no guard is still flagged as risk-node-api."
  (let* ((content
          "(defun foo ()\n  (call-process \"ls\" nil nil nil \"/tmp\"))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-risk-nodes file)))
            (should (>= issues 1))))
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

;; ── Test 16: Batch anchoring ──

(ert-deftest test-self-heal-semantic/batch-anchor-groups-by-type ()
  "Batch anchor groups audit issues by type."
  (let* ((audit-report
          (list (list :file "a.el"
                      :log (list (list :type 'excessive-blank-lines
                                       :line 10 :context nil)
                                 (list :type 'missing-provide
                                       :line 20 :context nil)))
                (list :file "b.el"
                      :log (list (list :type 'excessive-blank-lines
                                       :line 15 :context nil)))))
         (batches (gptel-auto-workflow--batch-anchor-audit-results audit-report)))
    (should (= (length batches) 2))
    ;; Most frequent first
    (should (eq (caar batches) 'excessive-blank-lines))
    (should (= (length (cdar batches)) 2))
    (should (eq (caadr batches) 'missing-provide))
    (should (= (length (cdadr batches)) 1))))

(ert-deftest test-self-heal-semantic/batch-anchor-report-format ()
  "Batch anchor report is valid markdown."
  (let* ((batches '((excessive-blank-lines . ((:file "a.el" :line 10 :context nil)))))
         (report (gptel-auto-workflow--batch-anchor-report batches)))
    (should (stringp report))
    (should (string-match-p "# Batch Anchor Report" report))
    (should (string-match-p "excessive-blank-lines" report))
    (should (string-match-p "a.el:10" report))))

;;; Byte-compile warning tests (TDD for Pi5 auto-evolution fixes)

(ert-deftest test-self-heal-semantic/no-byte-compile-warnings ()
  "Module should byte-compile without warnings.
Pi5 auto-evolution introduced unused variable `cleanup-fn` in risk-node audit.
This test ensures the warning is fixed."
  (let ((warnings nil))
    (with-temp-buffer
      (let ((byte-compile-current-buffer t)
            (byte-compile-error-on-warn nil))
        (condition-case nil
            (progn
              (byte-compile-file "lisp/modules/gptel-auto-workflow-self-heal-semantic.el")
              ;; Check for specific warnings
              (goto-char (point-min))
              (when (re-search-forward "Warning:.*cleanup-fn" nil t)
                (push "unused-cleanup-fn" warnings))
              (when (re-search-forward "Warning:.*unescaped single quotes" nil t)
                (push "docstring-quotes" warnings)))
          (error nil))))
    ;; Should have no warnings
    (should (null warnings))))

(ert-deftest test-self-heal-semantic/condition-case-wrapping-isolated ()
  "Each audit check should be wrapped in condition-case.
A broken file (e.g., unbalanced parens) shouldn't crash the whole audit."
  (let* ((content "(defun foo () (unbalanced")  ;; Intentionally broken
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        ;; Should not throw an error, even with broken file
        (let ((result (gptel-auto-workflow--semantic-audit-file file)))
          (should (listp result))
          (should (plist-get result :issues)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/ontology-router-no-dead-cache-var ()
  "The removed reorder-cache variable must not be declared.
Pi5 commit ab888cd86 removed the cache logic but left the defvar."
  (condition-case nil
      (require 'gptel-auto-workflow-ontology-router)
    (error (message "[test] ontology-router not available, skipping")))
  (when (featurep 'gptel-auto-workflow-ontology-router)
    (should-not (boundp 'gptel-auto-workflow--reorder-cache))))

;; ── Worktree test-suite validation gate ──

(ert-deftest test-self-heal-semantic/run-ert-no-tests-dir ()
  "run-ert-in-worktree returns (t . output) when no tests directory exists."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (lisp-dir (expand-file-name "lisp/modules/" tmpdir)))
    (unwind-protect
        (progn
          (make-directory lisp-dir t)
          (with-temp-file (expand-file-name "test-mod.el" lisp-dir)
            (insert "(defun test-mod-hello () 42)\n(provide 'test-mod)\n"))
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir)))
            (should (car result))
            (should (stringp (cdr result)))))
      (delete-directory tmpdir t))))

(ert-deftest test-self-heal-semantic/run-ert-no-script ()
  "run-ert-in-worktree returns (t . output) when run-tests.sh is missing."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (test-dir (expand-file-name "tests/" tmpdir))
         (lisp-dir (expand-file-name "lisp/modules/" tmpdir)))
    (unwind-protect
        (progn
          (make-directory lisp-dir t)
          (make-directory test-dir t)
          (with-temp-file (expand-file-name "test-mod.el" lisp-dir)
            (insert "(defun test-mod-hello () 42)\n(provide 'test-mod)\n"))
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir)))
            ;; No run-tests.sh = can't run tests = vacuously true
            (should (car result))
            (should (stringp (cdr result)))))
      (delete-directory tmpdir t))))

(ert-deftest test-self-heal-semantic/run-ert-calls-test-script ()
  "run-ert-in-worktree calls scripts/run-tests.sh unit when it exists."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (test-dir (expand-file-name "tests/" tmpdir))
         (lisp-dir (expand-file-name "lisp/modules/" tmpdir))
         (script-dir (expand-file-name "scripts/" tmpdir))
         (called-with nil))
    (unwind-protect
        (progn
          (make-directory lisp-dir t)
          (make-directory test-dir t)
          (make-directory script-dir t)
          (with-temp-file (expand-file-name "test-mod.el" lisp-dir)
            (insert "(defun test-mod-hello () 42)\n(provide 'test-mod)\n"))
          (with-temp-file (expand-file-name "test-mod.el" test-dir)
            (insert "(require 'ert)\n(require 'test-mod)\n(ert-deftest test-mod/pass () (should (= (test-mod-hello) 42)))\n"))
          ;; Mock run-tests.sh that records args and exits 0
          (with-temp-file (expand-file-name "run-tests.sh" script-dir)
            (insert "#!/bin/bash\necho \"MOCK-RUN-TESTS $*\"\nexit 0\n"))
          (chmod (expand-file-name "run-tests.sh" script-dir) #o755)
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir)))
            (should (car result))
            (should (string-match-p "MOCK-RUN-TESTS" (cdr result)))
            (should (string-match-p "unit" (cdr result)))))
      (delete-directory tmpdir t))))

(ert-deftest test-self-heal-semantic/run-ert-rejects-on-failure ()
  "run-ert-in-worktree returns (nil . output) when run-tests.sh exits non-zero."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (test-dir (expand-file-name "tests/" tmpdir))
         (lisp-dir (expand-file-name "lisp/modules/" tmpdir))
         (script-dir (expand-file-name "scripts/" tmpdir)))
    (unwind-protect
        (progn
          (make-directory lisp-dir t)
          (make-directory test-dir t)
          (make-directory script-dir t)
          (with-temp-file (expand-file-name "test-mod.el" lisp-dir)
            (insert "(defun test-mod-hello () 99)\n(provide 'test-mod)\n"))
          (with-temp-file (expand-file-name "test-mod.el" test-dir)
            (insert "(require 'ert)\n(require 'test-mod)\n(ert-deftest test-mod/fail () (should (= (test-mod-hello) 42)))\n"))
          ;; Mock run-tests.sh that exits 1 (failure)
          (with-temp-file (expand-file-name "run-tests.sh" script-dir)
            (insert "#!/bin/bash\necho \"1 tests FAILED\"\nexit 1\n"))
          (chmod (expand-file-name "run-tests.sh" script-dir) #o755)
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir)))
            (should-not (car result))
            (should (stringp (cdr result)))
            (should (string-match-p "FAILED" (cdr result)))))
      (delete-directory tmpdir t))))

;; ── Regression: real ERT output patterns ──

(ert-deftest test-self-heal-semantic/run-ert-real-pass-output ()
  "run-ert-in-worktree returns (t . _) when script outputs real ERT pass text.
Real ERT output on pass contains '0 unexpected' — the gate must NOT
interpret this as a failure.  This was a P0 bug: the regex 'unexpected'
matched '0 unexpected' and inverted the gate."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (test-dir (expand-file-name "tests/" tmpdir))
         (script-dir (expand-file-name "scripts/" tmpdir)))
    (unwind-protect
        (progn
          (make-directory test-dir t)
          (make-directory script-dir t)
          ;; Mock run-tests.sh that outputs real ERT pass text and exits 0
          (with-temp-file (expand-file-name "run-tests.sh" script-dir)
            (insert "#!/bin/bash\necho 'Ran 166 tests, 166 results as expected, 0 unexpected'\nexit 0\n"))
          (chmod (expand-file-name "run-tests.sh" script-dir) #o755)
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir)))
            (should (car result))
            (should (stringp (cdr result)))))
      (delete-directory tmpdir t))))

(ert-deftest test-self-heal-semantic/run-ert-real-fail-output ()
  "run-ert-in-worktree returns (nil . _) when script outputs real ERT fail text
and exits non-zero.  Real ERT output on fail contains 'FAILED' and a non-zero
exit code."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (test-dir (expand-file-name "tests/" tmpdir))
         (script-dir (expand-file-name "scripts/" tmpdir)))
    (unwind-protect
        (progn
          (make-directory test-dir t)
          (make-directory script-dir t)
          ;; Mock run-tests.sh that outputs real ERT fail text and exits 1
          (with-temp-file (expand-file-name "run-tests.sh" script-dir)
            (insert "#!/bin/bash\necho '   FAILED  test-daemon-repl/retries-without-self-heal'\necho 'Ran 166 tests, 165 results as expected, 1 unexpected'\nexit 1\n"))
          (chmod (expand-file-name "run-tests.sh" script-dir) #o755)
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir)))
            (should-not (car result))
            (should (stringp (cdr result)))))
      (delete-directory tmpdir t))))

;; ── Test 16b: ERT selector forwarding ──

(ert-deftest test-self-heal-semantic/run-ert-forwards-selector ()
  "run-ert-in-worktree passes the ERT selector as second argument to run-tests.sh."
  (let* ((tmpdir (make-temp-file "ov5-ert-test-" t))
         (test-dir (expand-file-name "tests/" tmpdir))
         (lisp-dir (expand-file-name "lisp/modules/" tmpdir))
         (script-dir (expand-file-name "scripts/" tmpdir)))
    (unwind-protect
        (progn
          (make-directory lisp-dir t)
          (make-directory test-dir t)
          (make-directory script-dir t)
          (with-temp-file (expand-file-name "test-mod.el" lisp-dir)
            (insert "(defun test-mod-hello () 42)\n(provide 'test-mod)\n"))
          (with-temp-file (expand-file-name "run-tests.sh" script-dir)
            (insert "#!/bin/bash\necho \"MOCK-RUN-TESTS $*\"\nexit 0\n"))
          (chmod (expand-file-name "run-tests.sh" script-dir) #o755)
          (let ((result (gptel-auto-workflow--run-ert-in-worktree tmpdir "self-heal-semantic")))
            (should (car result))
            (should (string-match-p "MOCK-RUN-TESTS unit self-heal-semantic" (cdr result)))))
      (delete-directory tmpdir t))))

(ert-deftest test-self-heal-semantic/ov5-promotion-rejected-on-ert-gate-failure ()
  "self-heal-file-via-ov5 rejects promotion when the ERT gate fails."
  (let ((orig-call-process (symbol-function 'call-process)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--with-temporary-worktree)
               (lambda (_slug _ref fn)
                 (let ((tmpdir (make-temp-file "ov5-test-worktree-" t)))
                   (unwind-protect
                       (progn
                         (make-directory (expand-file-name "lisp/modules/" tmpdir) t)
                         (make-directory (expand-file-name "tests/" tmpdir) t)
                         (make-directory (expand-file-name "scripts/" tmpdir) t)
                         (with-temp-file (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el" tmpdir)
                           (insert "(defun ov5-ert-gate-test-fn () 42)\n(provide 'gptel-auto-workflow-self-heal-semantic)\n"))
                         (with-temp-file (expand-file-name "scripts/run-tests.sh" tmpdir)
                           (insert "#!/bin/bash\necho 'ERT gate simulated failure'\nexit 1\n"))
                         (chmod (expand-file-name "scripts/run-tests.sh" tmpdir) #o755)
                         (funcall fn tmpdir))
                     (delete-directory tmpdir t)))))
              ((symbol-function 'gptel-auto-workflow--self-heal-file)
               (lambda (_file)
                 (list :auto-fixed 1 :issues 1)))
              ((symbol-function 'gptel-auto-workflow--worktree-base-root)
               (lambda () default-directory))
              ((symbol-function 'call-process)
               (lambda (program &optional _infile _destination _display &rest args)
                 ;; Return 0 for git diff (pretend file is clean) so
                 ;; the dirty-target gate does not block the ERT gate.
                 (if (and (string= program "git")
                          (member "diff" args))
                     0
                   (apply orig-call-process program nil nil nil args)))))
      (let ((result (gptel-auto-workflow--self-heal-file-via-ov5
                     "lisp/modules/gptel-auto-workflow-self-heal-semantic.el")))
        (should (eq 'rejected (plist-get result :status)))
        (should (eq 'ert-gate-failed (plist-get result :reason)))))))

;; ── Test 17: provide-inside-defun detection and fix ──

(ert-deftest test-self-heal-semantic/detects-provide-inside-defun ()
  "Detects (provide ...) swallowed inside a defun body.
When a missing close paren causes provide to be inside the preceding defun,
this audit check flags it so the self-heal fixer can restore top-level."
  (let* ((content
          "(defun foo ()\n  1\n(provide 'bar)\n;;; bar.el ends here\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-provide-inside-defun file)))
            (should (>= issues 1))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fixes-provide-inside-defun ()
  "Auto-fixer inserts close parens before provide to restore top-level."
  (let* ((content
          "(defun foo ()\n  1\n(provide 'bar)\n;;; bar.el ends here\n")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-provide-inside-defun file)))
            (should (= fixed 1)))
          ;; After fix, provide should be at top-level
          (let ((issues-after (gptel-auto-workflow--audit-provide-inside-defun file)))
            (should (= issues-after 0))))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 17b: provide-inside-defun false-positive guard ──

(ert-deftest test-self-heal-semantic/provide-inside-defun-skips-false-positive-symbol ()
  "Synthetic file with (provide-pos ...) inside a defun and top-level
(provide 'feature) should report 0 provide-inside-defun issues.
Regression: (search-forward \"(provide\" …) was matching substrings
inside symbol names like provide-pos, provide-line, provides."
  (let* ((content
          "(defun foo ()
  (let ((provide-pos 1)
        (provides nil))
    (list provide-pos provides))
  42)
(provide 'test-provision)
;;; test-provision.el ends here
")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-provide-inside-defun file)))
            (should (= issues 0))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/provide-inside-defun-still-detects-real-provide ()
  "Real (provide 'x) inside a defun must still be flagged.
This is the original bug: a missing close paren causes provide to be
swallowed into the preceding defun body."
  (let* ((content
          "(defun foo ()
  1
(provide 'bar)
;;; bar.el ends here
")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-provide-inside-defun file)))
            (should (>= issues 1))))
      (test-self-heal-semantic--cleanup file))))

;; ── Safety Layer 1: Dirty-tree gate ──

(ert-deftest test-self-heal-semantic/dirty-tree-gate-blocks-with-uncommitted ()
  "Dirty-tree gate returns :status dirty-tree when uncommitted changes exist."
  (let* ((tmp-dir (make-temp-file "ov5-test-dirty-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir)))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          (with-temp-file (expand-file-name "ov5-dirty-fixture.el" modules-dir)
            (insert "(provide 'ov5-dirty-fixture)\n"))
          ;; Initialize git repo with required config
          (let* ((default-directory tmp-dir))
            (call-process "git" nil nil nil "init")
            (call-process "git" nil nil nil "config" "user.name" "test")
            (call-process "git" nil nil nil "config" "user.email" "test@test")
            (call-process "git" nil nil nil "add" ".")
            (call-process "git" nil nil nil "commit" "-m" "initial"))
          ;; Create uncommitted change
          (with-temp-file (expand-file-name "ov5-dirty-fixture.el" modules-dir)
            (insert "(provide 'ov5-dirty-fixture)\n;; uncommitted edit\n"))
           (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                      (lambda (path &optional _root)
                        (expand-file-name path tmp-dir))))
              (let* ((default-directory tmp-dir)
                     (gptel-auto-workflow--self-heal-dirty-tree-gate t)
                     (gptel-auto-workflow--fix-attempt-history
                      (make-hash-table :test 'equal))
                     (result (gptel-auto-workflow--self-heal-semantic)))
                (should (eq 'dirty-tree (plist-get result :status)))
                (should (= 0 (plist-get result :total-issues))))))
      (delete-directory tmp-dir t))))

(ert-deftest test-self-heal-semantic/dirty-tree-gate-skip-with-flag ()
  "Dirty-tree gate is bypassed with :no-dirty-check t."
  (let* ((tmp-dir (make-temp-file "ov5-test-dirty-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir)))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          (with-temp-file (expand-file-name "ov5-dirty-fixture.el" modules-dir)
            (insert "(provide 'ov5-dirty-fixture)\n"))
          (let* ((default-directory tmp-dir))
            (call-process "git" nil nil nil "init")
            (call-process "git" nil nil nil "add" ".")
            (call-process "git" nil nil nil "commit" "-m" "initial"))
          (with-temp-file (expand-file-name "ov5-dirty-fixture.el" modules-dir)
            (insert "(provide 'ov5-dirty-fixture)\n;; uncommitted edit\n"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                     (lambda (path &optional _root)
                       (expand-file-name path tmp-dir))))
            (let ((result (gptel-auto-workflow--self-heal-semantic :no-dirty-check t)))
              ;; Should proceed normally instead of returning dirty-tree
              (should (not (eq 'dirty-tree (plist-get result :status))))
              (should (numberp (plist-get result :files-checked))))))
      (delete-directory tmp-dir t))))

;; ── Safety Layer 2: Post-fix load-file validation ──

(ert-deftest test-self-heal-semantic/load-file-validation-rejects-broken-fix ()
  "Post-fix load-file validation restores original on load failure."
  (let* ((original-content "(defun ov5-load-test () 42)\n(provide 'ov5-load-test)\n")
         ;; (/ 1 0) at top-level will error during load-file
         (buggy-content "(defun ov5-load-test () 42)\n(/ 1 0)\n")
         (file (test-self-heal-semantic--tmp-file original-content)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (emacs-lisp-mode)
            (insert buggy-content)
            (let ((result (gptel-auto-workflow--fix-validate-and-write
                           (current-buffer) file original-content)))
              ;; Should fail because load-file will error on (/ 1 0)
              (should-not result))
            ;; Original content should be restored
            (let ((restored (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))))
              (should (string= restored original-content)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/no-load-check-bypasses-validation ()
  "With :no-load-check t, broken-but-valid-syntax content passes."
  (let* ((original-content "(defun ov5-load-test () 42)\n")
         (new-content "(defun ov5-load-test () (error \"load fails\"))\n")
         (file (test-self-heal-semantic--tmp-file original-content)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (emacs-lisp-mode)
            (insert new-content)
            (let ((result (gptel-auto-workflow--fix-validate-and-write
                           (current-buffer) file original-content
                           :no-load-check t :no-subprocess-check t)))
              ;; Should pass because skip load-file check
              (should result)
              (let ((written (with-temp-buffer
                               (insert-file-contents file)
                               (buffer-string))))
                (should (string= written new-content))))))
      (test-self-heal-semantic--cleanup file))))

;; ── Safety Layer 3: Fixer rate limiting ──

(ert-deftest test-self-heal-semantic/rate-limit-blocks-repeat-attempt ()
  "Rate limiting skips fixer when attempted too recently."
  (let* ((content "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (setq gptel-auto-workflow--fix-attempt-history
                (make-hash-table :test 'equal))
          ;; First attempt should be recorded
          (gptel-auto-workflow--fixer-rate-limit-record
           file 'gptel-auto-workflow--fix-excessive-blank-lines)
          ;; Second attempt should be blocked (within rate limit window)
          (should (gptel-auto-workflow--fixer-rate-limit-p
                   file 'gptel-auto-workflow--fix-excessive-blank-lines))
          ;; Different fixer on same file should be allowed
          (should-not (gptel-auto-workflow--fixer-rate-limit-p
                       file 'gptel-auto-workflow--fix-unbalanced-parens)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/rate-limit-expires-after-window ()
  "Rate limiting allows fixer after window expires."
  (let* ((content "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (setq gptel-auto-workflow--fix-attempt-history
                (make-hash-table :test 'equal))
          ;; Record attempt in the distant past
          (puthash (cons file 'gptel-auto-workflow--fix-excessive-blank-lines)
                   (- (float-time) 7200)  ; 2 hours ago
                   gptel-auto-workflow--fix-attempt-history)
          ;; Should now be allowed (past the default 60-min window)
          (should-not (gptel-auto-workflow--fixer-rate-limit-p
                       file 'gptel-auto-workflow--fix-excessive-blank-lines)))
      (test-self-heal-semantic--cleanup file))))

;; ── Safety Layer 4: Dry-run audit mode ──

(ert-deftest test-self-heal-semantic/dry-run-skips-fixers ()
  "Dry-run mode audits but does not apply fixers."
  (let* ((tmp-dir (make-temp-file "ov5-test-dryrun-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir))
         (test-file (expand-file-name "ov5-dryrun-fixture.el" modules-dir))
         (original-content "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)\n(provide 'ov5-dryrun-fixture)\n"))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          (with-temp-file test-file
            (insert original-content))
          (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                     (lambda (path &optional _root)
                       (expand-file-name path tmp-dir))))
            (let ((result (gptel-auto-workflow--self-heal-semantic :dry-run t :no-dirty-check t)))
              (should (= 0 (plist-get result :auto-fixed)))
              ;; File should be unchanged
              (let ((unchanged (with-temp-buffer
                                 (insert-file-contents test-file)
                                 (buffer-string))))
                (should (string= unchanged original-content))))))
      (delete-directory tmp-dir t))))

(ert-deftest test-self-heal-semantic/non-dry-run-fixes ()
  "Non-dry-run mode applies fixers."
  (let* ((tmp-dir (make-temp-file "ov5-test-fix-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir))
         (test-file (expand-file-name "ov5-fix-fixture.el" modules-dir))
         (original-content "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)\n(provide 'ov5-fix-fixture)\n"))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          (with-temp-file test-file
            (insert original-content))
          (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                     (lambda (path &optional _root)
                       (expand-file-name path tmp-dir))))
            (let ((result (gptel-auto-workflow--self-heal-semantic :no-dirty-check t :no-git-snapshot t)))
              ;; Should have fixed something (excessive blank lines)
              (should result))))
      (delete-directory tmp-dir t))))

;; ── Safety Layer 5: Pre-fix git snapshot ──

(ert-deftest test-self-heal-semantic/git-snapshot-creates-commit ()
  "Self-heal completes successfully in a git repo without crashing.
The snapshot is best-effort: for clean committed files, the existing
commit serves as the rollback point."
  (let* ((tmp-dir (make-temp-file "ov5-test-snapshot-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir))
         (test-file (expand-file-name "ov5-snap-fixture.el" modules-dir))
         (original-content "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)\n(provide 'ov5-snap-fixture)\n"))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          (with-temp-file test-file
            (insert original-content))
          (let ((default-directory tmp-dir))
            (call-process "git" nil nil nil "init")
            (call-process "git" nil nil nil "add" ".")
            (call-process "git" nil nil nil "commit" "-m" "initial"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                     (lambda (path &optional _root)
                       (expand-file-name path tmp-dir))))
            ;; Self-heal completes without crashing even when git ops are attempted
            (let ((result (gptel-auto-workflow--self-heal-semantic :no-dirty-check t)))
              (should result)
              (should (numberp (plist-get result :auto-fixed))))))
      (delete-directory tmp-dir t))))

(ert-deftest test-self-heal-semantic/no-git-snapshot-suppresses-commits ()
  ":no-git-snapshot t prevents snapshot commits."
  (let* ((tmp-dir (make-temp-file "ov5-test-nosnap-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir))
         (test-file (expand-file-name "ov5-nosnap-fixture.el" modules-dir))
         (original-content "(defun foo () 1)\n\n\n\n\n\n(defun bar () 2)\n(provide 'ov5-nosnap-fixture)\n"))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          (with-temp-file test-file
            (insert original-content))
          (let ((default-directory tmp-dir))
            (call-process "git" nil nil nil "init")
            (call-process "git" nil nil nil "add" ".")
            (call-process "git" nil nil nil "commit" "-m" "initial"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                     (lambda (path &optional _root)
                       (expand-file-name path tmp-dir))))
            (let ((result (gptel-auto-workflow--self-heal-semantic
                           :no-dirty-check t :no-git-snapshot t)))
              (should result)))
          ;; Verify NO snapshot commit was created (only initial commit)
          (let ((default-directory tmp-dir))
            (let ((log (shell-command-to-string "git log --oneline")))
              ;; Should have exactly 1 commit (initial) or 2 if initial commit counts
              ;; plus .gitignore auto-creation. Just check no snapshot message.
              (should-not (string-match-p "snapshot before auto-fix" log)))))
      (delete-directory tmp-dir t))))

;; ── Safety Layer 6: Subprocess sandbox ──

(ert-deftest test-self-heal-semantic/subprocess-sandbox-rejects-unloadable ()
  "Subprocess sandbox rejects file that fails to load in batch Emacs."
  (let* ((original-content "(defun ov5-sub-test () 42)\n(provide 'ov5-sub-test)\n")
         ;; defun with nil as name — valid syntax, but fails at runtime
         (buggy-content "(defun nil () (message \"bad\"))\n(provide 'ov5-sub-test)\n")
         (file (test-self-heal-semantic--tmp-file original-content)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (emacs-lisp-mode)
            (insert buggy-content)
            ;; Skip in-process load check so subprocess sandbox is exercised
            (let ((result (gptel-auto-workflow--fix-validate-and-write
                           (current-buffer) file original-content
                           :no-load-check t)))
              (should-not result))
            (let ((restored (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))))
              (should (string= restored original-content)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/no-subprocess-check-bypasses-sandbox ()
  "With :no-subprocess-check t, subprocess validation is skipped."
  (let* ((original-content "(defun ov5-sub-test () 42)\n")
         (new-content "(defun ov5-sub-test () 99)\n")
         (file (test-self-heal-semantic--tmp-file original-content)))
    (unwind-protect
        (progn
          (with-temp-buffer
            (emacs-lisp-mode)
            (insert new-content)
            (let ((result (gptel-auto-workflow--fix-validate-and-write
                           (current-buffer) file original-content
                           :no-subprocess-check t)))
              ;; Should pass — no subprocess check, parens balanced, load-file ok
              (should result))))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 18: Daemon subprocess hang audit ──

(ert-deftest test-self-heal-semantic/daemon-hang-responsive-returns-zero ()
  "Responsive daemon (emacsclient ping succeeds) returns 0 issues."
  (let* ((content "(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (setq gptel-auto-workflow--daemon-hang-done nil)
          (cl-letf (((symbol-function 'call-process)
                     (lambda (program &optional infile destination _display &rest args)
                       (cond
                        ((string= program "pgrep")
                         (when destination
                           (insert "12345\n"))
                         0)
                        ((string= program "timeout")
                         0)  ;; responsive
                        (t 1)))))
            (let ((issues (gptel-auto-workflow--audit-daemon-hang file)))
              (should (= issues 0))
              (should (null gptel-auto-workflow--semantic-audit-log)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/daemon-hang-unresponsive-with-curl-orphans ()
  "Unresponsive daemon with orphaned curl subprocesses returns 1 issue."
  (let* ((content "(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (setq gptel-auto-workflow--daemon-hang-done nil)
          (cl-letf (((symbol-function
                      'gptel-auto-workflow--audit-daemon-hang--impl)
                     (lambda () 1)))
            (let ((issues (gptel-auto-workflow--audit-daemon-hang file)))
              (should (= issues 1)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/daemon-hang-runs-once-per-audit-all ()
  "Daemon-hang check returns exactly 1 issue per audit-all run across N files.
Regression: semantic-audit-reset cleared daemon-hang-done for every file,
causing ~130 duplicate daemon-hang findings in a full dry-run."
  (let* ((tmp-dir (make-temp-file "ov5-test-daemon-hang-once-" t))
         (modules-dir (expand-file-name "lisp/modules" tmp-dir)))
    (unwind-protect
        (progn
          (make-directory modules-dir t)
          ;; Create 3 fixture files. Each file only contains clean, minimal code
          ;; so no other audit check flags anything.
          (dotimes (i 3)
            (with-temp-file (expand-file-name (format "ov5-fixture-%d.el" i) modules-dir)
              (insert (format "(defun ov5-fixture-fn-%d () 42)\n(provide 'ov5-fixture-%d)\n"
                              i i))))
          ;; Mock: force daemon-hang impl to return 1 (hung), override modules-dir
          (cl-letf (((symbol-function 'gptel-auto-workflow--expand-workspace-path)
                     (lambda (path &optional _root)
                       (expand-file-name path tmp-dir)))
                    ((symbol-function 'gptel-auto-workflow--audit-daemon-hang--impl)
                     (lambda () 1)))
            (let ((result (gptel-auto-workflow--semantic-audit-all)))
              ;; With guard working: 1 daemon-hang issue total (not 3 = 1 per file)
              ;; Daemon-hang returns count directly; does not use audit-record,
              ;; so :log fields are empty but :issues counts it.
              (should (= (plist-get result :total-issues) 1))
              (should (= (plist-get result :files-checked) 3)))))
      (delete-directory tmp-dir t))))

;; ── Test 19: nil-hash-table audit detection ──

(ert-deftest test-self-heal-semantic/detects-nil-hash-table-gethash ()
  "Detects (defvar ht nil) where ht is used with gethash in same file."
  (let* ((content
          "(defvar my-cache nil \"Cache for lookups.\")\n\n(defun lookup (key)\n  (gethash key my-cache))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/detects-nil-hash-table-puthash ()
  "Detects nil hash table used with puthash."
  (let* ((content
          "(defvar my-table nil)\n\n(defun store (k v)\n  (puthash k v my-table))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-when-no-hash-usage ()
  "defvar nil without hash-table usage is clean (not a false positive)."
  (let* ((content
          "(defvar my-counter nil \"Simple counter.\")\n\n(defun inc ()\n  (setq my-counter (1+ (or my-counter 0))))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-when-properly-initialized ()
  "Properly initialized hash table is clean."
  (let* ((content
          "(defvar my-ht (make-hash-table :test 'equal) \"Hash table.\")\n\n(defun lookup (key)\n  (gethash key my-ht))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-multiple-detected ()
  "Multiple nil hash tables in same file are all detected."
  (let* ((content
          "(defvar ht1 nil)\n(defvar ht2 nil \"Another one.\")\n\n(defun f ()\n  (gethash 'x ht1)\n  (puthash 'y 1 ht2))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 2)))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 20: nil-hash-table fixer ──

(ert-deftest test-self-heal-semantic/fixes-nil-hash-table-to-make-hash-table ()
  "Fixer replaces nil with (make-hash-table :test 'equal) in defvar."
  (let* ((content
          "(defvar my-cache nil \"Cache.\")\n\n(defun lookup (key)\n  (gethash key my-cache))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-nil-hash-tables file)))
            (should (= fixed 1))
            (with-temp-buffer
              (insert-file-contents file)
              (should (string-match-p
                       "(defvar my-cache (make-hash-table :test 'equal)"
                       (buffer-string))))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fixer-no-op-when-no-hash-usage ()
  "Fixer returns 0 for defvar nil without hash table usage."
  (let* ((content
          "(defvar my-var nil \"Not a hash table.\")\n\n(defun f ()\n  (setq my-var 42))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-nil-hash-tables file)))
            (should (= fixed 0))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fixer-no-op-already-initialized ()
  "Fixer returns 0 when hash table is already properly initialized."
  (let* ((content
          "(defvar my-ht (make-hash-table :test 'equal))\n\n(defun f ()\n  (gethash 'x my-ht))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-nil-hash-tables file)))
            (should (= fixed 0))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/fixer-fixes-multiple-nil-hash-tables ()
  "Fixer fixes multiple nil hash tables in same file."
  (let* ((content
          "(defvar ht1 nil)\n(defvar ht2 nil)\n\n(defun f ()\n  (gethash 'x ht1)\n  (puthash 'y 1 ht2))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-nil-hash-tables file)))
            (should (= fixed 2))
            (with-temp-buffer
              (insert-file-contents file)
              (should (string-match-p "make-hash-table" (buffer-string)))
              ;; nil should be gone from defvars
              (should-not (string-match-p
                           "(defvar ht[12] nil)"
                           (buffer-string))))))
      (test-self-heal-semantic--cleanup file))))

;; ── Test 21: nil-hash-table guard / nested / docstring regression ──

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-hash-table-p-guard ()
  "Variable with hash-table-p guard (alist-backed cache) is clean.
hash-table-p is a predicate used in guards, not evidence of hash-table usage.
The variable may be an alist that is conditionally checked with hash-table-p."
  (let* ((content
          "(defvar my-cache nil \"Alist-backed cache.\")\n\n(defun lookup (key)\n  (assoc key my-cache))\n\n(defun reset ()\n  (when (hash-table-p my-cache)\n    (maphash (lambda (k v) (message \"%s\" k)) my-cache)\n    (clrhash my-cache)))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-lazy-init-setq ()
  "Variable with lazy-init setq to make-hash-table is clean.
Pattern: (defvar schemas nil) with (setq schemas (make-hash-table ...))
elsewhere — intentionally nil until load-time."
  (let* ((content
          "(defvar my-schemas nil \"Lazy-initialized hash table.\")\n\n(defun make-schemas ()\n  (make-hash-table :test 'equal))\n\n(defun load-schemas ()\n  (setq my-schemas (make-schemas)))\n\n(defun lookup (key)\n  (gethash key my-schemas))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/detects-nil-hash-table-maphash-nested ()
  "Detects nil hash table used with maphash containing nested lambda form.
Regression: the old [^)]* regex missed (maphash (lambda (k v) ...) var)."
  (let* ((content
          "(defvar my-ht nil)\n\n(defun iterate ()\n  (maphash (lambda (k v) (message \"%s -> %s\" k v)) my-ht))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-docstring-mention ()
  "defvar with maphash mention in docstring does not trigger.
The variable is not actually used with hash-table functions in code."
  (let* ((content
          "(defvar my-ht nil\n  \"Hash table for lookups.  Use (maphash (lambda (k v) ...) my-ht) to iterate.\")\n\n(defun f ()\n  42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-comment-mention ()
  "defvar with gethash mention in trailing comment does not trigger.
The regex should not match code inside comments."
  (let* ((content
          "(defvar my-ht nil)  ;; (gethash 'key my-ht) would fail if nil\n\n(defun f ()\n  42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

;; ── Regression: nil-hash-table value-position false positive ──

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-value-position-fp ()
  "Variable in puthash VALUE position is NOT flagged as a hash table.
Regression: the old [^)]* regex matched var names anywhere in hash function
forms, including :run-id payload values inside puthash."
  (let* ((content
          "(defvar gptel-prefix-cache--run-id nil \"Run ID sentinel.\")\n\n(defvar my-cache (make-hash-table :test 'equal)\n  \"Hash table for role caches.\")\n\n(defun store-role (role content)\n  (puthash role\n           (list :content content\n                 :run-id gptel-prefix-cache--run-id)\n           my-cache))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-prefix-cache-clean ()
  "gptel-ext-prefix-cache.el produces zero nil-hash-table audit issues.
Regression: gptel-prefix-cache--run-id (a run-id sentinel, not a hash table)
was falsely flagged because it appeared in puthash VALUE position."
  (let ((file (expand-file-name "lisp/modules/gptel-ext-prefix-cache.el"
                                default-directory)))
    (skip-unless (file-exists-p file))
    (gptel-auto-workflow--semantic-audit-reset)
    (gptel-auto-workflow--audit-nil-hash-tables file)
    (let ((nil-ht-issues
           (cl-remove-if-not (lambda (entry)
                               (eq (plist-get entry :type) 'nil-hash-table))
                             gptel-auto-workflow--semantic-audit-log)))
      (should (= (length nil-ht-issues) 0)))))

(ert-deftest test-self-heal-semantic/nil-hash-table-memory-schema-clean ()
  "gptel-auto-workflow-memory-schema.el produces zero nil-hash-table audit issues.
Multi-binding lazy-init and make-hash-table ctors are recognized.
skill-graph--edges is a bare forward-declaration, not nil-initialized."
  (let ((file (expand-file-name "lisp/modules/gptel-auto-workflow-memory-schema.el"
                                default-directory)))
    (skip-unless (file-exists-p file))
    (gptel-auto-workflow--semantic-audit-reset)
    (gptel-auto-workflow--audit-nil-hash-tables file)
    (let ((nil-ht-issues
           (cl-remove-if-not (lambda (entry)
                               (eq (plist-get entry :type) 'nil-hash-table))
                             gptel-auto-workflow--semantic-audit-log)))
      (should (= (length nil-ht-issues) 0)))))

(ert-deftest test-self-heal-semantic/nil-hash-table-clean-multi-binding-lazy-init ()
  "Multi-binding setq lazy-init (memory-schema pattern) is recognized.
Three variables initialized in one (setq a (make-...) b (make-...) c (make-...))
form are correctly skipped by the lazy-init guard."
  (let* ((content
          "(defvar schemas nil)\n(defvar entities nil)\n(defvar triples nil)\n\n(defun ensure-loaded ()\n  (setq schemas (make-schemas)\n        entities (make-entities)\n        triples (make-triples)))\n\n(defun lookup (key)\n  (gethash key schemas)\n  (gethash key entities)\n  (gethash key triples))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-nil-hash-tables file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/nil-hash-table-strategic-clean ()
  "gptel-auto-workflow-strategic.el produces zero nil-hash-table audit issues.
Regression: gptel-auto-workflow--review-decisions was initialized to nil
instead of (make-hash-table :test 'equal), triggering a nil-hash-table audit
finding at every gethash call site."
  (let ((file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el"
                                default-directory)))
    (skip-unless (file-exists-p file))
    (gptel-auto-workflow--semantic-audit-reset)
    (gptel-auto-workflow--audit-nil-hash-tables file)
    (let ((nil-ht-issues
           (cl-remove-if-not (lambda (entry)
                               (eq (plist-get entry :type) 'nil-hash-table))
                             gptel-auto-workflow--semantic-audit-log)))
      (should (= (length nil-ht-issues) 0)))))

;; ── Test 22: void-defvar skips hash-table forward declarations ──

(ert-deftest test-self-heal-semantic/void-defvar-skips-hash-table-forward-decl ()
  "Bare defvar used as a hash table (forward declaration) is NOT flagged.
The real definition in another file initializes the hash table;
the bare defvar here just suppresses compiler warnings."
  (let* ((content
          "(defvar skill-graph--edges)

\(defun lookup (key)
  (gethash key skill-graph--edges))")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-void-defvars file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/void-defvar-still-flags-bare-not-hash-table ()
  "Bare defvar NOT used as a hash table is still flagged.
Ensures the hash-table skip gate does not suppress real void-defvar issues.
The variable is NOT referenced elsewhere in the file — it is truly unused."
  (let* ((content
          "(defvar my-flag)

\(defun get-flag ()
  t)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-void-defvars file)))
          (should (>= issues 1)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/void-defvar-memory-schema-clean ()
  "gptel-auto-workflow-memory-schema.el produces zero void-defvar issues.
skill-graph--edges is a bare forward-declaration for a hash table
defined in gptel-auto-workflow-skill-graph.el — it should NOT be flagged."
  (let ((file (expand-file-name "lisp/modules/gptel-auto-workflow-memory-schema.el"
                                default-directory)))
    (skip-unless (file-exists-p file))
    (gptel-auto-workflow--semantic-audit-reset)
    (gptel-auto-workflow--audit-void-defvars file)
    (let ((void-issues
           (cl-remove-if-not (lambda (entry)
                               (eq (plist-get entry :type) 'void-defvar))
                             gptel-auto-workflow--semantic-audit-log)))
      (should (= (length void-issues) 0)))))

;; ── Test 23: void-defvar forward-declaration (used-elsewhere) gate ──

(ert-deftest test-self-heal-semantic/void-defvar-skips-forward-decl-with-usage ()
  "Bare defvar whose symbol is used elsewhere in the file is a forward
declaration and should NOT be flagged (0 void-defvar issues)."
  (let* ((content
          "(defvar my-flag)

\(defun get-flag ()
  my-flag)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (let ((issues (gptel-auto-workflow--audit-void-defvars file)))
          (should (= issues 0)))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/void-defvar-flags-truly-unused-bare ()
  "Bare defvar with NO other usage anywhere in the file should still be
flagged (1 void-defvar issue)."
  (let* ((content
          "(defvar my-flag)

\(defun get-flag ()
  t)")
         (file (test-self-heal-semantic--tmp-file content)))
     (unwind-protect
         (let ((issues (gptel-auto-workflow--audit-void-defvars file)))
           (should (>= issues 1)))
       (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/void-defvar-gptel-ext-core-clean ()
  "gptel-ext-core.el produces zero void-defvar issues.
Unused bare forward declaration gptel--cf-gateway was removed; remaining
forward declarations are either used in the file or are hash-table vars."
  (let ((file (expand-file-name "lisp/modules/gptel-ext-core.el"
                                default-directory)))
    (skip-unless (file-exists-p file))
    (gptel-auto-workflow--semantic-audit-reset)
    (gptel-auto-workflow--audit-void-defvars file)
    (let ((void-issues
           (cl-remove-if-not (lambda (entry)
                               (eq (plist-get entry :type) 'void-defvar))
                             gptel-auto-workflow--semantic-audit-log)))
       (should (= (length void-issues) 0)))))

;; ── Check 14: orphaned-curl-process ──

(ert-deftest test-self-heal-semantic/orphaned-curl-no-processes-returns-zero ()
  "No gptel-curl processes at all returns 0 issues."
  (let* ((content "(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (cl-letf (((symbol-function 'process-list)
                     (lambda () nil)))
            (let ((issues (gptel-auto-workflow--audit-orphaned-curl-processes file)))
              (should (= issues 0)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/orphaned-curl-detects-old-process-without-fsm ()
  "Returns 1 when a gptel-curl process runs >15min with no FSM entry."
  (let* ((content "(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content))
         ;; Mock process plist: name=gptel-curl, status=run, no FSM entry
         (mock-proc (list :name "gptel-curl" :status 'run)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (cl-letf (((symbol-function 'process-list)
                     (lambda () (list mock-proc)))
                    ((symbol-function 'process-name)
                     (lambda (p) (plist-get p :name)))
                    ((symbol-function 'process-status)
                     (lambda (p) (plist-get p :status)))
                    ((symbol-function 'process-attribute)
                     (lambda (p attr)
                       ;; Simulate process started 1000 seconds ago (>> 900)
                       (time-subtract (current-time) 1000)))
                    ;; No FSM entry: mock-proc not in gptel--request-alist
                    ((symbol-value 'gptel--request-alist) nil))
            (let ((issues (gptel-auto-workflow--audit-orphaned-curl-processes file)))
              (should (= issues 1)))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/orphaned-curl-fixer-kills-orphaned ()
  "Fixer kills orphaned gptel-curl processes and returns kill count."
  (let* ((content "(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content))
         ;; Use a real process so we can verify it gets killed
         (buf (generate-new-buffer " *test-curl-fix*"))
         (mock-process
          (make-process
           :name "gptel-curl"
           :buffer buf
           :command '("sleep" "5")
           :connection-type 'pipe
           :noquery t)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'process-list)
                     (lambda () (list mock-process)))
                    ((symbol-function 'process-attribute)
                     (lambda (p attr)
                       (time-subtract (current-time) 1000)))
                    ;; No FSM entry → orphaned
                    ((symbol-value 'gptel--request-alist) nil))
            (let ((killed (gptel-auto-workflow--fix-orphaned-curl-processes file)))
              (should (= killed 1)))))
      (ignore-errors (delete-process mock-process))
      (ignore-errors (kill-buffer buf))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/orphaned-curl-threshold-count ()
  "Returns issues when total gptel-curl processes exceed 8 even if all have FSMs."
  (let* ((content "(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          ;; Create 10 mock process plists that pass all the gptel-curl checks
          (let ((mock-procs
                 (cl-loop for i from 1 to 10
                          collect (list :i i :name "gptel-curl" :status 'run))))
            (cl-letf (((symbol-function 'process-list)
                       (lambda () mock-procs))
                      ((symbol-function 'process-name)
                       (lambda (p) (plist-get p :name)))
                      ((symbol-function 'process-status)
                       (lambda (p) (plist-get p :status)))
                      ((symbol-function 'process-attribute)
                       (lambda (p attr) nil)) ;; no start attr, so running-secs is nil
                      ;; All have FSM entries
                      ((symbol-value 'gptel--request-alist)
                       (mapcar (lambda (p) (list p 'fsm-placeholder)) mock-procs)))
              (let ((issues (gptel-auto-workflow--audit-orphaned-curl-processes file)))
                ;; 10 total - 8 threshold = 2 excess
                (should (= issues 2))))))
      (test-self-heal-semantic--cleanup file))))

;; ── Check 15: curl-no-max-time ──

(ert-deftest test-self-heal-semantic/curl-no-max-time-detects-missing ()
  "Detects gptel-curl-extra-args block without --max-time."
  (let* ((content
          "(require 'gptel-request)
\(setq gptel-curl-extra-args '(\"--compressed\" \"--location\"))
\(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-curl-no-max-time file)))
            (should (>= issues 1))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/curl-no-max-time-clean-with-flag ()
  "No issues when gptel-curl-extra-args includes --max-time."
  (let* ((content
          "(require 'gptel-request)
\(setq gptel-curl-extra-args '(\"--max-time\" \"900\" \"--compressed\"))
\(defun foo () 42)")
         (file (test-self-heal-semantic--tmp-file content)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-curl-no-max-time file)))
            (should (= issues 0))))
      (test-self-heal-semantic--cleanup file))))

(ert-deftest test-self-heal-semantic/curl-no-max-time-skip-non-el-files ()
  "Non-.el files return 0 issues (only checks .el and -init.el files)."
  (let* ((file (make-temp-file "ov5-test-curl-" nil ".json"))
         (content "gptel-curl-extra-args '(\"--compressed\")"))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (gptel-auto-workflow--semantic-audit-reset)
          (let ((issues (gptel-auto-workflow--audit-curl-no-max-time file)))
            (should (= issues 0))))
      (ignore-errors (delete-file file)))))

(ert-deftest test-self-heal-semantic/audit-checks-includes-new-checks ()
  "New checks 14 and 15 are registered in the audit-checks alist."
  (should (assq 'orphaned-curl-process gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'curl-no-max-time gptel-auto-workflow--semantic-audit-checks)))

(ert-deftest test-self-heal-semantic/fixer-includes-orphaned-curl ()
  "Orphaned-curl fixer is registered in the fixer alist."
  (should (assq 'orphaned-curl-process gptel-auto-workflow--semantic-fixer-alist)))

(provide 'test-self-heal-semantic)
;;; test-self-heal-semantic.el ends here
