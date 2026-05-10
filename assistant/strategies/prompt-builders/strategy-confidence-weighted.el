;;; strategy-confidence-weighted.el --- Confidence-scored guidance strategy -*- lexical-binding: t; -*-
;; Hypothesis: Weighting guidance sections by confidence based on sample counts
;; will focus the agent's attention on more reliable patterns.
;;
;; NEW MECHANISM: This strategy computes confidence scores for each pattern based on
;; how many times it was observed. Patterns are then weighted and annotated with
;; confidence levels (HIGH/LOW) to guide the agent's attention appropriately.

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-confidence-weighted--compute-confidence (pattern-data)
  "Compute confidence score for PATTERN-DATA based on sample count.
Uses logarithmic scaling to avoid over-weighting highly repeated patterns.
Returns a score between 0.0 and 1.0."
  (let* ((count (or (plist-get pattern-data :count) 0))
         (baseline (max count 1))
         (confidence (min 1.0 (/ (log (+ 1 baseline)) 4.0))))
    confidence))

(defun strategy-confidence-weighted--score-pattern (pattern)
  "Score a PATTERN by combining confidence with impact and frequency."
  (let* ((confidence (strategy-confidence-weighted--compute-confidence pattern))
         (impact (or (plist-get pattern :impact-score) 0.5))
         (times (or (plist-get pattern :times-encountered) 1))
         (frequency-score (min 1.0 (/ times 10.0))))
    (+ (* confidence 0.4) (* impact 0.4) (* frequency-score 0.2))))

(defun strategy-confidence-weighted--classify-patterns (patterns)
  "Classify PATTERNS into high and low confidence groups.
Returnsplist with :high-confidence, :low-confidence, and :all-patterns."
  (when patterns
    (let* ((scored-patterns
            (mapcar (lambda (p)
                      (cons p (strategy-confidence-weighted--score-pattern p)))
                    patterns))
           (sorted (cl-sort scored-patterns #'> :key 'cdr))
           (high-confidence (cl-loop for (p . score) in sorted
                                     when (>= score 0.6)
                                     collect p))
           (low-confidence (cl-loop for (p . score) in sorted
                                    when (< score 0.4)
                                    collect p))
           (avg-score (if sorted
                          (/ (apply '+ (mapcar 'cdr sorted))
                             (float (length sorted)))
                        0.0)))
      (list :high-confidence high-confidence
            :low-confidence low-confidence
            :all-patterns patterns
            :average-score avg-score))))

(defun strategy-confidence-weighted--format-weighted-section (section-title patterns patterns-type)
  "Format a section with confidence-weighted patterns.
SECTION-TITLE is the header for this section.
PATTERNS-TYPE indicates what kind of patterns these are."
  (when patterns
    (let* ((classified (strategy-confidence-weighted--classify-patterns patterns))
           (high-conf (plist-get classified :high-confidence))
           (low-conf (plist-get classified :low-confidence))
           (avg-score (plist-get classified :average-score))
           lines)
      ;; High confidence patterns first
      (when high-conf
        (push (format "### %s (HIGH CONFIDENCE - avg score: %.2f)\n" section-title avg-score)
              lines)
        (dolist (p high-conf)
          (push (format "- %s [HIGH CONFIDENCE]"
                        (or (plist-get p :description)
                            (plist-get p :pattern)
                            (format "Pattern: %s" p)))
                lines)))
      ;; Low confidence patterns with caution
      (when low-conf
        (push (format "\n### %s (LOW CONFIDENCE - verify independently)\n" section-title)
              lines)
        (dolist (p low-conf)
          (push (format "- %s [LOW CONFIDENCE - explore but verify]"
                        (or (plist-get p :description)
                            (plist-get p :pattern)
                            (format "Pattern: %s" p)))
                lines)))
      (mapconcat 'identity (nreverse lines) "\n"))))

(defun strategy-confidence-weighted-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using confidence-weighted guidance.
This strategy annotates guidance patterns with confidence scores."
  ;; Get baseline prompt
(let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         ;; Format failure patterns with confidence scoring
         (failure-patterns (gptel-auto-experiment--format-failure-patterns target))
         ;; Build confidence-weighted guidance section
         (weighted-guidance
          (when failure-patterns
            (strategy-confidence-weighted--format-weighted-section
             "Failure Patterns (Confidence-Scored)"
             (if (listp failure-patterns) failure-patterns nil)
             :failure-patterns))))
    ;; Inject weighted guidance into the prompt
    (if (and weighted-guidance (not (string-empty-p weighted-guidance)))
        (concat base-prompt "\n\n" weighted-guidance)
      base-prompt)))

(defun strategy-confidence-weighted-get-metadata ()
  "Return metadata for this strategy."
  (list :name "confidence-weighted"
        :version "1.0"
        :hypothesis "Weighting guidance by confidence based on sample counts focuses attention on reliable patterns"
        :axis "A"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies '("template-default")
        :components '("confidence-scoring" "pattern-classification" "weighted-guidance" "high-low-tiering")
        :description "Scores each guidance pattern by confidence (based on sample count) and annotates guidance with HIGH/LOW confidence tiers."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "confidence-weighted"
   #'strategy-confidence-weighted-build-prompt
   (strategy-confidence-weighted-get-metadata)))

(provide 'strategy-confidence-weighted)
;;; strategy-confidence-weighted.el ends here
