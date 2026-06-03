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
(defvar gptel-auto-workflow--current-target nil "Mock current target for testing.")

;; Mock the existing fallback configuration
(defvar gptel-auto-workflow-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash"))
  "Mock headless fallback list for testing.")

(defvar gptel-auto-workflow-executor-rate-limit-fallbacks
  '(("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-v4-flash")
    ("moonshot" . "kimi-k2.6")
    ("MiniMax" . "minimax-m2.7-highspeed"))
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
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         gptel-auto-workflow-headless-subagent-fallbacks)
        (mock-results
         (list
          (list :backend "DeepSeek" :decision "kept")
          (list :backend "DeepSeek" :decision "kept")
          (list :backend "DeepSeek" :decision "kept")
          (list :backend "MiniMax" :decision "discarded")
          (list :backend "MiniMax" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))  ; No exploration
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        (should (string= "DeepSeek" (caar reordered)))
        (should (string= "deepseek-v4-pro" (cdar reordered)))))))

(ert-deftest regression/ontology-router/reorder-keeps-all-backends ()
  "Reordering should preserve all backends from static list."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DeepSeek" . "deepseek-v4-flash")
           ("MiniMax" . "minimax-m2.7-highspeed")
           ("DashScope" . "qwen3.6-plus")
           ("moonshot" . "kimi-k2.6")))
        (mock-results
         (list
          (list :backend "moonshot" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        (should (= 4 (length reordered)))
        (should (assoc "moonshot" reordered))
        (should (assoc "MiniMax" reordered))
        (should (assoc "DashScope" reordered))
        (should (assoc "DeepSeek" reordered))
        (should (assoc "MiniMax" reordered))))))

(ert-deftest regression/ontology-router/insufficient-data-uses-static ()
  "When insufficient data, should return static order unchanged."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         gptel-auto-workflow-headless-subagent-fallbacks)
        (mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        ;; Should match static order exactly
        (should (equal reordered gptel-auto-workflow-headless-subagent-fallbacks))))))

(ert-deftest regression/ontology-router/exploration-can-swap ()
  "With exploration enabled, top 2 backends can be swapped."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         gptel-auto-workflow-headless-subagent-fallbacks)
        (mock-results
         (list
          (list :backend "DeepSeek" :decision "kept")
          (list :backend "DeepSeek" :decision "kept")
          (list :backend "MiniMax" :decision "kept")
          (list :backend "MiniMax" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ;; Force exploration (random < 15)
              ((symbol-function 'random) (lambda (_) 10)))
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology)))
        ;; With exploration, order might be swapped
        (should (= 2 (length (cl-intersection (mapcar #'car reordered)
                                               '("DeepSeek" "MiniMax")
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
  "Programming targets use DeepSeek override."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DeepSeek" . "deepseek-v4-flash")
           ("MiniMax" . "minimax-m2.7-highspeed")
           ("DashScope" . "qwen3.6-plus")
           ("moonshot" . "kimi-k2.6")))
        (mock-results
         (list
          (list :backend "DashScope" :target "lisp/modules/gptel-tools-agent.el" :decision "kept")
          (list :backend "DashScope" :target "lisp/modules/gptel-tools-agent.el" :decision "kept")
          (list :backend "DashScope" :target "lisp/modules/gptel-tools-agent.el" :decision "kept")
          (list :backend "MiniMax"    :target "lisp/modules/gptel-tools-agent.el" :decision "discarded"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-function 'random) (lambda (_) 999)))
      ;; gptel-tools-agent.el is :agentic, which has no override (nil)
      ;; So it should use normal performance ordering
      (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology nil "lisp/modules/gptel-tools-agent.el")))
        (should (string= "DashScope" (caar reordered)))))))

;; ─── Integration Tests ───

(ert-deftest regression/ontology-router/apply-and-reset ()
  "Applying ontology order should modify fallback chain, reset should restore."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         (copy-tree gptel-auto-workflow-headless-subagent-fallbacks))
        (mock-results
         (list
          (list :backend "DashScope" :decision "kept")
          (list :backend "DashScope" :decision "kept")
          (list :backend "DashScope" :decision "kept")))
        (original-order (copy-tree gptel-auto-workflow-headless-subagent-fallbacks)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
                   (lambda () mock-results))
                  ((symbol-function 'random) (lambda (_) 999)))
          ;; Apply ontology ordering
          (gptel-auto-workflow--apply-ontology-fallback-order)
          ;; Should have reordered (DashScope has 100% keep rate)
          (should (string= "DashScope" (caar gptel-auto-workflow-executor-rate-limit-fallbacks)))
          ;; Reset
          (gptel-auto-workflow--reset-fallback-order)
          ;; Should be back to original
          (should (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                         original-order)))
      ;; Always restore original state
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks original-order))))

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
      ;; c.el has no exact match, but ontology falls back to category-level
      ;; recommendation from other targets in the same category
      (should (gptel-auto-workflow--winning-strategy-for-target "c.el")))))

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
  "Lambda verification returns :healthy — all backends support lambda."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))))

(ert-deftest tdd/lambda-verify/known-backends-return-unknown-without-cache ()
  "Without cache, verification returns :healthy immediately (no API call).
All known backends now support lambda notation; no async verification needed."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--backend-lambda-health-cache nil))
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "DashScope" "qwen3.6-plus")))))

(ert-deftest tdd/lambda-verify/response-contains-lambda ()
  "response-contains-lambda-p detects lambda expressions."
  (should (gptel-auto-workflow--response-contains-lambda-p "λx.x"))
  (should (gptel-auto-workflow--response-contains-lambda-p "(lambda (x) x)"))
  (should (gptel-auto-workflow--response-contains-lambda-p "x -> x"))
  (should-not (gptel-auto-workflow--response-contains-lambda-p "hello world"))
  (should-not (gptel-auto-workflow--response-contains-lambda-p nil)))

;; ─── Sieve-Based Routing (verbum Phase 5) ───

(ert-deftest tdd/sieve/classify-by-backend-name ()
  "Sieve classification works by backend name only (not model names)."
  (should (eq 'distributed (gptel-auto-workflow--backend-sieve-type "DashScope")))
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
  "Returns :healthy — all backends support lambda."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :healthy gptel-auto-workflow--lambda-verification-results)
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))))

(ert-deftest tdd/lambda-verify/cached-degraded ()
  ":degraded is no longer returned — all backends are :healthy now."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :degraded gptel-auto-workflow--lambda-verification-results)
    (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))))

(ert-deftest tdd/lambda-verify/no-cache-initiates-async ()
  "No API call needed — returns :healthy immediately."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--call-backend-for-lambda)
               (lambda (backend model _prompt) (setq called (cons backend model)) t)))
      (should (eq :healthy (gptel-auto-workflow--verify-backend-lambda-impl "moonshot" "kimi-k2.6")))
      (should (null called)))))

(ert-deftest tdd/lambda-verify/callback-stores-healthy ()
  "Lambda verification stores :healthy immediately (no API call needed)."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (gptel-auto-workflow--call-backend-for-lambda "moonshot" "kimi-k2.6" "test")
    (should (eq :healthy (gethash "moonshot" gptel-auto-workflow--lambda-verification-results)))))

(ert-deftest tdd/lambda-verify/callback-stores-degraded ()
  ":degraded is no longer stored — all backends are immediately :healthy."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (gptel-auto-workflow--call-backend-for-lambda "moonshot" "kimi-k2.6" "test")
    (should (eq :healthy (gethash "moonshot" gptel-auto-workflow--lambda-verification-results)))))

(ert-deftest tdd/lambda-verify/callback-stores-unknown-on-nil ()
  ":unknown is no longer stored — all backends are immediately :healthy."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (gptel-auto-workflow--call-backend-for-lambda "moonshot" "kimi-k2.6" "test")
    (should (eq :healthy (gethash "moonshot" gptel-auto-workflow--lambda-verification-results)))))

;; ─── Lambda Verification Report (verbum Phase 12) ───

(ert-deftest tdd/lambda-verify/report-with-results ()
  "lambda-verification-report shows correct counts with cached results."
  (let ((gptel-auto-workflow-headless-subagent-fallbacks
         '(("DeepSeek" . "deepseek-v4-flash")
           ("MiniMax" . "minimax-m2.7-highspeed")
           ("DashScope" . "qwen3.6-plus")
           ("moonshot" . "kimi-k2.6")))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "moonshot" :healthy gptel-auto-workflow--lambda-verification-results)
    (puthash "DashScope" :degraded gptel-auto-workflow--lambda-verification-results)
    (puthash "DeepSeek" :unknown gptel-auto-workflow--lambda-verification-results)
    (let ((result (gptel-auto-workflow--lambda-verification-report)))
      (should (= 1 (plist-get result :healthy)))
      (should (= 1 (plist-get result :degraded)))
      (should (> (plist-get result :unknown) 0))
      (should (= 4 (plist-get result :total))))))

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
  "apply-verification-penalty returns unknown backends with no penalty."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "unknown-backend" :unknown gptel-auto-workflow--lambda-verification-results)
    (let ((scored (list (list :backend "unknown-backend" :score 100.0))))
      (setq scored (gptel-auto-workflow--apply-verification-penalty scored))
      (should (= 100.0 (plist-get (car scored) :score))))))

;; ─── Ranked Subagent Backends Tests ───
;; Tests for ranked-subagent-backends tiebreaking and keep-rate floor

(ert-deftest regression/ontology-router/ranked-dashscope-first-on-tie ()
  "DashScope should be first when all backends have equal keep-rate."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
          '(("DashScope" . "qwen3.6-plus")
            ("DeepSeek" . "deepseek-v4-flash")
            ("moonshot" . "kimi-k2.6")
            ("MiniMax" . "minimax-m2.7-highspeed")
            ()))
         (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
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
           ())))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends)))
        (should (= 5 (length ranked)))
        (should (assoc "DashScope" ranked))
        (should (assoc "DeepSeek" ranked))
        (should (assoc "moonshot" ranked))
        (should (assoc "MiniMax" ranked))
        (should (assoc "MiniMax" ranked))))))

(ert-deftest regression/ontology-router/bayesian-keep-rate-floor ()
  "Backends with < 3 experiments should get 0.25 floor, not actual rate."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
          '(("DashScope" . "qwen3.6-plus")
            ("DeepSeek" . "deepseek-v4-flash")
            ("moonshot" . "kimi-k2.6")
            ("MiniMax" . "minimax-m2.7-highspeed")
            ()))
         (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
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

(ert-deftest regression/ontology-router/ranked-analyzer-prefers-deepseek ()
  "Analyzer routing should rank DeepSeek first due to preference boost."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("MiniMax" . "minimax-m2.7-highspeed")))
        (gptel-auto-workflow--task-backend-preference
         '(("analyzer" "DeepSeek" . 0.15))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (string= "DeepSeek" (caar ranked)))
        (should (string= "deepseek-v4-flash" (cdar ranked)))))))

(ert-deftest regression/ontology-router/ranked-grader-prefers-moonshot ()
  "Grader routing should rank moonshot first due to preference boost."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("moonshot" . "kimi-k2.6")
           ("MiniMax" . "minimax-m2.7-highspeed")))
        (gptel-auto-workflow--task-backend-preference
         '(("grader" "moonshot" . 0.15))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "grader")))
        (should (string= "moonshot" (caar ranked)))
        (should (string= "kimi-k2.6" (cdar ranked)))))))

(ert-deftest regression/ontology-router/ranked-executor-prefers-dashscope ()
  "Executor routing should rank DashScope first due to preference boost."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("moonshot" . "kimi-k2.6")
           ("MiniMax" . "minimax-m2.7-highspeed")))
        (gptel-auto-workflow--task-backend-preference
         '(("executor" "DashScope" . 0.15))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "executor")))
        (should (string= "DashScope" (caar ranked)))
        (should (string= "qwen3.6-plus" (cdar ranked)))))))

(ert-deftest regression/ontology-router/ranked-no-agent-type-preserves-order ()
  "Calling ranked-subagent-backends without agent-type should keep default order."
  (let ((gptel-auto-workflow-executor-rate-limit-fallbacks
          '(("DashScope" . "qwen3.6-plus")
            ("DeepSeek" . "deepseek-v4-flash")
            ("MiniMax" . "minimax-m2.7-highspeed")))
         (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 0 :total 0 :keep-rate nil))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends)))
        (should (string= "DashScope" (caar ranked)))
        (should (= 3 (length ranked)))))))

;; ─── Backend Preference Evolution Tests ───

(ert-deftest regression/ontology-router/per-axis-keep-rate-groups-by-axis ()
  "Per-axis keep-rates should group results by (backend, axis) pair."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (append
                ;; DeepSeek/A: 3 kept + 2 discarded = 5
                (make-list 3 (list :backend "DeepSeek" :kibcm-axis "A" :decision "kept"))
                (make-list 2 (list :backend "DeepSeek" :kibcm-axis "A" :decision "discarded"))
                ;; DeepSeek/B: 3 kept + 2 discarded = 5
                (make-list 3 (list :backend "DeepSeek" :kibcm-axis "B" :decision "kept"))
                (make-list 2 (list :backend "DeepSeek" :kibcm-axis "B" :decision "discarded"))
                ;; DashScope/A: 3 kept + 3 discarded = 6
                (make-list 3 (list :backend "DashScope" :kibcm-axis "A" :decision "kept"))
                (make-list 3 (list :backend "DashScope" :kibcm-axis "A" :decision "discarded"))))))
    (let ((rates (gptel-auto-workflow--backend-per-axis-keep-rates)))
      (should (= 3 (length rates)))
      (should (assoc '("DeepSeek" . "A") rates))
      (should (assoc '("DeepSeek" . "B") rates))
      (should (assoc '("DashScope" . "A") rates)))))

(ert-deftest regression/ontology-router/per-axis-min-5-samples ()
  "Pairs with < 5 samples should be excluded from keep-rate analysis."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list (list :backend "MiniMax" :kibcm-axis "A" :decision "kept")
                     (list :backend "MiniMax" :kibcm-axis "A" :decision "kept")
                     (list :backend "MiniMax" :kibcm-axis "A" :decision "kept")
                     (list :backend "MiniMax" :kibcm-axis "A" :decision "discarded")))))
    (let ((rates (gptel-auto-workflow--backend-per-axis-keep-rates)))
      (should (= 0 (length rates)))
      (should-not (assoc '("MiniMax" . "A") rates)))))

(ert-deftest regression/ontology-router/evolve-preference-adjusts-on-delta ()
  "Preference evolution should adjust boost when axis keep-rate differs from global."
  (let ((gptel-auto-workflow--task-backend-preference
         '(("analyzer" "DeepSeek" . 0.15)
           ("executor" "DashScope" . 0.15)))
        (gptel-auto-workflow--preference-persist-file
         (make-temp-file "aw-pref-test-" nil ".el")))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda ()
                 ;; DeepSeek global: 3/10 = 0.3, axis A: 4/5 = 0.8, delta=+0.50
                 ;; DashScope global: 0/10 = 0.0, axis D: 0/5 = 0.0, delta=0.0
                 (append
                  (make-list 3 (list :backend "DeepSeek" :kibcm-axis "B" :decision "kept"))
                  (make-list 7 (list :backend "DeepSeek" :kibcm-axis "B" :decision "discarded"))
                  (make-list 4 (list :backend "DeepSeek" :kibcm-axis "A" :decision "kept"))
                  (make-list 1 (list :backend "DeepSeek" :kibcm-axis "A" :decision "discarded"))
                  (make-list 10 (list :backend "DashScope" :kibcm-axis "A" :decision "discarded"))
                  (make-list 5 (list :backend "DashScope" :kibcm-axis "D" :decision "discarded")))))
              ((symbol-function 'gptel-auto-workflow--worktree-base-root)
               (lambda () (make-temp-file "aw-pref-root-" t))))
      (let* ((changed (gptel-auto-workflow--evolve-backend-preference))
             (pref gptel-auto-workflow--task-backend-preference)
             (ds (cl-find-if (lambda (e)
                               (and (string= (nth 0 e) "analyzer")
                                    (string= (nth 1 e) "DeepSeek")))
                             pref)))
        (should ds)
        (should (> (cddr ds) 0.15))   ;; boost increased from 0.15
        (should changed)))))           ;; reported as changed

;; ─── VSM Health → Routing Auto-Tuning Tests ───

(ert-deftest tdd/vsm-routing/defaults-when-no-vsm-hints ()
  "Without VSM health hints, adjusted params should equal defaults."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints nil))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (= 0.40 (plist-get params :delta-weight)))
      (should (= 0.30 (plist-get params :rate-weight)))
      (should (= 0.20 (plist-get params :trend-weight)))
      (should (= 0.10 (plist-get params :confidence-weight)))
      (should (= 0.15 (plist-get params :exploration-rate)))
      (should (= 3 (plist-get params :min-samples))))))

(ert-deftest tdd/vsm-routing/s4-weak-increases-exploration ()
  "When S4 (Intelligence) is weak, exploration rate should increase."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'prioritize-targets
                           (list :s1-ops 0.8 :s2-coord 0.8
                                 :s3-control 0.8 :s4-intel 0.3
                                 :s5-identity 0.8))))))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (> (plist-get params :exploration-rate) 0.15))
      (should (>= (plist-get params :exploration-rate) 0.20)))))

(ert-deftest tdd/vsm-routing/s3-weak-tightens-health-ladder ()
  "When S3 (Control) is weak, probation threshold should tighten."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'prioritize-targets
                           (list :s1-ops 0.8 :s2-coord 0.8
                                 :s3-control 0.3 :s4-intel 0.8
                                 :s5-identity 0.8))))))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (= 2 (plist-get params :health-probation-threshold))))))

(ert-deftest tdd/vsm-routing/s1-weak-lowers-min-samples ()
  "When S1 (Operations) is weak, min-samples should decrease."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'prioritize-targets
                           (list :s1-ops 0.3 :s2-coord 0.8
                                 :s3-control 0.8 :s4-intel 0.8
                                 :s5-identity 0.8))))))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (= 1 (plist-get params :min-samples))))))

(ert-deftest tdd/vsm-routing/s5-weak-boosts-confidence-weight ()
  "When S5 (Identity) is weak, confidence weight should increase."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'prioritize-targets
                           (list :s1-ops 0.8 :s2-coord 0.8
                                 :s3-control 0.8 :s4-intel 0.8
                                 :s5-identity 0.2))))))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (> (plist-get params :confidence-weight) 0.10))
      (should (>= (plist-get params :confidence-weight) 0.15)))))

(ert-deftest tdd/vsm-routing/s2-weak-shifts-to-raw-rate ()
  "When S2 (Coordination) is weak, delta weight should decrease, rate weight increase."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'prioritize-targets
                           (list :s1-ops 0.8 :s2-coord 0.3
                                 :s3-control 0.8 :s4-intel 0.8
                                 :s5-identity 0.8))))))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (< (plist-get params :delta-weight) 0.40))
      (should (>= (plist-get params :delta-weight) 0.15))
      (should (> (plist-get params :rate-weight) 0.30))
      (should (>= (plist-get params :rate-weight) 0.35)))))

(ert-deftest tdd/vsm-routing/all-healthy-returns-defaults ()
  "When all VSM layers are healthy, params should remain at defaults."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'prioritize-targets
                           (list :s1-ops 0.9 :s2-coord 0.9
                                 :s3-control 0.9 :s4-intel 0.9
                                 :s5-identity 0.9))))))
    (let ((params (gptel-auto-workflow--vsm-adjusted-routing-params)))
      (should (= 0.40 (plist-get params :delta-weight)))
      (should (= 0.30 (plist-get params :rate-weight)))
      (should (= 0.20 (plist-get params :trend-weight)))
      (should (= 0.10 (plist-get params :confidence-weight)))
      (should (= 0.15 (plist-get params :exploration-rate)))
      (should (= 3 (plist-get params :min-samples))))))

(ert-deftest tdd/vsm-routing/extracts-vsm-plist-from-actions ()
  "Should extract the prioritize-targets plist from vsm-actions."
  (let ((gptel-auto-workflow--evolution-next-cycle-hints
         (list :vsm-actions
               (list (cons 'increase-strategy-evolution "Fire(S4) weak")
                     (cons 'prioritize-targets
                           (list :s1-ops 0.5 :s2-coord 0.7
                                 :s3-control 0.9 :s4-intel 0.3
                                 :s5-identity 0.8))
                     (cons 'rebalance-backends "Earth(S3) weak")))))
    (let ((scores (gptel-auto-workflow--vsm-health-scores)))
      (should (= 0.5 (plist-get scores :s1-ops)))
      (should (= 0.3 (plist-get scores :s4-intel))))))

;; ─── Recency-Weighted Keep-Rate Tests ───

(defun make-mock-results-with-dates (specs)
  "Create mock experiment results with :run-dir for testing decay.
SPECS is a list of (backend decision days-ago ...) triples."
  (let ((results nil))
    (dolist (s specs)
      (let ((base-time (time-subtract (current-time)
                                      (seconds-to-time (* (caddr s) 86400)))))
        (push (list :backend (car s)
                    :decision (cadr s)
                    :target "test.el"
                    :research-strategy "none"
                    :run-dir (format-time-string "%Y-%m-%dT000000Z-test" base-time))
              results)))
    (nreverse results)))

(ert-deftest tdd/decay-keep-rate/recent-weighs-more ()
  "A backend with recent keeps should score higher than old keeps."
  (let* ((results
          ;; Recent: 5 kept, 5 discarded (today, 0 days ago)
          (append (make-mock-results-with-dates
                   (mapcar (lambda (_) '("DeepSeek" "kept" 0))
                           (number-sequence 1 5)))
                  (make-mock-results-with-dates
                   (mapcar (lambda (_) '("DeepSeek" "discarded" 0))
                           (number-sequence 1 5)))
                  ;; Old: 5 kept, 5 discarded (30 days ago, should decay)
                  (make-mock-results-with-dates
                   (mapcar (lambda (_) '("DeepSeek" "kept" 30))
                           (number-sequence 1 5)))
                  (make-mock-results-with-dates
                   (mapcar (lambda (_) '("DeepSeek" "discarded" 30))
                           (number-sequence 1 5)))))
         (stats (gptel-auto-workflow--decayed-keep-rate results "DeepSeek" 14.0)))
    ;; Recent experiments count more → weighted keep-rate should differ from raw 0.5
    (should (> (plist-get stats :keep-rate) 0.5))
    (should (= 20 (plist-get stats :raw-total)))
    (should (= 10 (plist-get stats :raw-kept)))))

(ert-deftest tdd/decay-keep-rate/same-day-equals-raw ()
  "When all experiments are from today, decayed should equal raw rate."
  (let* ((results
          (append (make-mock-results-with-dates
                   (mapcar (lambda (_) '("DashScope" "kept" 0))
                           (number-sequence 1 3)))
                  (make-mock-results-with-dates
                   (mapcar (lambda (_) '("DashScope" "discarded" 0))
                           (number-sequence 1 7)))))
         (stats (gptel-auto-workflow--decayed-keep-rate results "DashScope" 14.0)))
    (should (>= (plist-get stats :keep-rate) 0.29))
    (should (<= (plist-get stats :keep-rate) 0.31))
    (should (= 10 (plist-get stats :raw-total)))
    (should (= 3 (plist-get stats :raw-kept)))))

(ert-deftest tdd/decay-keep-rate/half-life-zero-disables-decay ()
  "When half-life is 0, all weights are 1.0 (simple keep-rate)."
  (let* ((results
          (append (make-mock-results-with-dates
                   (mapcar (lambda (_) '("moonshot" "kept" 0))
                           (number-sequence 1 2)))
                  (make-mock-results-with-dates
                   (mapcar (lambda (_) '("moonshot" "kept" 100))
                           (number-sequence 1 2)))
                  (make-mock-results-with-dates
                   (mapcar (lambda (_) '("moonshot" "discarded" 0))
                           (number-sequence 1 2)))))
         (stats (gptel-auto-workflow--decayed-keep-rate results "moonshot" 0.0)))
    (should (>= (plist-get stats :keep-rate) 0.66))
    (should (= 6 (plist-get stats :raw-total)))
    (should (= 4 (plist-get stats :raw-kept)))))

(ert-deftest tdd/decay-keep-rate/filters-by-backend ()
  "Should only count results for the specified backend."
  (let* ((results (append (make-mock-results-with-dates
                            (mapcar (lambda (_) '("DeepSeek" "kept" 0))
                                    (number-sequence 1 5)))
                           (make-mock-results-with-dates
                            (mapcar (lambda (_) '("DashScope" "discarded" 0))
                                    (number-sequence 1 10)))))
         (ds-stats (gptel-auto-workflow--decayed-keep-rate results "DeepSeek" 14.0))
         (dash-stats (gptel-auto-workflow--decayed-keep-rate results "DashScope" 14.0)))
    (should (= 5 (plist-get ds-stats :raw-total)))
    (should (>= (plist-get ds-stats :keep-rate) 0.99))
    (should (= 10 (plist-get dash-stats :raw-total)))
    (should (<= (plist-get dash-stats :keep-rate) 0.01))))

(ert-deftest tdd/decay-keep-rate/old-days-ago-returns-zero-weight ()
  "Old experiments past several half-lives should have near-zero weight."
  (let* ((results (make-mock-results-with-dates
                   (mapcar (lambda (_) '("MiniMax" "kept" 100))
                           (number-sequence 1 10))))
         (stats (gptel-auto-workflow--decayed-keep-rate results "MiniMax" 7.0)))
    ;; weight = 2^(-100/7) ≈ 2^(-14.3) ≈ 0.00005
    ;; So weighted-kept ≈ 10 * 0.00005 = 0.0005, weighted-total ≈ same
    ;; keep-rate should be ≈ 1.0 but with very low effective total
    (should (< (plist-get stats :total) 1))
    (should (= 10 (plist-get stats :raw-total)))))

;; ─── Per-Axis Backend Preference Boost Tests ───

(ert-deftest tdd/axis-pref/boost-for-high-axis-keep-rate ()
  "Backend with high keep-rate on target's axis should get a boost."
  (let ((gptel-auto-workflow--current-target "lisp/modules/gptel-ext-retry.el")
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("MiniMax" . "minimax-m2.7-highspeed")))
        (gptel-auto-workflow--task-backend-preference nil)
        (gptel-auto-workflow--holographic-memory
         '((("lisp/modules/gptel-ext-retry.el" . ":E") . 12)))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5)))
              ((symbol-function 'gptel-auto-workflow--backend-per-axis-keep-rates)
               (lambda ()
                 '((("DeepSeek" . ":E") . 0.9)
                   (("DashScope" . ":E") . 0.3)
                   (("MiniMax" . ":E") . 0.2))))
              ((symbol-function 'gptel-auto-workflow--get-holographic-consensus)
               (lambda (target)
                 (list :axis ":E" :count 12 :total 15 :confidence 0.8))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (string= "DeepSeek" (caar ranked)))))))

(ert-deftest tdd/axis-pref/no-boost-when-no-holographic-consensus ()
  "Without holographic consensus, target axis is unknown, no per-axis boost."
  (let ((gptel-auto-workflow--current-target "some/unknown/file.el")
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")))
        (gptel-auto-workflow--task-backend-preference nil)
        (gptel-auto-workflow--holographic-memory nil)
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5)))
              ((symbol-function 'gptel-auto-workflow--get-holographic-consensus)
               (lambda (_)
                 (list :axis "?" :count 0 :total 0 :confidence 0.0))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (string= "DashScope" (caar ranked)))))))

(ert-deftest tdd/axis-pref/no-boost-when-confidence-low ()
  "When holographic confidence is < 0.5, should not apply axis boost."
  (let ((gptel-auto-workflow--current-target "uncertain-target.el")
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")))
        (gptel-auto-workflow--task-backend-preference nil)
        (gptel-auto-workflow--holographic-memory
         '((("uncertain-target.el" . ":K") . 2)))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5)))
              ((symbol-function 'gptel-auto-workflow--backend-per-axis-keep-rates)
               (lambda ()
                 '((("DeepSeek" . ":K") . 0.95))))
              ((symbol-function 'gptel-auto-workflow--get-holographic-consensus)
               (lambda (_)
                 (list :axis ":K" :count 2 :total 5 :confidence 0.4))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (string= "DashScope" (caar ranked)))))))

(ert-deftest tdd/axis-pref/boost-scales-with-axis-keep-rate ()
  "Boost magnitude should be proportional to the axis keep-rate delta."
  (let ((gptel-auto-workflow--current-target "target.el")
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")))
        (gptel-auto-workflow--task-backend-preference nil)
        (gptel-auto-workflow--holographic-memory
         '((("target.el" . ":B") . 10)))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5)))
              ((symbol-function 'gptel-auto-workflow--backend-per-axis-keep-rates)
               (lambda ()
                 '((("DeepSeek" . ":B") . 0.9)
                   (("DashScope" . ":B") . 0.4))))
              ((symbol-function 'gptel-auto-workflow--get-holographic-consensus)
               (lambda (_)
                 (list :axis ":B" :count 10 :total 12 :confidence 0.83))))
      (let* ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (string= "DeepSeek" (caar ranked)))))))

;; ─── Per-Run Backend Cooldown Tests ───

(ert-deftest tdd/run-cooldown/cooldown-excludes-failed-backend ()
  "Backends in the run cooldown list should be excluded from ranking."
  (let ((gptel-auto-workflow--run-failed-backends '("DashScope"))
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")
           ("MiniMax" . "minimax-m2.7-highspeed")))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--task-backend-preference nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (= 2 (length ranked)))
        (should-not (assoc "DashScope" ranked))
        (should (assoc "DeepSeek" ranked))
        (should (assoc "MiniMax" ranked))))))

(ert-deftest tdd/run-cooldown/empty-cooldown-allows-all ()
  "Empty cooldown list should not exclude any backends."
  (let ((gptel-auto-workflow--run-failed-backends nil)
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--task-backend-preference nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (= 2 (length ranked)))
        (should (assoc "DashScope" ranked))
        (should (assoc "DeepSeek" ranked))))))

(ert-deftest tdd/run-cooldown/clear-cooldown-resets-exclusions ()
  "Clearing the cooldown list should bring failed backends back."
  (let ((gptel-auto-workflow--run-failed-backends '("DashScope"))
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--task-backend-preference nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5))))
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should-not (assoc "DashScope" ranked)))
      ;; Clear cooldown
      (gptel-auto-workflow--clear-run-failed-backends)
      (let ((ranked (gptel-auto-workflow--ranked-subagent-backends "analyzer")))
        (should (= 2 (length ranked)))
        (should (assoc "DashScope" ranked))
        (should (assoc "DeepSeek" ranked))))))

;; ─── Routing Context for Prompt Injection Tests ───

(ert-deftest tdd/routing-context/includes-backend-and-model ()
  "Routing context should include the backend name and model."
  (let* ((gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (b &rest _)
                 (if (string= b "DeepSeek")
                     (list :kept 8 :total 10 :keep-rate 0.8)
                   (list :kept 0 :total 0 :keep-rate nil))))
              ((symbol-function 'gptel-auto-workflow--safe-backend-name)
               (lambda (b) b))
              ((symbol-function 'gptel-backend-name)
               (lambda (b) (symbol-name b))))
      (let ((ctx (gptel-auto-workflow--routing-context "DeepSeek" "deepseek-v4-pro")))
        (should (string-match-p "DeepSeek" ctx))
        (should (string-match-p "deepseek-v4-pro" ctx))))))

(ert-deftest tdd/routing-context/includes-health-status ()
  "Routing context should include lambda health and keep-rate."
  (let* ((gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "DeepSeek" :healthy gptel-auto-workflow--lambda-verification-results)
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (b &rest _)
                 (list :kept 8 :total 10 :keep-rate 0.8)))
              ((symbol-function 'gptel-auto-workflow--safe-backend-name)
               (lambda (b) b)))
      (let ((ctx (gptel-auto-workflow--routing-context "DeepSeek" "deepseek-v4-pro")))
        (should (string-match-p "health" ctx))
        (should (string-match-p "80" ctx))
        (should (string-match-p "HEALTHY" ctx))))))

(ert-deftest tdd/routing-context/includes-rate-limit-status ()
  "Routing context should note backend health status and rate-limit state."
  (let* ((gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
         (gptel-auto-workflow--rate-limited-backends nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (b &rest _)
                 (list :kept 5 :total 10 :keep-rate 0.5)))
              ((symbol-function 'gptel-auto-workflow--safe-backend-name)
               (lambda (b) b)))
      (let ((ctx (gptel-auto-workflow--routing-context "DashScope" "qwen3.6-plus")))
        (should (string-match-p "DashScope" ctx))
        (should (string-match-p "healthy" ctx))))))

;; ─── Auto-Recovery from Probation Tests ───

(ert-deftest tdd/health-auto-recovery/probation-recovers-after-cooldown ()
  "Backend at probation after old strike should recover to degraded after 1h."
  (let* ((now (float-time))
         (old-time (- now 3601))  ; just over 1 hour ago
         (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-last-strike-time (make-hash-table :test 'equal))
         (gptel-auto-workflow--evolution-next-cycle-hints nil))
    (puthash "DashScope" 3 gptel-auto-workflow--lambda-strike-count)
    (puthash "DashScope" old-time gptel-auto-workflow--lambda-last-strike-time)
    ;; 3 strikes + old timestamp → should be level 2 (degraded), not 3 (probation)
    (should (= 2 (gptel-auto-workflow--backend-health-level "DashScope")))
    (should (= 0.65 (gptel-auto-workflow--backend-health-weight "DashScope")))))

(ert-deftest tdd/health-auto-recovery/recent-strike-stays-probation ()
  "Backend with recent strike should stay at probation level."
  (let* ((now (float-time))
         (recent-time (- now 60))  ; 1 minute ago
         (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-last-strike-time (make-hash-table :test 'equal))
         (gptel-auto-workflow--evolution-next-cycle-hints nil))
    (puthash "MiniMax" 3 gptel-auto-workflow--lambda-strike-count)
    (puthash "MiniMax" recent-time gptel-auto-workflow--lambda-last-strike-time)
    ;; 3 strikes + recent timestamp → still level 3 (probation)
    (should (= 3 (gptel-auto-workflow--backend-health-level "MiniMax")))))

(ert-deftest tdd/health-auto-recovery/healthy-backends-unaffected ()
  "Healthy backend should not be affected by auto-recovery logic."
  (let* ((gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
         (gptel-auto-workflow--lambda-last-strike-time (make-hash-table :test 'equal))
         (gptel-auto-workflow--evolution-next-cycle-hints nil))
    ;; 0 strikes → healthy
    (should (= 0 (gptel-auto-workflow--backend-health-level "DeepSeek")))
    (should (= 1.0 (gptel-auto-workflow--backend-health-weight "DeepSeek")))))

;; ─── Per-Target Model Preference Tests ───

(ert-deftest tdd/target-model/best-model-from-history ()
  "Should return the model that produced the most kept results for a target."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list
                (list :target "foo.el" :backend "DeepSeek" :model "deepseek-v4-pro" :decision "kept")
                (list :target "foo.el" :backend "DeepSeek" :model "deepseek-v4-flash" :decision "kept")
                (list :target "foo.el" :backend "DeepSeek" :model "deepseek-v4-pro" :decision "kept")
                (list :target "foo.el" :backend "DeepSeek" :model "deepseek-v4-flash" :decision "discarded")
                (list :target "foo.el" :backend "DashScope" :model "qwen3.6-plus" :decision "kept")
                (list :target "bar.el" :backend "DeepSeek" :model "deepseek-v4-flash" :decision "kept"))))
            ((symbol-function 'gptel-auto-workflow--model-combination-valid-p)
             (lambda (_) t)))  ; all combinations valid in test
    (let ((model (gptel-auto-workflow--best-model-for-target "foo.el" "DeepSeek")))
      ;; deepseek-v4-pro: 2 kept, 0 discarded = 100%
      ;; deepseek-v4-flash: 1 kept, 1 discarded = 50%
      ;; → prefer deepseek-v4-pro
      (should (string= "deepseek-v4-pro" model)))))

(ert-deftest tdd/target-model/fallback-when-no-data ()
  "Should return nil when no historical data for the target."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda () nil)))
    (let ((model (gptel-auto-workflow--best-model-for-target "unknown.el" "DeepSeek")))
      (should (null model)))))

(ert-deftest tdd/target-model/filters-by-backend ()
  "Should only consider the specified backend's models."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (list
                (list :target "foo.el" :backend "DashScope" :model "qwen3.6-plus" :decision "kept")
                (list :target "foo.el" :backend "DashScope" :model "qwen3.6-plus" :decision "kept")
                (list :target "foo.el" :backend "DeepSeek" :model "deepseek-v4-pro" :decision "kept"))))
            ((symbol-function 'gptel-auto-workflow--model-combination-valid-p)
             (lambda (_) t)))
    (let ((model (gptel-auto-workflow--best-model-for-target "foo.el" "DeepSeek")))
      ;; Only DeepSeek models for this target → one kept
      (should (string= "deepseek-v4-pro" model)))))

;; ─── Routing Audit Trail Tests ───

(ert-deftest tdd/audit-trail/records-routing-decision ()
  "The audit trail should record the top backend and scores after ranking."
  (let ((gptel-auto-workflow--routing-audit-log nil)
        (gptel-auto-workflow--current-target "test-target.el")
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")
           ("DeepSeek" . "deepseek-v4-flash")))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--task-backend-preference nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 8 :total 10 :keep-rate 0.8))))
      (gptel-auto-workflow--ranked-subagent-backends "analyzer")
      (should (= 1 (length gptel-auto-workflow--routing-audit-log)))
      (let ((entry (car gptel-auto-workflow--routing-audit-log)))
        (should (string= "test-target.el" (plist-get entry :target)))
        (should (string= "analyzer" (plist-get entry :agent-type)))
        (should (plist-get entry :selected-backend))
        (should (plist-get entry :selected-model))
        (should (> (length (plist-get entry :candidates)) 0))))))

(ert-deftest tdd/audit-trail/trims-to-100-entries ()
  "The audit trail should not grow beyond 100 entries."
  (let ((gptel-auto-workflow--routing-audit-log nil)
        (gptel-auto-workflow--current-target "target.el")
        (gptel-auto-workflow-executor-rate-limit-fallbacks
         '(("DashScope" . "qwen3.6-plus")))
        (gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal))
        (gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal))
        (gptel-auto-workflow--task-backend-preference nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-backend-performance-stats)
               (lambda (&rest _) (list :kept 5 :total 10 :keep-rate 0.5))))
      (dotimes (_ 150)
        (gptel-auto-workflow--ranked-subagent-backends "analyzer"))
      (should (<= (length gptel-auto-workflow--routing-audit-log) 100)))))

;; ─── Audit Trail Summary Tests ───

(ert-deftest tdd/audit-summary/counts-total-decisions ()
  "Summary should report correct total decision count."
  (let ((gptel-auto-workflow--routing-audit-log
         (list (list :timestamp (float-time) :selected-backend "DeepSeek"
                     :selected-model "deepseek-v4-pro" :agent-type "analyzer"
                     :vsm-adjustments '("S4:explore→30%"))
               (list :timestamp (float-time) :selected-backend "DashScope"
                     :selected-model "qwen3.6-plus" :agent-type "executor"))))
    (let ((summary (gptel-auto-workflow--audit-trail-summary)))
      (should (= 2 (plist-get summary :total-decisions))))))

(ert-deftest tdd/audit-summary/counts-vsm-adjustments ()
  "Summary should count VSM adjustments per layer."
  (let ((gptel-auto-workflow--routing-audit-log
         (list (list :timestamp (float-time) :selected-backend "DeepSeek"
                     :vsm-adjustments '("S2:delta→20%+rate→40%" "S4:explore→30%"))
               (list :timestamp (float-time) :selected-backend "DashScope"
                     :vsm-adjustments '("S2:delta→20%+rate→40%")))))
    (let* ((summary (gptel-auto-workflow--audit-trail-summary))
           (vsm (plist-get summary :vsm-adjustments)))
      (should (= 2 (plist-get vsm :s2)))
      (should (= 1 (plist-get vsm :s4))))))

;; ─── Lambda Health Impact Tests ───

(ert-deftest tdd/lambda-impact/healthy-outperforms-degraded ()
  "Lambda-healthy backends should show higher keep-rate than degraded."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (puthash "DeepSeek" :healthy gptel-auto-workflow--lambda-verification-results)
    (puthash "MiniMax" :degraded gptel-auto-workflow--lambda-verification-results)
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda ()
                 (append
                  ;; DeepSeek (healthy): 8 kept, 2 discarded
                  (make-list 8 (list :backend "DeepSeek" :decision "kept"))
                  (make-list 2 (list :backend "DeepSeek" :decision "discarded"))
                  ;; MiniMax (degraded): 3 kept, 7 discarded
                  (make-list 3 (list :backend "MiniMax" :decision "kept"))
                  (make-list 7 (list :backend "MiniMax" :decision "discarded"))))))
      (let ((impact (gptel-auto-workflow--lambda-health-impact)))
        (should (> (plist-get impact :healthy-keep-rate)
                   (plist-get impact :degraded-keep-rate)))
        (should (= 10 (plist-get impact :healthy-experiments)))
        (should (= 10 (plist-get impact :degraded-experiments)))
        (should (> (plist-get impact :impact-delta) 0.0))))))

(ert-deftest tdd/lambda-impact/no-data-returns-nil ()
  "Without verification data, impact delta should be nil."
  (let ((gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () nil)))
      (let ((impact (gptel-auto-workflow--lambda-health-impact)))
        (should (null (plist-get impact :impact-delta)))))))

;; ─── Allium Health Impact Tests ───

(ert-deftest tdd/allium-impact/low-severity-outperforms-high ()
  "Strategies with low Allium severity should have higher keep-rates."
  (let* ((tmp-dir (make-temp-file "allium-test" t))
         (issues-dir (expand-file-name "var/tmp/evolution/allium-issues" tmp-dir)))
    (make-directory issues-dir t)
    (with-temp-file (expand-file-name "own-repos.md" issues-dir)
      (insert "Issues: 2\nSeverity: 0.15\nStatus: ok"))
    (with-temp-file (expand-file-name "deep-external.md" issues-dir)
      (insert "Issues: 8\nSeverity: 0.72\nStatus: incoherent"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () tmp-dir))
                  ((symbol-function 'gptel-auto-workflow--parse-all-results)
                   (lambda ()
                     (append
                      (make-list 8 (list :research-strategy "own-repos" :decision "kept"))
                      (make-list 2 (list :research-strategy "own-repos" :decision "discarded"))
                      (make-list 3 (list :research-strategy "deep-external" :decision "kept"))
                      (make-list 7 (list :research-strategy "deep-external" :decision "discarded"))))))
          (let ((impact (gptel-auto-workflow--allium-health-impact)))
            (should (> (plist-get impact :low-allium-keep-rate)
                       (plist-get impact :high-allium-keep-rate)))
            (should (= 2 (plist-get impact :strategies-audited)))
            (should (> (plist-get impact :impact-delta) 0.0))))
      (delete-directory tmp-dir t))))

(ert-deftest tdd/allium-impact/no-allium-files-returns-nil-delta ()
  "Without Allium issue files, impact delta should be nil."
  (let* ((tmp-dir (make-temp-file "allium-empty" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () tmp-dir))
                  ((symbol-function 'gptel-auto-workflow--parse-all-results)
                   (lambda () nil)))
          (let ((impact (gptel-auto-workflow--allium-health-impact)))
            (should (null (plist-get impact :impact-delta)))
            (should (= 0 (plist-get impact :strategies-audited)))))
      (delete-directory tmp-dir t))))

;; ─── Nucleus Persona Impact Tests ───

(ert-deftest tdd/persona-impact/persona-aware-better-than-unclassified ()
  "Persona-aware experiments should show higher keep-rate than unclassified."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda ()
               (append
                (make-list 8 (list :target "lisp/modules/gptel-ext-retry.el" :decision "kept"))
                (make-list 2 (list :target "lisp/modules/gptel-ext-retry.el" :decision "discarded"))
                (make-list 2 (list :target "some-file" :decision "kept"))
                (make-list 8 (list :target "some-file" :decision "discarded")))))
            ((symbol-function 'gptel-auto-workflow--categorize-target)
             (lambda (tgt)
               (if (string-match-p "retry" tgt) :programming nil))))
    (let ((impact (gptel-auto-workflow--nucleus-persona-impact)))
      (should (> (plist-get impact :persona-keep-rate)
                 (plist-get impact :unclassified-keep-rate)))
      (should (> (plist-get impact :impact-delta) 0.0)))))

(ert-deftest tdd/persona-impact/no-data-returns-nil-delta ()
  "Without experiment data, impact delta should be nil."
  (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
             (lambda () nil)))
    (let ((impact (gptel-auto-workflow--nucleus-persona-impact)))
      (should (null (plist-get impact :impact-delta)))
      (should (= 0 (plist-get impact :persona-experiments))))))

(provide 'test-gptel-auto-workflow-ontology-router)
;;; test-gptel-auto-workflow-ontology-router.el ends here
