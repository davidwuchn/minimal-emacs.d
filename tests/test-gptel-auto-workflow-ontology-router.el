;;; test-gptel-auto-workflow-ontology-router.el --- Ontology fallback reordering tests -*- lexical-binding: t; -*-

;;; Commentary:

;; TDD tests for ontology-aware fallback chain reordering.
;; Verifies that existing fallback lists are reordered based on performance,
;; not replaced with a new routing system.

;;; Code:

(require 'ert)

;; Mock the existing fallback configuration
(defvar gptel-auto-workflow-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))
  "Mock headless fallback list for testing.")

(defvar gptel-auto-workflow-executor-rate-limit-fallbacks
  gptel-auto-workflow-headless-subagent-fallbacks
  "Mock executor fallback list for testing.")

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-ontology-router.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── Performance Lookup Tests ───

(ert-deftest regression/ontology-router/keep-rate-from-results ()
  "Keep-rate should be calculated from experiment results."
  (let ((mock-results
         (list
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((rate (gptel-auto-workflow--get-backend-keep-rate "moonshot")))
        (should (= rate (/ 2.0 3)))))))

(ert-deftest regression/ontology-router/keep-rate-no-data ()
  "No data should return nil."
  (let ((mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (should-not (gptel-auto-workflow--get-backend-keep-rate "moonshot")))))

(ert-deftest regression/ontology-router/keep-rate-filtered-by-strategy ()
  "Filtering by strategy should only count matching experiments."
  (let ((mock-results
         (list
          (list :backend "moonshot" :strategy "strat-a" :decision "kept")
          (list :backend "moonshot" :strategy "strat-b" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((rate (gptel-auto-workflow--get-backend-keep-rate "moonshot" "strat-a")))
        (should (= rate 1.0))))))

;; ─── Fallback Reordering Tests ───

(ert-deftest regression/ontology-router/reorder-puts-best-first ()
  "Backend with highest keep-rate should be first in reordered list."
  (let ((mock-results
         (list
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")
          (list :backend "MiniMax" :decision "discarded")
          (list :backend "MiniMax" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))  ; No exploration
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        (should (string= "moonshot" (caar reordered)))
        (should (string= "kimi-k2.6" (cdar reordered)))))))

(ert-deftest regression/ontology-router/reorder-keeps-all-backends ()
  "Reordering should preserve all backends from static list."
  (let ((mock-results
         (list
          (list :backend "moonshot" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        (should (= 5 (length reordered)))
        (should (assoc "moonshot" reordered))
        (should (assoc "MiniMax" reordered))
        (should (assoc "DashScope" reordered))
        (should (assoc "DeepSeek" reordered))
        (should (assoc "CF-Gateway" reordered))))))

(ert-deftest regression/ontology-router/insufficient-data-uses-static ()
  "When insufficient data, should return static order unchanged."
  (let ((mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        ;; Should match static order exactly
        (should (equal reordered gptel-auto-workflow-headless-subagent-fallbacks))))))

(ert-deftest regression/ontology-router/exploration-can-swap ()
  "With exploration enabled, top 2 backends can be swapped."
  (let ((mock-results
         (list
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")
          (list :backend "MiniMax" :decision "kept")
          (list :backend "MiniMax" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ;; Force exploration (random < 15)
              ((symbol-function 'random) (lambda (_) 10)))
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        ;; With exploration, order might be swapped
        (should (= 2 (length (cl-intersection (mapcar #'car reordered)
                                               '("moonshot" "MiniMax")
                                               :test #'string=))))))))

;; ─── Target Categorization Tests ───

(ert-deftest regression/ontology-router/categorize-programming ()
  "FSM, benchmark, test, retry files should be :programming."
  (should (eq :programming (gptel-auto-workflow--categorize-target "lisp/modules/gptel-ext-fsm.el")))
  (should (eq :programming (gptel-auto-workflow--categorize-target "lisp/modules/gptel-benchmark-memory.el")))
  (should (eq :programming (gptel-auto-workflow--categorize-target "lisp/modules/gptel-benchmark-tests.el")))
  (should (eq :programming (gptel-auto-workflow--categorize-target "lisp/modules/gptel-ext-retry.el")))
  (should (eq :programming (gptel-auto-workflow--categorize-target "lisp/modules/gptel-tools-introspection.el"))))

(ert-deftest regression/ontology-router/categorize-tool-calls ()
  "Sandbox and tool files should be :tool-calls."
  (should (eq :tool-calls (gptel-auto-workflow--categorize-target "lisp/modules/gptel-sandbox.el")))
  (should (eq :tool-calls (gptel-auto-workflow--categorize-target "lisp/modules/gptel-tools-bash.el")))
  (should (eq :tool-calls (gptel-auto-workflow--categorize-target "lisp/modules/gptel-tools-grep.el"))))

(ert-deftest regression/ontology-router/categorize-agentic ()
  "Agent, workflow, strategy files should be :agentic."
  (should (eq :agentic (gptel-auto-workflow--categorize-target "lisp/modules/gptel-tools-agent.el")))
  (should (eq :agentic (gptel-auto-workflow--categorize-target "lisp/modules/gptel-auto-workflow-strategic.el")))
  (should (eq :agentic (gptel-auto-workflow--categorize-target "lisp/modules/gptel-tools-agent-strategy-harness.el"))))

(ert-deftest regression/ontology-router/categorize-natural-language ()
  "Context, streaming, prompt files should be :natural-language."
  (should (eq :natural-language (gptel-auto-workflow--categorize-target "lisp/modules/gptel-ext-context.el")))
  (should (eq :natural-language (gptel-auto-workflow--categorize-target "lisp/modules/gptel-ext-streaming.el")))
  (should (eq :natural-language (gptel-auto-workflow--categorize-target "lisp/modules/gptel-ext-context-cache.el"))))

;; ─── Category Override Tests ───

(ert-deftest regression/ontology-router/category-override-programming ()
  "Programming targets should prefer DeepSeek."
  (let ((mock-results
         (list
          (list :backend "moonshot" :target "lisp/modules/gptel-ext-fsm.el" :decision "kept")
          (list :backend "moonshot" :target "lisp/modules/gptel-ext-fsm.el" :decision "kept")
          (list :backend "moonshot" :target "lisp/modules/gptel-ext-fsm.el" :decision "kept")
          (list :backend "MiniMax"  :target "lisp/modules/gptel-ext-fsm.el" :decision "discarded")
          (list :backend "MiniMax"  :target "lisp/modules/gptel-ext-fsm.el" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))
      ;; FSM is :programming, which overrides to DeepSeek
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology nil "lisp/modules/gptel-ext-fsm.el")))
        (should (string= "DeepSeek" (caar reordered)))
        (should (string= "deepseek-v4-flash" (cdar reordered)))))))

(ert-deftest regression/ontology-router/category-override-tool-calls ()
  "Tool-call targets have no override — use ontology ordering (MiniMax default)."
  (let ((mock-results
         (list
          (list :backend "moonshot" :target "lisp/modules/gptel-sandbox.el" :decision "kept")
          (list :backend "moonshot" :target "lisp/modules/gptel-sandbox.el" :decision "kept")
          (list :backend "moonshot" :target "lisp/modules/gptel-sandbox.el" :decision "kept")
          (list :backend "MiniMax"  :target "lisp/modules/gptel-sandbox.el" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))
      ;; Sandbox is :tool-calls, which has no override — uses normal performance ordering
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology nil "lisp/modules/gptel-sandbox.el")))
        (should (string= "moonshot" (caar reordered)))))))

(ert-deftest regression/ontology-router/category-override-natural-language ()
  "Natural-language targets should prefer DeepSeek."
  (let ((mock-results
         (list
          (list :backend "moonshot" :target "lisp/modules/gptel-ext-context.el" :decision "kept")
          (list :backend "moonshot" :target "lisp/modules/gptel-ext-context.el" :decision "kept")
          (list :backend "moonshot" :target "lisp/modules/gptel-ext-context.el" :decision "kept")
          (list :backend "MiniMax"  :target "lisp/modules/gptel-ext-context.el" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))
      ;; gptel-ext-context.el is :natural-language, which overrides to DeepSeek
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology nil "lisp/modules/gptel-ext-context.el")))
        (should (string= "DeepSeek" (caar reordered)))
        (should (string= "deepseek-v4-flash" (cdar reordered)))))))

(ert-deftest regression/ontology-router/category-override-agentic ()
  "Agentic targets have no override — use ontology ordering."
  (let ((mock-results
         (list
          (list :backend "CF-Gateway" :target "lisp/modules/gptel-tools-agent.el" :decision "kept")
          (list :backend "CF-Gateway" :target "lisp/modules/gptel-tools-agent.el" :decision "kept")
          (list :backend "CF-Gateway" :target "lisp/modules/gptel-tools-agent.el" :decision "kept")
          (list :backend "MiniMax"     :target "lisp/modules/gptel-tools-agent.el" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))
      ;; gptel-tools-agent.el is :agentic, which has no override (nil)
      ;; So it should use normal performance ordering
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology nil "lisp/modules/gptel-tools-agent.el")))
        (should (string= "CF-Gateway" (caar reordered)))))))

;; ─── Integration Tests ───

(ert-deftest regression/ontology-router/apply-and-reset ()
  "Applying ontology order should modify fallback chain, reset should restore."
  (let ((mock-results
         (list
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")
          (list :backend "moonshot" :decision "kept")))
        (original-order gptel-auto-workflow-executor-rate-limit-fallbacks))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))
      ;; Apply ontology ordering
      (gptel-auto-workflow--apply-ontology-fallback-order)
      ;; Should have reordered
      (should (string= "moonshot" (caar gptel-auto-workflow-executor-rate-limit-fallbacks)))
      ;; Reset
      (gptel-auto-workflow--reset-fallback-order)
      ;; Should be back to original
      (should (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                     gptel-auto-workflow-headless-subagent-fallbacks)))))

(provide 'test-gptel-auto-workflow-ontology-router)
;;; test-gptel-auto-workflow-ontology-router.el ends here
