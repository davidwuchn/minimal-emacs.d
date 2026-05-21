;;; test-gptel-auto-workflow-ontology-predict.el --- Ontology prediction tests -*- lexical-binding: t; -*-

;;; Commentary:

;; TDD tests for ontology-based experiment outcome prediction.
;; Verifies prediction accuracy, anti-pattern detection, and target saturation.

;;; Code:

(require 'ert)

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-ontology-predict.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── Prediction Core Tests ───

(ert-deftest regression/ontology-predict/no-data-returns-fifty-fifty ()
  "When no data, prediction should be 0.5 (neutral)."
  (let ((mock-ontology '(:classes () :instances ()))
        (mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((predicted (gptel-auto-workflow--predict-outcome "any-strat" "any-target")))
        (should (= predicted 0.5))))))

(ert-deftest regression/ontology-predict/strategy-rate-only ()
  "Strategy keep-rate should influence prediction."
  (let ((mock-ontology
         '(:classes ((:name "good-strat" :keep-rate 0.8))
           :instances ())))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      ;; Strategy-only: 0.8 * 2 / 2 = 0.8
      (let ((predicted (gptel-auto-workflow--predict-outcome "good-strat" "any-target")))
        (should (> predicted 0.75))
        (should (< predicted 0.85))))))

(ert-deftest regression/ontology-predict/pair-history-dominates ()
  "Pair history should dominate prediction (3x weight)."
  (let ((mock-ontology
         '(:classes ((:name "strat" :keep-rate 0.1))
           :instances ((:name "target" :keep-rate 0.1))))
        (mock-results
         (list
          (list :strategy "strat" :target "target" :decision "kept")
          (list :strategy "strat" :target "target" :decision "kept")
          (list :strategy "strat" :target "target" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      ;; Pair rate 1.0 * 3 + strategy 0.1 * 2 + target 0.1 * 1 = 3.3 / 6 = 0.55
      (let ((predicted (gptel-auto-workflow--predict-outcome "strat" "target")))
        (should (> predicted 0.5))))))

;; ─── Experiment Filtering Tests ───

(ert-deftest regression/ontology-predict/should-run-above-threshold ()
  "Experiment above threshold should be approved."
  (let ((mock-ontology
         '(:classes ((:name "good-strat" :keep-rate 0.9))
           :instances ((:name "good-target" :keep-rate 0.9)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      (should (gptel-auto-workflow--should-run-experiment-p "good-strat" "good-target")))))

(ert-deftest regression/ontology-predict/should-skip-below-threshold ()
  "Experiment below threshold should be skipped."
  (let ((mock-ontology
         '(:classes ((:name "bad-strat" :keep-rate 0.05))
           :instances ((:name "bad-target" :keep-rate 0.05)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      (should-not (gptel-auto-workflow--should-run-experiment-p "bad-strat" "bad-target")))))

;; ─── Anti-Pattern Tests ───

(ert-deftest regression/ontology-predict/anti-pattern-three-failures ()
  "Three consecutive failures should trigger anti-pattern block."
  (let ((mock-results
         (list
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 3)
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 2)
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 1))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (should (gptel-auto-workflow--check-anti-pattern "strat" "target")))))

(ert-deftest regression/ontology-predict/anti-pattern-broken-by-success ()
  "Success should break anti-pattern streak."
  (let ((mock-results
         (list
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 3)
          (list :strategy "strat" :target "target" :decision "kept" :timestamp 2)
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 1))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (should-not (gptel-auto-workflow--check-anti-pattern "strat" "target")))))

;; ─── Target Saturation Tests ───

(ert-deftest regression/ontology-predict/target-saturated ()
  "Target with 10+ experiments should be saturated."
  (let ((mock-ontology
         '(:instances ((:name "old-target" :total 10 :keep-rate 0.5)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (should (gptel-auto-workflow--target-saturated-p "old-target")))))

(ert-deftest regression/ontology-predict/target-not-saturated ()
  "Target with <10 experiments should not be saturated."
  (let ((mock-ontology
         '(:instances ((:name "new-target" :total 5 :keep-rate 0.5)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (should-not (gptel-auto-workflow--target-saturated-p "new-target")))))

;; ─── Pre-Flight Integration Tests ───

(ert-deftest regression/ontology-predict/preflight-approves-good ()
  "Pre-flight should approve good strategy+target."
  (let ((mock-ontology
         '(:classes ((:name "good-strat" :keep-rate 0.9))
           :instances ((:name "good-target" :total 5 :keep-rate 0.9)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      (let ((result (gptel-auto-workflow--experiment-preflight "good-strat" "good-target")))
        (should (plist-get result :run))
        (should-not (plist-get result :reason))))))

(ert-deftest regression/ontology-predict/preflight-blocks-anti-pattern ()
  "Pre-flight should block anti-pattern even if prediction is good."
  (let ((mock-ontology
         '(:classes ((:name "strat" :keep-rate 0.9))
           :instances ((:name "target" :total 5 :keep-rate 0.9))))
        (mock-results
         (list
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 3)
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 2)
          (list :strategy "strat" :target "target" :decision "discarded" :timestamp 1))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((result (gptel-auto-workflow--experiment-preflight "strat" "target")))
        (should-not (plist-get result :run))
        (should (string-match-p "anti-pattern" (plist-get result :reason)))))))

(ert-deftest regression/ontology-predict/preflight-blocks-saturated ()
  "Pre-flight should block saturated target."
  (let ((mock-ontology
         '(:classes ((:name "strat" :keep-rate 0.9))
           :instances ((:name "target" :total 15 :keep-rate 0.9)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      (let ((result (gptel-auto-workflow--experiment-preflight "strat" "target")))
        (should-not (plist-get result :run))
        (should (string-match-p "saturated" (plist-get result :reason)))))))

(ert-deftest regression/ontology-predict/preflight-blocks-low-prediction ()
  "Pre-flight should block low prediction."
  (let ((mock-ontology
         '(:classes ((:name "bad-strat" :keep-rate 0.05))
           :instances ((:name "bad-target" :total 5 :keep-rate 0.05)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      (let ((result (gptel-auto-workflow--experiment-preflight "bad-strat" "bad-target")))
        (should-not (plist-get result :run))
        (should (string-match-p "predicted failure" (plist-get result :reason)))))))

(provide 'test-gptel-auto-workflow-ontology-predict)
;;; test-gptel-auto-workflow-ontology-predict.el ends here
