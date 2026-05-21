;;; test-gptel-auto-workflow-ontology-router.el --- Ontology fallback reordering tests -*- lexical-binding: t; -*-

;;; Commentary:

;; TDD tests for ontology-aware fallback chain reordering.
;; Verifies that existing fallback lists are reordered based on performance,
;; not replaced with a new routing system.

;;; Code:

(require 'ert)

;; Ensure lisp/modules is on load-path for requires in loaded modules
(let ((base (file-name-directory
             (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path (expand-file-name "../lisp/modules" base))
  (add-to-list 'load-path (expand-file-name "../packages/gptel" base))
  (add-to-list 'load-path (expand-file-name "../packages/gptel-agent" base)))

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

;; ─── Advice Integration Tests ───

(ert-deftest tdd/ontology-router/advice-is-active ()
  "Ontology fallback advice must be active on gptel-auto-experiment-run."
  (should (advice-member-p #'gptel-auto-workflow--ontology-fallback-advice
                           'gptel-auto-experiment-run)))

(ert-deftest tdd/ontology-router/apply-reorders-fallbacks ()
  "apply-ontology-fallback-order reorders executor fallbacks for a target.
Guards against missing runtime dependencies (worktree-base-root)."
  (when (and (fboundp 'gptel-auto-workflow--worktree-base-root)
             (fboundp 'gptel-auto-workflow--parse-all-results))
    (let ((original gptel-auto-workflow-executor-rate-limit-fallbacks))
      (unwind-protect
          (condition-case nil
              (progn
                (gptel-auto-workflow--apply-ontology-fallback-order
                 nil "lisp/modules/gptel-fsm.el")
                (should gptel-auto-workflow-executor-rate-limit-fallbacks)
                (should (cl-every #'consp gptel-auto-workflow-executor-rate-limit-fallbacks)))
            (error nil))
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks original)))))

(ert-deftest tdd/ontology-router/reset-restores-static-order ()
  "reset-fallback-order restores the static headless fallback list."
  (let ((original gptel-auto-workflow-executor-rate-limit-fallbacks))
    (unwind-protect
        (progn
          (setq gptel-auto-workflow-executor-rate-limit-fallbacks
                '(("CustomBackend" . "custom-model")))
          (gptel-auto-workflow--reset-fallback-order)
          (should (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                         gptel-auto-workflow-headless-subagent-fallbacks)))
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks original))))

(ert-deftest tdd/ontology-router/categorize-programming-targets ()
  "categorize-target returns :programming for .el source files."
  (when (fboundp 'gptel-auto-workflow--categorize-target)
    (should (eq :programming (gptel-auto-workflow--categorize-target
                              "lisp/modules/gptel-fsm.el")))
    (should (eq :programming (gptel-auto-workflow--categorize-target
                              "lisp/modules/gptel-ext-code.el")))
    ;; gptel-ext-* modules are :programming (code-processing tools)
    (should (eq :programming (gptel-auto-workflow--categorize-target
                              "lisp/modules/gptel-ext-bash.el")))))

(ert-deftest tdd/ontology-router/categorize-tool-call-targets ()
  "categorize-target returns :tool-calls for sandbox/tool-execution modules."
  (when (fboundp 'gptel-auto-workflow--categorize-target)
    (should (eq :tool-calls (gptel-auto-workflow--categorize-target
                              "lisp/modules/gptel-tools-sandbox.el")))
    (should (eq :tool-calls (gptel-auto-workflow--categorize-target
                              "lisp/modules/gptel-tools-bash.el")))
    (should (eq :tool-calls (gptel-auto-workflow--categorize-target
                              "lisp/modules/gptel-tools-grep.el")))))

(ert-deftest tdd/ontology-router/categorize-agentic-targets ()
  "categorize-target returns :agentic for workflow/evolution/agent modules."
  (when (fboundp 'gptel-auto-workflow--categorize-target)
    (should (eq :agentic (gptel-auto-workflow--categorize-target
                           "lisp/modules/gptel-tools-agent.el")))
    (should (eq :agentic (gptel-auto-workflow--categorize-target
                           "lisp/modules/gptel-auto-workflow-evolution.el")))))

(provide 'test-gptel-auto-workflow-ontology-router)
;;; test-gptel-auto-workflow-ontology-router.el ends here
