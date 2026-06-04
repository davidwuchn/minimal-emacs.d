;;; gptel-auto-workflow-ontology-predict.el --- Ontology-based experiment outcome prediction -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, prediction, experiment-filtering, token-saving

;;; Commentary:

;; Predict experiment outcomes before running to save LLM tokens.
;; Uses ontology data: strategy keep-rate, target value, historical pair performance.
;; Skips experiments with predicted success < threshold.

;;; Code:

(require 'gptel-auto-workflow-evolution)

(declare-function gptel-auto-experiment-run "gptel-tools-agent-experiment-core")

(defcustom gptel-auto-workflow--prediction-threshold 0.15
  "Minimum predicted success probability to run an experiment.
Experiments below this threshold are skipped to save LLM tokens."
  :type 'float
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--prediction-skip-message
  "[onto-predict] Skipping %s/%s: predicted %.2f < threshold %.2f (saved ~%d tokens)"
  "Message format when skipping experiment due to low prediction.
Args: strategy target predicted threshold tokens."
  :type 'string
  :group 'gptel-auto-workflow)

;; ─── Prediction Core ───

(defun gptel-auto-workflow--research-quality-for-target (target)
  "Compute research-quality signal for TARGET from AutoTTS trace outcomes.
Returns float 0.0-1.0 combining trace confidence, trace-success, and
pattern actionability.  Returns nil when no trace data exists for TARGET.
AutoTTS→Preflight: feeds research provenance into experiment gating."
  (let ((traces (and (fboundp 'gptel-auto-workflow--load-research-traces)
                     (condition-case nil
                         (gptel-auto-workflow--load-research-traces)
                       (error nil))))
        (qualities nil))
    (dolist (trace traces)
      (let ((outcomes (plist-get trace :outcomes)))
        (dolist (outcome outcomes)
          (when (string= (or (plist-get outcome :target) "") target)
            (let* ((confidence (or (plist-get trace :confidence) 0.5))
                   (trace-success (if (and (fboundp 'gptel-auto-workflow--trace-success-p)
                                            (gptel-auto-workflow--trace-success-p trace))
                                      1.0 0.3))
                   (actionability (min 1.0 (/ (or (plist-get outcome :pattern-actionability) 0) 5.0)))
                   (quality (* confidence trace-success (+ 0.5 (* 0.5 actionability)))))
              (push quality qualities))))))
    (when qualities
      (/ (apply #'+ qualities) (float (length qualities))))))

(defun gptel-auto-workflow--predict-outcome (strategy target)
  "Predict success probability for STRATEGY + TARGET combination.
Returns float 0.0-1.0 based on:
- Strategy keep-rate from ontology
- Target keep-rate from ontology
- Strategy+target pair history (3x weight)
- Recent trend (last 3 experiments)
- Research trace quality from AutoTTS (2x weight, when available)"
  (let* ((ontology (gptel-auto-workflow--generate-experiment-ontology))
         (strategy-rate 0.0)
         (target-rate 0.0)
         (pair-rate 0.0)
         (pair-total 0)
         (trend-rate 0.0)
         (trend-count 0)
         (research-quality (gptel-auto-workflow--research-quality-for-target target))
         (has-research (and research-quality (numberp research-quality))))
    
    ;; Strategy rate
    (dolist (cls (plist-get ontology :classes))
      (when (string= (plist-get cls :name) strategy)
        (setq strategy-rate (or (plist-get cls :keep-rate) 0.0))))
    
    ;; Target rate
    (dolist (inst (plist-get ontology :instances))
      (when (string= (plist-get inst :name) target)
        (setq target-rate (or (plist-get inst :keep-rate) 0.0))))
    
    ;; Pair history (3x weight)
    (let* ((results (gptel-auto-workflow--parse-all-results))
           (pair-kept 0)
           (pair-total-local 0))
      (dolist (r results)
        (when (and (string= (or (plist-get r :strategy) "") strategy)
                   (string= (or (plist-get r :target) "") target))
          (setq pair-total-local (1+ pair-total-local))
          (when (equal (plist-get r :decision) "kept")
            (setq pair-kept (1+ pair-kept)))))
      (when (> pair-total-local 0)
        (setq pair-rate (/ (float pair-kept) pair-total-local)
              pair-total pair-total-local)))
    
    ;; Recent trend (last 3 experiments for this strategy)
    (let* ((results (gptel-auto-workflow--parse-all-results))
           (recent nil)
           (kept 0)
           (total 0))
      (dolist (r results)
        (when (string= (or (plist-get r :strategy) "") strategy)
          (push r recent)))
      (setq recent (seq-take (sort recent
                                   (lambda (a b)
                                     (> (or (plist-get a :timestamp) 0)
                                        (or (plist-get b :timestamp) 0))))
                             3))
      (setq total (length recent))
      (dolist (r recent)
        (when (equal (plist-get r :decision) "kept")
          (setq kept (1+ kept))))
      (when (> total 0)
        (setq trend-rate (/ (float kept) total)
              trend-count total)))
    
    ;; Weighted combination
    ;; Pair history (3x) + strategy rate (2x) + target rate (1x) + trend (1x)
    ;; + research quality (2x, when available)
    (let* ((has-strategy-data (or (> pair-total 0) (> strategy-rate 0)))
           (has-target-data (or (> pair-total 0) (> target-rate 0)))
           (total-weight (+ (if (> pair-total 0) 3 0)
                            (if has-strategy-data 2 0)
                            (if has-target-data 1 0)
                            (if (> trend-count 0) 1 0)
                            (if has-research 2 0)))
           (weighted-sum (+ (* pair-rate (if (> pair-total 0) 3 0))
                            (* strategy-rate (if has-strategy-data 2 0))
                            (* target-rate (if has-target-data 1 0))
                            (* trend-rate (if (> trend-count 0) 1 0))
                            (* (or research-quality 0) (if has-research 2 0)))))
      (if (> total-weight 0)
          (/ weighted-sum total-weight)
        0.5))))  ; No data = 50/50

;; ─── Experiment Filtering ───

(defun gptel-auto-workflow--should-run-experiment-p (strategy target)
  "Return t if experiment for STRATEGY + TARGET should run.
Checks predicted outcome against threshold."
  (let ((predicted (gptel-auto-workflow--predict-outcome strategy target)))
    (if (>= predicted gptel-auto-workflow--prediction-threshold)
        (progn
          (message "[onto-predict] %s/%s: predicted %.2f ≥ threshold %.2f → RUN"
                   strategy target predicted
                   gptel-auto-workflow--prediction-threshold)
          t)
      (message gptel-auto-workflow--prediction-skip-message
               strategy target predicted
               gptel-auto-workflow--prediction-threshold
               15000)  ; ~15K tokens saved per skipped experiment
      nil)))

;; ─── Anti-Pattern Blocking ───

(defun gptel-auto-workflow--check-anti-pattern (strategy target)
  "Check if STRATEGY + TARGET pair has 3+ consecutive failures.
Returns t if should block (anti-pattern detected)."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (consecutive-failures 0))
    ;; Sort by timestamp descending
    (setq results (sort results
                         (lambda (a b)
                           (> (or (plist-get a :timestamp) 0)
                               (or (plist-get b :timestamp) 0)))))
    ;; Count consecutive failures
    (catch 'streak-broken
      (dolist (r results)
        (when (and (string= (or (plist-get r :strategy) "") strategy)
                   (string= (or (plist-get r :target) "") target))
          (if (or (equal (plist-get r :decision) "discarded")
                  (equal (plist-get r :decision) "failed"))
              (setq consecutive-failures (1+ consecutive-failures))
            ;; Success breaks the streak
            (throw 'streak-broken nil)))))
    (when (>= consecutive-failures 3)
      (message "[onto-anti] BLOCKED %s/%s: %d consecutive failures"
               strategy target consecutive-failures))
    (>= consecutive-failures 3)))

;; ─── Target Saturation ───

(defun gptel-auto-workflow--target-saturated-p (target &optional max-experiments)
  "Return t if TARGET has enough experiments (default 10).
Skips saturated targets to focus exploration on unknowns."
  (let* ((ontology (gptel-auto-workflow--generate-experiment-ontology))
         (max (or max-experiments 10))
         (count 0))
    (dolist (inst (plist-get ontology :instances))
      (when (string= (plist-get inst :name) target)
        (setq count (or (plist-get inst :total) 0))))
    (when (>= count max)
      (message "[onto-sat] %s saturated: %d experiments ≥ %d max"
               target count max))
    (>= count max)))

;; ─── Unified Pre-Flight Check ───

(defun gptel-auto-workflow--experiment-preflight (strategy target)
  "Run all ontology checks before experiment.
Returns (:run t :reason nil) or (:run nil :reason string)."
  (cond
   ;; Anti-pattern: 3+ consecutive failures
   ((gptel-auto-workflow--check-anti-pattern strategy target)
    (list :run nil
          :reason (format "anti-pattern: 3+ consecutive failures for %s/%s"
                          strategy target)))
   ;; Saturation: target has enough data
   ((gptel-auto-workflow--target-saturated-p target)
    (list :run nil
          :reason (format "saturated: %s has enough experiments" target)))
   ;; Prediction: too low probability
   ((not (gptel-auto-workflow--should-run-experiment-p strategy target))
    (let ((predicted (gptel-auto-workflow--predict-outcome strategy target)))
      (list :run nil
            :reason (format "predicted failure: %.2f < %.2f threshold"
                            predicted gptel-auto-workflow--prediction-threshold))))
   ;; All checks passed
   (t (list :run t :reason nil))))

;; ─── Advice to hook into experiment runner ───

(defun gptel-auto-workflow--experiment-preflight-advice (orig-fun &rest args)
  "Advice around experiment runner to check ontology before running.
ARGS: (target experiment-id max-experiments ...)."
  (let* ((target (car args))
         ;; Try to determine strategy (may not be known yet)
         (strategy (or (and (fboundp 'gptel-auto-workflow--select-best-strategy)
                            (gptel-auto-workflow--select-best-strategy target))
                       "template-default"))
         (preflight (gptel-auto-workflow--experiment-preflight strategy target)))
    (if (plist-get preflight :run)
        (apply orig-fun args)
      ;; Skip experiment, return synthetic failure result
      (let ((reason (plist-get preflight :reason)))
        (message "[onto-preflight] SKIPPED %s: %s" target reason)
        ;; Suggest alternative
        (when (fboundp 'gptel-auto-workflow--preflight-alternative)
          (let ((alt (gptel-auto-workflow--preflight-alternative target strategy)))
            (when (plist-get alt :reason)
              (message "[onto-preflight]   alt: %s" (plist-get alt :reason)))))
        (when (> (length args) 5)
          ;; Call callback with skip result
          (let ((callback (nth 5 args)))
            (when (functionp callback)
              (funcall callback
                       (list :target target
                             :decision "discarded"
                             :reason reason
                             :predicted (gptel-auto-workflow--predict-outcome strategy target)
                             :skipped t)))))
        nil))))

;; ─── Register preflight advice ───
(when (and (fboundp 'gptel-auto-experiment-run)
           (not (bound-and-true-p gptel-auto-workflow--ontology-advice-installed)))
  (advice-add 'gptel-auto-experiment-run :around
              #'gptel-auto-workflow--experiment-preflight-advice)
  (with-no-warnings
    (setq gptel-auto-workflow--ontology-advice-installed t)))

(provide 'gptel-auto-workflow-ontology-predict)
;;; gptel-auto-workflow-ontology-predict.el ends here
