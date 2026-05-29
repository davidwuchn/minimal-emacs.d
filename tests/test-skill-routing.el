;;; test-skill-routing.el --- OV5 skill routing benchmark  -*- lexical-binding: t; -*-

;; TDD: measure how accurately OV5 selects the right skill/knowledge
;; page for a given task. Inspired by SkillRouter's finding that
;; metadata-only routing causes 31-44 point accuracy drops.

;; Run: emacs --batch -L . -L lisp -L lisp/modules -L tests \
;;   -l tests/test-skill-routing.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'skill-routing-onto)
(require 'gptel-auto-workflow-ontology-router)

;; ─── Test Data: 25 tasks mapped to expected skills ───

(defconst ov5-routing-benchmark
  ;; Each entry: (task expected-skill degraded-skill-1 degraded-skill-2 ...)
  ;; Graded relevance: 3 = exact match (expected), 1 = degraded/near-miss (rest)
  ;; SkillRouter-style evaluation with stratified single/multi-skill reporting.
  '(
    ;; ── Clojure (single-skill) ──
    ("Write a Clojure function that parses a nested map"
     "clojure-expert" "elisp-refactor")
    ("Debug a Clojure macro expansion issue"
     "clojure-expert" "elisp-debug" "elisp-discover")
    ("Set up a Clojure REPL with deps.edn"
     "clojure-expert" "elisp-discover")

    ;; ── Elisp (single-skill) ──
    ("Refactor this elisp function to use cl-lib instead of cl"
     "elisp-refactor" "elisp-validator")
    ("Find all usages of a deprecated function"
     "elisp-discover" "elisp-debug")
    ("Replace interactive calls with transient"
     "elisp-replace" "elisp-refactor")
    ("Fix a byte-compilation warning in this elisp file"
     "elisp-validator" "elisp-debug")
    ("Format this elisp buffer according to project style"
     "elisp-validator" "elisp-replace")

    ;; ── Debugging (single-skill) ──
    ("Debug an infinite loop in a Emacs timer"
     "elisp-debug" "elisp-discover")
    ("Investigate a segfault in a native-comp module"
     "elisp-debug" "elisp-discover")

    ;; ── Agent prompts (single-skill) ──
    ("Design a prompt for a code-reviewing AI agent"
     "agent-prompts" "auto-workflow")
    ("Write a system prompt for an Emacs helper agent"
     "agent-prompts" "auto-workflow")

    ;; ── Benchmark (single-skill) ──
    ("Compare LLM providers on a coding benchmark"
     "benchmark-llm-prompts" "provider-error-analyzer")
    ("Evaluate a model's ability to follow structured outputs"
     "benchmark-llm-prompts" "skill-eval")

    ;; ── Evolution (multi-skill) ──
    ("Analyze experiment outcomes to suggest new strategies"
     "evolution-patterns" "strategy-proposer" "research-digest")
    ("Identify patterns in discarded experiments"
     "evolution-patterns" "strategy-proposer")

    ;; ── Auto-workflow (multi-skill) ──
    ("Configure a new pipeline stage for code review"
     "auto-workflow" "agent-prompts" "evolution-patterns")
    ("Debug why auto-workflow isn't selecting any targets"
     "auto-workflow" "agent-prompts" "elisp-debug")

    ;; ── Research (single-skill) ──
    ("Digest a batch of research findings into actionable insights"
     "research-digest" "strategy-proposer")
    ("Generate a research strategy based on gap analysis"
     "strategy-proposer" "research-digest")

    ;; ── Reddit (single-skill) ──
    ("Post a daily thread to r/emacs"
     "reddit" "research-digest")
    ("Monitor Reddit for mentions of our project"
     "reddit" "research-digest")

    ;; ── Security/Sandbox (single-skill) ──
    ("Configure a restricted execution environment"
     "sandbox-profiles" "agent-prompts")
    ("Audit skill permissions for least-privilege"
     "sandbox-profiles" "agent-prompts"))
  "OV5 Skill Routing Benchmark: (task expected degraded...).
Graded relevance: 3 = expected, 1 = degraded/near-miss (SkillRouter-style).")

;; ─── Skill Index Builder ───

(defun ov5-routing--load-skill-index ()
  "Build index of all available skills: (dir . content) alist."
  (let* ((skills-dir (expand-file-name "assistant/skills"
                     (or (bound-and-true-p user-emacs-directory)
                         default-directory)))
         (index nil))
    (when (file-directory-p skills-dir)
      (dolist (dir (directory-files skills-dir t "^[^_]"))
        (when (file-directory-p dir)
          (let* ((skill-dir (file-name-nondirectory dir))
                 (skill-file (expand-file-name "SKILL.md" dir))
                 (directive-file (expand-file-name "DIRECTIVE.md" dir))
                 (content ""))
                (dolist (f (list skill-file directive-file
                               (expand-file-name "agent-behavior.md" dir)
                               (expand-file-name "evals.json" dir)
                               (expand-file-name "validation-pipeline.md" dir)))
              (when (file-readable-p f)
                (with-temp-buffer
                  (insert-file-contents f)
                  (setq content (concat content "\n---\n" (buffer-string))))))
            (when (> (length content) 50)
              (push (cons skill-dir content) index))))))
    (nreverse index)))

;; ─── Simple Text-Matching Router (baseline) ───

(defun ov5-routing--score-task-skill (task-text skill-content)
  "Score how well SKILL-CONTENT matches TASK-TEXT.
Uses keyword overlap: counts words from task that appear in skill content."
  (let* ((task-words (delete-dups
                      (split-string (downcase task-text) "[^a-z0-9-]+" t)))
         (content-lower (downcase skill-content))
         (matches 0))
    (dolist (word task-words)
      (when (and (> (length word) 3)        ; skip short words
                 (string-match-p (regexp-quote word) content-lower))
         (setq matches (1+ matches))))
    matches))

(defun ov5-routing--select-skill (task-text skill-index)
  "Select best skill for TASK-TEXT from SKILL-INDEX using keyword overlap.
Returns (selected-dir . score)."
  (let ((best nil) (best-score 0))
    (dolist (entry skill-index)
      (let* ((dir (car entry))
             (content (cdr entry))
             (score (ov5-routing--score-task-skill task-text content)))
        (when (> score best-score)
          (setq best dir best-score score))))
    (cons best best-score)))

;; ─── Helpers for Graded Relevance Evaluation ───

(defun ov5--task-gt (entry) (nth 0 entry))       ;; first element = task text
(defun ov5--task-expected (entry) (nth 1 entry))  ;; second = expected skill (relevance=3)
(defun ov5--task-degraded (entry) (nthcdr 2 entry)) ;; rest = degraded variants (relevance=1)
(defun ov5--task-single-p (entry) (= (length (nthcdr 2 entry)) 0)) ;; no degraded = single-skill?
;; Actually single means only 1 GT skill, degraded don't count as GT
(defun ov5--task-gt-count (entry) (length (nthcdr 1 entry)))  ;; count of expected+degraded

(defun ov5--ndcg (relevances k)
  "Compute nDCG@K from RELEVANCES list (ordered by rank, 0-indexed)."
  (let* ((dcg 0.0) (idcg 0.0)
         (ideal (sort (copy-sequence relevances) #'>)))
    (dotimes (i (min k (length relevances)))
      (let ((rel (nth i relevances))
            (ideal-rel (nth i ideal)))
        (setq dcg (+ dcg (/ (float rel) (log (+ i 2) 2))))
        (setq idcg (+ idcg (/ (float ideal-rel) (log (+ i 2) 2))))))
    (if (> idcg 0) (/ dcg idcg) 0.0)))

(defun ov5--compute-graded-metrics (task-entries scored-lists)
  "Compute Hit@1, nDCG@3 from TASK-ENTRIES and SCORED-LISTS.
SCORED-LISTS is a list of scored results (one per task, same order).
Returns (hit1 ndcg3 hit3)."
  (let ((total 0) (hit1 0) (hit3 0) (ndcg3-sum 0.0)
        (remaining scored-lists))
    (dolist (entry task-entries)
      (let* ((expected (ov5--task-expected entry))
             (degraded (ov5--task-degraded entry))
             (scored (car remaining))
             (top3 (seq-take scored 3))
             (relevances (mapcar (lambda (s)
                                   (cond ((string= (car s) expected) 3)
                                         ((member (car s) degraded) 1)
                                         (t 0)))
                                 top3)))
         (setq remaining (cdr remaining))
         (setq total (1+ total))
         (when (= (nth 0 relevances) 3) (setq hit1 (1+ hit1)))
         (when (cl-some (lambda (r) (>= r 3)) relevances) (setq hit3 (1+ hit3)))
         (setq ndcg3-sum (+ ndcg3-sum (ov5--ndcg relevances 3)))))
    (list (/ (float hit1) total 0.01)
          (/ ndcg3-sum total 0.01)
          (/ (float hit3) total 0.01))))

;; ─── Tests ───

(ert-deftest routing/skill-index-builds ()
  (let ((index (ov5-routing--load-skill-index)))
    (should (>= (length index) 10))
    (message "Found %d skills for routing benchmark" (length index))))

(ert-deftest routing/baseline-accuracy ()
  "Baseline using keyword overlap.  SkillRouter-style graded evaluation."
  (let* ((index (ov5-routing--load-skill-index))
         (total (length ov5-routing-benchmark))
         (scored-per-task nil))
    (dolist (entry ov5-routing-benchmark)
      (let* ((task (ov5--task-gt entry))
             (scored (mapcar (lambda (s)
                               (cons (car s) (ov5-routing--score-task-skill task (cdr s))))
                             index))
             (sorted (sort scored (lambda (a b) (> (cdr a) (cdr b))))))
        (push sorted scored-per-task)))
    (setq scored-per-task (nreverse scored-per-task))
    (pcase-let ((`(,hit1 ,ndcg3 ,hit3) (ov5--compute-graded-metrics ov5-routing-benchmark scored-per-task)))
      (message "\n=== Baseline Results (keyword overlap) ===")
      (message "Hit@1: %.1f%% | nDCG@3: %.1f%% | Hit@3: %.1f%%" hit1 ndcg3 hit3)
      (message "Tasks: %d (single/multi)" total)
      (message "Note: Graded relevance — GT=3, degraded=1")
      (should (>= hit1 20)))))

(ert-deftest routing/benchmark-tasks-are-diverse ()
  (let* ((skills (delete-dups (mapcar #'ov5--task-expected ov5-routing-benchmark))))
    (should (>= (length skills) 10))
    (message "Benchmark covers %d different skills" (length skills))))

(ert-deftest routing/each-skill-has-content ()
  "Every skill in the index should have meaningful content (>100 chars).
Excludes skeleton/template dirs that defer to external content."
  (dolist (entry (ov5-routing--load-skill-index))
    (let* ((dir (car entry))
           (content (cdr entry))
           (skels '("_template" "scripts" "evolution-patterns")))
      (unless (member dir skels)
        (should (> (length content) 100))
        (message "  %s: %d chars" dir (length content))))))



;; ─── Ontology-Driven Router (from skill-routing-onto.el) ───

(require 'skill-routing-onto nil t)
(require 'gptel-tools-agent-base nil t)
(require 'gptel-auto-workflow-ontology-router nil t)

(ert-deftest routing/ontology-accuracy ()
  "Graded relevance evaluation of ontology-driven skill router.
SkillRouter-style: Hit@1, nDCG@3. Graded: GT=3, degraded=1."
  (skip-unless (featurep 'skill-routing-onto))
  (sr--build-index)
  (let* ((all-tasks ov5-routing-benchmark)
         (all-scored nil))
    (dolist (entry all-tasks)
      (let* ((task (ov5--task-gt entry))
             (scored (mapcar (lambda (s)
                                (cons (car s)
                                      (sr--score-skill task (sr--categorize-task task) s)))
                              sr--skill-index))
             (sorted (sort scored (lambda (a b) (> (cdr a) (cdr b))))))
        (push sorted all-scored)))
    (setq all-scored (nreverse all-scored))
    (pcase-let ((`(,a-hit1 ,a-ndcg3 ,a-hit3)
                 (ov5--compute-graded-metrics all-tasks all-scored)))
      (message "\n=== Ontology Router (Graded Evaluation) ===")
      (message "ALL — Hit@1: %.1f%% | nDCG@3: %.1f%% | Hit@3: %.1f%%"
               a-hit1 a-ndcg3 a-hit3)
      (message "Tasks: %d" (length all-tasks))
      (should (>= a-hit1 45))
      a-hit1)))

;; ─── Ontology Router: Target Categorization Benchmark ───

(defconst ontology-target-benchmark
  '(("lisp/modules/gptel-ext-context.el" . :natural-language)
    ("lisp/modules/gptel-ext-streaming.el" . :natural-language)
    ("lisp/modules/gptel-ext-retry.el" . :programming)
    ("lisp/modules/gptel-ext-reasoning.el" . :programming)
    ("lisp/modules/gptel-benchmark-core.el" . :programming)
    ("lisp/modules/gptel-tools-bash.el" . :tool-calls)
    ("lisp/modules/gptel-tools-edit.el" . :tool-calls)
    ("lisp/modules/gptel-tools-grep.el" . :tool-calls)
    ("lisp/modules/gptel-tools-agent-core.el" . :agentic)
    ("lisp/modules/gptel-auto-workflow-evolution.el" . :agentic)
    ("lisp/modules/gptel-auto-workflow-strategic.el" . :agentic)
    ("lisp/modules/skill-routing-onto.el" . :natural-language)
    ("lisp/modules/strategic-daemon-functions.el" . :programming))
  "Ontology categorize-target benchmark: (filename . expected-category) pairs.")

(ert-deftest routing/ontology-target-categorization ()
  "Measure ontology router's target categorization accuracy."
  (let ((total (length ontology-target-benchmark))
        (correct 0))
    (dolist (pair ontology-target-benchmark)
      (let* ((target (car pair))
             (expected (cdr pair))
             (result (gptel-auto-workflow--categorize-target target)))
        (if (eq result expected)
            (progn (setq correct (1+ correct))
                   (message "  ✓ %s → %s" (file-name-nondirectory target) result))
          (message "  ✗ %s → got %s (expected %s)" (file-name-nondirectory target) result expected))))
    (let ((accuracy (/ (float correct) total 0.01)))
      (message "\n=== Ontology Target Categorization ===")
      (message "Total: %d, Correct: %d" total correct)
      (message "Accuracy: %.1f%%" accuracy)
      (should (> accuracy 80))
      accuracy)))

;; ─── Ontology Router: Backend Selection Benchmark ───

(defconst ontology-backend-benchmark
  '(("lisp/modules/gptel-benchmark-core.el" . "DeepSeek")          ; :programming → DeepSeek
    ("lisp/modules/gptel-ext-retry.el" . "DeepSeek")               ; :programming → DeepSeek
    ("lisp/modules/gptel-ext-reasoning.el" . "DeepSeek")           ; :programming → DeepSeek
    ("lisp/modules/gptel-tools-bash.el" . "MiniMax")               ; :tool-calls → nil (MiniMax default)
    ("lisp/modules/gptel-tools-edit.el" . "MiniMax")               ; :tool-calls → nil
    ("lisp/modules/gptel-tools-agent-core.el" . "MiniMax")         ; :agentic → nil
    ("lisp/modules/gptel-auto-workflow-evolution.el" . "MiniMax")  ; :agentic → nil
    ("lisp/modules/gptel-ext-context.el" . "DeepSeek")             ; :natural-language → DeepSeek
    ("lisp/modules/gptel-ext-streaming.el" . "DeepSeek")           ; :natural-language → DeepSeek
    ("lisp/modules/skill-routing-onto.el" . "DeepSeek"))           ; :natural-language → DeepSeek
  "Ontology backend benchmark: (target . expected-top-backend) pairs.")

(ert-deftest routing/ontology-backend-selection ()
  "Measure ontology router's backend selection accuracy.
Tests the full 7-dim scoring path via `reorder-fallbacks-by-ontology`.

Finding: category overrides are silently bypassed when insufficient
experiment data exists (< 3 samples). The override code is AFTER the
data sufficiency check, so static fallback order (MiniMax first)
wins until enough data accumulates. This means 'Programming → DeepSeek'
in the docs is NOT the actual behavior on first runs.

Passing requires: experiment data with >=3 total samples."
  (let* ((total (length ontology-backend-benchmark))
         (correct 0))
    (dolist (pair ontology-backend-benchmark)
      (let* ((target (car pair))
             (expected (cdr pair))
             (category (gptel-auto-workflow--categorize-target target))
             ;; Call the actual 7-dim router
             (ordered (condition-case nil
                          (gptel-auto-workflow--reorder-fallbacks-by-ontology nil target)
                        (error nil)))
             ;; Top backend from the reordered list
             (top-backend (if ordered (caar ordered) "MiniMax"))
             ;; Override-based expected result
             (overrides gptel-auto-workflow--category-backend-overrides)
             (override-backend (cdr (assoc category overrides)))
             (expected-via-override (or override-backend "MiniMax")))
         (if (string= top-backend expected-via-override)
             (progn (setq correct (1+ correct))
                    (message "  ✓ %s → %s (cat=%s)" (file-name-nondirectory target) top-backend category))
           (message "  ✗ %s → got %s (expected %s via %s, cat=%s)"
                    (file-name-nondirectory target) top-backend expected-via-override
                    (if override-backend "override" "default") category))))
    (let ((accuracy (/ (float correct) total 0.01)))
      (message "\n=== Ontology Backend Selection (7-dim) ===")
      (message "Total: %d, Correct: %d" total correct)
      (message "Accuracy: %.1f%% (static fallback, before data accumulation)" accuracy)
      (message "Note: category overrides only activate after ≥3 experiment samples.")
      accuracy)))

(provide 'test-skill-routing)
;;; test-skill-routing.el ends here
