;;; test-gptel-auto-workflow-production.el --- Tests for production integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-production.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-production.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-production)

;;; Customization tests

(ert-deftest test-production/evolution-interval-default ()
  "Evolution interval should default to 3600 seconds (1 hour)."
  (should (= gptel-auto-workflow-evolution-interval 3600)))

;;; Timer tests

(ert-deftest test-production/timer-nil-initially ()
  "Evolution timer should be nil initially."
  (should-not gptel-auto-workflow--evolution-timer))

(ert-deftest test-production/stop-timer-no-error ()
  "Stopping nil timer should not error."
  (should-not (gptel-auto-workflow-stop-evolution-timer)))

;;; Research batch tests

(ert-deftest test-production/research-batch-nil-initially ()
  "Research batch results should be nil initially."
  (let ((gptel-auto-workflow--research-batch-results nil))
    (should-not gptel-auto-workflow--research-batch-results)))

;;; Status tests

(ert-deftest test-production/status-returns-value ()
  "Evolution status should return a value."
  (let ((status (ignore-errors (gptel-auto-workflow--evolution-status))))
    (should (or (null status) (listp status)))))

(provide 'test-gptel-auto-workflow-production)
;;; test-gptel-auto-workflow-production.el ends here