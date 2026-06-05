;;; gptel-auto-workflow-ontology-strategy.el --- Ontology-aware strategy and target selection -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, strategy-selection, target-prioritization

;;; Commentary:

;; Use ontology data to improve strategy selection and target prioritization.
;; The ontology tracks strategy effectiveness and target value classification.
;; This module wires ontology knowledge into operational decisions.

;;; Code:

(require 'gptel-auto-workflow-evolution)

;; ─── Target Prioritization ───

(defun gptel-auto-workflow--ontology-target-value (target)
  "Return ontology classification for TARGET.
The value is high-value, moderate, low-value, or unknown.
Queries the live experiment ontology for target keep-rate."
  (let ((ontology (gptel-auto-workflow--generate-experiment-ontology)))
    (catch 'found
      (dolist (inst (plist-get ontology :instances))
        (when (string= (plist-get inst :name) target)
          (throw 'found (or (plist-get inst :classification) "unknown"))))
      "unknown")))

(defun gptel-auto-workflow--ontology-filter-targets (targets)
  "Filter TARGETS based on ontology classification.
Returns list with low-value targets moved to end.
Preserves all targets - just reorders by predicted value."
  (let ((scored nil))
    (dolist (tgt targets)
      (let ((value (gptel-auto-workflow--ontology-target-value tgt)))
        (push (cons tgt
                    (cond ((string= value "high-value") 3)
                          ((string= value "moderate") 2)
                          ((string= value "low-value") 0)
                          (t 1)))
              scored)))
    (mapcar #'car (sort scored (lambda (a b) (> (cdr a) (cdr b)))))))

;; ─── Strategy Selection Enhancement ───

(defun gptel-auto-workflow--ontology-strategy-status (strategy)
  "Return ontology status for STRATEGY.
The value is effective, promising, underperforming, or unknown."
  (let ((ontology (gptel-auto-workflow--generate-experiment-ontology)))
    (catch 'found
      (dolist (cls (plist-get ontology :classes))
        (when (string= (plist-get cls :name) strategy)
          (throw 'found (or (plist-get cls :status) "unknown"))))
      "unknown")))

(defun gptel-auto-workflow--ontology-strategy-score (strategy)
  "Return ontology keep-rate for STRATEGY, or 0.0 if unknown."
  (let ((ontology (gptel-auto-workflow--generate-experiment-ontology)))
    (catch 'found
      (dolist (cls (plist-get ontology :classes))
        (when (string= (plist-get cls :name) strategy)
          (throw 'found (or (plist-get cls :keep-rate) 0.0))))
      0.0)))

(defun gptel-auto-workflow--strategy-experiment-count (strategy)
  "Return total experiment count for STRATEGY from TSV history."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (count 0))
    (dolist (r results)
      (when (string= (or (plist-get r :strategy) "") strategy)
        (setq count (1+ count))))
    count))

(defun gptel-auto-workflow--strategy-recent-experiments (strategy &optional n)
  "Return the N most recent experiment plists for STRATEGY."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (matching nil))
    (dolist (r results)
      (when (string= (or (plist-get r :strategy) "") strategy)
        (push r matching)))
    (seq-take (sort matching
                    (lambda (a b)
                      (> (or (plist-get a :timestamp) 0)
                         (or (plist-get b :timestamp) 0))))
              (or n 5))))

(defun gptel-auto-workflow--category-eight-key-weight (category)
  "Return the primary Eight Key weight multiplier for CATEGORY.
Uses dynamically aggregated weights from experiment history when available,
otherwise falls back to hardcoded defaults based on category semantics:
  :programming → μ Directness (code must work, fewer tokens per kept)
  :agentic     → ∀ Vigilance (agent must avoid anti-patterns)
  :tool-calls  → φ Vitality (tools must show improving trend)
  :natural-language → fractal Clarity (output must be high quality)"
  (let* ((cat-weights (and (boundp 'gptel-auto-workflow--category-eight-key-weights)
                           (assoc category gptel-auto-workflow--category-eight-key-weights)))
         (defaults '((:programming (mu-directness . 1.3))
                     (:agentic (forall-vigilance . 1.3))
                     (:tool-calls (phi-vitality . 1.3))
                     (:natural-language (fractal-clarity . 1.3))
                     (t (epsilon-purpose . 1.0)))))
    (if cat-weights
        ;; Dynamic: find the key with the highest average delta for this category
        (let* ((key-deltas (cdr cat-weights))
               (sorted (sort (copy-sequence key-deltas)
                             (lambda (a b) (> (abs (cdr a)) (abs (cdr b))))))
               (best (car sorted))
               (delta (abs (or (cdr best) 0)))
               ;; Scale: avg delta of 0.10 → 1.5x, 0.05 → 1.25x, etc.
               (multiplier (max 0.8 (min 2.0 (+ 1.0 (* delta 5))))))
          (cons (car best) multiplier))
      ;; Fallback: hardcoded defaults
      (or (cdr (assoc category defaults))
          (cdr (assoc t defaults))))))

(defun gptel-auto-workflow--select-best-strategy-with-ontology (strategies target)
  "Select best strategy using ontology classification + Eight Key alignment.
Prefers strategies classified as `effective', then `promising'.
Adds category-specific Eight Key bonus for strategies that score well
on the dimension most relevant to the target's category.
Eight Keys→Strategy: category-aligned scoring for better targeting."
  (let* ((cat (if (fboundp 'gptel-auto-workflow--categorize-target)
                  (gptel-auto-workflow--categorize-target target)
                :natural-language))
         (ekey (gptel-auto-workflow--category-eight-key-weight cat))
         (best nil)
         (best-score -1.0))
    (dolist (s strategies)
      (let* ((status (gptel-auto-workflow--ontology-strategy-status s))
             (keep-rate (gptel-auto-workflow--ontology-strategy-score s))
             ;; Category-specific Eight Key bonus:
             ;; :programming → reward strategies with high keep-rate (μ Directness)
             ;; :agentic → reward strategies with data history (∀ Vigilance = proven)
             ;; :tool-calls → reward strategies with improving trend (φ Vitality)
             ;; :natural-language → reward strategies via raw keep-rate (fractal Clarity)
             (ekey-multiplier (cdr ekey))
             (ekey-bonus
              (pcase (car ekey)
                ('mu-directness (* keep-rate ekey-multiplier 0.3))
                ('forall-vigilance
                 ;; Prefer strategies with 3+ experiments (proven vigilance)
                 (let ((total (gptel-auto-workflow--strategy-experiment-count s)))
                   (* (min 1.0 (/ total 5.0)) ekey-multiplier 0.3)))
                ('phi-vitality
                 ;; Prefer strategies with recent activity (vitality)
                 (let* ((recent (gptel-auto-workflow--strategy-recent-experiments s 5))
                        (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) recent))
                        (trend (if (> (length recent) 0) (/ (float kept) (length recent)) 0.5)))
                   (* trend ekey-multiplier 0.3)))
                ('fractal-clarity (* keep-rate ekey-multiplier 0.3))
                (_ 0.0)))
             (score (cond ((string= status "effective") (+ keep-rate 1.0 ekey-bonus))
                          ((string= status "promising") (+ keep-rate 0.5 ekey-bonus))
                          ((string= status "underperforming") (- keep-rate 0.3 ekey-bonus))
                          (t (+ keep-rate ekey-bonus)))))
        (when (> score best-score)
          (setq best s best-score score))))
    (message "[onto-strategy] Selected %s for %s (cat=%s key=%s score=%.2f status=%s)"
             best target cat (car ekey) best-score
             (gptel-auto-workflow--ontology-strategy-status best))
    best))

(defun gptel-auto-workflow--ontology-backend-per-target (strategy target)
  "Return backend performance data for STRATEGY+TARGET combination.
Returns plist with :backend, :kept-count, :total-count, :rate,
or nil if no data."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (by-backend (make-hash-table :test 'equal)))
    ;; Aggregate kept/total per backend for this strategy+target
    (dolist (r results)
      (let* ((s (plist-get r :strategy))
             (tgt (plist-get r :target))
             (backend (or (plist-get r :backend) "unknown"))
             (decision (plist-get r :decision)))
        (when (and (string= s strategy)
                   (string= tgt target))
          (let* ((entry (gethash backend by-backend))
                 (kept (if (equal decision "kept") 1 0))
                 (total 1))
            (puthash backend
                     (list :kept (+ kept (or (plist-get entry :kept) 0))
                           :total (+ total (or (plist-get entry :total) 0)))
                     by-backend)))))
    ;; Find best backend
    (when (> (hash-table-count by-backend) 0)
      (let (best-backend best-entry best-rate)
        (maphash
         (lambda (b entry)
           (let ((rate (/ (float (plist-get entry :kept))
                          (max 1 (plist-get entry :total)))))
             (when (or (null best-rate) (> rate best-rate))
               (setq best-backend b best-entry entry best-rate rate))))
         by-backend)
        (when best-backend
          (list :backend best-backend
                :kept-count (plist-get best-entry :kept)
                :total-count (plist-get best-entry :total)
                :rate best-rate))))))


;; ─── Backend Recommendation ───

(defun gptel-auto-workflow--ontology-recommend-backend (strategy target)
  "Recommend backend based on ontology data for STRATEGY + TARGET combination.
Returns backend name or nil if no data."
  (ignore target)
  ;; TODO: Track backend performance per strategy-target in ontology
  ;; For now, use strategy-level backend performance
  (let ((results (gptel-auto-workflow--parse-all-results)))
    (catch 'found
      (let ((by-backend (make-hash-table :test 'equal)))
        (dolist (r results)
          (let ((s (plist-get r :strategy))
                (backend (or (plist-get r :backend) "unknown"))
                (decision (plist-get r :decision)))
            (when (and (string= s strategy)
                       (equal decision "kept"))
              (puthash backend (1+ (gethash backend by-backend 0)) by-backend))))
        ;; Return backend with most kept experiments for this strategy
        (let ((best-backend nil) (best-count 0))
          (maphash (lambda (b c)
                     (when (> c best-count)
                       (setq best-backend b best-count c)))
                   by-backend)
          (when best-backend
            (message "[onto-backend] Recommended %s for %s (%d kept)"
                     best-backend strategy best-count)
            (throw 'found best-backend))))
      nil)))

;; ─── Knowledge Gap Detection ───

(defun gptel-auto-workflow--ontology-check-knowledge-gaps ()
  "Detect knowledge gaps from ontology.
Returns list of strategies with no associated KnowledgePage.
Triggers skill evolution for knowledge-management when gaps found."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (strategies-with-knowledge nil)
        (all-strategies nil))
    ;; Collect all strategies and those with knowledge
    (dolist (r results)
      (let ((strategy (plist-get r :strategy))
            (knowledge (plist-get r :knowledge-hash)))
        (when strategy
          (cl-pushnew strategy all-strategies :test #'string=)
          (when (and knowledge (not (string= knowledge "none")))
            (cl-pushnew strategy strategies-with-knowledge :test #'string=)))))
    ;; Find gaps
    (let ((gaps (cl-set-difference all-strategies strategies-with-knowledge :test 'string=)))
      (when gaps
        (message "[onto-knowledge] %d strategy(s) lack knowledge pages: %s"
                 (length gaps) (string-join gaps ", ")))
      gaps)))

;; ─── Wire into existing functions ───

(defun gptel-auto-workflow--ontology-enhance-experiment-setup (target)
  "Enhance experiment setup for TARGET with ontology data.
Returns plist with :strategy, :backend recommendations."
  (let* ((ontology (gptel-auto-workflow--generate-experiment-ontology))
         (strategies (mapcar (lambda (c) (plist-get c :name))
                             (plist-get ontology :classes)))
         (recommended-strategy (when strategies
                                 (gptel-auto-workflow--select-best-strategy-with-ontology
                                  strategies target)))
         (recommended-backend (when recommended-strategy
                                (gptel-auto-workflow--ontology-recommend-backend
                                 recommended-strategy target))))
    `(:strategy ,recommended-strategy
      :backend ,recommended-backend
      :target-value ,(gptel-auto-workflow--ontology-target-value target))))

(provide 'gptel-auto-workflow-ontology-strategy)
;;; gptel-auto-workflow-ontology-strategy.el ends here
