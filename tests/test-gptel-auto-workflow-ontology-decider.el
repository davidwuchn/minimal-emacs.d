;;; test-gptel-auto-workflow-ontology-decider.el --- Ontology vs LLM decider tests -*- lexical-binding: t; -*-

;;; Commentary:

;; TDD tests for the ontology vs LLM decision framework.
;; Verifies that decisions route correctly based on data and complexity.

;;; Code:

(require 'ert)

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-ontology-decider.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── Decision Type Catalog Tests ───

(ert-deftest regression/ontology-decider/catalog-has-pre-flight ()
  "Decision catalog should include pre-flight type."
  (should (cl-find-if (lambda (d) (string= (plist-get d :name) "pre-flight"))
                      gptel-auto-workflow--decision-types)))

(ert-deftest regression/ontology-decider/catalog-has-code-generation ()
  "Code generation should default to LLM."
  (let ((type (cl-find-if (lambda (d) (string= (plist-get d :name) "code-generation"))
                          gptel-auto-workflow--decision-types)))
    (should (eq :llm (plist-get type :default)))))

(ert-deftest regression/ontology-decider/catalog-has-knowledge-synthesis ()
  "Knowledge synthesis should default to hybrid."
  (let ((type (cl-find-if (lambda (d) (string= (plist-get d :name) "knowledge-synthesis"))
                          gptel-auto-workflow--decision-types)))
    (should (eq :hybrid (plist-get type :default)))))

;; ─── Formal Decider Tests ───

(ert-deftest regression/ontology-decider/simple-with-data-goes-ontology ()
  "Simple decision with abundant data → ontology."
  (let ((result (gptel-auto-workflow--decide-ontology-or-llm
                 "pre-flight" :abundant :simple)))
    (should (eq result :ontology))))

(ert-deftest regression/ontology-decider/complex-goes-llm ()
  "Complex decision → LLM regardless of data."
  (let ((result (gptel-auto-workflow--decide-ontology-or-llm
                 "pre-flight" :abundant :complex)))
    (should (eq result :llm))))

(ert-deftest regression/ontology-decider/no-data-goes-llm ()
  "No data → LLM regardless of complexity."
  (let ((result (gptel-auto-workflow--decide-ontology-or-llm
                 "pre-flight" :none :simple)))
    (should (eq result :llm))))

(ert-deftest regression/ontology-decider/code-generation-always-llm ()
  "Code generation should always use LLM."
  (let ((result (gptel-auto-workflow--decide-ontology-or-llm
                 "code-generation" :abundant :simple)))
    (should (eq result :llm))))

(ert-deftest regression/ontology-decider/sparse-moderate-uses-default ()
  "Sparse data + moderate complexity uses type default."
  (let ((pre-flight (gptel-auto-workflow--decide-ontology-or-llm
                     "pre-flight" :sparse :moderate))
        (code-gen (gptel-auto-workflow--decide-ontology-or-llm
                   "code-generation" :sparse :moderate)))
    (should (eq pre-flight :ontology))  ; pre-flight default
    (should (eq code-gen :llm))))       ; code-gen default

;; ─── Cost Guard Tests ───

(ert-deftest regression/ontology-decider/guard-skips-llm-for-ontology ()
  "Guard should skip LLM when ontology is sufficient."
  (let ((llm-called nil)
        (mock-ontology '(:classes ((:name "good-strat" :status "effective" :keep-rate 0.8)))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--decide-ontology-or-llm)
               (lambda (_type _data _complexity) 'ontology))
              ((symbol-function 'gptel-auto-workflow--ontology-answer)
               (lambda (_type &rest _args) 'ontology-result))
              ((symbol-function 'mock-llm)
               (lambda () (setq llm-called t) 'llm-result)))
      (let ((result (gptel-auto-workflow--guard-llm-with-ontology
                     "pre-flight" #'mock-llm)))
        (should (eq result 'ontology-result))
        (should-not llm-called)))))

(ert-deftest regression/ontology-decider/guard-calls-llm-when-needed ()
  "Guard should call LLM when ontology is insufficient."
  (let ((llm-called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--decide-ontology-or-llm)
               (lambda (_type _data _complexity) 'llm))
              ((symbol-function 'mock-llm)
               (lambda () (setq llm-called t) 'llm-result)))
      (let ((result (gptel-auto-workflow--guard-llm-with-ontology
                     "code-generation" #'mock-llm)))
        (should (eq result 'llm-result))
        (should llm-called)))))

;; ─── Decision Statistics Tests ───

(ert-deftest regression/ontology-decider/stats-record-decision ()
  "Recording decisions should update stats."
  (setq gptel-auto-workflow--decision-stats (make-hash-table :test 'equal))
  (gptel-auto-workflow--record-decision "pre-flight" 'ontology)
  (gptel-auto-workflow--record-decision "pre-flight" 'ontology)
  (gptel-auto-workflow--record-decision "pre-flight" 'llm)
  (let ((stats (gethash "pre-flight" gptel-auto-workflow--decision-stats)))
    (should (= 3 (plist-get stats :total)))
    (should (= 2 (plist-get stats :ontology)))
    (should (= 1 (plist-get stats :llm)))))

(ert-deftest regression/ontology-decider/stats-report-format ()
  "Report should format stats as readable strings."
  (clrhash gptel-auto-workflow--decision-stats)
  (gptel-auto-workflow--record-decision "pre-flight" 'ontology)
  (let ((report (gptel-auto-workflow--decision-stats-report)))
    (should (> (length report) 0))
    (should (string-match-p "pre-flight" (car report)))))

(provide 'test-gptel-auto-workflow-ontology-decider)
;;; test-gptel-auto-workflow-ontology-decider.el ends here
