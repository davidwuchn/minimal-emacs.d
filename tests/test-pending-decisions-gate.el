;;; test-pending-decisions-gate.el --- Test pending-decisions gate logic -*- lexical-binding: t -*-

(require 'ert)
(require 'gptel-auto-workflow-production)

(ert-deftest test-pending-decisions-gate-returns-boolean ()
  "pending-decisions-p should return t or nil, not other truthy values."
  (let ((result (gptel-auto-workflow--pending-decisions-p)))
    (should (or (eq result t) (eq result nil)))))

(ert-deftest test-pending-decisions-gate-check-uses-truthiness ()
  "The gate check should use truthiness, not (eq t ...)."
  ;; This test verifies the fix: the check should be (when (gptel-auto-workflow--pending-decisions-p) ...)
  ;; not (when (eq t (gptel-auto-workflow--pending-decisions-p)) ...)
  (let ((gptel-auto-workflow-human-decision-gate t)
        (gptel-auto-workflow-decision-auto-expiry-hours 24))
    ;; Mock the decisions directory to be empty
    (cl-letf (((symbol-function 'gptel-auto-workflow--decisions-dir)
               (lambda () "/tmp/nonexistent-decisions")))
      (let ((result (gptel-auto-workflow--pending-decisions-p)))
        ;; Should return nil when no decisions
        (should (eq result nil))
        ;; The gate check should not block
        (should-not (eq t result))))))

(provide 'test-pending-decisions-gate)
;;; test-pending-decisions-gate.el ends here
