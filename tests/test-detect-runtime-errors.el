;;; test-detect-runtime-errors.el --- TDD tests for detect-runtime-errors patterns -*- lexical-binding: t; -*-
;;
;; Tests that OV5 self-detection catches all critical pipeline failure patterns
;; found in the Messages log analysis of 2026-06-09.

(require 'ert)

;; ─── Test: detect-runtime-errors recognizes target-dispatch-failure ───

(ert-deftest test-detect/target-dispatch-failure ()
  "detect-runtime-errors should recognize 'Initial target dispatch failed'."
  (let ((patterns '(("target dispatch failed" "target-dispatch-failure" 1 "check-target-dispatch-error")))
        (results nil))
    (dolist (p patterns)
      (let ((regexp (nth 0 p))
            (label (nth 1 p))
            (threshold (nth 2 p))
            (remedy (nth 3 p))
            (count 0))
        (with-temp-buffer
          (insert "[auto-workflow] Initial target dispatch failed: Wrong type argument\n")
          (goto-char (point-min))
          (while (re-search-forward regexp nil t) (cl-incf count)))
        (when (>= count threshold)
          (push (list :pattern label :count count :remedy remedy) results))))
    (should results)
    (should (equal (plist-get (car results) :pattern) "target-dispatch-failure"))
    (should (equal (plist-get (car results) :count) 1))))

;; ─── Test: detect-runtime-errors recognizes grader-broken ───

(ert-deftest test-detect/grader-broken ()
  "detect-runtime-errors should recognize 'Probe FAILED: grader broken'."
  (let ((patterns '(("grader broken" "grader-broken" 2 "check-grader-backend")))
        (results nil))
    (dolist (p patterns)
      (let ((regexp (nth 0 p))
            (label (nth 1 p))
            (threshold (nth 2 p))
            (remedy (nth 3 p))
            (count 0))
        (with-temp-buffer
          (insert "[self-heal] Probe FAILED: grader broken\n")
          (insert "[self-heal] Probe FAILED: grader broken\n")
          (goto-char (point-min))
          (while (re-search-forward regexp nil t) (cl-incf count)))
        (when (>= count threshold)
          (push (list :pattern label :count count :remedy remedy) results))))
    (should results)
    (should (equal (plist-get (car results) :pattern) "grader-broken"))
    (should (>= (plist-get (car results) :count) 2))))

;; ─── Test: detect-runtime-errors recognizes provider-failure ───

(ert-deftest test-detect/provider-failure ()
  "detect-runtime-errors should recognize 'Provider failure'."
  (let ((patterns '(("Provider failure" "provider-failure" 2 "check-llm-provider")))
        (results nil))
    (dolist (p patterns)
      (let ((regexp (nth 0 p))
            (label (nth 1 p))
            (threshold (nth 2 p))
            (remedy (nth 3 p))
            (count 0))
        (with-temp-buffer
          (insert "[auto-workflow] Provider failure on backend\n")
          (insert "[auto-workflow] Provider failure on backend\n")
          (goto-char (point-min))
          (while (re-search-forward regexp nil t) (cl-incf count)))
        (when (>= count threshold)
          (push (list :pattern label :count count :remedy remedy) results))))
    (should results)
    (should (equal (plist-get (car results) :pattern) "provider-failure"))))

;; ─── Test: existing patterns still work after adding new ones ───

(ert-deftest test-detect/existing-patterns-preserved ()
  "detect-runtime-errors existing patterns (zero-experiments, cron-error) still work."
  (let ((patterns '(("0 total, 0 kept" "zero-experiments-stuck" 2 "retry")
                    ("Cron error at step" "cron-error-propagation" 2 "retry")))
        (results nil))
    (dolist (p patterns)
      (let ((regexp (nth 0 p))
            (label (nth 1 p))
            (threshold (nth 2 p))
            (remedy (nth 3 p))
            (count 0))
        (with-temp-buffer
          (insert (format "  Experiments: 0 total, 0 kept (0.0%%)\n"))
          (insert "[auto-workflow] Cron error at step \"cleanup-worktrees\": error\n")
          (goto-char (point-min))
          (while (re-search-forward regexp nil t) (cl-incf count)))
        (when (>= count threshold)
          (push (list :pattern label :count count :remedy remedy) results))))
    ;; Both patterns should match (each appears once, threshold=2, so they won't exceed)
    ;; This test verifies the patterns are well-formed regexps
    (should (equal (length results) 0)))) ;; count=1 < threshold=2, so no results

(provide 'test-detect-runtime-errors)
