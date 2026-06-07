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
  "Predicted values below threshold should be skipped most of the time,
but exploration allows some through to prevent cold-start death spiral."
  (let ((counter 0))
    (cl-letf (((symbol-function 'gptel-auto-workflow--predict-outcome)
               (lambda (_strategy _target) 0.05))
              ;; Mock random: first 3 calls return 0 (explore → run),
              ;; rest return most-positive-fixnum (skip).
              ((symbol-function 'random)
               (lambda (&rest _)
                 (setq counter (1+ counter))
                 (if (<= counter 3) 0 most-positive-fixnum))))
      ;; With 15% exploration, most should be skipped but some run
      (let ((runs 0))
        (dotimes (_ 20)
          (when (gptel-auto-workflow--should-run-experiment-p "test-strategy" "test-target")
            (setq runs (1+ runs))))
        ;; At least 1 out of 20 should run with 15% exploration
        (should (>= runs 1))
        ;; But most should be skipped (at least 10 out of 20)
        (should (>= (- 20 runs) 10))))))

(ert-deftest ontology-predict/precision-near-threshold ()
  "Predicted values near threshold should not be incorrectly skipped."
  (cl-letf (((symbol-function 'gptel-auto-workflow--predict-outcome)
             (lambda (_strategy _target)
               ;; Return a value that rounds to 0.15 but is slightly less
               0.14999999999999999)))
    (let ((result (gptel-auto-workflow--should-run-experiment-p "test-strategy" "test-target")))
      (should result))))

(provide 'test-ontology-predict)
