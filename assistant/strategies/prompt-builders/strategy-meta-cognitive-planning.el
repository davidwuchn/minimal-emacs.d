;;; strategy-meta-cognitive-planning.el --- Meta-cognitive planning wrapper -*- lexical-binding: t; -*-
;; Hypothesis: Forcing a structured pre-analysis and planning phase before code generation reduces scope creep and improves surgical precision.
;; Axis: A

(require 'gptel-tools-agent-prompt-build)

(defun strategy-meta-cognitive-planning-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with meta-cognitive planning layer."
  (let ((base-prompt (gptel-auto-experiment-build-prompt
                      target experiment-id max-experiments analysis baseline previous-results)))
    (concat
     "META-COGNITIVE INSTRUCTION: Do not write or modify any code yet. First, complete a mandatory structured analysis of the target Emacs Lisp file in exactly this order:\n\n"
     "1. AUDIT: Identify the three most significant weaknesses (correctness, performance, or maintainability).\n"
     "2. PRIORITIZE: Rank these by impact versus effort. Select exactly ONE issue to address.\n"
     "3. PLAN: Describe the minimal surgical change to address the selected issue. Explicitly state boundaries: what you will NOT modify.\n"
     "4. EXECUTE: Only after completing steps 1-3, follow the instructions below to produce the improved code.\n\n"
     "--- BASELINE TASK INSTRUCTIONS ---\n"
     base-prompt
     "\n--- END BASELINE ---\n\n"
     "Your response MUST begin with the AUDIT, PRIORITIZE, and PLAN sections, followed by the code. "
     "If the file is already optimal, state that in the PLAN and return the original code verbatim.")))

(defun strategy-meta-cognitive-planning-get-metadata ()
  "Return metadata for this strategy."
  (list :name "meta-cognitive-planning"
        :version "1.0"
        :hypothesis "Forcing a structured pre-analysis and planning phase before code generation reduces scope creep and improves surgical precision."
        :axis "A"
        :components ["template-architecture" "meta-cognition" "planning"]))

(provide 'strategy-meta-cognitive-planning)