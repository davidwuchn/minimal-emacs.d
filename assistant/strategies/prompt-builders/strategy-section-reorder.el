;;; strategy-section-reorder.el --- Evolved prompt-building strategy -*- lexical-binding: t; -*-
;; Strategy for gptel-tools-agent-strategy-harness
;;
;; Hypothesis: Reordering prompt sections to put failure patterns and axis guidance
;; BEFORE the general instructions will help the agent avoid known pitfalls earlier
;; Axis: A (Prompt template architecture)
;; Parents: (template-default)
;; Generated: 2026-05-02
;;
;; CRITICAL: This strategy introduces a NEW mechanism, not just parameter tuning.
;; It changes the fundamental PROMPT ARCHITECTURE by reordering sections.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-section-reorder-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using evolved strategy evolved-0001.
HYPOTHESIS: Reordering prompt sections to put failure patterns and axis guidance
;; BEFORE the general instructions will help the agent avoid known pitfalls earlier"
  ;; Adapt compression based on token efficiency analysis
  (gptel-auto-workflow--adapt-prompt-compression)
  
  ;; Select sections for A/B testing
  (let* ((included-sections (gptel-auto-workflow--select-ab-test-sections))
         (section-included-p (lambda (section) (member section included-sections)))
         
         (worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         (worktree-quoted (shell-quote-argument worktree-path))
         (git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               worktree-quoted)))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (target-full-path (expand-file-name target worktree-path))
         (sexp-check-command
          (format
           "emacs -Q --batch --eval %s"
           (shell-quote-argument
            (format
             "(progn (find-file %S) (emacs-lisp-mode) (condition-case err (progn (scan-sexps (point-min) (point-max)) (message \"OK\")) (error (message \"ERROR: %%s\" err) (kill-emacs 1))))"
             target-full-path))))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (recovery-p
          (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (large-target-p
          (and (numberp target-bytes)
               (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
         (focus-candidate
          (when large-target-p
            (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
         (large-target-guidance
          (when large-target-p
            (concat "## Large Target Guidance\n"
                    (format "This target is large (%d bytes). Start from one concrete function or variable instead of surveying the whole file.\n"
                            target-bytes)
                    (when focus-candidate
                      (format "- Begin at `%s` or a direct caller/callee.\n"
                              (plist-get focus-candidate :name)))
                    "- Prefer focused Grep or narrow Read before broader Code_Map surveys.\n"
                    "- Make the first edit before exploring a second subsystem.\n\n")))
         (focus-line
          (format "FOCUS: %s"
                  (or (plist-get focus-candidate :name)
                      "<one concrete function or variable>")))
         (controller-focus
          (when focus-candidate
            (format "## Controller-Selected Starting Symbol\n- Symbol: `%s`\n- Kind: %s\n- Approx lines: %d-%d (%d lines)\n- Reason: controller-selected small or medium helper in a very large file; start here or at a direct caller/callee.\n\n"
                    (plist-get focus-candidate :name)
                    (plist-get focus-candidate :kind)
                    (plist-get focus-candidate :start-line)
                    (plist-get focus-candidate :end-line)
                    (plist-get focus-candidate :size-lines))))
         (inspection-thrash-contract
          (when recovery-p
            (concat "## Mandatory Focus Contract\n"
                    "A previous attempt on this target already failed with inspection-thrash.\n"
                    (when large-target-p
                      (format "This target is large (%d bytes). Broad file surveys are likely to fail.\n"
                              target-bytes))
                     "CRITICAL: You previously failed with inspection-thrash on this file.\n"
                     "The system will ABORT your turn if you do too many read-only inspections without writing.\n\n"
                     "Follow this exact opening sequence:\n"
                     (format "1. The second line after HYPOTHESIS must be exactly `%s`.\n"
                             focus-line)
                     "2. Do NOT use Code_Map on the whole file.\n"
                     "3. Use at most 2 read-only tool calls (Read, Grep, Code_Inspect), all on that same symbol.\n"
                     "4. Your NEXT tool call MUST be a write (Edit, Write, ApplyPatch) on that same symbol.\n"
                     "5. If you do more than 2 read-only calls without writing, your turn will be aborted.\n"
                     "6. Do not inspect a second subsystem before the first edit exists.\n\n"))))
    (setq gptel-auto-workflow--last-prompt-sections
          (mapconcat #'symbol-name included-sections ","))
    ;; Build variables alist for template substitution
    ;; KEY DIFFERENCE: We reorder sections to put critical guidance first
    (let* ((template (gptel-auto-workflow--load-prompt-template))
           (variables
            `((experiment-id . ,experiment-id)
              (max-experiments . ,max-experiments)
              (target . ,target)
              (worktree-path . ,worktree-path)
              (target-full-path . ,target-full-path)
              (large-target-guidance . ,(or large-target-guidance ""))
              (controller-focus . ,(or controller-focus ""))
              (inspection-thrash-contract . ,(or inspection-thrash-contract ""))
              ;; CRITICAL GUIDANCE FIRST (reordered from default)
              (failure-patterns . ,(if (funcall section-included-p 'failure-patterns)
                                       (gptel-auto-experiment--format-failure-patterns target)
                                     ""))
              (axis-guidance . ,(if (funcall section-included-p 'axis-guidance)
                                    (or (gptel-auto-experiment--format-axis-guidance
                                         (gptel-auto-experiment--get-underexplored-axis target)) "")
                                  ""))
              (saturation-status . ,(gptel-auto-experiment--frontier-saturation-guidance target))
              ;; Then the standard sections
              (previous-experiment-analysis . ,(or patterns "No previous experiments"))
              (suggestions . ,(if (funcall section-included-p 'suggestions)
                                  (or suggestions "None")
                                ""))
              (self-evolution . ,(if (funcall section-included-p 'self-evolution)
                                     (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                                         (gptel-auto-workflow--evolution-get-knowledge)
                                       "")
                                   ""))
              (topic-knowledge . ,(if (funcall section-included-p 'topic-specific)
                                      (gptel-auto-experiment--get-topic-knowledge target)
                                    ""))
              (git-history . ,(if (funcall section-included-p 'git-history)
                                  git-history
                                ""))
              (baseline . ,(format "%.2f" (or baseline 0.5)))
              (weakest-keys . ,(if weakest-keys
                                   (format "## Weakest Keys (Priority Focus)\n%s" weakest-keys)
                                 ""))
              (suggested-hypothesis . ,(if suggested-hypothesis
                                           (format "## Suggested Hypothesis (from skill)\n%s" suggested-hypothesis)
                                         ""))
              (mutation-templates . ,(if mutation-templates
                                         (format "## Hypothesis Templates\n%s"
                                                 (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
                                       ""))
              ;; Performance data after the agent knows what to avoid
              (axis-performance . ,(if (funcall section-included-p 'axis-performance)
                                       (gptel-auto-experiment--format-axis-performance target)
                                     ""))
              (frontier-guidance . ,(gptel-auto-experiment--format-frontier-guidance target))
              (cross-target-patterns . ,(if (funcall section-included-p 'cross-target-patterns)
                                            (gptel-auto-experiment--format-cross-target-patterns target)
                                          ""))
              (agent-behavior . ,(gptel-auto-workflow--load-skill-content "auto-workflow/agent-behavior"))
              (validation-pipeline . ,(gptel-auto-workflow--load-skill-content "auto-workflow/validation-pipeline"))
              (time-budget . ,(/ gptel-auto-experiment-time-budget 60))
              (focus-line . ,focus-line)
              (sexp-check-command . ,sexp-check-command))))
      (gptel-auto-workflow--substitute-template template variables))))

(defun strategy-section-reorder-get-metadata ()
  "Return metadata for this strategy."
  (list :name "evolved-0001"
        :version "1.0"
        :hypothesis "Reordering prompt sections to put failure patterns and axis guidance BEFORE the general instructions will help the agent avoid known pitfalls earlier"
        :axis "A"
        :created "2026-05-02"
        :parent-strategies '("template-default")
        :description "Changes prompt architecture by moving critical guidance (failure patterns, axis guidance) to the beginning of the prompt, before standard sections."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "evolved-0001"
   #'strategy-section-reorder-build-prompt
   (strategy-section-reorder-get-metadata)))

(provide 'strategy-section-reorder)
;;; strategy-section-reorder.el ends here