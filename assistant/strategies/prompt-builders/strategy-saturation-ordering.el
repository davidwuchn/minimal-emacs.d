;;; strategy-saturation-ordering.el --- Saturation-based adaptive section ordering -*- lexical-binding: t; -*-
;; Hypothesis: Reordering prompt sections based on saturation analysis delivers higher-value content earlier.
;; Axis: C (Section ordering)

(require 'gptel-tools-agent-prompt-build)

(defvar saturation-ordering--section-baseline-values
  '((failure-analysis . high)
    (pattern-guidance . high)
    (cross-target . medium)
    (axis-guidance . medium)
    (compression . low))
  "Baseline value scores for each prompt section.")

(defvar saturation-ordering--size-thresholds
  '((small . 500) (medium . 2000) (large . 5000))
  "File size thresholds in tokens for adaptive ordering.")

(defvar saturation-ordering--entropy-threshold
  0.4
  "Minimum entropy to trigger section reordering.")

(defvar saturation-ordering--reorder-window
  3
  "Number of top sections to prioritize.")

(defun strategy-saturation-ordering-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using saturation-based section ordering.
Computes section value scores and reorders sections dynamically."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (file-size (or (plist-get analysis :file-size) 1000))
         (size-cat (strategy-saturation-ordering--classify-size file-size))
         (saturation-scores (strategy-saturation-ordering--compute-saturation baseline))
         (entropy (strategy-saturation-ordering--compute-entropy saturation-scores))
         (reordered-guidance (if (> entropy saturation-ordering--entropy-threshold)
                                  (strategy-saturation-ordering--generate-reordered
                                   saturation-scores size-cat analysis)
                                (strategy-saturation-ordering--generate-default analysis))))
    (concat base-prompt "\n\n" reordered-guidance)))

(defun strategy-saturation-ordering--classify-size (file-size)
  "Classify FILE-SIZE into category."
  (cond
   ((< file-size 500) 'small)
   ((< file-size 2000) 'medium)
   (t 'large)))

(defun strategy-saturation-ordering--compute-saturation (baseline)
  "Compute saturation scores from BASELINE string."
  (let ((str (if (stringp baseline) baseline ""))
        (scores '()))
    (push (cons 'failure-analysis (min 1.0 (* 0.1 (length (string-match-all "failure" str))))) scores)
    (push (cons 'pattern-guidance (min 1.0 (* 0.1 (length (string-match-all "pattern" str))))) scores)
    (push (cons 'cross-target (min 1.0 (* 0.1 (length (string-match-all "cross" str))))) scores)
    (push (cons 'axis-guidance (min 1.0 (* 0.1 (length (string-match-all "axis" str))))) scores)
    (push (cons 'compression (min 1.0 (* 0.1 (length (string-match-all "compress" str))))) scores)
    scores))

(defun string-match-all (regexp string)
  "Return list of all matches of REGEXP in STRING."
  (let ((matches nil)
        (start 0))
    (while (string-match regexp string start)
      (push (match-string 0 string) matches)
      (setq start (match-end 0)))
    matches))

(defun strategy-saturation-ordering--compute-entropy (saturation-scores)
  "Compute entropy of SATURATION-SCORES for reordering decision."
  (let ((values (mapcar #'cdr saturation-scores))
        (total (apply #'+ (mapcar #'cdr saturation-scores))))
    (if (= total 0) 0.5
      (- 1.0 (/ (abs (- (apply #'max values) (apply #'min values))) (max 1.0 total))))))

(defun strategy-saturation-ordering--get-priority-order (size-cat)
  "Get section priority order for SIZE-CAT."
  (pcase size-cat
    ('small '(failure-analysis cross-target axis-guidance compression pattern-guidance))
    ('medium '(failure-analysis pattern-guidance compression cross-target axis-guidance))
    ('large '(pattern-guidance compression axis-guidance cross-target failure-analysis))
    (_ '(failure-analysis pattern-guidance cross-target axis-guidance compression))))

(defun strategy-saturation-ordering--generate-reordered (saturation-scores size-cat analysis)
  "Generate reordered guidance based on SATURATION-SCORES and SIZE-CAT."
  (let ((priority-order (strategy-saturation-ordering--get-priority-order size-cat))
        (sections nil)
        (patterns (or (plist-get analysis :patterns) '())))
    (push "## Prioritized Guidance (Saturation-Optimized Order)\n" sections)
    (push "Sections ordered by relevance to maximize early delivery of high-value content:\n" sections)
    (dolist (section priority-order)
      (let* ((score (or (cdr (assq section saturation-scores)) 0.5))
             (value-label (or (cdr (assq section saturation-ordering--section-baseline-values)) 'medium))
             (detail (pcase section
                       ('failure-analysis "Lead with failure analysis when baseline is unsaturated")
                       ('pattern-guidance "Pattern-specific guidance for targeted fixes")
                       ('cross-target "Cross-target insights for holistic improvements")
                       ('axis-guidance "Axis-based reasoning for systematic changes")
                       ('compression "Compression strategies for resource-constrained contexts")))
             (sat-str (cond
                       ((< score 0.3) "(undersaturated - expand)")
                       ((> score 0.7) "(saturated - concise)")
                       (t "(balanced)"))))
        (push (format "- **%s**: %s %s" section detail sat-str) sections)))
    (string-join (nreverse sections) "\n")))

(defun strategy-saturation-ordering--generate-default (analysis)
  "Generate default guidance when no reordering needed."
  (let ((patterns (or (plist-get analysis :patterns) '())))
    (format "## Section Ordering Guidance\nPrioritize sections by: failure-analysis > pattern-guidance > cross-target > axis-guidance > compression.\nFocus areas: %s"
            (if patterns (string-join (cl-subseq patterns 0 (min 3 (length patterns))) ", ") "general improvements"))))

(defun strategy-saturation-ordering-get-metadata ()
  (list :name "saturation-ordering"
        :version "1.0"
        :hypothesis "Reordering prompt sections based on saturation analysis delivers higher-value content earlier."
        :axis "C"
        :components ["saturation-computation" "entropy-analysis" "adaptive-ordering"]))

(provide 'strategy-saturation-ordering)