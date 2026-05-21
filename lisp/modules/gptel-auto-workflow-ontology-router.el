;;; gptel-auto-workflow-ontology-router.el --- Ontology-aware backend fallback reordering -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, backend, routing, fallback, reordering

;;; Commentary:

;; Enhance existing headless fallback chain with ontology-aware reordering.
;; Uses `gptel-auto-workflow-headless-subagent-fallbacks' as source of truth,
;; reorders based on historical performance per task type.
;;
;; No new backends are added - only the ORDER is optimized.
;; Falls back to static order when insufficient data.

;;; Code:

(require 'gptel-auto-workflow-evolution)

(defcustom gptel-auto-workflow--ontology-reorder-min-samples 3
  "Minimum experiments before reordering fallback chain.
Below this, use the static order from `gptel-auto-workflow-headless-subagent-fallbacks'."
  :type 'integer
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--ontology-reorder-exploration-rate 0.15
  "Probability of trying non-optimal backend for learning (15%).
Ensures all backends get samples for fair comparison."
  :type 'float
  :group 'gptel-auto-workflow)

;; ─── Performance Lookup ───

(defun gptel-auto-workflow--get-backend-performance-stats (backend &optional strategy target)
  "Get performance stats for BACKEND, optionally filtered by STRATEGY/TARGET.
Returns plist with :kept :total :keep-rate."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (kept 0)
        (total 0))
    (dolist (r results)
      (let ((r-backend (or (plist-get r :backend) "unknown"))
            (r-strategy (plist-get r :strategy))
            (r-target (plist-get r :target))
            (r-decision (plist-get r :decision)))
        (when (string= r-backend backend)
          (when (or (null strategy) (string= r-strategy strategy))
            (when (or (null target) (string= r-target target))
              (setq total (1+ total))
              (when (equal r-decision "kept")
                (setq kept (1+ kept))))))))
    (list :kept kept
          :total total
          :keep-rate (if (> total 0) (/ (float kept) total) nil))))

(defun gptel-auto-workflow--get-backend-keep-rate (backend &optional strategy target)
  "Get keep-rate for BACKEND from ontology, optionally filtered by STRATEGY/TARGET.
Returns float 0.0-1.0 or nil if no data."
  (plist-get (gptel-auto-workflow--get-backend-performance-stats backend strategy target) :keep-rate))

;; ─── Fallback Chain Reordering ───

(defun gptel-auto-workflow--reorder-fallbacks-by-ontology (&optional strategy target)
  "Reorder `gptel-auto-workflow-headless-subagent-fallbacks' using ontology data.
Returns new ordered list of (backend . model) cons cells.
STRATEGY and TARGET filter the performance data."
  (let* ((static-fallbacks (if (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
                               gptel-auto-workflow-headless-subagent-fallbacks
                             '(("MiniMax" . "minimax-m2.7-highspeed")
                               ("moonshot" . "kimi-k2.6")
                               ("DashScope" . "glm-5")
                               ("DeepSeek" . "deepseek-v4-flash")
                               ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
         (scored nil))
    
    ;; Score each backend from static list
    (dolist (entry static-fallbacks)
      (let* ((backend (car entry))
             (model (cdr entry))
             (stats (gptel-auto-workflow--get-backend-performance-stats backend strategy target))
             (keep-rate (plist-get stats :keep-rate))
             (total (plist-get stats :total))
             (score (if keep-rate
                        (+ (* keep-rate 100)  ; Weighted by keep-rate
                           (if (> total 0) 1 0))
                      -1)))  ; No data = low priority
        (push (list :backend backend :model model :score score :rate keep-rate :total total) scored)))
    
    ;; Sort by score descending
    (setq scored (sort scored (lambda (a b) (> (plist-get a :score) (plist-get b :score)))))
    
    ;; Check if we have enough data to trust the reordering
    ;; Count total experiments across all backends
    (let ((total-samples (cl-reduce #'+ scored
                                    :key (lambda (s) (or (plist-get s :total) 0))
                                    :initial-value 0)))
      (if (>= total-samples gptel-auto-workflow--ontology-reorder-min-samples)
          (progn
            (message "[onto-router] Reordered %d backends by performance (≥%d samples)"
                     (length scored) total-samples)
            ;; Exploration: 15% chance to swap first two for learning
            (when (and (> (length scored) 1)
                       (< (random 100) (* gptel-auto-workflow--ontology-reorder-exploration-rate 100)))
              (let ((tmp (car scored)))
                (setcar scored (cadr scored))
                (setcar (cdr scored) tmp))
              (message "[onto-router] EXPLORATION: swapped top 2 backends for learning"))
            ;; Return as (backend . model) cons cells
            (mapcar (lambda (s) (cons (plist-get s :backend) (plist-get s :model))) scored))
        ;; Not enough data - return static order
        (progn
          (message "[onto-router] Using static order (%d samples < %d threshold)"
                   total-samples gptel-auto-workflow--ontology-reorder-min-samples)
          static-fallbacks)))))

;; ─── Integration with Existing Fallback System ───

(defun gptel-auto-workflow--apply-ontology-fallback-order (&optional strategy target)
  "Apply ontology-reordered fallback chain to the active system.
Temporarily overrides `gptel-auto-workflow-executor-rate-limit-fallbacks'.
Call this before experiment runs."
  (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology strategy target)))
    (when (and reordered (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks))
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks reordered)
      (message "[onto-router] Applied ontology-ordered fallback chain: %s"
               (mapconcat (lambda (e) (format "%s/%s" (car e) (cdr e))) reordered " → ")))))

;; ─── Reset to Static Order ───

(defun gptel-auto-workflow--reset-fallback-order ()
  "Reset fallback chain to static order from headless config."
  (when (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
    (setq gptel-auto-workflow-executor-rate-limit-fallbacks
          gptel-auto-workflow-headless-subagent-fallbacks)
    (message "[onto-router] Reset to static fallback order")))

;; ─── Advice Integration ───

(defun gptel-auto-workflow--ontology-fallback-advice (orig-fun &rest args)
  "Advice around experiment runner to apply ontology fallback ordering.
Reorders fallback chain before each experiment based on historical performance."
  (let* ((target (car args))
         (strategy (if (> (length args) 4) (nth 4 args) nil)))
    ;; Apply ontology-ordered fallbacks
    (gptel-auto-workflow--apply-ontology-fallback-order strategy target)
    ;; Run the experiment
    (unwind-protect
        (apply orig-fun args)
      ;; Reset to static order after experiment
      (gptel-auto-workflow--reset-fallback-order))))

;; ;; Uncomment to enable ontology-aware fallback reordering
;; (advice-add 'gptel-auto-experiment-run
;;             :around #'gptel-auto-workflow--ontology-fallback-advice)

(provide 'gptel-auto-workflow-ontology-router)
;;; gptel-auto-workflow-ontology-router.el ends here
