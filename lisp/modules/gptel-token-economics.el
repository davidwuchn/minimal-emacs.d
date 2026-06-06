;;; gptel-token-economics.el --- Token economics tracking and budget optimization -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Project

;; Author: OV5 AI System
;; Keywords: economics, tokens, optimization

;;; Commentary:

;; Phase 3 of YC Vision: Token Economics
;; Tracks ROI per token spent and optimizes budget allocation by category.
;; Implements "burn tokens on high-ROI categories" strategy.

;;; Code:

(require 'cl-lib)
(require 'json)

(defvar gptel-token-economics--records nil
  "List of experiment records with token usage.")

(defvar gptel-token-economics--pricing
  '(:input-price 0.00003 :output-price 0.00006)
  "Token pricing configuration.")

;; ============================================================================
;; Task 3.1: Token Cost Tracking
;; ============================================================================

(defun gptel-token-economics--calculate-cost (input-tokens output-tokens pricing)
  "Calculate cost from INPUT-TOKENS and OUTPUT-TOKENS using PRICING."
  (let ((input-price (plist-get pricing :input-price))
        (output-price (plist-get pricing :output-price)))
    (+ (* input-tokens input-price)
       (* output-tokens output-price))))

(defun gptel-token-economics--track-experiment (experiment)
  "Track EXPERIMENT with token usage.
Returns t if successful."
  (let* ((category (or (plist-get experiment :category) :unknown))
         (input-tokens (or (plist-get experiment :input-tokens) 0))
         (output-tokens (or (plist-get experiment :output-tokens) 0))
         (cost (gptel-token-economics--calculate-cost
                input-tokens output-tokens
                gptel-token-economics--pricing)))
    (push (append experiment
                  (list :cost cost
                        :category category))
          gptel-token-economics--records)
    t))

(defun gptel-token-economics--get-records ()
  "Get all tracked experiment records."
  gptel-token-economics--records)

;; ============================================================================
;; Task 3.2: ROI Calculation
;; ============================================================================

(defun gptel-token-economics--calculate-roi (experiment)
  "Calculate ROI for EXPERIMENT.
ROI = value gained / cost.
Value gained = score improvement (score-after - score-before).
Returns 0.0 for discarded experiments or zero cost.
Correlates cost with business rationale from context database when available."
  (let ((decision (plist-get experiment :decision))
        (score-before (plist-get experiment :score-before))
        (score-after (plist-get experiment :score-after))
        (cost (or (plist-get experiment :cost)
                  (gptel-token-economics--calculate-cost
                   (or (plist-get experiment :input-tokens) 0)
                   (or (plist-get experiment :output-tokens) 0)
                   gptel-token-economics--pricing)))
        ;; Get business context from context database (Phase 3)
        (business-context (when (fboundp 'gptel-auto-workflow--get-context)
                           (gptel-auto-workflow--get-context
                            (plist-get experiment :experiment-id)))))
    (cond
     ;; Discarded experiments have zero ROI
     ((equal decision "discarded") 0.0)
     ;; Avoid division by zero
     ((<= cost 0.0) 0.0)
     ;; Calculate ROI with business context correlation
     (t
      (let* ((value-gained (- score-after score-before))
             (base-roi (if (<= value-gained 0.0)
                           0.0
                         (/ value-gained cost)))
             ;; Boost ROI if business rationale is strong
             (business-boost (if (and business-context
                                     (plist-get business-context :decision-rationale))
                                 1.2  ; 20% boost for experiments with strong rationale
                               1.0)))
        (* base-roi business-boost))))))

(defun gptel-token-economics--category-roi (category)
  "Calculate average ROI for CATEGORY."
  (let ((category-records (cl-remove-if-not
                           (lambda (r) (equal (plist-get r :category) category))
                           gptel-token-economics--records)))
    (if (null category-records)
        0.0
      (let ((total-roi (apply #'+ (mapcar #'gptel-token-economics--calculate-roi
                                          category-records))))
        (/ total-roi (length category-records))))))

(defun gptel-token-economics--rank-categories-by-roi ()
  "Rank all categories by ROI (highest first).
Returns list of (category . roi) pairs."
  (let ((categories (delete-dups
                     (mapcar (lambda (r) (plist-get r :category))
                             gptel-token-economics--records))))
    (sort (mapcar (lambda (cat)
                    (cons cat (gptel-token-economics--category-roi cat)))
                  categories)
          (lambda (a b) (> (cdr a) (cdr b))))))

;; ============================================================================
;; Task 3.3: Budget Allocation
;; ============================================================================

(defun gptel-token-economics--allocate-budget (category-rois total-budget &optional min-budget)
  "Allocate TOTAL-BUDGET across categories based on CATEGORY-ROIS.
CATEGORY-ROIS is an alist of (category . roi).
MIN-BUDGET is optional minimum budget per category (default 0).
Returns plist of (:category budget) pairs."
  (let* ((min-budget (or min-budget 0.0))
         (num-categories (length category-rois))
         (min-total (* min-budget num-categories))
         (remaining-budget (- total-budget min-total))
         (total-roi (apply #'+ (mapcar #'cdr category-rois)))
         (allocation nil))
    ;; Allocate minimum budget to all categories
    (dolist (pair category-rois)
      (let ((category (car pair)))
        (push (cons category min-budget) allocation)))
    ;; Allocate remaining budget proportionally to ROI
    (when (> total-roi 0.0)
      (dolist (pair category-rois)
        (let* ((category (car pair))
               (roi (cdr pair))
               (proportion (/ roi total-roi))
               (additional (* remaining-budget proportion))
               (current (cdr (assoc category allocation))))
          (setf (cdr (assoc category allocation))
                (+ current additional)))))
    ;; Convert to plist
    (let ((plist nil))
      (dolist (pair allocation)
        (push (car pair) plist)
        (push (cdr pair) plist))
      (nreverse plist))))

(defun gptel-token-economics--optimize-allocation (total-budget &optional min-budget)
  "Optimize budget allocation based on historical ROI.
TOTAL-BUDGET is the total amount to allocate.
MIN-BUDGET is optional minimum per category.
Returns plist of optimal allocation."
  (let ((category-rois (gptel-token-economics--rank-categories-by-roi)))
    (gptel-token-economics--allocate-budget category-rois total-budget min-budget)))

;; ============================================================================
;; Integration Functions
;; ============================================================================

(defun gptel-token-economics--cost-per-kept-experiment (category)
  "Calculate average cost per kept experiment for CATEGORY."
  (let* ((kept-records (cl-remove-if-not
                        (lambda (r)
                          (and (equal (plist-get r :category) category)
                               (equal (plist-get r :decision) "kept")))
                        gptel-token-economics--records))
         (num-kept (length kept-records)))
    (if (= num-kept 0)
        0.0
      (let ((total-cost (apply #'+ (mapcar (lambda (r)
                                             (or (plist-get r :cost) 0.0))
                                           kept-records))))
        (/ total-cost num-kept)))))

(defun gptel-token-economics--generate-report ()
  "Generate comprehensive economics report.
Returns plist with :total-cost, :total-roi, :category-breakdown,
:optimization-recommendations."
  (let* ((records gptel-token-economics--records)
         (total-cost (apply #'+ (mapcar (lambda (r) (or (plist-get r :cost) 0.0))
                                        records)))
         (total-roi (if (> (length records) 0)
                        (/ (apply #'+ (mapcar #'gptel-token-economics--calculate-roi
                                              records))
                           (length records))
                      0.0))
         (category-ranking (gptel-token-economics--rank-categories-by-roi))
         (category-breakdown
          (mapcar (lambda (pair)
                    (let* ((cat (car pair))
                           (roi (cdr pair))
                           (cost-per-kept (gptel-token-economics--cost-per-kept-experiment cat)))
                      (list :category cat
                            :roi roi
                            :cost-per-kept cost-per-kept)))
                  category-ranking))
         (recommendations
          (if (> (length category-ranking) 1)
              (list :increase-budget (car (car category-ranking))
                    :decrease-budget (car (car (last category-ranking))))
            nil)))
    (list :total-cost total-cost
          :total-roi total-roi
          :category-breakdown category-breakdown
          :optimization-recommendations recommendations)))

;; ============================================================================
;; Data Persistence
;; ============================================================================

(defun gptel-token-economics--persist-data (file)
  "Persist economics data to FILE."
  (with-temp-file file
    (insert (json-encode
             (mapcar (lambda (r)
                       (list :id (plist-get r :id)
                             :category (symbol-name (plist-get r :category))
                             :input-tokens (plist-get r :input-tokens)
                             :output-tokens (plist-get r :output-tokens)
                             :cost (plist-get r :cost)
                             :score-before (plist-get r :score-before)
                             :score-after (plist-get r :score-after)
                             :decision (plist-get r :decision)))
                     gptel-token-economics--records)))))

(defun gptel-token-economics--load-data (file)
  "Load economics data from FILE."
  (when (and (stringp file) (file-exists-p file))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file)
          (let ((raw (json-read-from-string (buffer-string))))
            (when (listp raw)
              (setq gptel-token-economics--records
                    (mapcar (lambda (r)
                              (list :id (plist-get r :id)
                                    :category (intern (plist-get r :category))
                                    :input-tokens (plist-get r :input-tokens)
                                    :output-tokens (plist-get r :output-tokens)
                                    :cost (plist-get r :cost)
                                    :score-before (plist-get r :score-before)
                                    :score-after (plist-get r :score-after)
                                    :decision (plist-get r :decision)))
                            raw)))))
      (error (message "gptel-token-economics: failed to load %s: %s" file err)))))

(provide 'gptel-token-economics)

;;; gptel-token-economics.el ends here
