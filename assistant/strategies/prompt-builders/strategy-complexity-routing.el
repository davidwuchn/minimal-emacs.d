;;; strategy-complexity-routing.el --- Template complexity routing based on target size -*- lexical-binding: t; -*-
;; Hypothesis: Different target file complexities require different prompt complexity levels.
;; Small files need minimal prompts, medium files need standard prompts, and large files
;; need extended guidance with focus constraints to avoid thrashing.
;; Axis: A (Prompt template architecture)
;;
;; Key mechanism: Route to different prompt templates based on target byte size,
;; reducing overhead for simple targets and adding focus for complex ones.

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-complexity-routing--template-variants
  '((minimal
     .
     ,(concat
       "You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.\n"
       "Working Directory: {{worktree-path}}\n"
       "Target: {{target-full-path}}\n\n"
       "## HYPOTHESIS FORMAT\n"
       "HYPOTHESIS: [What CODE change and why]\n"
       "FOCUS: {{focus-line}}\n\n"
       "## Baseline\n"
       "Eight Keys score: {{baseline}}\n\n"
       "{{weakest-keys}}\n\n"
       "## Objective\n"
       "Improve CODE QUALITY for {{target}}. Make minimal, targeted changes.\n\n"
       "## Constraints\n"
       "- Time budget: {{time-budget}} minutes\n"
       "- Must pass tests: ./scripts/verify-nucleus.sh\n"
       "- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)\n"
       "- FORBIDDEN: Adding comments, docstrings, or documentation-only changes\n\n"
       "## Instructions\n"
       "1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]\n"
       "2. Identify a real code issue in {{target-full-path}}\n"
       "3. Implement the CODE change using Edit tool\n"
       "4. Run tests to verify: ./scripts/verify-nucleus.sh\n"
       "5. FINAL RESPONSE must include: CHANGED, EVIDENCE, VERIFY\n"
       "6. End with: Task completed\n\n"
       "CRITICAL: Focus on ONE improvement at a time. Do not add comments.\n"))

    (standard
     .
     ,(concat
       "You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.\n\n"
       "## Working Directory\n"
       "{{worktree-path}}\n\n"
       "## Target File\n"
       "{{target-full-path}}\n\n"
       "{{large-target-guidance}}"
       "{{controller-focus}}"
       "{{inspection-thrash-contract}}\n\n"
       "## Previous Experiment Analysis\n"
       "{{previous-experiment-analysis}}\n\n"
       "## Suggestions\n"
       "{{suggestions}}\n\n"
       "## Baseline\n"
       "Eight Keys score: {{baseline}}\n\n"
       "{{weakest-keys}}\n\n"
       "{{suggested-hypothesis}}\n\n"
       "{{mutation-templates}}\n\n"
       "{{axis-guidance}}\n"
       "{{axis-performance}}\n\n"
       "## Objective\n"
       "Improve CODE QUALITY for {{target}}. Focus on one improvement at a time.\n\n"
       "## Constraints\n"
       "- Time budget: {{time-budget}} minutes\n"
       "- Must pass tests: ./scripts/verify-nucleus.sh\n"
       "- FORBIDDEN: Adding comments, docstrings, or documentation-only changes\n"
       "- REQUIRED: Actual code changes\n\n"
       "## Instructions\n"
       "1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]\n"
       "2. Start from one concrete function or variable\n"
       "3. Implement the CODE change using Edit tool\n"
       "4. Run tests: ./scripts/verify-nucleus.sh\n"
       "5. FINAL RESPONSE must include: CHANGED, EVIDENCE, VERIFY\n"
       "6. End with: Task completed\n\n"
       "{{failure-patterns}}\n"))

    (extended
     .
     ,(concat
       "You are running experiment {{experiment-id}} of {{max-experiments}} to optimize {{target}}.\n\n"
       "## Working Directory\n"
       "{{worktree-path}}\n\n"
       "## Target File\n"
       "{{target-full-path}}\n\n"
       "{{large-target-guidance}}"
       "{{controller-focus}}"
       "{{inspection-thrash-contract}}\n\n"
       "## Previous Experiment Analysis\n"
       "{{previous-experiment-analysis}}\n\n"
       "## Suggestions\n"
       "{{suggestions}}\n\n"
       "{{self-evolution}}\n\n"
       "{{topic-knowledge}}\n\n"
       "{{git-history}}\n\n"
       "## Current Baseline\n"
       "Eight Keys score: {{baseline}}\n\n"
       "{{weakest-keys}}\n\n"
       "{{suggested-hypothesis}}\n\n"
       "{{mutation-templates}}\n\n"
       "## Objective\n"
       "Improve CODE QUALITY for {{target}}.\n\n"
       "## Constraints\n"
       "- Time budget: {{time-budget}} minutes\n"
       "- Must pass tests: ./scripts/verify-nucleus.sh\n"
       "- FORBIDDEN: Adding comments, docstrings, or documentation-only changes\n"
       "- REQUIRED: Actual code changes\n\n"
       "## Instructions\n"
       "1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]\n"
       "2. Start from one concrete function or variable\n"
       "3. Implement the CODE change using Edit tool\n"
       "4. Run tests: ./scripts/verify-nucleus.sh\n"
       "5. FINAL RESPONSE must include: CHANGED, EVIDENCE, VERIFY\n"
       "6. End with: Task completed\n\n"
       "{{axis-guidance}}\n"
       "{{axis-performance}}\n"
       "{{frontier-guidance}}\n"
       "{{saturation-status}}\n\n"
       "{{failure-patterns}}\n"
       "{{cross-target-patterns}}\n\n"
       "{{strategy-frontier}}\n\n"
       "{{agent-behavior}}\n"
       "{{validation-pipeline}}\n\n")))
  "Template variants indexed by complexity tier.")

(defun strategy-complexity-routing--select-tier (target-bytes)
  "Select complexity tier based on TARGET-BYTES.
Returns symbol: 'minimal, 'standard, or 'extended."
  (cond
   ;; Large files (>50KB) get minimal - thrashing risk is too high
   ((>= target-bytes 50000) 'minimal)
   ;; Medium-large files (10-50KB) get extended - more context needed
   ((>= target-bytes 10000) 'extended)
   ;; Small-medium files (2-10KB) get standard
   ((>= target-bytes 2000) 'standard)
   ;; Very small files (<2KB) get minimal - overhead not worth it
   (t 'minimal)))

(defun strategy-complexity-routing--build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with complexity routing.
Selects template variant based on target file size."
  ;; Adapt compression
  (gptel-auto-workflow--adapt-prompt-compression)
  
  ;; Get target size
  (let* ((worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         (target-full-path (expand-file-name target worktree-path))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (tier (strategy-complexity-routing--select-tier (or target-bytes 0)))
         (template (alist-get tier strategy-complexity-routing--template-variants))
         
         ;; Common variables for all tiers
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (time-budget (/ gptel-auto-experiment-time-budget 60))
         (focus-line "FOCUS: <one concrete function or variable>")
         
         ;; Variables only used in standard/extended templates
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (large-target-p (and (numberp target-bytes)
                              (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
         (focus-candidate (when large-target-p
                            (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
         (large-target-guidance (when large-target-p
                                  (concat "## Large Target Guidance\n"
                                          (format "This target is large (%d bytes). Start from one concrete function or variable.\n" target-bytes)
                                          (when focus-candidate
                                            (format "- Begin at `%s`.\n" (plist-get focus-candidate :name)))
                                          "- Prefer focused Grep or narrow Read before broader surveys.\n\n")))
         (controller-focus (when focus-candidate
                            (format "## Controller-Selected Starting Symbol\n- Symbol: `%s`\n- Kind: %s\n\n"
                                    (plist-get focus-candidate :name)
                                    (plist-get focus-candidate :kind))))
         (recovery-p (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (inspection-thrash-contract (when recovery-p
                                       (concat "## Mandatory Focus Contract\n"
                                               "A previous attempt failed with inspection-thrash.\n"
                                               "CRITICAL: Do at most 2 read-only calls before writing.\n\n"))))
    ;; Update focus-line if we have a candidate
    (when focus-candidate
      (setq focus-line (format "FOCUS: %s" (plist-get focus-candidate :name))))
    
    ;; Build variables based on tier
    (let* ((variables
            (pcase tier
              ('minimal
               `((experiment-id . ,experiment-id)
                 (max-experiments . ,max-experiments)
                 (target . ,target)
                 (worktree-path . ,worktree-path)
                 (target-full-path . ,target-full-path)
                 (baseline . ,(format "%.2f" (or baseline 0.5)))
                 (focus-line . ,focus-line)
                 (weakest-keys . ,(if weakest-keys
                                        (format "## Weakest Keys\n%s" weakest-keys)
                                      ""))
                 (time-budget . ,time-budget)))
              ('standard
               `((experiment-id . ,experiment-id)
                 (max-experiments . ,max-experiments)
                 (target . ,target)
                 (worktree-path . ,worktree-path)
                 (target-full-path . ,target-full-path)
                 (large-target-guidance . ,(or large-target-guidance ""))
                 (controller-focus . ,(or controller-focus ""))
                 (inspection-thrash-contract . ,(or inspection-thrash-contract ""))
                 (previous-experiment-analysis . ,(or patterns "No previous experiments"))
                 (suggestions . ,(or suggestions "None"))
                 (baseline . ,(format "%.2f" (or baseline 0.5)))
                 (weakest-keys . ,(if weakest-keys
                                        (format "## Weakest Keys\n%s" weakest-keys)
                                      ""))
                 (suggested-hypothesis . ,(if suggested-hypothesis
                                               (format "## Suggested Hypothesis\n%s" suggested-hypothesis)
                                             ""))
                 (mutation-templates . ,(if mutation-templates
                                            (format "## Hypothesis Templates\n%s"
                                                    (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
                                          ""))
                 (axis-guidance . ,(or (gptel-auto-experiment--format-axis-guidance
                                         (gptel-auto-experiment--get-underexplored-axis target)) ""))
                 (axis-performance . ,(gptel-auto-experiment--format-axis-performance target))
                 (failure-patterns . ,(gptel-auto-experiment--format-failure-patterns target))
                 (time-budget . ,time-budget)))
              ('extended
               `((experiment-id . ,experiment-id)
                 (max-experiments . ,max-experiments)
                 (target . ,target)
                 (worktree-path . ,worktree-path)
                 (target-full-path . ,target-full-path)
                 (large-target-guidance . ,(or large-target-guidance ""))
                 (controller-focus . ,(or controller-focus ""))
                 (inspection-thrash-contract . ,(or inspection-thrash-contract ""))
                 (previous-experiment-analysis . ,(or patterns "No previous experiments"))
                 (suggestions . ,(or suggestions "None"))
                 (self-evolution . ,(if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                                         (gptel-auto-workflow--evolution-get-knowledge)
                                       ""))
                 (topic-knowledge . ,(gptel-auto-experiment--get-topic-knowledge target))
                 (git-history . ,(let ((gh (shell-command-to-string
                                              (format "cd %s && git log --oneline -20 2>/dev/null || echo ''"
                                                      (shell-quote-argument worktree-path)))))
                                    (if (> (length gh) 0) gh "")))
                 (baseline . ,(format "%.2f" (or baseline 0.5)))
                 (weakest-keys . ,(if weakest-keys
                                        (format "## Weakest Keys\n%s" weakest-keys)
                                      ""))
                 (suggested-hypothesis . ,(if suggested-hypothesis
                                               (format "## Suggested Hypothesis\n%s" suggested-hypothesis)
                                             ""))
                 (mutation-templates . ,(if mutation-templates
                                            (format "## Hypothesis Templates\n%s"
                                                    (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
                                          ""))
                 (axis-guidance . ,(or (gptel-auto-experiment--format-axis-guidance
                                         (gptel-auto-experiment--get-underexplored-axis target)) ""))
                 (axis-performance . ,(gptel-auto-experiment--format-axis-performance target))
                 (frontier-guidance . ,(gptel-auto-experiment--format-frontier-guidance target))
                 (saturation-status . ,(gptel-auto-experiment--frontier-saturation-guidance target))
                 (failure-patterns . ,(gptel-auto-experiment--format-failure-patterns target))
                 (cross-target-patterns . ,(gptel-auto-experiment--format-cross-target-patterns target))
                 (strategy-frontier . ,(if (fboundp 'gptel-auto-workflow--format-strategy-frontier)
                                           (gptel-auto-workflow--format-strategy-frontier)
                                         ""))
                 (agent-behavior . ,(gptel-auto-workflow--load-skill-content "auto-workflow/agent-behavior"))
                 (validation-pipeline . ,(gptel-auto-workflow--load-skill-content "auto-workflow/validation-pipeline"))
                 (time-budget . ,time-budget))))))
      (message "[complexity-routing] Target %s (%d bytes) -> tier %s" target target-bytes tier)
      (gptel-auto-workflow--substitute-template template variables))))

(defun strategy-complexity-routing-get-metadata ()
  "Return metadata for this strategy."
  (list :name "complexity-routing"
        :version "1.0"
        :hypothesis "Routing to different prompt complexity based on target file size reduces thrashing for large files and overhead for small files"
        :axis "A"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies '("template-default")
        :components '("complexity-tiering" "template-routing" "byte-threshold")
        :description "Selects minimal/standard/extended template based on target byte size."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "complexity-routing"
   #'strategy-complexity-routing--build-prompt
   (strategy-complexity-routing-get-metadata)))

(provide 'strategy-complexity-routing)
;;; strategy-complexity-routing.el ends here
