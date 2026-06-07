;;; test-ontology-predict-threshold.el --- Tests for prediction threshold -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-auto-workflow-ontology-predict)

(ert-deftest ontology-predict/threshold-allows-new-experiments ()
  "When no historical data exists, prediction should allow experiments to run."
  (cl-letf (((symbol-function 'gptel-auto-workflow--predict-outcome)
             (lambda (_strategy _target)
               ;; Simulate a value very close to threshold
               0.149)))
    (let ((result (gptel-auto-workflow--should-run-experiment-p "test-strategy" "test-target")))
      ;; This should run because 0.149 rounds to 0.15
      (should result))))

(provide 'test-ontology-predict-threshold)
