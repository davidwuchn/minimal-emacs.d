;;; gptel-tools-agent-strategy-evolver.el --- Meta-Harness style strategy evolution -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split
;;
;; This module implements the Meta-Harness outer loop for evolving prompt-building strategies.
;; It generates new strategy files, validates them, and tracks their performance.
;;
;; Key principle: We evolve the HARNESS (how prompts are built), not just the prompt content.

(require 'cl-lib)
(require 'subr-x)
(require 'gptel-tools-agent-strategy-harness)

(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-base" ())
(declare-function gptel-auto-workflow--results-file-path "gptel-tools-agent-base" (&optional run-id))
(declare-function gptel-request "gptel" (prompt &rest args))
(defvar gptel-auto-workflow--suppress-strategy-metadata-persistence)

;;; Strategy Generation

(defvar gptel-auto-workflow--strategy-evolution-axes
  '((A . "Prompt template architecture")
    (B . "Context retrieval and selection")
    (C . "Section ordering and inclusion")
    (D . "Variable computation and formatting")
    (E . "Skill loading and integration")
    (F . "Adaptive compression and filtering"))
  "Exploration axes for strategy evolution, analogous to Meta-Harness exploitation axes.")

(defun gptel-auto-workflow--strategy-axis-description (axis)
  "Return a human-readable description for strategy AXIS."
  (or (cdr (assoc (if (symbolp axis) axis (intern-soft (format "%s" axis)))
                  gptel-auto-workflow--strategy-evolution-axes))
      "Unknown strategy axis"))

(defun gptel-auto-workflow--generate-strategy-name ()
  "Generate a unique strategy name."
  (let* ((dir (gptel-auto-workflow--strategies-directory))
         (max-n 0))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir nil "^strategy-evolved-[0-9]+\\.el$"))
        (when (string-match "^strategy-evolved-\\([0-9]+\\)\\.el$" file)
          (setq max-n (max max-n (string-to-number (match-string 1 file)))))))
    (format "evolved-%04d" (1+ max-n))))

;;; Strategy Template

(defun gptel-auto-workflow--strategy-template (name hypothesis axis parent-strategies code)
  "Generate a strategy file from template.
NAME: strategy name
HYPOTHESIS: what this strategy changes and why
AXIS: which exploitation axis this targets (A-F)
PARENT-STRATEGIES: list of parent strategy names this builds on
CODE: the actual implementation code"
  (format ";;; strategy-%s.el --- Evolved prompt-building strategy -*- lexical-binding: t; -*-
;; Strategy for gptel-tools-agent-strategy-harness
;;
;; Hypothesis: %s
;; Axis: %s (%s)
;; Parents: %s
;; Generated: %s
;;
;; CRITICAL: This strategy introduces a NEW mechanism, not just parameter tuning.
;; If this is just changing constants or ordering, it should be rejected.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-%s-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  %S
  %s)

(defun strategy-%s-get-metadata ()
  %S
  (list :name %S
        :version %S
        :hypothesis %S
        :axis %S
        :created %S
        :parent-strategies '%s
        :description %S))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   %S
   #'strategy-%s-build-prompt
   (strategy-%s-get-metadata)))

(provide 'strategy-%s)
;;; strategy-%s.el ends here"
          name
          hypothesis
          axis
          (gptel-auto-workflow--strategy-axis-description axis)
          (prin1-to-string parent-strategies)
          (format-time-string "%Y-%m-%d")
          name
          (format "Build prompt using evolved strategy %s.\nHYPOTHESIS: %s" name hypothesis)
          code
          name
          "Return metadata for this strategy."
          name
          "1.0"
          hypothesis
          (format "%s" axis)
          (format-time-string "%Y-%m-%d")
          (prin1-to-string parent-strategies)
          hypothesis
          name
          name
          name
          name
          name))

;;; Self-Critique: Parameter vs Mechanism Detection

(defun gptel-auto-workflow--is-parameter-variant-p (new-code parent-code)
  "Check if NEW-CODE is just a parameter variant of PARENT-CODE.
Returns t if the only changes are constants, ordering, or formatting.
Returns nil if there's a genuine new mechanism."
  (let ((new-clean (gptel-auto-workflow--normalize-code new-code))
        (parent-clean (gptel-auto-workflow--normalize-code parent-code)))
    ;; Check if the core logic structure is identical
    ;; A parameter variant will have the same function calls and control flow
    ;; but different constants/literals
    (and
     ;; Same top-level functions defined
     (equal (gptel-auto-workflow--extract-function-names new-clean)
            (gptel-auto-workflow--extract-function-names parent-clean))
     ;; Same control flow structures
     (equal (gptel-auto-workflow--extract-control-flow new-clean)
            (gptel-auto-workflow--extract-control-flow parent-clean))
     ;; But different constants
     (not (equal (gptel-auto-workflow--extract-constants new-clean)
                 (gptel-auto-workflow--extract-constants parent-clean))))))

(defun gptel-auto-workflow--normalize-code (code)
  "Normalize code for comparison by removing whitespace and comments."
  (with-temp-buffer
    (insert code)
    ;; Remove comments
    (goto-char (point-min))
    (while (re-search-forward ";.*$" nil t)
      (replace-match ""))
    ;; Normalize whitespace
    (goto-char (point-min))
    (while (re-search-forward "[ \t\n]+" nil t)
      (replace-match " "))
    (buffer-string)))

(defun gptel-auto-workflow--extract-function-names (code)
  "Extract defined function names from CODE."
  (let (names)
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      (while (re-search-forward "(defun\\s-+\\([^ ]+\\)" nil t)
        (push (match-string 1) names)))
    (sort names #'string<)))

(defun gptel-auto-workflow--extract-control-flow (code)
  "Extract control flow structure from CODE (if/cond/while/etc)."
  (let (structures)
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      (while (re-search-forward "(\\(if\\|cond\\|when\\|unless\\|while\\|dolist\\|dotimes\\|cl-loop\\)" nil t)
        (push (match-string 1) structures)))
    (sort structures #'string<)))

(defun gptel-auto-workflow--extract-constants (code)
  "Extract string and number constants from CODE."
  (let (constants)
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      ;; Extract strings
      (while (re-search-forward "\"[^\"]*\"" nil t)
        (push (match-string 0) constants))
      ;; Extract numbers
      (goto-char (point-min))
      (while (re-search-forward "\\b[0-9]+\\b" nil t)
        (push (match-string 0) constants)))
    (sort constants #'string<)))

;;; Prototyping Phase

(defun gptel-auto-workflow--prototype-strategy (strategy-code test-target)
  "Prototype STRATEGY-CODE against TEST-TARGET before finalizing.
Returns plist with :valid t/nil :errors list :test-output string."
  (let ((temp-file (make-temp-file "strategy-prototype-" nil ".el"))
        (errors '())
        (test-output ""))
    (unwind-protect
        (progn
          ;; Write strategy to temp file
          (with-temp-file temp-file
            (insert strategy-code))
          
          ;; Test 1: Load without errors
          (condition-case err
              (let ((gptel-auto-workflow--suppress-strategy-metadata-persistence t))
                (load temp-file nil t t))
            (error
             (push (format "Load error: %s" err) errors)))
          
          ;; Test 2: Build function exists and is callable
          (unless errors
            (condition-case err
                (let* ((build-fn-name (gptel-auto-workflow--extract-build-function-name strategy-code))
                        (build-fn (intern build-fn-name)))
                  (if (fboundp build-fn)
                      (setq test-output
                            (funcall build-fn test-target 1 10 nil 0.5 nil))
                    (push "Build function not found after loading" errors)))
              (error
               (push (format "Build error: %s" err) errors))))
          
          ;; Test 3: Output is a string
          (when (and (not errors) (not (stringp test-output)))
            (push (format "Build function returned %s instead of string" (type-of test-output)) errors))
          
          (list :valid (null errors)
                :errors (nreverse errors)
                :output test-output))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(defun gptel-auto-workflow--extract-build-function-name (code)
  "Extract the build function name from strategy CODE."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (if (re-search-forward "(defun\\s-+\\(strategy-[^ ]+-build-prompt\\)" nil t)
        (match-string 1)
      "strategy-unknown-build-prompt")))

(defun gptel-auto-workflow--extract-build-function-body (code)
  "Extract just the function body from strategy CODE.
Returns the body as a string, or the full code if extraction fails."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    ;; Find the build-prompt function
    (if (re-search-forward "(defun\\s-+strategy-[^ ]+-build-prompt\\s-+" nil t)
        (let ((start (point)))
          ;; Find matching closing paren
          (condition-case nil
              (progn
                (forward-sexp)
                ;; Extract body (skip docstring if present)
                (let ((func-end (point))
                      (body-start start))
                  (goto-char start)
                  ;; Skip docstring
                  (when (looking-at "\\s-*\"")
                    (forward-sexp)
                    (setq body-start (point)))
                  ;; Skip interactive declaration
                  (goto-char body-start)
                  (when (looking-at "\\s-*(interactive")
                    (forward-sexp)
                    (setq body-start (point)))
                  ;; Return body
                  (string-trim (buffer-substring body-start (1- func-end)))))
            (error code)))
      code)))

;;; Warm-Start from Historical Trace Analysis

(defun gptel-auto-workflow--analyze-strategy-failures (strategy-name)
  "Analyze TSV results to find failure patterns for STRATEGY-NAME.
Returns formatted string of top 5 failure reasons, or empty string if none found."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (failure-reasons (make-hash-table :test 'equal))
        (total-failures 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1) ; Skip header
        (while (not (eobp))
          (let* ((line (buffer-substring (line-beginning-position) (line-end-position)))
                 (fields (split-string line "\t")))
            (when (>= (length fields) 20)
              (let ((entry-strategy (nth 19 fields))
                    (decision (nth 7 fields))
                    (reason (nth 11 fields)))
                (when (and (equal entry-strategy strategy-name)
                           (equal decision "discarded")
                           (not (string-empty-p reason)))
                  (setq total-failures (1+ total-failures))
                  (puthash reason (1+ (gethash reason failure-reasons 0)) failure-reasons)))))
          (forward-line 1))))

    (if (= total-failures 0)
        ""
      ;; Sort by frequency and take top 5
      (let ((sorted '()))
        (maphash (lambda (reason count)
                   (push (cons count reason) sorted))
                 failure-reasons)
        (setq sorted (sort sorted (lambda (a b) (> (car a) (car b)))))
        (concat "## Historical Failure Patterns for This Strategy\n"
                (format "Total discarded experiments: %d\n" total-failures)
                "Top failure reasons:\n"
                (mapconcat (lambda (pair)
                            (format "- %s (occurred %d times)" (cdr pair) (car pair)))
                          (cl-subseq sorted 0 (min 5 (length sorted)))
                          "\n")
                "\n\nAVOID these failure modes in your new strategy.\n\n")))))

(defvar gptel-auto-workflow--proposer-skill-path
  "assistant/skills/meta-harness-proposer/SKILL.md"
  "Path to the Meta-Harness proposer skill file.")

(defun gptel-auto-workflow--load-proposer-skill ()
  "Load the proposer skill content if available."
  (let ((skill-file (expand-file-name gptel-auto-workflow--proposer-skill-path
                                      (gptel-auto-workflow--project-root))))
    (when (file-exists-p skill-file)
      (with-temp-buffer
        (insert-file-contents skill-file)
        (buffer-string)))))

(defun gptel-auto-workflow--propose-strategies (parent-strategy-name axis hypothesis parent-code parent-perf)
  "Use gptel to propose 3 new strategy implementations.
Returns list of 3 strategy code strings, or nil if generation fails."
  (cond
   (gptel-auto-workflow--strategy-interrupted
    (message "[strategy-evolution] Interrupted, skipping proposal")
    nil)
   ((not (fboundp 'gptel-request))
    (message "[strategy-evolution] gptel not available, cannot propose strategies")
    nil)
   (t
    (let* ((axis-desc (gptel-auto-workflow--strategy-axis-description axis))
           (failure-analysis (gptel-auto-workflow--analyze-strategy-failures parent-strategy-name))
           (skill-content (gptel-auto-workflow--load-proposer-skill))
           (proposer-prompt
            (format "You are a Meta-Harness strategy proposer. Your job is to generate NEW Emacs Lisp prompt-building strategies.

## Context

We are evolving prompt-building STRATEGIES (not prompt content). Strategies are Emacs Lisp functions that build prompts for an AI code improvement system.

%s

Evolution hypothesis: %s

## Parent Strategy

Current strategy: %s
Performance: %d experiments, %.0f%% success rate, avg score %.2f

Parent strategy code:
```elisp
%s
```

%s

## Anti-Overfitting Rules

- NO target-specific hints. Do not hardcode knowledge about specific files or modules.
- NEVER mention target file names in strategy code, prompts, or comments.
- Strategies must work on ANY Emacs Lisp file. Do not assume specific module structures.
- General patterns are OK (e.g., 'prioritize failure patterns for large files').

## Task

Generate 3 NEW strategy implementations that target axis %s (%s).

Axis %s means: %s

## Requirements

1. Each strategy MUST introduce a genuinely NEW mechanism, not just parameter tuning
2. Valid mechanism changes:
   - Different section ordering or inclusion logic
   - New context retrieval (e.g., load additional files, use different git commands)
   - Different variable computation (e.g., compute new statistics, filter differently)
   - New skill loading patterns
   - Different adaptive compression strategies
3. INVALID changes (will be rejected):
   - Same logic, different constants
   - Just reordering existing code without changing behavior
   - Changing string literals but keeping same structure

## Output Format

For each candidate, output EXACTLY:

CANDIDATE_1:
```elisp
;;; strategy-NAME.el --- DESCRIPTION -*- lexical-binding: t; -*-
;; Hypothesis: ONE SENTENCE
;; Axis: %%s

(require 'gptel-tools-agent-prompt-build)

(defun strategy-NAME-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  ;; NEW MECHANISM HERE
  ;; Must return a string (the prompt)
  )

(defun strategy-NAME-get-metadata ()
  (list :name \"NAME\"
        :version \"1.0\"
        :hypothesis \"DESCRIPTION\"
        :axis \"%%s\"
        :components [\"tag1\" \"tag2\"]))

(provide 'strategy-NAME)
```

CANDIDATE_2:
[same format, different mechanism]

CANDIDATE_3:
[same format, different mechanism]

## Important

- The build function MUST call functions from `gptel-tools-agent-prompt-build` module
- Available functions include:
  - `gptel-auto-experiment-build-prompt` (baseline)
  - `gptel-auto-workflow--load-prompt-template`
  - `gptel-auto-workflow--substitute-template`
  - `gptel-auto-workflow--select-ab-test-sections`
  - `gptel-auto-workflow--adapt-prompt-compression`
  - `gptel-auto-experiment--format-failure-patterns`
  - `gptel-auto-experiment--format-axis-guidance`
  - `gptel-auto-experiment--frontier-saturation-guidance`
  - `gptel-auto-experiment--format-cross-target-patterns`
  - `gptel-auto-workflow--load-skill-content`
  - `gptel-auto-workflow--get-worktree-dir`
  - `gptel-auto-experiment--get-topic-knowledge`
- Each candidate should explore a DIFFERENT mechanism within axis %s
- Do NOT output any explanation, ONLY the 3 candidates"
                  (if (and skill-content (not (string-empty-p skill-content)))
                      (format "## Proposer Skill\n\n%s" skill-content)
                    "")
                  hypothesis
                  parent-strategy-name
                  (plist-get parent-perf :total)
                  (* 100 (plist-get parent-perf :success-rate))
                  (plist-get parent-perf :avg-score)
                  (or parent-code "(baseline strategy)")
                  (or failure-analysis "")
                  axis axis-desc
                  axis axis-desc
                  axis)))

    ;; Make synchronous gptel request
    (message "[strategy-evolution] Requesting strategy proposals from agent...")
    (let ((responses nil)
          (done nil))
      (condition-case err
          (progn
            (gptel-request proposer-prompt
                          :system "You are a strategy proposer for an automated code improvement system. You generate Emacs Lisp code for prompt-building strategies. Output ONLY code, no explanations."
                          :callback (lambda (response _info)
                                     (setq responses response
                                           done t)))
            ;; Wait for response (with timeout)
            (with-timeout (60 (message "[strategy-evolution] Timeout waiting for proposals")
                             nil)
              (while (not done)
                (sleep-for 0.5)))

            (when responses
              (message "[strategy-evolution] Received proposals, parsing...")
              (gptel-auto-workflow--parse-strategy-candidates responses)))
        (error
         (message "[strategy-evolution] Error requesting proposals: %s" err)
         nil)))))))

(defun gptel-auto-workflow--parse-strategy-candidates (response)
  "Parse 3 strategy candidates from gptel RESPONSE.
Returns list of 3 code strings."
  (let ((candidates '()))
    (dotimes (i 3)
      (let* ((start-label (format "CANDIDATE_%d:" (1+ i)))
             (end-label (format "CANDIDATE_%d:" (+ i 2)))
             (case-fold-search nil))
        (when (string-match (regexp-quote start-label) response)
          (let* ((start (match-end 0))
                 (end (if (string-match (regexp-quote end-label) response start)
                          (match-beginning 0)
                        (length response)))
                 (block (string-trim (substring response start end))))
            (when (string-match "```\\(?:elisp\\|emacs-lisp\\)?[[:space:]]*\\(\\(?:.\\|\n\\)*?\\)[[:space:]]*```" block)
              (setq block (string-trim (match-string 1 block))))
            (push (and (> (length block) 100) block) candidates)))))
    (setq candidates (nreverse candidates))
    (while (< (length candidates) 3)
      (setq candidates (append candidates (list nil))))
    (message "[strategy-evolution] Parsed %d valid candidates"
             (length (cl-remove-if #'null candidates)))
    candidates))

(defun gptel-auto-workflow--strategy-code-rewrite-name (code old-name new-name)
  "Rewrite strategy CODE from OLD-NAME to NEW-NAME."
  (let ((rewritten code))
    (setq rewritten (replace-regexp-in-string
                     (regexp-quote old-name) new-name rewritten t t))
    (setq rewritten (replace-regexp-in-string
                     "(provide 'strategy-[^)]+)"
                     (format "(provide 'strategy-%s)" new-name)
                     rewritten t t))
    rewritten))

(defun gptel-auto-workflow--prepare-strategy-candidate (candidate-code candidate-name)
  "Prepare CANDIDATE-CODE as a standalone strategy named CANDIDATE-NAME."
  (let ((code (string-trim candidate-code)))
    (if (string-match "strategy-\\([^[:space:])]+\\)-build-prompt" code)
        (gptel-auto-workflow--strategy-code-rewrite-name
         code
         (match-string 1 code)
         candidate-name)
      (gptel-auto-workflow--strategy-template
       candidate-name
       "Agent-proposed strategy candidate"
       'A
       nil
       code))))

;;; Strategy Evolution Loop

(defun gptel-auto-workflow--evolve-strategy (parent-strategy-name hypothesis axis)
  "Evolve a new strategy from PARENT-STRATEGY-NAME.
HYPOTHESIS describes the mechanism change.
AXIS is the exploitation axis (A-F).
Returns new strategy name or nil if rejected."
  (let* ((parent-file (expand-file-name
                       (format "strategy-%s.el" parent-strategy-name)
                       (gptel-auto-workflow--strategies-directory)))
         (parent-code (when (file-exists-p parent-file)
                        (with-temp-buffer
                          (insert-file-contents parent-file)
                          (buffer-string))))
         (parent-perf (gptel-auto-workflow--get-strategy-performance parent-strategy-name))
         (new-name (gptel-auto-workflow--generate-strategy-name))
         ;; Generate 3 candidates using agent-driven proposer
         (candidates (gptel-auto-workflow--propose-strategies
                      parent-strategy-name axis hypothesis parent-code parent-perf))
         (valid-candidates '()))
    
    ;; Validate each candidate
    (dolist (candidate (or candidates '()))
      (when candidate
        (let* ((candidate-index (1+ (- (length candidates)
                                        (length (member candidate candidates)))))
               (candidate-name (format "%s-candidate-%d" new-name candidate-index))
               (candidate-code (gptel-auto-workflow--prepare-strategy-candidate candidate candidate-name)))

          ;; Check 1: Not a parameter variant
          (if (and parent-code
                   (gptel-auto-workflow--is-parameter-variant-p candidate-code parent-code))
              (message "[strategy-evolution] REJECTED candidate: Parameter variant")

            ;; Check 2: Prototype validation
            (let ((prototype (gptel-auto-workflow--prototype-strategy
                             candidate-code
                             "lisp/modules/gptel-tools-agent-base.el")))
              (if (not (plist-get prototype :valid))
                  (message "[strategy-evolution] REJECTED candidate: Prototype failed: %s"
                           (mapconcat #'identity (plist-get prototype :errors) ", "))

                ;; Check 3: Actually returns a non-empty string
                (let ((output (plist-get prototype :output)))
                  (if (or (not (stringp output))
                          (< (length output) 100))
                      (message "[strategy-evolution] REJECTED candidate: Output too short (%d chars)"
                               (length output))

                    ;; Valid candidate
                    (push (list :code candidate-code
                               :name candidate-name
                               :output output
                               :output-length (length output))
                           valid-candidates)))))))))
    
    ;; Pick best candidate (longest output = most content, heuristic for completeness)
    (when valid-candidates
      (let* ((sorted (sort valid-candidates
                          (lambda (a b)
                            (> (plist-get a :output-length)
                               (plist-get b :output-length)))))
             (best (car sorted))
             (best-code (plist-get best :code))
             (final-code (gptel-auto-workflow--strategy-code-rewrite-name
                          best-code
                          (plist-get best :name)
                          new-name)))

        ;; Write strategy to filesystem
          (let ((strategy-file (expand-file-name
                              (format "strategy-%s.el" new-name)
                              (gptel-auto-workflow--strategies-directory))))
          (make-directory (file-name-directory strategy-file) t)
          (with-temp-file strategy-file
            (insert final-code))
          (let ((final-prototype
                 (gptel-auto-workflow--prototype-strategy
                  final-code
                  "lisp/modules/gptel-tools-agent-base.el")))
            (if (not (plist-get final-prototype :valid))
                (progn
                  (delete-file strategy-file)
                  (message "[strategy-evolution] REJECTED %s: Final prototype failed: %s"
                           new-name
                           (mapconcat #'identity (plist-get final-prototype :errors) ", "))
                  nil)
              (gptel-auto-workflow--load-strategy new-name)
              (message "[strategy-evolution] ACCEPTED %s (axis %s) from %d candidates"
                       new-name axis (length valid-candidates))
              new-name)))))))

;;; Periodic Strategy Evolution

(defun gptel-auto-workflow--maybe-evolve-strategy (target)
  "Maybe evolve a new strategy for TARGET based on recent performance.
Called periodically from the experiment loop.
If current strategy is underperforming, tries to generate a new one."
  (when (and gptel-auto-workflow--strategy-evolution-enabled
             (fboundp 'gptel-auto-workflow--select-best-strategy))
    (let* ((current-strategy gptel-auto-workflow--active-strategy)
           (current-perf (gptel-auto-workflow--get-strategy-performance current-strategy))
           (current-success-rate (plist-get current-perf :success-rate))
           (current-total (plist-get current-perf :total)))
      ;; Only evolve if we have enough data and performance is mediocre
      (when (and (>= current-total 5)
                 (<= current-success-rate 0.4))
         (message "[strategy] Current strategy '%s' has %.0f%% success rate, triggering evolution"
                 current-strategy (* 100 current-success-rate))
        ;; Check for interruption before starting
        (if gptel-auto-workflow--strategy-interrupted
            (message "[strategy] Interrupted, skipping evolution")
          ;; Pick an exploitation axis that's been least explored
          (let* ((axis-perf (make-hash-table :test 'equal))
                 (all-axes '("A" "B" "C" "D" "E" "F")))
          ;; Count experiments per axis for current strategy
          (let ((eval-file (gptel-auto-workflow--strategy-results-file)))
            (when (file-exists-p eval-file)
              (with-temp-buffer
                (insert-file-contents eval-file)
                (goto-char (point-min))
                (while (not (eobp))
                  (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
                    (when (not (string-empty-p line))
                      (condition-case nil
                          (let* ((entry (json-read-from-string line))
                                 (entry-strategy (cdr (assoc 'strategy entry)))
                                 (entry-axis (cdr (assoc 'axis entry))))
                            (when (and (equal entry-strategy current-strategy)
                                       entry-axis)
                              (puthash entry-axis
                                       (1+ (gethash entry-axis axis-perf 0))
                                       axis-perf)))
                        (error nil)))
                    (forward-line 1))))))
          ;; Find least explored axis
          (let ((min-count most-positive-fixnum)
                (target-axis nil))
            (dolist (axis all-axes)
              (let ((count (gethash axis axis-perf 0)))
                (when (< count min-count)
                  (setq min-count count)
                  (setq target-axis axis))))
            ;; Evolve strategy (with interrupt protection)
            (let ((new-strategy
                   (condition-case quit
                       (gptel-auto-workflow--evolve-strategy
                        current-strategy
                        (format "Improve strategy by targeting axis %s (%s)"
                                target-axis
                                (gptel-auto-workflow--strategy-axis-description target-axis))
                        target-axis)
                     (quit
                      (setq gptel-auto-workflow--strategy-interrupted t)
                      (message "[strategy] Evolution interrupted by signal, got %.0f%% complete"
                               (* 100 (/ (float (length all-axes)) 6.0)))
                      nil))))
              (when new-strategy
                (message "[strategy] Evolved new strategy: %s" new-strategy)
                ;; Write evolution summary
                (let* ((perf (gptel-auto-workflow--get-strategy-performance new-strategy))
                       (val-scores (make-hash-table :test 'equal))
                       (candidates (list (list :name new-strategy
                                              :axis target-axis
                                              :hypothesis (format "Axis %s improvement" target-axis)
                                              :components (list (format "axis-%s" target-axis))))))
                  (puthash new-strategy (plist-get perf :avg-score) val-scores)
                  (gptel-auto-workflow--ensure-strategy-run-directories)
                  (gptel-auto-workflow--write-evolution-summary
                   (1+ (gethash current-strategy val-scores 0))
                   candidates
                   val-scores
                   (list :propose 0.0 :bench 0.0 :wall 0.0)))
                 ;; Switch to new strategy if it passed validation
                  (setq gptel-auto-workflow--active-strategy new-strategy))))))))))

(provide 'gptel-tools-agent-strategy-evolver)
;;; gptel-tools-agent-strategy-evolver.el ends here
