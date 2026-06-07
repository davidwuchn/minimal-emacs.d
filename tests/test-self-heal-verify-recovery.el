;;; test-self-heal-verify-recovery.el --- Tests for self-heal verify-recovery -*- lexical-binding: t; -*-
;;
;; Verifies the verify-recovery function handles the 0→0 case using
;; secondary health signals (grader failures, timeouts) — not just keep-rate.
;; Bug fixed: PENDING remediations were never resolved when keep-rate stayed
;; at 0% across runs (e.g. 0% → 0% with fewer grader failures).

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Mock required variables/functions used by verify-recovery
(defvar gptel-auto-workflow--last-remediation nil)
(defvar gptel-auto-workflow--consecutive-failed-remediations 0)

;; Load the real function under test FIRST
(load-file (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el"
                             default-directory))

;; Mock health value used by tests (set inside test, read by mock function)
(defvar test-verify-recovery--mock-health nil)

;; Use cl-letf to mock the function dynamically during each test.
;; This avoids issues where other test files re-load the evolution file
;; and overwrite any defun-based mock.
(defun test-verify-recovery--with-mock (body-fn)
  "Run BODY-FN with `gptel-auto-workflow--check-pipeline-health' mocked."
  (declare-function gptel-auto-workflow--check-pipeline-health
                   "gptel-auto-workflow-evolution")
  (cl-letf (((symbol-function 'gptel-auto-workflow--check-pipeline-health)
             (lambda (&optional _)
               test-verify-recovery--mock-health)))
    (funcall body-fn)))

(defun test-verify-recovery--reset ()
  (setq gptel-auto-workflow--last-remediation nil
        gptel-auto-workflow--consecutive-failed-remediations 0
        test-verify-recovery--mock-health nil))

(defmacro test-verify-recovery--with-cleanup (&rest body)
  "Run BODY after resetting state; ensure cleanup runs even on failure."
  `(progn
     (test-verify-recovery--reset)
     (unwind-protect
         (test-verify-recovery--with-mock (lambda () ,@body))
       (test-verify-recovery--reset))))

(ert-deftest test-verify-recovery/0-to-0-with-fewer-failures-marks-effective ()
  "When keep-rate stays 0% but grader failures drop, mark as effective.
This is the bug: previously, 0→0 with any signal never marked remediation
as effective, so PENDING accumulated forever."
  (test-verify-recovery--with-cleanup
   (setq gptel-auto-workflow--last-remediation
         (list :timestamp 1000.0
               :diagnosis "grader-destroying-experiments"
               :remedy "grader-timeout=900"
               :before-rate 0.0
               :verified-p nil))
   ;; 10 experiments, 0 kept, 1 grader failure (was 6+) — significant drop
   (setq test-verify-recovery--mock-health
         (list :healthy-p nil
               :diagnosis "grader-destroying-experiments"
               :keep-rate 0.0
               :grader-failures 1
               :timeouts 0
               :total 10))
   (gptel-auto-workflow--verify-recovery)
   (should (eq (plist-get gptel-auto-workflow--last-remediation :verified-p) t))
   (should (= (plist-get gptel-auto-workflow--last-remediation :after-rate) 0.0))))

(ert-deftest test-verify-recovery/0-to-0-still-both-bad-marks-failed ()
  "When keep-rate stays 0% AND all signals are still bad, mark as failed."
  (test-verify-recovery--with-cleanup
   (setq gptel-auto-workflow--last-remediation
         (list :timestamp 1000.0
               :diagnosis "grader-destroying-experiments"
               :remedy "grader-timeout=900"
               :before-rate 0.0
               :verified-p nil))
   ;; 10 experiments, 0 kept, 8 grader failures — still broken
   (setq test-verify-recovery--mock-health
         (list :healthy-p nil
               :diagnosis "grader-destroying-experiments"
               :keep-rate 0.0
               :grader-failures 8
               :timeouts 1
               :total 10))
   (gptel-auto-workflow--verify-recovery)
   (should (eq (plist-get gptel-auto-workflow--last-remediation :verified-p) nil))
   (should (= gptel-auto-workflow--consecutive-failed-remediations 1))))

(ert-deftest test-verify-recovery/rate-improved-marks-effective ()
  "When keep-rate improves from 5% to 20%, mark as effective (basic case)."
  (test-verify-recovery--with-cleanup
   (setq gptel-auto-workflow--last-remediation
         (list :timestamp 1000.0
               :diagnosis "hypotheses-poor-quality"
               :remedy "max-exp/target=2"
               :before-rate 0.05
               :verified-p nil))
   (setq test-verify-recovery--mock-health
         (list :healthy-p t
               :diagnosis nil
               :keep-rate 0.20
               :grader-failures 0
               :timeouts 0
               :total 10))
   (gptel-auto-workflow--verify-recovery)
   (should (eq (plist-get gptel-auto-workflow--last-remediation :verified-p) t))
   (should (= (plist-get gptel-auto-workflow--last-remediation :after-rate) 0.20))))

(provide 'test-self-heal-verify-recovery)
;;; test-self-heal-verify-recovery.el ends here
