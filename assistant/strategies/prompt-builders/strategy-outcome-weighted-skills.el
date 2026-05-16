;;; strategy-outcome-weighted-skills.el --- Historical outcome-based skill selection -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills based on historical success patterns for similar improvement types produces better results than static skill loading.
;; Axis: E

(require 'gptel-tools-agent-prompt-build)
(require 'seq)

(defun strategy-outcome-weighted-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using outcome-weighted skill selection.
Analyzes previous outcomes to prioritize skills with highest historical success."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (skill-weights (strategy-ows--compute-skill-weights previous-results analysis))
         (relevant-skills (strategy-ows--select-skills-by-weight skill-weights target)))
    (concat base-prompt "\n\n;; Outcome-Weighted Skill Guidance\n" relevant-skills)))

(defun strategy-ows--compute-skill-weights (previous-results analysis)
  "Compute skill weights from PREVIOUS-RESULTS and ANALYSIS.
Returns alist of (skill-name . weight) pairs."
  (let* ((outcome-patterns (strategy-ows--extract-outcome-patterns previous-results))
         (base-skills '("refactoring" "performance" "readability" "safety" "clarity"))
         (skill-scores (mapcar
                        (lambda (skill)
                          (cons skill (strategy-ows--calculate-skill-score skill outcome-patterns analysis)))
                        base-skills)))
    (sort skill-scores (lambda (a b) (> (cdr a) (cdr b))))))

(defun strategy-ows--extract-outcome-patterns (results)
  "Extract improvement patterns from RESULTS."
  (when results
    (let (patterns)
      (dolist (result results)
        (when (and (listp result)
                   (plist-get result :improvement-type))
          (push (plist-get result :improvement-type) patterns)))
      patterns)))

(defun strategy-ows--calculate-skill-score (skill patterns analysis)
  "Calculate relevance score for SKILL based on PATTERNS and ANALYSIS.
Higher score = more relevant for current context."
  (let ((base-score 50)
        (pattern-boost 0)
        (recommendation-boost 0))
    ;; Boost based on matching patterns
    (when (member skill patterns)
      (setq pattern-boost 30))
    ;; Boost based on analysis recommendations
    (when (and (listp analysis)
               (seq-some
                (lambda (rec) (string-match skill (format "%s" rec)))
                (plist-get analysis :recommendations)))
      (setq recommendation-boost 20))
    (+ base-score pattern-boost recommendation-boost)))

(defun strategy-ows--select-skills-by-weight (weights target)
  "Select top skills from WEIGHTS relevant to TARGET."
  (let* ((top-skills (seq-take weights 3))
         (skill-details (mapconcat
                         (lambda (skill-weight)
                           (let ((skill-name (car skill-weight))
                                 (weight (cdr skill-weight)))
                             (format ";; %s (relevance: %d%%)"
                                     skill-name weight)))
                         top-skills
                         "\n")))
    (concat
     ";; Top relevant skills based on historical outcomes:\n"
     skill-details
     "\n\n"
     ";; Guidance: Prioritize techniques from highest-ranked skills when available.")))

(defun strategy-outcome-weighted-skills-get-metadata ()
  (list :name "outcome-weighted-skills"
        :version "1.0"
        :hypothesis "Loading skills based on historical success patterns for similar improvement types yields better results than static skill-to-filetype mapping"
        :axis "E"
        :components ["outcome-extraction" "skill-weighting" "adaptive-selection"]))

(provide 'strategy-outcome-weighted-skills)