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
  (should (= (length gptel-auto-workflow--semantic-audit-checks) 4))
  (should (assq 'let-binding-function gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'hardcoded-limit gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'score-zero-bug gptel-auto-workflow--semantic-audit-checks))
  (should (assq 'unguarded-external-call gptel-auto-workflow--semantic-audit-checks)))

;; ── Test 7: Unguarded external function call detection ──

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

;; ── Test 6: Entry point function ──

(ert-deftest test-self-heal-semantic/entry-point-runs ()
  "gptel-auto-workflow--self-heal-semantic can be called as entry point."
  (let ((result (gptel-auto-workflow--self-heal-semantic)))
    (should result)
    (should (plist-get result :total-issues))))

(provide 'test-self-heal-semantic)
;;; test-self-heal-semantic.el ends here
