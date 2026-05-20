;;; strategy-outcome-reasoning-chain.el --- Build reasoning chains from historical outcomes -*- lexical-binding: t; -*-
;; Hypothesis: Constructing explicit causal chains from historical outcomes enables better decision-making.
;; Axis: D (Variable computation)

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-outcome-reasoning-chain--extract-outcome-patterns (previous-results)
  "Extract patterns from PREVIOUS-RESULTS for reasoning chain construction."
  (let ((patterns '()))
    (dolist (result previous-results)
      (let ((intervention (or (plist-get result :intervention) "unknown"))
            (outcome (plist-get result :outcome))
            (reasoning (or (plist-get result :reasoning) "")))
        (push (list :intervention intervention
                    :outcome outcome
                    :reasoning reasoning)
              patterns)))
    (nreverse patterns)))

(defun strategy-outcome-reasoning-chain--identify-outcome-clusters (patterns)
  "Group outcomes into clusters based on similarity."
  (let ((positive '())
        (negative '())
        (neutral '()))
    (dolist (p patterns)
      (let ((outcome (plist-get p :outcome)))
        (cond ((and (numberp outcome) (> outcome 0))
               (push p positive))
              ((and (numberp outcome) (< outcome 0))
               (push p negative))
              (t (push p neutral)))))
    (list :positive positive :negative negative :neutral neutral)))

(defun strategy-outcome-reasoning-chain--build-reasoning-chain (clusters)
  "Build an explicit reasoning chain from outcome CLUSTERS."
  (let ((chain '())
        (positives (plist-get clusters :positive))
        (negatives (plist-get clusters :negative)))
    (when positives
      (let ((avg-outcome (/ (cl-loop for p in positives sum (or (plist-get p :outcome) 0)) (float (length positives)))))
        (push (format "SUCCESS PATTERN: When interventions like '%s' were applied, average outcome was %.2f"
                      (plist-get (car positives) :intervention)
                      avg-outcome)
              chain)))
    (when negatives
      (let ((avg-outcome (/ (cl-loop for p in negatives sum (or (plist-get p :outcome) 0)) (float (length negatives)))))
        (push (format "FAILURE PATTERN: Interventions like '%s' yielded average outcome %.2f"
                      (plist-get (car negatives) :intervention)
                      avg-outcome)
              chain)))
    (push "REASONING CHAIN: From these patterns, we infer that" chain)
    (when (and positives (not negatives))
      (push "continuing with similar interventions is likely to succeed" chain))
    (when (and negatives (not positives))
      (push "a different approach should be considered" chain))
    (when (and positives negatives)
      (push "the intervention selection is critical and context-dependent" chain))
    (when (and (not positives) (not negatives))
      (push "insufficient data for strong inference" chain))
    (mapconcat #'identity (nreverse chain) "\n")))

(defun strategy-outcome-reasoning-chain-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with an explicit outcome reasoning chain."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (strategy-outcome-reasoning-chain--extract-outcome-patterns previous-results))
         (clusters (strategy-outcome-reasoning-chain--identify-outcome-clusters patterns))
         (reasoning-chain (strategy-outcome-reasoning-chain--build-reasoning-chain clusters)))
    (concat base-prompt "\n\n;; Outcome Reasoning Chain\n" reasoning-chain)))

(defun strategy-outcome-reasoning-chain-get-metadata ()
  (list :name "outcome-reasoning-chain"
        :version "1.0"
        :hypothesis "Constructing explicit causal chains from historical outcomes enables better decision-making"
        :axis "D"
        :components ["outcome-clustering" "reasoning-chain" "causal-inference"]))

(provide 'strategy-outcome-reasoning-chain)