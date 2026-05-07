;;; strategy-adaptive-framing.el --- Adaptive persona/task framing strategy -*- lexical-binding: t; -*-
;; Hypothesis: Changing the agent's framing based on experiment progression stage
;; (exploration vs exploitation) will improve early diversity and late-stage optimization.
;;
;; NEW MECHANISM: This strategy dynamically selects the agent's persona and task framing
;; based on how far along the experiment sequence is. Early experiments get exploration framing,
;; middle experiments get balanced framing, and late experiments get optimization framing.

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-adaptive-framing--stage-thresholds
  '((early . 0.2)
    (middle . 0.5)
    (late . 0.8)))

(defun strategy-adaptive-framing--determine-stage (experiment-id max-experiments)
  "Determine the current experiment stage based on progress.
Returns one of: early, middle, late, exhausted."
  (let ((progress (/ (float (max 1 experiment-id)) (max 1 max-experiments))))
    (cond
     ((<= progress 0.2) 'early)
     ((<= progress 0.5) 'middle)
     ((<= progress 0.8) 'late)
     (t 'exhausted))))

(defun strategy-adaptive-framing--get-persona (stage)
  "Get the agent persona for STAGE."
  (pcase stage
    ('early
     "You are an EXPLORER seeking diverse solutions. Try unconventional approaches, explore the problem space broadly, and do not fear failure. Each failed experiment teaches us something valuable about what NOT to do.")
    ('middle
     "You are an ANALYST balancing exploration and exploitation. Focus on the most promising directions while maintaining some diversity. Combine insights from earlier experiments to build better hypotheses.")
    ('late
     "You are an OPTIMIZER maximizing final performance. Focus on the most effective approaches found so far, fine-tune the best solutions, and eliminate remaining issues. Every attempt counts now.")
    ('exhausted
     "You are a FINALIZER. This is the final attempt - use everything you have learned and pick your single best approach. Execute it flawlessly.")
    (_
     "You are an ANALYST balancing exploration and exploitation.")))

(defun strategy-adaptive-framing--get-task-directive (stage)
  "Get task directive for STAGE."
  (pcase stage
    ('early
     "DIRECTIVE: Generate diverse hypotheses and approaches. Do not cluster around the first solution. Think creatively about what might work - even unconventional ideas have value here.")
    ('middle
     "DIRECTIVE: Build on successful patterns while exploring alternatives. Balance refinement with innovation. Use what worked before, but don't be afraid to try variations.")
    ('late
     "DIRECTIVE: Optimize the best solutions. Focus on eliminating remaining issues. Leave no obvious improvement on the table. This is time to be thorough and precise.")
    ('exhausted
     "DIRECTIVE: FINAL SUBMISSION. Execute your single best hypothesis with precision. No more experiments after this - make this one count.")
    (_
     "DIRECTIVE: Generate and test hypotheses systematically.")))

(defun strategy-adaptive-framing--get-stage-note (stage)
  "Get explanatory note for STAGE."
  (pcase stage
    ('early
     "NOTE: Early experiments are primarily for learning. Failures are expected and valuable - they narrow the search space.")
    ('middle
     "NOTE: Mid-stage experimentation should focus while staying open to new insights. Build on early learnings.")
    ('late
     "NOTE: Late-stage experiments should be targeted and efficient. Focus on the most promising approaches found so far.")
    ('exhausted
     "NOTE: This is the final submission. No more experiments will follow.")
    (_
     "NOTE: Systematic experimentation improves outcomes.")))

(defun strategy-adaptive-framing--build-framing-block (experiment-id max-experiments)
  "Build the adaptive framing block to inject into the prompt."
  (let* ((stage (strategy-adaptive-framing--determine-stage experiment-id max-experiments))
         (persona (strategy-adaptive-framing--get-persona stage))
         (task (strategy-adaptive-framing--get-task-directive stage))
         (note (strategy-adaptive-framing--get-stage-note stage)))
    (format "## ADAPTIVE FRAMING (Experiment %d of %d - Stage: %s)\n\n%s\n\n%s\n\n%s\n"
            experiment-id max-experiments
            (symbol-name stage)
            persona
            task
            note)))

(defun strategy-adaptive-framing-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using adaptive framing based on experiment stage.
This strategy changes the agent's persona and task framing dynamically."
  ;; Get baseline prompt
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         ;; Build adaptive framing block
         (framing-block (strategy-adaptive-framing--build-framing-block experiment-id max-experiments)))
    ;; Inject framing block at the beginning of the prompt
    (concat framing-block "\n" base-prompt)))

(defun strategy-adaptive-framing-get-metadata ()
  "Return metadata for this strategy."
  (list :name "adaptive-framing"
        :version "1.0"
        :hypothesis "Dynamically changing agent framing based on experiment progression improves early exploration and late optimization"
        :axis "A"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies '("template-default")
        :components '("stage-detection" "persona-switching" "task-directive" "progression-guidance")
        :description "Adapts agent persona and task framing based on experiment progression: EXPLORER in early stage, ANALYST in middle, OPTIMIZER in late, FINALIZER when exhausted."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "adaptive-framing"
   #'strategy-adaptive-framing-build-prompt
   (strategy-adaptive-framing-get-metadata)))

(provide 'strategy-adaptive-framing)
;;; strategy-adaptive-framing.el ends here
