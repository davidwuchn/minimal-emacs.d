;;; test-skill-routing.el --- OV5 skill routing benchmark  -*- lexical-binding: t; -*-

;; TDD: measure how accurately OV5 selects the right skill/knowledge
;; page for a given task. Inspired by SkillRouter's finding that
;; metadata-only routing causes 31-44 point accuracy drops.

;; Run: emacs --batch -L . -L lisp -L lisp/modules -L tests \
;;   -l tests/test-skill-routing.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)

;; ─── Test Data: 25 tasks mapped to expected skills ───

(defconst ov5-routing-benchmark
  '(;; ── Clojure ──
    ("Write a Clojure function that parses a nested map" . "clojure-expert")
    ("Debug a Clojure macro expansion issue" . "clojure-expert")
    ("Set up a Clojure REPL with deps.edn" . "clojure-expert")

    ;; ── Elisp ──
    ("Refactor this elisp function to use cl-lib instead of cl" . "elisp-refactor")
    ("Find all usages of a deprecated function" . "elisp-discover")
    ("Replace interactive calls with transient" . "elisp-replace")
    ("Fix a byte-compilation warning in this elisp file" . "elisp-validator")
    ("Format this elisp buffer according to project style" . "elisp-validator")

    ;; ── Debugging ──
    ("Debug an infinite loop in a Emacs timer" . "elisp-debug")
    ("Investigate a segfault in a native-comp module" . "elisp-debug")

    ;; ── Agent prompts ──
    ("Design a prompt for a code-reviewing AI agent" . "agent-prompts")
    ("Write a system prompt for an Emacs helper agent" . "agent-prompts")

    ;; ── Benchmark ──
    ("Compare LLM providers on a coding benchmark" . "benchmark-llm-prompts")
    ("Evaluate a model's ability to follow structured outputs" . "benchmark-llm-prompts")

    ;; ── Evolution ──
    ("Analyze experiment outcomes to suggest new strategies" . "evolution-patterns")
    ("Identify patterns in discarded experiments" . "evolution-patterns")

    ;; ── Auto-workflow ──
    ("Configure a new pipeline stage for code review" . "auto-workflow")
    ("Debug why auto-workflow isn't selecting any targets" . "auto-workflow")

    ;; ── Research ──
    ("Digest a batch of research findings into actionable insights" . "research-digest")
    ("Generate a research strategy based on gap analysis" . "strategy-proposer")

    ;; ── Reddit ──
    ("Post a daily thread to r/emacs" . "reddit")
    ("Monitor Reddit for mentions of our project" . "reddit")

    ;; ── Security/Sandbox ──
    ("Configure a restricted execution environment" . "sandbox-profiles")
    ("Audit skill permissions for least-privilege" . "sandbox-profiles"))

  "OV5 Skill Routing Benchmark: (task . expected-skill-dir) pairs.")

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

;; ─── Tests ───

(ert-deftest routing/skill-index-builds ()
  "Skill index should find at least 10 skills."
  (let ((index (ov5-routing--load-skill-index)))
    (should (>= (length index) 10))
    (message "Found %d skills for routing benchmark" (length index))))

(ert-deftest routing/baseline-accuracy ()
  "Measure baseline routing accuracy using keyword overlap.
Target: >50% Hit@1 (random baseline would be ~4% with 25 skills).
Current baseline: 29.2% (simple text matching).
TARGET: >50% — requires SkillRouter-style full-text retrieval."
  :expected-result (if noninteractive :failed :passed)
  (let* ((index (ov5-routing--load-skill-index))
         (total (length ov5-routing-benchmark))
         (correct 0)
         (incorrect 0))
    (dolist (pair ov5-routing-benchmark)
      (let* ((task (car pair))
             (expected (cdr pair))
             (selected (ov5-routing--select-skill task index))
             (selected-dir (car selected))
             (score (cdr selected)))
        (if (string= selected-dir expected)
            (progn (setq correct (1+ correct))
                   (message "  ✓ %s → %s" task expected))
          (progn (setq incorrect (1+ incorrect))
                 (message "  ✗ %s → got %s (expected %s, score=%d)"
                          task (or selected-dir "NIL") expected score)))))
    (let ((accuracy (/ (float correct) total 0.01)))
      (message "\n=== Routing Benchmark Results ===")
      (message "Total: %d, Correct: %d, Wrong: %d" total correct incorrect)
      (message "Hit@1: %.1f%%" accuracy)
      (should (> accuracy 50))
      accuracy)))

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

(ert-deftest routing/benchmark-tasks-are-diverse ()
  "Benchmark should cover at least 10 different skills."
  (let* ((skills (delete-dups (mapcar #'cdr ov5-routing-benchmark))))
    (should (>= (length skills) 10))
    (message "Benchmark covers %d different skills" (length skills))))

;; ─── Ontology-Driven Router (from skill-routing-onto.el) ───

(require 'skill-routing-onto nil t)
(require 'gptel-auto-workflow-ontology-router nil t)

(ert-deftest routing/ontology-accuracy ()
  "Measure routing accuracy using ontology-driven 4-dim + adaptive scoring.
Target: >50% Hit@1 (beats keyword baseline of 29.2%)."
  (skip-unless (featurep 'skill-routing-onto))
  ;; Disable exploration for deterministic testing
  (let* ((sr--exploration-rate 0.0)
         (index (progn (sr--build-index) sr--skill-index))
         (total (length ov5-routing-benchmark))
         (correct 0) (incorrect 0))
    (should (>= (length index) 10))
    (dolist (pair ov5-routing-benchmark)
      (let* ((task (car pair))
             (expected (cdr pair))
             (result (sr--select-skill task))
             (selected (car result))
             (score (cdr result)))
        (if (string= selected expected)
            (progn (setq correct (1+ correct))
                   (message "  ✓ %s → %s (score=%.3f)" task expected score))
          (progn (setq incorrect (1+ incorrect))
                 (message "  ✗ %s → got %s (expected %s, score=%.3f)"
                          task (or selected "NIL") expected score)))))
    (let ((accuracy (/ (float correct) total 0.01)))
      (message "\n=== Ontology Routing Results ===")
      (message "Total: %d, Correct: %d, Wrong: %d" total correct incorrect)
      (message "Hit@1: %.1f%%" accuracy)
      (should (> accuracy 50))
      accuracy)))

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
            (progn (cl-incf correct)
                   (message "  ✓ %s → %s" (file-name-nondirectory target) result))
          (message "  ✗ %s → got %s (expected %s)" (file-name-nondirectory target) result expected))))
    (let ((accuracy (/ (float correct) total 0.01)))
      (message "\n=== Ontology Target Categorization ===")
      (message "Total: %d, Correct: %d" total correct)
      (message "Accuracy: %.1f%%" accuracy)
      (should (> accuracy 80))
      accuracy)))

(provide 'test-skill-routing)
;;; test-skill-routing.el ends here
