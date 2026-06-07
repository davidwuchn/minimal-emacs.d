;;; test-ontology-predict.el --- Tests for ontology prediction -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-auto-workflow-ontology-predict)

(ert-deftest ontology-predict/above-threshold ()
  "Predicted values above threshold should run."
  (cl-letf (((symbol-function 'gptel-auto-workflow--predict-outcome)
             (lambda (_strategy _target) 0.25)))
    (let ((result (gptel-auto-workflow--should-run-experiment-p "test-strategy" "test-target")))
      (should result))))

(ert-deftest ontology-predict/below-threshold ()
  "Predicted values below threshold should be skipped."
  (cl-letf (((symbol-function 'gptel-auto-workflow--predict-outcome)
             (lambda (_strategy _target) 0.05)))
    (let ((result (gptel-auto-workflow--should-run-experiment-p "test-strategy" "test-target")))
      (should-not result))))

(ert-deftest ontology-predict/precision-near-threshold ()
  "Predicted values near threshold should not be incorrectly skipped."
  (cl-letf (((symbol-function 'gptel-auto-workflow--predict-outcome)
             (lambda (_strategy _target)
               ;; Return a value that rounds to 0.15 but is slightly less
               0.14999999999999999)))
    (let ((result (gptel-auto-workflow--should-run-experiment-p "test-strategy" "test-target")))
      (should result))))

(provide 'test-ontology-predict)
