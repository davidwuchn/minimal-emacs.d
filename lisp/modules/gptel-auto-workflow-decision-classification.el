;;; gptel-auto-workflow-decision-classification.el --- Risk-based approval system -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: decision, classification, risk, approval

;;; Commentary:

;; Phase 4 Task 4.1: Decision Classification
;; Implements risk-based approval for experiments:
;; - Low risk: auto-approve
;; - Medium risk: recommend with human confirmation
;; - High risk: require human review

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; Configuration
;; ============================================================================

(defvar gptel-auto-workflow--risk-thresholds
  '(:low-max 0.3 :medium-max 0.7)
  "Risk score thresholds for classification.
:low-max - maximum risk score for low-risk classification
:medium-max - maximum risk score for medium-risk classification
Scores above :medium-max are classified as high-risk.")

(defvar gptel-auto-workflow--risk-weights
  '(:scope 0.25 :complexity 0.30 :coverage 0.20 :business-impact 0.25)
  "Weights for calculating overall risk score.
Must sum to 1.0.")

(defvar gptel-auto-workflow--approval-history nil
  "History of approval decisions.")

(defvar gptel-auto-workflow--risk-patterns nil
  "Learned risk patterns from approval history.")

;; ============================================================================
;; Risk Classification
;; ============================================================================

(defun gptel-auto-workflow--classify-experiment-risk (experiment)
  "Classify the risk level of EXPERIMENT.
Returns :low-risk, :medium-risk, or :high-risk."
  (let* ((factors (gptel-auto-workflow--calculate-risk-factors experiment))
         (risk-score (gptel-auto-workflow--calculate-risk-score factors)))
    (gptel-auto-workflow--classify-by-score `(:calculated-risk ,risk-score))))

(defun gptel-auto-workflow--calculate-risk-factors (experiment)
  "Calculate individual risk factors for EXPERIMENT.
Returns plist with :scope-factor, :complexity-factor,
:coverage-factor, :business-impact-factor."
  (let* ((files-changed (or (plist-get experiment :files-changed) 0))
         (lines-changed (or (plist-get experiment :lines-changed) 0))
         (test-coverage (or (plist-get experiment :test-coverage) 0.5))
         (business-value (or (plist-get experiment :business-value-score) 0.5))
         ;; Scope factor: more files = higher risk
         (scope-factor (min 1.0 (/ files-changed 10.0)))
         ;; Complexity factor: more lines = higher risk
         (complexity-factor (min 1.0 (/ lines-changed 200.0)))
         ;; Coverage factor: lower coverage = higher risk (inverted)
         (coverage-factor (- 1.0 test-coverage))
         ;; Business impact factor: higher business value = higher risk
         (business-impact-factor business-value))
    (list :scope-factor scope-factor
          :complexity-factor complexity-factor
          :coverage-factor coverage-factor
          :business-impact-factor business-impact-factor)))

(defun gptel-auto-workflow--calculate-risk-score (factors)
  "Calculate overall risk score from FACTORS.
Returns float between 0.0 and 1.0."
  (let* ((weights gptel-auto-workflow--risk-weights)
         (scope-weight (plist-get weights :scope))
         (complexity-weight (plist-get weights :complexity))
         (coverage-weight (plist-get weights :coverage))
         (business-weight (plist-get weights :business-impact))
         (scope-factor (plist-get factors :scope-factor))
         (complexity-factor (plist-get factors :complexity-factor))
         (coverage-factor (plist-get factors :coverage-factor))
         (business-factor (plist-get factors :business-impact-factor)))
    (+ (* scope-weight scope-factor)
       (* complexity-weight complexity-factor)
       (* coverage-weight coverage-factor)
       (* business-weight business-factor))))

(defun gptel-auto-workflow--classify-by-score (experiment)
  "Classify EXPERIMENT by its calculated risk score.
Uses thresholds from `gptel-auto-workflow--risk-thresholds'."
  (let* ((risk-score (or (plist-get experiment :calculated-risk) 0.5))
         (thresholds gptel-auto-workflow--risk-thresholds)
         (low-max (plist-get thresholds :low-max))
         (medium-max (plist-get thresholds :medium-max)))
    (cond
     ((<= risk-score low-max) :low-risk)
     ((<= risk-score medium-max) :medium-risk)
     (t :high-risk))))

;; ============================================================================
;; Approval Decisions
;; ============================================================================

(defun gptel-auto-workflow--make-approval-decision (experiment)
  "Make approval decision for EXPERIMENT.
Returns plist with :approval-type, :reason, :requires-human-input, etc."
  (let* ((risk-level (plist-get experiment :risk-level))
         (override-rule (plist-get experiment :override-rule))
         (experiment-id (plist-get experiment :id)))
    ;; Check for missing essential data
    (when (and (null risk-level)
               (gptel-auto-workflow--has-insufficient-data-p experiment))
      (setq risk-level :high-risk))
    ;; Calculate risk level if not provided
    (when (null risk-level)
      (setq risk-level (gptel-auto-workflow--classify-experiment-risk experiment)))
    (cond
     ;; Override rules take precedence
     ((eq override-rule :always-review)
      (list :experiment-id experiment-id
            :approval-type :require-review
            :reason "Override rule: always review"
            :requires-human-input t
            :high-priority t
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
     ;; Low risk: auto-approve
     ((eq risk-level :low-risk)
      (list :experiment-id experiment-id
            :approval-type :auto-approved
            :reason "Low risk experiment auto-approved"
            :requires-human-input nil
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
     ;; Medium risk: recommend with confirmation
     ((eq risk-level :medium-risk)
      (list :experiment-id experiment-id
            :approval-type :recommend-confirm
            :reason "Medium risk experiment requires human confirmation"
            :requires-human-input t
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
     ;; High risk: require review
     ((eq risk-level :high-risk)
      (list :experiment-id experiment-id
            :approval-type :require-review
            :reason "High risk experiment requires human review"
            :requires-human-input t
            :high-priority t
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
     ;; Fallback: require review for safety
     (t
      (list :experiment-id experiment-id
            :approval-type :require-review
            :reason "Unknown risk level, requires review"
            :requires-human-input t
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))))

(defun gptel-auto-workflow--has-insufficient-data-p (experiment)
  "Check if EXPERIMENT has insufficient data for risk classification.
Returns t if essential risk factors are missing."
  (let ((files-changed (plist-get experiment :files-changed))
        (lines-changed (plist-get experiment :lines-changed))
        (_test-coverage (plist-get experiment :test-coverage)))
    ;; Require at least files-changed or lines-changed to make a decision
    (and (null files-changed)
         (null lines-changed))))

;; ============================================================================
;; Approval History
;; ============================================================================

(defun gptel-auto-workflow--clear-approval-history ()
  "Clear approval history."
  (setq gptel-auto-workflow--approval-history nil))

(defun gptel-auto-workflow--track-approval-decision (decision)
  "Track approval DECISION in history."
  (push decision gptel-auto-workflow--approval-history))

(defun gptel-auto-workflow--get-approval-history ()
  "Get full approval history."
  gptel-auto-workflow--approval-history)

(defun gptel-auto-workflow--query-approval-history (&rest filters)
  "Query approval history with FILTERS.
Supported filters: :approval-type, :experiment-id, :timestamp-range."
  (let ((approval-type (plist-get filters :approval-type))
        (experiment-id (plist-get filters :experiment-id))
        (results nil))
    (dolist (decision gptel-auto-workflow--approval-history)
      (when (and (or (null approval-type)
                     (eq approval-type (plist-get decision :approval-type)))
                 (or (null experiment-id)
                     (string= experiment-id (plist-get decision :experiment-id))))
        (push decision results)))
    (nreverse results)))

(defun gptel-auto-workflow--calculate-approval-statistics ()
  "Calculate statistics from approval history.
Returns plist with :auto-approval-rate, :recommend-rate,
:review-rate, :total-count."
  (let* ((history gptel-auto-workflow--approval-history)
         (total (length history))
         (auto-count (cl-count :auto-approved history
                               :key (lambda (d) (plist-get d :approval-type))))
         (recommend-count (cl-count :recommend-confirm history
                                    :key (lambda (d) (plist-get d :approval-type))))
         (review-count (cl-count :require-review history
                                 :key (lambda (d) (plist-get d :approval-type)))))
    (if (> total 0)
        (list :auto-approval-rate (/ (float auto-count) total)
              :recommend-rate (/ (float recommend-count) total)
              :review-rate (/ (float review-count) total)
              :total-count total)
      (list :auto-approval-rate 0.0
            :recommend-rate 0.0
            :review-rate 0.0
            :total-count 0))))

;; ============================================================================
;; Risk Pattern Learning
;; ============================================================================

(defun gptel-auto-workflow--clear-risk-patterns ()
  "Clear learned risk patterns."
  (setq gptel-auto-workflow--risk-patterns nil))

(defun gptel-auto-workflow--learn-risk-patterns ()
  "Learn risk patterns from approval history.
Analyzes history to identify common patterns and their risk levels."
  (let* ((history gptel-auto-workflow--approval-history)
         (patterns (make-hash-table :test 'equal)))
    ;; Group experiments by target pattern
    (dolist (decision history)
      (let* ((risk-factors (plist-get decision :risk-factors))
             (target (plist-get decision :target))
             (approval-type (plist-get decision :approval-type))
             (key (gptel-auto-workflow--extract-pattern-key target risk-factors)))
        (when key
          (let ((existing (gethash key patterns)))
            (if existing
                (puthash key (gptel-auto-workflow--update-pattern existing approval-type) patterns)
              (puthash key (gptel-auto-workflow--create-pattern key approval-type risk-factors) patterns))))))
    ;; Convert hash table to list and store
    (setq gptel-auto-workflow--risk-patterns
          (let ((result nil))
            (maphash (lambda (_key pattern)
                       (push pattern result))
                     patterns)
            (nreverse result)))))

(defun gptel-auto-workflow--extract-pattern-key (target _risk-factors)
  "Extract pattern key from TARGET and RISK-FACTORS.
Returns string key or nil if no pattern can be extracted."
  (when target
    (let ((parts (split-string target "/")))
      (when (>= (length parts) 2)
        (format "%s/%s" (nth 0 parts) (nth 1 parts))))))

(defun gptel-auto-workflow--create-pattern (key approval-type risk-factors)
  "Create new pattern with KEY, APPROVAL-TYPE, and RISK-FACTORS."
  (list :pattern-name key
        :approval-type approval-type
        :risk-factors risk-factors
        :count 1
        :confidence 0.5
        :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))

(defun gptel-auto-workflow--update-pattern (pattern approval-type)
  "Update PATTERN with new APPROVAL-TYPE.
Increments count and updates confidence."
  (let* ((count (1+ (plist-get pattern :count)))
         (old-type (plist-get pattern :approval-type))
         (new-confidence (if (eq old-type approval-type)
                             (min 1.0 (+ (plist-get pattern :confidence) 0.1))
                           (max 0.0 (- (plist-get pattern :confidence) 0.1)))))
    (plist-put pattern :count count)
    (plist-put pattern :confidence new-confidence)
    (plist-put pattern :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))

(defun gptel-auto-workflow--get-risk-patterns ()
  "Get all learned risk patterns."
  gptel-auto-workflow--risk-patterns)

(defun gptel-auto-workflow--add-risk-pattern (pattern)
  "Add PATTERN to learned risk patterns."
  (push pattern gptel-auto-workflow--risk-patterns))

(defun gptel-auto-workflow--get-risk-pattern (pattern-name)
  "Get risk pattern by PATTERN-NAME."
  (cl-find pattern-name gptel-auto-workflow--risk-patterns
           :key (lambda (p) (plist-get p :pattern-name))
           :test #'string=))

(defun gptel-auto-workflow--update-pattern-confidence (pattern-name outcome)
  "Update confidence of PATTERN-NAME based on OUTCOME.
OUTCOME is :success or :failure."
  (let ((pattern (gptel-auto-workflow--get-risk-pattern pattern-name)))
    (when pattern
      (let* ((current-confidence (or (plist-get pattern :confidence) 0.5))
             (new-confidence (if (eq outcome :success)
                                 (min 1.0 (+ current-confidence 0.1))
                               (max 0.0 (- current-confidence 0.1)))))
        (plist-put pattern :confidence new-confidence)))))

(defun gptel-auto-workflow--apply-risk-patterns (experiment)
  "Apply learned risk patterns to EXPERIMENT.
Returns suggestion plist with :suggested-risk and :pattern-name."
  (let ((best-match nil)
        (best-confidence 0.0))
    (dolist (pattern gptel-auto-workflow--risk-patterns)
      (when (gptel-auto-workflow--matches-pattern-p experiment pattern)
        (let ((confidence (plist-get pattern :confidence)))
          (when (> confidence best-confidence)
            (setq best-confidence confidence)
            (setq best-match pattern)))))
    (when best-match
      (list :suggested-risk (plist-get best-match :suggested-risk)
            :pattern-name (plist-get best-match :pattern-name)
            :confidence best-confidence))))

(defun gptel-auto-workflow--matches-pattern-p (experiment pattern)
  "Check if EXPERIMENT matches PATTERN conditions."
  (let ((conditions (plist-get pattern :conditions)))
    (when conditions
      (and (or (null (plist-get conditions :max-files))
               (<= (or (plist-get experiment :files-changed) 0)
                   (plist-get conditions :max-files)))
           (or (null (plist-get conditions :max-lines))
               (<= (or (plist-get experiment :lines-changed) 0)
                   (plist-get conditions :max-lines)))
           (or (null (plist-get conditions :min-coverage))
               (>= (or (plist-get experiment :test-coverage) 0.0)
                   (plist-get conditions :min-coverage)))))))

;; ============================================================================
;; Integration Functions
;; ============================================================================

(defun gptel-auto-workflow--full-approval-workflow (experiment)
  "Run full approval workflow for EXPERIMENT.
Returns result plist with all decision information."
  (let* ((risk-level (gptel-auto-workflow--classify-experiment-risk experiment))
         (risk-factors (gptel-auto-workflow--calculate-risk-factors experiment))
         (experiment-with-risk (append experiment
                                       (list :risk-level risk-level
                                             :risk-factors risk-factors)))
         (approval-decision (gptel-auto-workflow--make-approval-decision experiment-with-risk)))
    ;; Track decision in history
    (gptel-auto-workflow--track-approval-decision
     (append approval-decision
             (list :risk-factors risk-factors
                   :target (plist-get experiment :target))))
    ;; Return full result
    (list :experiment-id (plist-get experiment :id)
          :target (plist-get experiment :target)
          :risk-level risk-level
          :risk-factors risk-factors
          :approval-decision approval-decision)))

(defun gptel-auto-workflow--batch-approval (experiments)
  "Process batch approval for multiple EXPERIMENTS.
Returns list of approval decisions."
  (mapcar (lambda (experiment)
            (gptel-auto-workflow--make-approval-decision experiment))
          experiments))

(provide 'gptel-auto-workflow-decision-classification)

;;; gptel-auto-workflow-decision-classification.el ends here
