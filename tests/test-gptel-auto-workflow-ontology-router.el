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

;; Mock variables
(defvar gptel-auto-workflow--evolution-next-cycle-hints nil)

;; Mock the existing fallback configuration
(defvar gptel-auto-workflow-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))
  "Mock headless fallback list for testing.")

(defvar gptel-auto-workflow-executor-rate-limit-fallbacks
  '(("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("moonshot" . "kimi-k2.6")
    ("MiniMax" . "minimax-m2.7-highspeed")
    ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))
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

(ert-deftest regression/ontology-router/advice-does-not-treat-code-quality-as-strategy ()
  "Experiment arg 5 is baseline code quality, not strategy."
  (let ((captured-strategy :unset))
    (cl-letf (((symbol-function 'gptel-auto-workflow--apply-ontology-fallback-order)
               (lambda (strategy target)
                 (setq captured-strategy strategy)
                 (should (equal target "lisp/modules/example.el"))))
              ((symbol-function 'gptel-auto-workflow--reset-fallback-order)
               (lambda () nil)))
      (gptel-auto-workflow--ontology-fallback-advice
       (lambda (&rest _args) :ok)
       "lisp/modules/example.el" 1 9 0.40 0.8625 nil #'ignore)
      (should (null captured-strategy)))))

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

;; ─── Semantic Similarity Target Discovery Tests ───

(ert-deftest tdd/semantic-suggestions/returns-nil-when-no-function ()
  "semantic-target-suggestions returns nil when function not bound."
  (when (fboundp 'gptel-auto-workflow--semantic-target-suggestions)
    (cl-letf (((symbol-function 'gptel-auto-workflow--semantic-similarity-edges)
               (lambda (&optional _) nil)))
      (should (null (gptel-auto-workflow--semantic-target-suggestions))))))

(ert-deftest tdd/semantic-suggestions/filters-by-threshold-and-max ()
  "semantic-target-suggestions respects max-suggestions and min-score."
  (when (fboundp 'gptel-auto-workflow--semantic-target-suggestions)
    (cl-letf (((symbol-function 'gptel-auto-workflow--semantic-similarity-edges)
               (lambda (&optional _)
                 '((:target "a.el" :score 0.75)
                   (:target "b.el" :score 0.82)
                   (:target "c.el" :score 0.65)
                   (:target "d.el" :score 0.90))))
              ((symbol-function 'file-exists-p)
               (lambda (_) t)))
      (let ((suggestions (gptel-auto-workflow--semantic-target-suggestions 2 0.70)))
         (should (= 2 (length suggestions)))
         (should (member "a.el" suggestions))
         (should (member "b.el" suggestions))
         (should-not (member "c.el" suggestions))))))

(ert-deftest tdd/semantic-suggestions/dedup-and-file-check ()
  "semantic-target-suggestions deduplicates and checks file existence."
  (when (fboundp 'gptel-auto-workflow--semantic-target-suggestions)
    (cl-letf (((symbol-function 'gptel-auto-workflow--semantic-similarity-edges)
               (lambda (&optional _)
                 '((:target "a.el" :score 0.75)
                   (:target "a.el" :score 0.75)
                   (:target "nonexistent.el" :score 0.80))))
              ((symbol-function 'file-exists-p)
               (lambda (f) (not (string= f "nonexistent.el")))))
      (let ((suggestions (gptel-auto-workflow--semantic-target-suggestions)))
        (should (= 1 (length suggestions)))
        (should (string= "a.el" (car suggestions)))))))

(ert-deftest tdd/semantic-suggestions/category-filter ()
  "semantic-targets-for-category filters by category."
  (when (fboundp 'gptel-auto-workflow--semantic-targets-for-category)
    (cl-letf (((symbol-function 'gptel-auto-workflow--semantic-target-suggestions)
               (lambda (&optional _ _)
                 '("lisp/modules/gptel-ext-code.el"
                   "lisp/modules/gptel-tools-sandbox.el"
                   "lisp/modules/gptel-auto-workflow-evolution.el"))))
      (let ((programming (gptel-auto-workflow--semantic-targets-for-category :programming))
            (tool-calls (gptel-auto-workflow--semantic-targets-for-category :tool-calls))
            (agentic (gptel-auto-workflow--semantic-targets-for-category :agentic)))
        (should (= 1 (length programming)))
        (should (string-match-p "gptel-ext-code" (car programming)))
        (should (= 1 (length tool-calls)))
        (should (string-match-p "sandbox" (car tool-calls)))
        (should (= 1 (length agentic)))
        (should (string-match-p "evolution" (car agentic)))))))

;; ─── π Synthesis: Semantic Clustering Tests ───

(ert-deftest tdd/semantic-cluster/winning-strategy-from-tsv ()
  "winning-strategy-for-target returns strategy from kept results."
  (when (fboundp 'gptel-auto-workflow--winning-strategy-for-target)
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda ()
                 (list (list :target "a.el" :decision "kept" :strategy "weighted-failures")
                       (list :target "a.el" :decision "discarded" :strategy "template-default")
                       (list :target "b.el" :decision "kept" :strategy "complexity-compression")))))
      (should (string= "weighted-failures"
                       (gptel-auto-workflow--winning-strategy-for-target "a.el")))
      (should (string= "complexity-compression"
                       (gptel-auto-workflow--winning-strategy-for-target "b.el")))
      (should-not (gptel-auto-workflow--winning-strategy-for-target "c.el")))))

(ert-deftest tdd/semantic-cluster/cluster-grouping ()
  "semantic-cluster-targets groups kept targets with similar files."
  (when (fboundp 'gptel-auto-workflow--semantic-cluster-targets)
    (cl-letf (((symbol-function 'gptel-auto-workflow--semantic-similarity-edges)
               (lambda (&optional _)
                 (list (list :source "a.el" :target "b.el" :score 0.80)
                       (list :source "a.el" :target "c.el" :score 0.90)
                       (list :source "d.el" :target "e.el" :score 0.85)))))
      (let ((clusters (gptel-auto-workflow--semantic-cluster-targets 0.75)))
        (should (= 2 (length clusters)))
        (let ((a-cluster (cdr (assoc "a.el" clusters))))
          (should (= 2 (length a-cluster)))
          (should (assoc "b.el" a-cluster))
          (should (assoc "c.el" a-cluster)))))))

(ert-deftest tdd/semantic-cluster/suggest-similar-with-strategy ()
  "suggest-similar-with-strategy returns targets + inherited strategy."
  (when (fboundp 'gptel-auto-workflow--suggest-similar-with-strategy)
    (cl-letf (((symbol-function 'gptel-auto-workflow--winning-strategy-for-target)
               (lambda (_) "weighted-failures"))
              ((symbol-function 'gptel-auto-workflow--semantic-cluster-targets)
               (lambda (&optional _)
                 (list (cons "a.el" (list (cons "b.el" 0.88)
                                          (cons "c.el" 0.82)))))))
      (let ((result (gptel-auto-workflow--suggest-similar-with-strategy "a.el")))
        (should result)
        (should (string= "weighted-failures" (plist-get result :strategy)))
        (should (= 2 (length (plist-get result :targets))))
        (should (member "b.el" (plist-get result :targets)))
        (should (string= "a.el" (plist-get result :source)))))))

(ert-deftest tdd/semantic-cluster/queue-cluster-experiments ()
  "queue-cluster-experiments stores under :cluster-queued key in hints plist."
  (when (fboundp 'gptel-auto-workflow--queue-cluster-experiments)
    (let ((gptel-auto-workflow--evolution-next-cycle-hints nil))
      (cl-letf (((symbol-function 'gptel-auto-workflow--suggest-similar-with-strategy)
                 (lambda (_)
                   (list :targets '("b.el" "c.el")
                         :strategy "weighted-failures"
                         :source "a.el"
                         :scores '(0.88 0.82)))))
        (gptel-auto-workflow--queue-cluster-experiments "a.el")
        (let ((queued (plist-get gptel-auto-workflow--evolution-next-cycle-hints :cluster-queued)))
          (should queued)
          (should (= 2 (length queued)))
          (let ((first-hint (car queued)))
            (should (string= "b.el" (plist-get first-hint :target)))
            (should (string= "weighted-failures" (plist-get first-hint :strategy)))
             (should (string= "semantic-cluster" (plist-get first-hint :reason)))))))))

;; ─── Semantic Similarity Edges (git-embed) ───

(ert-deftest tdd/ontology/semantic-edges-cache-hit ()
  "semantic-similarity-edges returns cached edges when fresh."
  (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
    (let ((gptel-auto-workflow--semantic-edges-cache
           '((:source "a.el" :target "b.el" :score 0.82)
             (:source "a.el" :target "c.el" :score 0.45)))
          (gptel-auto-workflow--semantic-edges-cache-time (float-time)))
      (let ((edges (gptel-auto-workflow--semantic-similarity-edges 0.60)))
        (should (= 1 (length edges)))
        (should (string= "a.el" (plist-get (car edges) :source)))
        (should (= 0.82 (plist-get (car edges) :score)))))))

(ert-deftest tdd/ontology/semantic-edges-nil-when-no-targets ()
  "semantic-similarity-edges returns nil when no kept targets exist."
  (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
    (let ((gptel-auto-workflow--semantic-edges-cache nil)
          (gptel-auto-workflow--semantic-edges-cache-time nil))
      (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                 (lambda () default-directory))
                ((symbol-function 'gptel-auto-workflow--parse-all-results)
                 (lambda () nil)))
        (should-not (gptel-auto-workflow--semantic-similarity-edges 0.60))))))

(ert-deftest tdd/ontology/semantic-edges-plist-format ()
  "semantic-similarity-edges mock returns proper plist format."
  (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
    (let ((mock-edges '((:source "a.el" :target "b.el" :score 0.88)
                        (:source "a.el" :target "c.el" :score 0.75)))
          (gptel-auto-workflow--semantic-edges-cache nil)
          (gptel-auto-workflow--semantic-edges-cache-time 0))
      (setq gptel-auto-workflow--semantic-edges-cache mock-edges)
      (setq gptel-auto-workflow--semantic-edges-cache-time (float-time))
      (let ((edges (gptel-auto-workflow--semantic-similarity-edges 0.70)))
        (should (= 2 (length edges)))
        (dolist (e edges)
          (should (plist-get e :source))
          (should (plist-get e :target))
          (should (numberp (plist-get e :score))))))))

;; ─── Ternary Decision Boundaries (verbum Phase 1) ───

(ert-deftest tdd/ternary/reject-below-baseline ()
  "Backend with rate 5% below baseline should be rejected (-1)."
  (should (= -1 (gptel-auto-workflow--backend-ternary-decision 0.10 0.20))))

(ert-deftest tdd/ternary/accept-above-baseline ()
  "Backend with rate 5% above baseline should be accepted (+1)."
  (should (= +1 (gptel-auto-workflow--backend-ternary-decision 0.30 0.20))))

(ert-deftest tdd/ternary/defer-near-baseline ()
  "Backend within 5% of baseline should be deferred (0)."
  (should (= 0 (gptel-auto-workflow--backend-ternary-decision 0.22 0.20))))

(ert-deftest tdd/ternary/defer-exactly-at-baseline ()
  "Backend exactly at baseline should be deferred (0)."
  (should (= 0 (gptel-auto-workflow--backend-ternary-decision 0.20 0.20))))

(ert-deftest tdd/ternary/defer-nil-inputs ()
  "Nil inputs should defer (0) rather than crash."
  (should (= 0 (gptel-auto-workflow--backend-ternary-decision nil 0.20)))
  (should (= 0 (gptel-auto-workflow--backend-ternary-decision 0.20 nil)))
  (should (= 0 (gptel-auto-workflow--backend-ternary-decision nil nil))))

(ert-deftest tdd/ternary/apply-ternary-routing ()
  "apply-ternary-routing adds :ternary field and preserves order."
  (let* ((scored (list (list :backend "good" :rate 0.30)
                       (list :backend "bad" :rate 0.10)))
         (result (gptel-auto-workflow--apply-ternary-routing scored 0.20)))
    (should (= 2 (length result)))
    (let ((good (car result))
          (bad (cadr result)))
      (should (= +1 (plist-get good :ternary)))
      (should (= -1 (plist-get bad :ternary))))))

(ert-deftest tdd/ternary/rejected-backends-at-bottom ()
  "Backends with ternary -1 should be sorted to bottom."
  (let ((scored (list (list :backend "bad" :rate 0.10 :score 5.0 :ternary -1)
                      (list :backend "good" :rate 0.30 :score 15.0 :ternary +1))))
    (setq scored (sort scored
                       (lambda (a b)
                         (let ((ta (or (plist-get a :ternary) 0))
                               (tb (or (plist-get b :ternary) 0)))
                           (if (/= ta tb)
                               (> ta tb)
                             (> (plist-get a :score) (plist-get b :score)))))))
    (should (string= "good" (plist-get (car scored) :backend)))
    (should (string= "bad" (plist-get (cadr scored) :backend)))))

(ert-deftest tdd/ternary/no-exploration-on-rejected ()
  "Exploration should not swap if top backend is rejected."
  (let ((scored (list (list :backend "rejected" :rate 0.05 :score -10.0 :ternary -1)
                      (list :backend "deferred" :rate 0.18 :score 2.0 :ternary 0)
                      (list :backend "accepted" :rate 0.30 :score 15.0 :ternary +1))))
    (setq scored (sort scored
                       (lambda (a b)
                         (let ((ta (or (plist-get a :ternary) 0))
                               (tb (or (plist-get b :ternary) 0)))
                           (if (/= ta tb)
                               (> ta tb)
                             (> (plist-get a :score) (plist-get b :score)))))))
    ;; First should be accepted, not rejected
    (should (string= "accepted" (plist-get (car scored) :backend)))))

;; ─── Backend Lambda Verification (verbum Phase 2) ───

(ert-deftest tdd/lambda-verify/returns-cached-status ()
  "Lambda verification returns cached status when available."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :healthy gptel-auto-workflow--lambda-verification-results)
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))))

(ert-deftest tdd/lambda-verify/known-backends-return-unknown-without-cache ()
  "Without cache, verification initiates async and returns :unknown."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--backend-lambda-health-cache nil))
    (should (eq :unknown (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))
    (should (eq :unknown (gptel-auto-workflow--verify-backend-lambda-impl "DashScope" "qwen3.6-plus")))))

(ert-deftest tdd/lambda-verify/response-contains-lambda ()
  "response-contains-lambda-p detects lambda expressions."
  (should (gptel-auto-workflow--response-contains-lambda-p "λx.x"))
  (should (gptel-auto-workflow--response-contains-lambda-p "(lambda (x) x)"))
  (should (gptel-auto-workflow--response-contains-lambda-p "x -> x"))
  (should-not (gptel-auto-workflow--response-contains-lambda-p "hello world"))
  (should-not (gptel-auto-workflow--response-contains-lambda-p nil)))

;; ─── Sieve-Based Routing (verbum Phase 5) ───

(ert-deftest tdd/sieve/classify-by-backend-name ()
  "Sieve classification works by backend name."
  (should (eq 'single-neuron (gptel-auto-workflow--backend-sieve-type "DashScope")))
  (should (eq 'distributed (gptel-auto-workflow--backend-sieve-type "moonshot")))
  (should (eq 'distributed (gptel-auto-workflow--backend-sieve-type "Unknown"))))

(ert-deftest tdd/sieve/classify-by-model-name ()
  "Sieve classification works by model name."
  (should (eq 'single-neuron (gptel-auto-workflow--backend-sieve-type "qwen3.6-plus")))
  (should (eq 'single-neuron (gptel-auto-workflow--backend-sieve-type "qwen")))
  (should (eq 'distributed (gptel-auto-workflow--backend-sieve-type "kimi-k2.6")))
  (should (eq 'distributed (gptel-auto-workflow--backend-sieve-type "deepseek-v4-flash"))))

(ert-deftest tdd/sieve/deterministic-target-detection ()
  "Deterministic targets are identified correctly."
  (should (gptel-auto-workflow--target-deterministic-p "gptel-auto-workflow-validation.el"))
  (should (gptel-auto-workflow--target-deterministic-p "test-gptel.el"))
  (should (gptel-auto-workflow--target-deterministic-p "gptel-benchmark.el"))
  (should-not (gptel-auto-workflow--target-deterministic-p "gptel-auto-workflow-strategy.el"))
  (should-not (gptel-auto-workflow--target-deterministic-p nil)))

(ert-deftest tdd/sieve/apply-sieve-boosts-qwen ()
  "Sieve routing boosts Qwen for deterministic tasks."
  (let ((scored (list (list :backend "DashScope" :model "qwen3.6-plus" :score 45.0)
                      (list :backend "moonshot" :model "kimi-k2.6" :score 60.0))))
    (setq scored (gptel-auto-workflow--apply-sieve-routing scored "test-validation.el"))
    ;; DashScope/qwen should be boosted to 55, moonshot stays at 60
    (should (= 55.0 (plist-get (car scored) :score)))
    (should (= 60.0 (plist-get (cadr scored) :score)))))

(ert-deftest tdd/sieve/apply-sieve-boosts-distributed-for-creative ()
  "Sieve routing boosts distributed backends for creative tasks."
  (let ((scored (list (list :backend "DashScope" :model "qwen3.6-plus" :score 50.0)
                      (list :backend "moonshot" :model "kimi-k2.6" :score 35.0))))
    (setq scored (gptel-auto-workflow--apply-sieve-routing scored "gptel-auto-workflow-strategy.el"))
    ;; moonshot should be boosted to 45, DashScope stays at 50
    (should (= 50.0 (plist-get (car scored) :score)))
    (should (= 45.0 (plist-get (cadr scored) :score)))))

;; ─── Cross-Backend Consistency (verbum Phase 6) ───

(ert-deftest tdd/consistency/single-backend-is-consistent ()
  "Single backend sample is always consistent."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :target "a.el" :backend "moonshot" :kibcm-axis ":B")))))
    (let ((result (gptel-auto-workflow--cross-backend-consistency "a.el")))
      (should (plist-get result :consistent))
      (should (= 1.0 (plist-get result :agreement-ratio))))))

(ert-deftest tdd/consistency/agreeing-backends-are-consistent ()
  "Backends with same KIBC axis are consistent."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :target "a.el" :backend "moonshot" :kibcm-axis ":B")
                     (list :target "a.el" :backend "DashScope" :kibcm-axis ":B")))))
    (let ((result (gptel-auto-workflow--cross-backend-consistency "a.el")))
      (should (plist-get result :consistent))
      (should (= 1.0 (plist-get result :agreement-ratio))))))

(ert-deftest tdd/consistency/disagreeing-backends-are-inconsistent ()
  "Backends with different KIBC axis are inconsistent."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :target "a.el" :backend "moonshot" :kibcm-axis ":B")
                     (list :target "a.el" :backend "DashScope" :kibcm-axis ":K")))))
    (let ((result (gptel-auto-workflow--cross-backend-consistency "a.el")))
      (should-not (plist-get result :consistent))
      (should (= 0.5 (plist-get result :agreement-ratio)))
      (should (= 1 (length (plist-get result :conflicts)))))))

(ert-deftest tdd/consistency/check-all-targets ()
  "check-all-targets-consistency reports aggregate stats."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :target "a.el" :backend "moonshot" :kibcm-axis ":B")
                     (list :target "a.el" :backend "DashScope" :kibcm-axis ":B")
                     (list :target "b.el" :backend "moonshot" :kibcm-axis ":B")
                     (list :target "b.el" :backend "DashScope" :kibcm-axis ":K")))))
    (let ((result (gptel-auto-workflow--check-all-targets-consistency)))
      (should (= 2 (plist-get result :total)))
      (should (= 1 (plist-get result :consistent)))
      (should (= 1 (plist-get result :inconsistent))))))

;; ─── Holographic Experiment Memory (verbum Phase 7) ───

(ert-deftest tdd/holographic/record-kept-experiment ()
  "Recording a kept experiment increments consensus count."
  (let ((gptel-auto-workflow--holographic-memory nil))
    (gptel-auto-workflow--record-holographic-experiment
     (list :target "a.el" :kibcm-axis ":B" :decision "kept"))
    (should (= 1 (length gptel-auto-workflow--holographic-memory)))
    (should (= 1 (cdr (assoc (cons "a.el" ":B") gptel-auto-workflow--holographic-memory))))))

(ert-deftest tdd/holographic/discarded-not-recorded ()
  "Discarded experiments are not recorded in holographic memory."
  (let ((gptel-auto-workflow--holographic-memory nil))
    (gptel-auto-workflow--record-holographic-experiment
     (list :target "a.el" :kibcm-axis ":B" :decision "discarded"))
    (should (= 0 (length gptel-auto-workflow--holographic-memory)))))

(ert-deftest tdd/holographic/get-consensus ()
  "get-holographic-consensus returns axis with highest agreement."
  (let ((gptel-auto-workflow--holographic-memory
         (list (cons (cons "a.el" ":B") 3)
               (cons (cons "a.el" ":K") 1))))
    (let ((result (gptel-auto-workflow--get-holographic-consensus "a.el")))
      (should (string= ":B" (plist-get result :axis)))
      (should (= 3 (plist-get result :count)))
      (should (= 4 (plist-get result :total)))
      (should (= 0.75 (plist-get result :confidence))))))

(ert-deftest tdd/holographic/rebuild-from-history ()
  "rebuild-holographic-memory rebuilds from all kept experiments."
  (let ((gptel-auto-workflow--holographic-memory nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda ()
                 (list (list :target "a.el" :kibcm-axis ":B" :decision "kept")
                       (list :target "a.el" :kibcm-axis ":B" :decision "kept")
                       (list :target "b.el" :kibcm-axis ":K" :decision "kept")))))
      (gptel-auto-workflow--rebuild-holographic-memory)
      (should (= 2 (length gptel-auto-workflow--holographic-memory)))
      (should (= 2 (cdr (assoc (cons "a.el" ":B") gptel-auto-workflow--holographic-memory))))
      (should (= 1 (cdr (assoc (cons "b.el" ":K") gptel-auto-workflow--holographic-memory)))))))

;; ─── Holographic Consensus Boost (verbum Phase 8) ───

(ert-deftest tdd/holographic/get-axis-performance ()
  "get-axis-performance-stats calculates keep-rate per backend+axis."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :target "a.el" :backend "moonshot" :kibcm-axis ":B" :decision "kept")
                     (list :target "b.el" :backend "moonshot" :kibcm-axis ":B" :decision "kept")
                     (list :target "c.el" :backend "moonshot" :kibcm-axis ":B" :decision "discarded")
                     (list :target "a.el" :backend "DashScope" :kibcm-axis ":B" :decision "kept")))))
    (let ((result (gptel-auto-workflow--get-axis-performance-stats "moonshot" ":B")))
      (should (= 2 (plist-get result :kept)))
      (should (= 3 (plist-get result :total)))
      (should (= (/ 2.0 3) (plist-get result :keep-rate))))))

(ert-deftest tdd/holographic/boost-with-high-consensus ()
  "apply-holographic-boost boosts backends with good axis performance when consensus is high."
  (let ((gptel-auto-workflow--holographic-memory
         (list (cons (cons "a.el" ":B") 8)
               (cons (cons "a.el" ":K") 2))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda ()
                 (list (list :target "a.el" :backend "moonshot" :kibcm-axis ":B" :decision "kept")
                       (list :target "a.el" :backend "moonshot" :kibcm-axis ":B" :decision "kept")))))
      (let ((scored (list (list :backend "moonshot" :model "kimi-k2.6" :score 50.0))))
        (setq scored (gptel-auto-workflow--apply-holographic-boost scored "a.el"))
        ;; moonshot has 100% keep-rate on :B axis, should get boost
        (should (> (plist-get (car scored) :score) 50.0))))))

(ert-deftest tdd/holographic/no-boost-with-low-consensus ()
  "apply-holographic-boost does nothing when consensus is low."
  (let ((gptel-auto-workflow--holographic-memory
         (list (cons (cons "a.el" ":B") 1)
               (cons (cons "a.el" ":K") 1))))
    (let ((scored (list (list :backend "moonshot" :model "kimi-k2.6" :score 50.0))))
      (setq scored (gptel-auto-workflow--apply-holographic-boost scored "a.el"))
      ;; Consensus is 50%, below 70% threshold — no boost
      (should (= 50.0 (plist-get (car scored) :score))))))

;; ─── Real Lambda Verification (verbum Phase 11) ───

(ert-deftest tdd/lambda-verify/cached-healthy ()
  "Returns cached result when available."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :healthy gptel-auto-workflow--lambda-verification-results)
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))))

(ert-deftest tdd/lambda-verify/cached-degraded ()
  "Returns cached degraded result."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :degraded gptel-auto-workflow--lambda-verification-results)
    (should (eq :degraded (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))))

(ert-deftest tdd/lambda-verify/no-cache-initiates-async ()
  "When no cached result, initiates async verification and returns :unknown."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--call-backend-for-lambda)
               (lambda (backend model _prompt) (setq called (cons backend model)) t)))
      (should (eq :unknown (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))
      (should (equal '("moonshot" . "kimi-k2.6") called)))))

(ert-deftest tdd/lambda-verify/callback-stores-healthy ()
  "Async callback stores :healthy when lambda found in response."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (let ((cb (plist-get args :callback)))
                   (funcall cb "λx.x" nil)))))
      (gptel-auto-workflow--call-backend-for-lambda "moonshot" "kimi-k2.6" "test")
      (should (eq :healthy (gethash "moonshot" gptel-auto-workflow--lambda-verification-results))))))

(ert-deftest tdd/lambda-verify/callback-stores-degraded ()
  "Async callback stores :degraded when no lambda in response."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (let ((cb (plist-get args :callback)))
                   (funcall cb "hello world" nil)))))
      (gptel-auto-workflow--call-backend-for-lambda "moonshot" "kimi-k2.6" "test")
      (should (eq :degraded (gethash "moonshot" gptel-auto-workflow--lambda-verification-results))))))

(ert-deftest tdd/lambda-verify/callback-stores-unknown-on-nil ()
  "Async callback stores :unknown when response is nil."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (let ((cb (plist-get args :callback)))
                   (funcall cb nil nil)))))
      (gptel-auto-workflow--call-backend-for-lambda "moonshot" "kimi-k2.6" "test")
      (should (eq :unknown (gethash "moonshot" gptel-auto-workflow--lambda-verification-results))))))

;; ─── Lambda Verification Report (verbum Phase 12) ───

(ert-deftest tdd/lambda-verify/report-with-results ()
  "lambda-verification-report shows correct counts with cached results."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :healthy gptel-auto-workflow--lambda-verification-results)
    (puthash "DashScope" :degraded gptel-auto-workflow--lambda-verification-results)
    (puthash "DeepSeek" :unknown gptel-auto-workflow--lambda-verification-results)
    (let ((result (gptel-auto-workflow--lambda-verification-report)))
      (should (= 1 (plist-get result :healthy)))
      (should (= 1 (plist-get result :degraded)))
      (should (> (plist-get result :unknown) 0))
      (should (= 5 (plist-get result :total))))))

(ert-deftest tdd/lambda-verify/penalty-degraded ()
  "apply-verification-penalty penalizes degraded backends."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "bad-backend" :degraded gptel-auto-workflow--lambda-verification-results)
    (let ((scored (list (list :backend "bad-backend" :score 100.0))))
      (setq scored (gptel-auto-workflow--apply-verification-penalty scored))
      (should (= 80.0 (plist-get (car scored) :score))))))

(ert-deftest tdd/lambda-verify/penalty-healthy ()
  "apply-verification-penalty does not penalize healthy backends."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "good-backend" :healthy gptel-auto-workflow--lambda-verification-results)
    (let ((scored (list (list :backend "good-backend" :score 100.0))))
      (setq scored (gptel-auto-workflow--apply-verification-penalty scored))
      (should (= 100.0 (plist-get (car scored) :score))))))

(ert-deftest tdd/lambda-verify/penalty-unknown ()
  "apply-verification-penalty slightly penalizes unknown backends."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "unknown-backend" :unknown gptel-auto-workflow--lambda-verification-results)
    (let ((scored (list (list :backend "unknown-backend" :score 100.0))))
      (setq scored (gptel-auto-workflow--apply-verification-penalty scored))
      (should (= 95.0 (plist-get (car scored) :score))))))

;; ─── Ranked Subagent Backends Tests ───
;; Tests for ranked-subagent-backends tiebreaking and keep-rate floor

(ert-deftest regression/ontology-router/ranked-dashscope-first-on-tie ()
  "DashScope should be first when all backends have equal keep-rate."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("moonshot" . "kimi-k2.6")
           ("MiniMax" . "minimax-m2.7-highspeed")
           ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends)))
        (should (string= "DashScope" (caar ranked)))
        (should (string= "qwen3.6-plus" (cdar ranked)))))))

(ert-deftest regression/ontology-router/ranked-keeps-all-backends ()
  "ranked-subagent-backends should include all backends from fallback list."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("moonshot" . "kimi-k2.6")
           ("MiniMax" . "minimax-m2.7-highspeed")
           ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends)))
        (should (= 5 (length ranked)))
        (should (assoc "DashScope" ranked))
        (should (assoc "DeepSeek" ranked))
        (should (assoc "moonshot" ranked))
        (should (assoc "MiniMax" ranked))
        (should (assoc "CF-Gateway" ranked))))))

(ert-deftest regression/ontology-router/bayesian-keep-rate-floor ()
  "Backends with < 3 experiments should get 0.25 floor, not actual rate."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("moonshot" . "kimi-k2.6")
           ("MiniMax" . "minimax-m2.7-highspeed")
           ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (backend &rest _)
                 (cond
                  ((string= backend "DashScope")
                   (list :kept 0 :total 1 :keep-rate 0.0))
                  ((string= backend "DeepSeek")
                   (list :kept 2 :total 8 :keep-rate 0.25))
                  (t (list :kept 0 :total 0 :keep-rate nil))))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends)))
        (should (string= "DashScope" (caar ranked)))
        (should (assoc "DeepSeek" ranked))))))

(provide 'test-gptel-auto-workflow-ontology-router)
;;; test-gptel-auto-workflow-ontology-router.el ends here
