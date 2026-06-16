;;; test-gptel-auto-workflow-recovery.el --- TDD tests for recovery module -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-recovery)

(ert-deftest test-recovery/any-circuit-open-p-returns-nil-when-no-state-fn ()
  "When gptel-circuit-state is not bound, return nil (no circuits open)."
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ;; Override fboundp for gptel-circuit-state to return nil
            ((symbol-function 'gptel-circuit-state) nil))  ; unbound equivalent
    ;; Use fmakunbound to make fboundp return nil
    (fmakunbound 'gptel-circuit-state)
    (should-not (gptel-recovery--any-circuit-open-p))))

(ert-deftest test-recovery/any-circuit-open-p-returns-t-when-some-open ()
  "When at least one circuit is open, return t."
  (fmakunbound 'gptel-circuit-state)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ((symbol-function 'gptel-circuit-state)
             (lambda (comp)
               (if (eq comp 'open-comp) 'open 'closed)))
            ((symbol-value 'gptel-auto-workflow-circuit-breaker-components)
             '(open-comp closed-comp)))
    (should (gptel-recovery--any-circuit-open-p))))

(ert-deftest test-recovery/any-circuit-open-p-returns-nil-when-all-closed ()
  "When all circuits are closed, return nil."
  (fmakunbound 'gptel-circuit-state)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ((symbol-function 'gptel-circuit-state)
             (lambda (_) 'closed))
            ((symbol-value 'gptel-auto-workflow-circuit-breaker-components)
             '(comp1 comp2 comp3)))
    (should-not (gptel-recovery--any-circuit-open-p))))

(ert-deftest test-recovery/open-circuits-returns-empty-when-all-closed ()
  "When all circuits are closed, return empty list."
  (fmakunbound 'gptel-circuit-state)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ((symbol-function 'gptel-circuit-state)
             (lambda (_) 'closed))
            ((symbol-value 'gptel-auto-workflow-circuit-breaker-components)
             '(comp1 comp2)))
    (should (null (gptel-recovery--open-circuits)))))

(ert-deftest test-recovery/open-circuits-returns-only-open ()
  "When some circuits are open, return only the open ones."
  (fmakunbound 'gptel-circuit-state)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ((symbol-function 'gptel-circuit-state)
             (lambda (comp)
               (if (memq comp '(a c)) 'open 'closed)))
            ((symbol-value 'gptel-auto-workflow-circuit-breaker-components)
             '(a b c d)))
    (should (equal '(a c) (gptel-recovery--open-circuits)))))

(ert-deftest test-recovery/open-circuits-returns-nil-when-no-state-fn ()
  "When gptel-circuit-state is not bound, return nil."
  (fmakunbound 'gptel-circuit-state)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil)))
    (should (null (gptel-recovery--open-circuits)))))

(ert-deftest test-recovery/circuit-health-summary-returns-no-circuits-message ()
  "When no circuits are registered, return the empty-status message."
  (fmakunbound 'gptel-circuit-status)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ((symbol-function 'gptel-circuit-status)
             (lambda () nil)))
    (should (string= "no circuits registered"
                     (gptel-recovery--circuit-health-summary)))))

(ert-deftest test-recovery/circuit-health-summary-formats-each-circuit ()
  "When circuits exist, format each as 'comp:state(F/S)'."
  (fmakunbound 'gptel-circuit-status)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil))
            ((symbol-function 'gptel-circuit-status)
             (lambda ()
               (list (list :component 'comp-a :state 'closed
                           :total-failures 0 :total-successes 5)
                     (list :component 'comp-b :state 'open
                           :total-failures 3 :total-successes 2
                           :last-failure-msg "timeout")))))
    (let ((summary (gptel-recovery--circuit-health-summary)))
      (should (string-match-p "comp-a:closed" summary))
      (should (string-match-p "comp-b:open" summary))
      (should (string-match-p "0F/5S" summary))
      (should (string-match-p "3F/2S" summary)))))

(ert-deftest test-recovery/circuit-health-summary-returns-nil-when-no-status-fn ()
  "When gptel-circuit-status is not bound, return nil."
  (fmakunbound 'gptel-circuit-status)
  (cl-letf (((symbol-function 'gptel-recovery--ensure-loaded)
             (lambda () nil)))
    (should (null (gptel-recovery--circuit-health-summary)))))
