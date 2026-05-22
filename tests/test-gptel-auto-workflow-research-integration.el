;;; test-gptel-auto-workflow-research-integration.el --- TDD for research integration -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for gptel-auto-workflow-research-integration.el
;; Covers: AutoTTS trace parsing, AutoGo champions, Ontology gaps,
;; Self-evolve correlation, Meta-harness proposals.

;;; Code:

(require 'ert)

;; Ensure load-path
(let ((base (file-name-directory
             (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path (expand-file-name "../lisp/modules" base))
  (add-to-list 'load-path (expand-file-name "../packages/gptel" base))
  (add-to-list 'load-path (expand-file-name "../packages/gptel-agent" base)))

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-research-integration.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── AutoTTS Trace Parsing ───

(ert-deftest tdd/research-integration/parse-autotts-traces-valid ()
  "parse-research-autotts-traces extracts trace plists from JSON blocks."
  (let* ((output "Some text\n===RESULT===\n{\"phase\":\"explore\",\"confidence\":0.8,\"tokens\":150,\"insights_count\":3}\nMore text")
         (traces (gptel-auto-workflow--parse-research-autotts-traces output)))
    (should (= 1 (length traces)))
    (should (eq :explore (plist-get (car traces) :phase)))
    (should (= 0.8 (plist-get (car traces) :confidence)))
    (should (= 3 (plist-get (car traces) :insights_count)))))

(ert-deftest tdd/research-integration/parse-autotts-traces-empty ()
  "parse-research-autotts-traces returns nil for empty input."
  (should-not (gptel-auto-workflow--parse-research-autotts-traces ""))
  (should-not (gptel-auto-workflow--parse-research-autotts-traces "No results here")))

(ert-deftest tdd/research-integration/parse-autotts-traces-multiple ()
  "parse-research-autotts-traces handles multiple ===RESULT=== blocks."
  (let* ((output "===RESULT===\n{\"phase\":\"P1\",\"confidence\":0.5}\n===RESULT===\n{\"phase\":\"P2\",\"confidence\":0.9}")
         (traces (gptel-auto-workflow--parse-research-autotts-traces output)))
    (should (= 2 (length traces)))
    (should (eq :P1 (plist-get (car traces) :phase)))
    (should (eq :P2 (plist-get (cadr traces) :phase)))))

(ert-deftest tdd/research-integration/autotts-stop-early-p-true ()
  "research-autotts-stop-early-p returns t when confidence > 0.7 and 2+ insights."
  (let ((traces (list (list :phase "P1" :confidence 0.6 :insights_count 1)
                      (list :phase "P2" :confidence 0.8 :insights_count 2))))
    (should (gptel-auto-workflow--research-autotts-stop-early-p traces))))

(ert-deftest tdd/research-integration/autotts-stop-early-p-false ()
  "research-autotts-stop-early-p returns nil when conditions not met."
  (let ((traces (list (list :phase "P1" :confidence 0.6 :insights_count 1))))
    (should-not (gptel-auto-workflow--research-autotts-stop-early-p traces)))
  (let ((traces (list (list :phase "P1" :confidence 0.8 :insights_count 0))))
    (should-not (gptel-auto-workflow--research-autotts-stop-early-p traces))))

(ert-deftest tdd/research-integration/autotts-stop-early-p-nil ()
  "research-autotts-stop-early-p returns nil for nil input."
  (should-not (gptel-auto-workflow--research-autotts-stop-early-p nil)))

;; ─── AutoGo: Category Champions ───

(ert-deftest tdd/research-integration/research-category-for-topic-programming ()
  "research-category-for-topic classifies elisp/code topics as :programming."
  (should (eq :programming (gptel-auto-workflow--research-category-for-topic "elisp functions")))
  (should (eq :programming (gptel-auto-workflow--research-category-for-topic "lisp modules"))))

(ert-deftest tdd/research-integration/research-category-for-topic-agentic ()
  "research-category-for-topic classifies agent/workflow topics as :agentic."
  (should (eq :agentic (gptel-auto-workflow--research-category-for-topic "agent orchestration")))
  (should (eq :agentic (gptel-auto-workflow--research-category-for-topic "daemon pipeline"))))

(ert-deftest tdd/research-integration/research-category-for-topic-tool-calls ()
  "research-category-for-topic classifies backend/api topics as :tool-calls."
  (should (eq :tool-calls (gptel-auto-workflow--research-category-for-topic "backend provider")))
  (should (eq :tool-calls (gptel-auto-workflow--research-category-for-topic "api gateway"))))

(ert-deftest tdd/research-integration/research-category-for-topic-default ()
  "research-category-for-topic defaults to :natural-language."
  (should (eq :natural-language (gptel-auto-workflow--research-category-for-topic "random topic"))))

(ert-deftest tdd/research-integration/update-research-champion-adopts ()
  "update-research-strategy-champion adopts strategy when keep-rate beats baseline."
  (let ((gptel-auto-workflow--research-strategy-champions nil))
    (gptel-auto-workflow--update-research-strategy-champion "elisp functions" "strategy-a" 0.20)
    (let ((entry (assq :programming gptel-auto-workflow--research-strategy-champions)))
      (should entry)
      (should (string= "strategy-a" (car (cdr entry))))
      (should (= 0.20 (cdr (cdr entry)))))))

(ert-deftest tdd/research-integration/update-research-champion-rejects-below-baseline ()
  "update-research-strategy-champion rejects strategy below baseline."
  (let ((gptel-auto-workflow--research-strategy-champions nil))
    (gptel-auto-workflow--update-research-strategy-champion "topic" "strategy-b" 0.10)
    (should-not (assq :programming gptel-auto-workflow--research-strategy-champions))))

(ert-deftest tdd/research-integration/update-research-champion-replaces-worse ()
  "update-research-strategy-champion replaces existing champion with better strategy."
  (let ((gptel-auto-workflow--research-strategy-champions
         '((:programming . ("old" . 0.18)))))
    (gptel-auto-workflow--update-research-strategy-champion "elisp" "new" 0.25)
    (let ((entry (assq :programming gptel-auto-workflow--research-strategy-champions)))
      (should (string= "new" (car (cdr entry))))
      (should (= 0.25 (cdr (cdr entry)))))))

;; ─── Ontology Research Gaps ───

(ert-deftest tdd/research-integration/ontology-gaps-empty ()
  "ontology-research-gaps handles empty ontology gracefully."
  (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
             (lambda () (list :classes nil))))
    (let ((result (gptel-auto-workflow--ontology-research-gaps)))
      (should-not (plist-get result :gaps))
      (should (plist-member result :priorities)))))

(ert-deftest tdd/research-integration/ontology-gaps-few-instances ()
  "ontology-research-gaps flags classes with <3 instances."
  (cl-letf (((symbol-function 'gptel-auto-workflow--generate-experiment-ontology)
             (lambda () (list :classes (list (list :name "TestClass" :instances 1 :properties '(a b)))))))
    (let ((result (gptel-auto-workflow--ontology-research-gaps)))
      (should (= 1 (length (plist-get result :gaps))))
      (should (string-match-p "TestClass" (car (plist-get result :gaps)))))))

(ert-deftest tdd/research-integration/top-priority-nil-when-no-gaps ()
  "top-research-priority returns nil when no gaps."
  (cl-letf (((symbol-function 'gptel-auto-workflow--ontology-research-gaps)
             (lambda () (list :gaps nil :priorities nil))))
    (should-not (gptel-auto-workflow--top-research-priority))))

(ert-deftest tdd/research-integration/top-priority-returns-topic ()
  "top-research-priority returns highest-priority topic."
  (cl-letf (((symbol-function 'gptel-auto-workflow--ontology-research-gaps)
             (lambda () (list :gaps '("gap1") :priorities '(("topic-a" . 0.8) ("topic-b" . 0.5))))))
    (should (string= "topic-a" (gptel-auto-workflow--top-research-priority)))))

;; ─── Self-Evolve: Research Correlation ───

(ert-deftest tdd/research-integration/correlate-research-empty ()
  "correlate-research-to-outcomes returns nil with no results."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda () nil)))
    (should-not (gptel-auto-workflow--correlate-research-to-outcomes))))

(ert-deftest tdd/research-integration/correlate-research-single-source ()
  "correlate-research-to-outcomes computes keep-rate per source."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :decision "kept" :research-strategy "deep-external" :research-hash "h1")
                     (list :decision "kept" :research-strategy "deep-external" :research-hash "h2")
                     (list :decision "discarded" :research-strategy "deep-external" :research-hash "h3")
                     (list :decision "discarded" :research-strategy "quick-own-only" :research-hash "h4")))))
    (let ((stats (gptel-auto-workflow--correlate-research-to-outcomes)))
      ;; deep-external: 2/2 = 100% (but N=2 < 3 threshold, filtered)
      (should (null stats)))))

(ert-deftest tdd/research-integration/correlate-research-above-threshold ()
  "correlate-research-to-outcomes includes sources with >=4 experiments."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (append
                (make-list 4 (list :decision "kept" :research-strategy "deep-external" :research-hash "h1"))
                (make-list 2 (list :decision "discarded" :research-strategy "deep-external" :research-hash "h2"))))))
    (let ((stats (gptel-auto-workflow--correlate-research-to-outcomes)))
      (should (= 1 (length stats)))
      (should (string= "deep-external" (caar stats)))
      (should (= (/ 4.0 6) (cdar stats))))))

(ert-deftest tdd/research-integration/effectiveness-report-empty ()
  "research-source-effectiveness-report handles empty stats."
  (cl-letf (((symbol-function 'gptel-auto-workflow--correlate-research-to-outcomes)
             (lambda () nil)))
    (let ((report (gptel-auto-workflow--research-source-effectiveness-report)))
      (should (stringp report))
      (should (string-match-p "No research-experiment correlation" report)))))

;; ─── Meta-Harness: Strategy Proposals ───

(ert-deftest tdd/research-integration/propose-strategy-new ()
  "propose-research-strategy adds new strategy to proposed list."
  (let ((gptel-auto-workflow--proposed-research-strategies nil)
        (gptel-auto-workflow--research-strategies '("existing")))
    (gptel-auto-workflow--propose-research-strategy "new-strat" "Test strategy" nil)
    (should (member "new-strat" gptel-auto-workflow--proposed-research-strategies))
    (should-not (member "new-strat" gptel-auto-workflow--research-strategies))))

(ert-deftest tdd/research-integration/propose-strategy-duplicate ()
  "propose-research-strategy ignores duplicates."
  (let ((gptel-auto-workflow--proposed-research-strategies nil)
        (gptel-auto-workflow--research-strategies '("existing")))
    (gptel-auto-workflow--propose-research-strategy "existing" "Duplicate" nil)
    (should-not (member "existing" gptel-auto-workflow--proposed-research-strategies))))

(ert-deftest tdd/research-integration/propose-strategy-creates-file ()
  "propose-research-strategy writes JSON definition file."
  (let ((gptel-auto-workflow--proposed-research-strategies nil)
        (gptel-auto-workflow--research-strategies nil)
        (root (make-temp-file "test" t)))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () root)))
            (gptel-auto-workflow--propose-research-strategy
             "test-strat" "Description" (list (list :name "P1" :prompt "test")))
            (let ((file (expand-file-name "assistant/skills/researcher-prompt/strategies/test-strat.json" root)))
              (should (file-exists-p file))
              (with-temp-buffer
                (insert-file-contents file)
                (should (string-match-p "test-strat" (buffer-string)))))))
      (delete-directory root t))))

(provide 'test-gptel-auto-workflow-research-integration)
;;; test-gptel-auto-workflow-research-integration.el ends here
