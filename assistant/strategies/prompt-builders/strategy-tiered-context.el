;;; strategy-tiered-context.el --- Hierarchical tiered context structure -*- lexical-binding: t; -*-
;; Hypothesis: Organizing prompt sections into hierarchical tiers (core/context/guidance)
;; with conditional inclusion will improve relevance and reduce noise compared to flat templates.
;; Axis: A (Prompt template architecture)
;;
;; Key mechanism: Instead of a flat template, use a hierarchical structure where:
;; - TIER-CORE: Always included - essential task framing
;; - TIER-CONTEXT: Included if baseline exists - baseline metrics
;; - TIER-GUIDANCE: Included if failures exist - what to avoid
;; - TIER-EXPLORATION: Included if many experiments run - cross-target patterns

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-tiered-context--tiered-template
  ;; This template uses mustache-style conditional sections
  ;; Sections wrapped in {{#name}}...{{/name}} are conditionally included
  (concat
   "You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.\n\n"
   "## TIER-CORE: Essential Task Framing\n"
   "Working Directory: {{worktree-path}}\n"
   "Target: {{target-full-path}}\n"
   "{{large-target-guidance}}"
   "{{controller-focus}}"
   "{{inspection-thrash-contract}}"
   "\n## HYPOTHESIS\n"
   "HYPOTHESIS: [What CODE change and why]\n"
   "{{focus-line}}\n\n"
   "{{#has-baseline}}"
   "## TIER-CONTEXT: Baseline Metrics\n"
   "Eight Keys score: {{baseline}}\n"
   "{{weakest-keys}}\n"
   "{{suggested-hypothesis}}\n"
   "{{mutation-templates}}\n\n"
   "{{/has-baseline}}"
   "{{#has-suggestions}}"
   "## TIER-CONTEXT: Suggestions\n"
   "{{suggestions}}\n\n"
   "{{/has-suggestions}}"
   "{{#has-previous-experiments}}"
   "## TIER-CONTEXT: Previous Experiments\n"
   "{{previous-experiment-analysis}}\n\n"
   "{{/has-previous-experiments}}"
   "{{#has-failures}}"
   "## TIER-GUIDANCE: What NOT to Do (Based on Failures)\n"
   "{{failure-patterns}}\n"
   "{{anti-patterns}}\n\n"
   "{{/has-failures}}"
   "{{#has-axis-info}}"
   "## TIER-GUIDANCE: Axis Information\n"
   "{{axis-guidance}}\n"
   "{{axis-performance}}\n\n"
   "{{/has-axis-info}}"
   "{{#is-exploration-phase}}"
   "## TIER-EXPLORATION: Cross-Target Patterns\n"
   "{{cross-target-patterns}}\n"
   "{{frontier-guidance}}\n"
   "{{saturation-status}}\n\n"
   "{{/is-exploration-phase}}"
   "{{#has-skills}}"
   "## TIER-EXPLORATION: Skills & Evolution\n"
   "{{self-evolution}}\n"
   "{{topic-knowledge}}\n"
   "{{git-history}}\n\n"
   "{{/has-skills}}"
   "## TIER-CORE: Objective & Constraints\n"
   "Improve CODE QUALITY for {{target}}.\n"
   "- Time budget: {{time-budget}} minutes\n"
   "- Must pass tests: ./scripts/verify-nucleus.sh\n"
   "- FORBIDDEN: Adding comments, docstrings, or documentation-only changes\n"
   "- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)\n\n"
   "## TIER-CORE: Instructions\n"
   "1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]\n"
   "2. Start from one concrete function or variable\n"
   "3. Implement the CODE change using Edit tool\n"
   "4. Run S-exp check: {{sexp-check-command}}\n"
   "5. Run tests: ./scripts/verify-nucleus.sh\n"
   "6. FINAL RESPONSE must include: CHANGED, EVIDENCE, VERIFY\n"
   "7. End with: Task completed\n\n"
   "{{agent-behavior}}\n"
   "{{validation-pipeline}}\n"
   "{{strategy-frontier}}\n\n"
   "CRITICAL: Focus on ONE improvement at a time. Make minimal, targeted changes to CODE."))

(defun strategy-tiered-context--compute-flags (target experiment-id max-experiments analysis baseline previous-results)
  "Compute boolean flags for conditional tier inclusion."
  (let* ((patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (failure-patterns (gptel-auto-experiment--format-failure-patterns target))
         (has-failure-patterns (and (stringp failure-patterns)
                                    (> (length failure-patterns) 50)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (has-skills (and skills (> (length skills) 0)))
         (weakest-keys (when (gptel-auto-experiment--eight-keys-scores)
                        (gptel-auto-workflow--format-weakest-keys
                         (gptel-auto-experiment--eight-keys-scores))))
         (has-axis-info (or (gptel-auto-experiment--get-underexplored-axis target)
                           (gptel-auto-experiment--format-axis-performance target)
                           (gptel-auto-experiment--format-frontier-guidance target)))
         (cross-target (gptel-auto-experiment--format-cross-target-patterns target))
         (has-cross-target (and (stringp cross-target)
                                (> (length cross-target) 50))))
    `((has-baseline . ,(and baseline (> baseline 0)))
      (has-suggestions . ,(and suggestions (> (length suggestions) 0)))
      (has-previous-experiments . ,(and patterns (> (length patterns) 0)))
      (has-failures . ,has-failure-patterns)
      (has-skills . ,(or has-skills
                         (fboundp 'gptel-auto-workflow--evolution-get-knowledge)))
      (has-axis-info . ,has-axis-info)
      (is-exploration-phase . ,(and max-experiments
                                    (> max-experiments 3)))
      (has-cross-target . ,has-cross-target))))

(defun strategy-tiered-context--build-anti-patterns (target)
  "Build anti-patterns from failure reasons."
  (let* ((failure-reasons (gptel-auto-experiment--get-common-failure-reasons target 5)))
    (when failure-reasons
      (concat "### Anti-Patterns (AVOID these patterns)\n"
               (mapconcat (lambda (pair)
                            (let ((reason (car pair)))
                              (cond
                               ((string-match-p "regressed" reason)
                                "- AVOID: Improving one metric while degrading another")
                               ((string-match-p "tie without" reason)
                                "- AVOID: Submitting changes that result in score ties")
                               ((string-match-p "quality.*→.*quality" reason)
                                "- AVOID: Maintaining quality without improvement")
                               (t (format "- AVOID: %s"
                                          (substring reason 0 (min 60 (length reason))))))))
                          failure-reasons "\n")
              "\n"))))

(defun strategy-tiered-context--substitute-with-conditions (template variables flags)
  "Substitute TEMPLATE with VARIABLES, respecting boolean FLAGS.
For each {{#flag}}...{{/flag}} block, only include if flag is non-nil."
  (let ((result template))
    ;; Process conditional blocks
    (dolist (flag flags)
      (let* ((flag-name (car flag))
             (flag-value (cdr flag))
             (pattern-start (format "{{#%s}}" flag-name))
             (pattern-end (format "{{/%s}}" flag-name))
             (start-idx 0))
        (while (and result
                    (string-match (regexp-quote pattern-start) result start-idx))
          (let ((block-start (match-beginning 0))
                (after-start (+ (match-end 0)
                                (string-match (regexp-quote pattern-end)
                                              (substring result (match-end 0))))))
            (if after-start
                (let ((block-end (match-beginning 0))
                      (block-content (substring result (match-end 0) (1- after-start))))
                  (if flag-value
                      (setq result (concat (substring result 0 block-start)
                                           block-content
                                           (substring result (1+ after-start))))
                    (setq result (concat (substring result 0 block-start)
                                         (substring result (1+ after-start)))))
                  (setq start-idx block-start))
              (setq start-idx (match-end 0))))))
    ;; Now do standard variable substitution
    (gptel-auto-workflow--substitute-template result variables)))

(defun strategy-tiered-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using hierarchical tiered context structure.
Sections are organized into tiers and conditionally included based on available data."
  ;; Adapt compression
  (gptel-auto-workflow--adapt-prompt-compression)
  
  ;; Compute all variables
  (let* ((worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         (target-full-path (expand-file-name target worktree-path))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (large-target-p (and (numberp target-bytes)
                              (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
         (focus-candidate (when large-target-p
                            (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
         (large-target-guidance (when large-target-p
                                  (concat "This target is large (" (format "%d" target-bytes) " bytes).\n"
                                          "- Start from one concrete function or variable\n"
                                          (when focus-candidate
                                            (format "- Begin at `%s` or a direct caller/callee\n"
                                                    (plist-get focus-candidate :name)))
                                          "- Prefer focused Grep or narrow Read\n\n")))
         (controller-focus (when focus-candidate
                             (format "Starting Symbol: `%s` (%s)\n\n"
                                     (plist-get focus-candidate :name)
                                     (plist-get focus-candidate :kind))))
         (recovery-p (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (inspection-thrash-contract (when recovery-p
                                       (concat "## Mandatory Focus Contract\n"
                                               "A previous attempt failed with inspection-thrash.\n"
                                               "CRITICAL: Do at most 2 read-only calls before writing.\n\n")))
         (focus-line (format "FOCUS: %s"
                             (or (plist-get focus-candidate :name)
                                 "<one concrete function or variable>")))
         (sexp-check-command
          (format
           "emacs -Q --batch --eval %s"
           (shell-quote-argument
            (format
             "(progn (find-file %S) (emacs-lisp-mode) (condition-case err (progn (scan-sexps (point-min) (point-max)) (message \"OK\")) (error (message \"ERROR: %%s\" err) (kill-emacs 1))))"
             target-full-path))))
         (anti-patterns (strategy-tiered-context--build-anti-patterns target))
         (git-history (let ((gh (shell-command-to-string
                                 (format "cd %s && git log --oneline -20 2>/dev/null || echo ''"
                                         (shell-quote-argument worktree-path)))))
                        (if (> (length gh) 0) gh "")))
         (time-budget (/ gptel-auto-experiment-time-budget 60))
         (axis-guidance (or (gptel-auto-experiment--format-axis-guidance
                             (gptel-auto-experiment--get-underexplored-axis target)) ""))
         (axis-performance (gptel-auto-experiment--format-axis-performance target))
         (failure-patterns (gptel-auto-experiment--format-failure-patterns target))
         (frontier-guidance (gptel-auto-experiment--format-frontier-guidance target))
         (saturation-status (gptel-auto-experiment--frontier-saturation-guidance target))
         (cross-target-patterns (gptel-auto-experiment--format-cross-target-patterns target))
         (self-evolution (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                            (gptel-auto-workflow--evolution-get-knowledge)
                          ""))
         (topic-knowledge (gptel-auto-experiment--get-topic-knowledge target))
         (strategy-frontier (if (fboundp 'gptel-auto-workflow--format-strategy-frontier)
                                (gptel-auto-workflow--format-strategy-frontier)
                              ""))
         (agent-behavior (gptel-auto-workflow--load-skill-content "auto-workflow/agent-behavior"))
         (validation-pipeline (gptel-auto-workflow--load-skill-content "auto-workflow/validation-pipeline"))
         
         ;; Compute conditional flags
         (flags (strategy-tiered-context--compute-flags target experiment-id max-experiments analysis baseline previous-results))
         
         ;; Build variables
         (variables
          `((experiment-id . ,experiment-id)
            (max-experiments . ,max-experiments)
            (target . ,target)
            (worktree-path . ,worktree-path)
            (target-full-path . ,target-full-path)
            (large-target-guidance . ,(or large-target-guidance ""))
            (controller-focus . ,(or controller-focus ""))
            (inspection-thrash-contract . ,(or inspection-thrash-contract ""))
            (focus-line . ,focus-line)
            (baseline . ,(format "%.2f" (or baseline 0.5)))
            (weakest-keys . ,(or weakest-keys ""))
            (suggested-hypothesis . ,(if suggested-hypothesis
                                          (format "## Suggested Hypothesis\n%s" suggested-hypothesis)
                                        ""))
            (mutation-templates . ,(if mutation-templates
                                       (format "## Hypothesis Templates\n%s"
                                               (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
                                     ""))
            (suggestions . ,(or suggestions "None"))
            (previous-experiment-analysis . ,(or patterns "No previous experiments"))
            (failure-patterns . ,failure-patterns)
            (anti-patterns . ,(or anti-patterns ""))
            (axis-guidance . ,axis-guidance)
            (axis-performance . ,axis-performance)
            (cross-target-patterns . ,cross-target-patterns)
            (frontier-guidance . ,frontier-guidance)
            (saturation-status . ,saturation-status)
            (self-evolution . ,self-evolution)
            (topic-knowledge . ,topic-knowledge)
            (git-history . ,git-history)
            (strategy-frontier . ,strategy-frontier)
            (agent-behavior . ,agent-behavior)
            (validation-pipeline . ,validation-pipeline)
            (time-budget . ,time-budget)
            (sexp-check-command . ,sexp-check-command))))
    
    ;; Substitute with conditional logic
    (strategy-tiered-context--substitute-with-conditions
     strategy-tiered-context--tiered-template variables flags)))

(defun strategy-tiered-context-get-metadata ()
  "Return metadata for this strategy."
  (list :name "tiered-context"
        :version "1.0"
        :hypothesis "Hierarchical tiered context structure with conditional inclusion improves relevance by only showing applicable guidance"
        :axis "A"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies '("template-default")
        :components '("tiered-structure" "conditional-sections" "hierarchical-context")
        :description "Organizes prompt into TIER-CORE, TIER-CONTEXT, TIER-GUIDANCE, TIER-EXPLORATION with conditional inclusion."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "tiered-context"
   #'strategy-tiered-context-build-prompt
   (strategy-tiered-context-get-metadata)))

(provide 'strategy-tiered-context)
