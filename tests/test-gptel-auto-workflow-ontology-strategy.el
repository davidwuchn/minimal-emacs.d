;;; test-gptel-auto-workflow-ontology-strategy.el --- Ontology strategy tests -*- lexical-binding: t; -*-

;;; Commentary:

;; TDD tests for ontology-aware strategy and target selection.
;; Verifies that ontology data improves operational decisions.

;;; Code:

(require 'ert)

;; Ensure lisp/modules and subtrees are on load-path
(let ((base (file-name-directory
             (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path (expand-file-name "../lisp/modules" base))
  (add-to-list 'load-path (expand-file-name "../packages/gptel" base))
  (add-to-list 'load-path (expand-file-name "../packages/gptel-agent" base)))

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-ontology-strategy.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── Target Prioritization Tests ───

(ert-deftest regression/ontology/target-value-high-value ()
  "High-value targets should be classified correctly."
  (let ((mock-ontology
         '(:instances ((:name "lisp/foo.el" :classification "high-value" :keep-rate 0.8)
                       (:name "lisp/bar.el" :classification "low-value" :keep-rate 0.1)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (should (string= "high-value"
                       (gptel-auto-workflow--ontology-target-value "lisp/foo.el")))
      (should (string= "low-value"
                       (gptel-auto-workflow--ontology-target-value "lisp/bar.el"))))))

(ert-deftest regression/ontology/target-value-unknown ()
  "Unknown targets should return 'unknown'."
  (let ((mock-ontology '(:instances ())))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (should (string= "unknown"
                       (gptel-auto-workflow--ontology-target-value "lisp/new.el"))))))

(ert-deftest regression/ontology/filter-targets-reorders-by-value ()
  "Target filtering should reorder: high-value first, low-value last."
  (let ((mock-ontology
         '(:instances ((:name "lisp/high.el" :classification "high-value" :keep-rate 0.8)
                       (:name "lisp/moderate.el" :classification "moderate" :keep-rate 0.4)
                       (:name "lisp/low.el" :classification "low-value" :keep-rate 0.1)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (let ((filtered (gptel-auto-workflow--ontology-filter-targets
                       '("lisp/low.el" "lisp/moderate.el" "lisp/high.el"))))
        (should (string= "lisp/high.el" (car filtered)))
        (should (string= "lisp/low.el" (car (last filtered))))))))

;; ─── Strategy Selection Tests ───

(ert-deftest regression/ontology/strategy-status-effective ()
  "Effective strategies should have high status."
  (let ((mock-ontology
         '(:classes ((:name "strategy-a" :status "effective" :keep-rate 0.7)
                     (:name "strategy-b" :status "underperforming" :keep-rate 0.1)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (should (string= "effective"
                       (gptel-auto-workflow--ontology-strategy-status "strategy-a")))
      (should (string= "underperforming"
                       (gptel-auto-workflow--ontology-strategy-status "strategy-b"))))))

(ert-deftest regression/ontology/select-strategy-prefers-effective ()
  "Strategy selection should prefer effective over promising and underperforming."
  (let ((mock-ontology
         '(:classes ((:name "underperf" :status "underperforming" :keep-rate 0.2)
                     (:name "promising" :status "promising" :keep-rate 0.4)
                     (:name "effective" :status "effective" :keep-rate 0.6)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      (let ((selected (gptel-auto-workflow--select-best-strategy-with-ontology
                       '("underperf" "promising" "effective")
                       "lisp/test.el")))
        (should (string= "effective" selected))))))

(ert-deftest regression/ontology/select-strategy-score-boost ()
  "Effective strategies should get score boost in selection."
  (let ((mock-ontology
         '(:classes ((:name "eff-low-rate" :status "effective" :keep-rate 0.35)
                     (:name "prom-high-rate" :status "promising" :keep-rate 0.45)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology)))
      ;; effective (0.35 + 1.0 = 1.35) should beat promising (0.45 + 0.5 = 0.95)
      (let ((selected (gptel-auto-workflow--select-best-strategy-with-ontology
                       '("eff-low-rate" "prom-high-rate")
                       "lisp/test.el")))
        (should (string= "eff-low-rate" selected))))))

;; ─── Backend Recommendation Tests ───

(ert-deftest regression/ontology/recommend-backend-for-strategy ()
  "Backend recommendation should return most successful backend for strategy."
  (let ((mock-results
         (list
          (list :strategy "strat-a" :backend "moonshot" :decision "kept")
          (list :strategy "strat-a" :backend "moonshot" :decision "kept")
          (list :strategy "strat-a" :backend "minimax" :decision "kept")
          (list :strategy "strat-a" :backend "minimax" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((backend (gptel-auto-workflow--ontology-recommend-backend
                      "strat-a" "lisp/test.el")))
        (should (string= "moonshot" backend))))))

(ert-deftest regression/ontology/recommend-backend-no-data ()
  "Backend recommendation should return nil when no data."
  (let ((mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((backend (gptel-auto-workflow--ontology-recommend-backend
                      "unknown-strat" "lisp/test.el")))
        (should-not backend)))))

;; ─── Knowledge Gap Tests ───

(ert-deftest regression/ontology/knowledge-gap-detection ()
  "Knowledge gaps should detect strategies without knowledge pages."
  (let ((mock-results
         (list
          (list :strategy "has-knowledge" :knowledge-hash "abc123")
          (list :strategy "has-knowledge" :knowledge-hash "def456")
          (list :strategy "no-knowledge" :knowledge-hash "none")
          (list :strategy "no-knowledge" :knowledge-hash nil))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((gaps (gptel-auto-workflow--ontology-check-knowledge-gaps)))
        (should (member "no-knowledge" gaps))
        (should-not (member "has-knowledge" gaps))))))

;; ─── Integration Test ───

(ert-deftest regression/ontology/enhance-experiment-setup ()
  "Experiment setup enhancement should return strategy and backend recommendations."
  (let ((mock-ontology
         '(:classes ((:name "effective-strat" :status "effective" :keep-rate 0.7))
           :instances ((:name "lisp/test.el" :classification "high-value" :keep-rate 0.8))))
        (mock-results
         (list (list :strategy "effective-strat" :backend "moonshot" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
               (lambda () mock-ontology))
              ((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((setup (gptel-auto-workflow--ontology-enhance-experiment-setup "lisp/test.el")))
        (should (string= "effective-strat" (plist-get setup :strategy)))
        (should (string= "moonshot" (plist-get setup :backend)))
        (should (string= "high-value" (plist-get setup :target-value)))))))

(provide 'test-gptel-auto-workflow-ontology-strategy)
;;; test-gptel-auto-workflow-ontology-strategy.el ends here
