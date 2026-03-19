;;; gptel-skill-comparator.el --- A/B comparison for skill outputs -*- lexical-binding: t; -*-

;; Copyright (C) 2024

;; Author: David Wu
;; Keywords: ai, benchmark, comparison

;;; Commentary:

;; Perform blind A/B comparison between two skill outputs.

;;; Code:

(require 'json)
(require 'cl-lib)

(defconst gptel-skill-comparator-version "1.0.0"
  "Version of the comparator system.")

(defun gptel-skill-compare-outputs (output-a output-b criteria)
  "Compare OUTPUT-A and OUTPUT-B against CRITERIA.
Returns a comparison result with winner and reasoning."
  (let ((scores-a (gptel-skill-comparator-score output-a criteria))
        (scores-b (gptel-skill-comparator-score output-b criteria)))
    (let* ((total-a (apply #'+ (mapcar #'cdr scores-a)))
           (total-b (apply #'+ (mapcar #'cdr scores-b)))
           (winner (cond ((> total-a total-b) 'a)
                         ((< total-a total-b) 'b)
                         (t 'tie))))
      (list :winner winner
            :scores-a scores-a
            :scores-b scores-b
            :total-a total-a
            :total-b total-b
            :reasoning (gptel-skill-comparator-reasoning winner scores-a scores-b)))))

(defun gptel-skill-comparator-score (output criteria)
  "Score OUTPUT against CRITERIA list.
Returns list of (criterion . score) pairs."
  (mapcar (lambda (criterion)
            (let ((score (gptel-skill-comparator-evaluate output criterion)))
              (cons (plist-get criterion :name) score)))
          criteria))

(defun gptel-skill-comparator-evaluate (output criterion)
  "Evaluate OUTPUT against single CRITERION.
Returns a score 0-10."
  (let ((type (plist-get criterion :type)))
    (cond
     ((string= type "contains-all")
      (let ((required (plist-get criterion :items))
            (found 0))
        (dolist (item required)
          (when (string-match-p (regexp-quote item) output)
            (cl-incf found)))
        (* 10 (/ (float found) (length required)))))
     ((string= type "contains-any")
      (if (cl-some (lambda (item) (string-match-p (regexp-quote item) output))
                   (plist-get criterion :items))
          10 0))
     ((string= type "min-length")
      (let ((min-len (plist-get criterion :value)))
        (if (>= (length output) min-len) 10 0)))
     ((string= type "max-length")
      (let ((max-len (plist-get criterion :value)))
        (if (<= (length output) max-len) 10 0)))
     ((string= type "regex-match")
      (if (string-match-p (plist-get criterion :pattern) output) 10 0))
     ((string= type "json-valid")
      (condition-case nil
          (and (json-parse-string output) 10)
        (error 0)))
     (t
      (message "Unknown criterion type: %s" type)
      5))))

(defun gptel-skill-comparator-reasoning (winner scores-a scores-b)
  "Generate reasoning for WINNER based on SCORES-A and SCORES-B."
  (let ((diffs '()))
    (cl-loop for (criterion-a . score-a) in scores-a
             for (_criterion-b . score-b) in scores-b
             do (let ((diff (- score-a score-b)))
                  (when (not (= diff 0))
                    (push (format "%s: A=%.1f B=%.1f (%s)" 
                                  criterion-a score-a score-b
                                  (cond ((> diff 0) "A better")
                                        ((< diff 0) "B better")
                                        (t "equal")))
                          diffs))))
    (format "Winner: %s. Differences: %s"
            (symbol-name winner)
            (if diffs (string-join (reverse diffs) "; ") "none"))))

(defun gptel-skill-comparator-blind-compare (outputs-a outputs-b prompt)
  "Perform blind comparison of OUTPUTS-A and OUTPUTS-B for PROMPT.
Returns comparison without revealing which is which."
  (let ((label-a (if (= (random 2) 0) "X" "Y"))
        (label-b (if (= (random 2) 0) "Y" "X")))
    (list :comparison-type 'blind
          :prompt prompt
          :label-a label-a
          :label-b label-b
          :output-a (plist-get outputs-a :output)
          :output-b (plist-get outputs-b :output)
          :note "Labels randomized for blind comparison")))

(defun gptel-skill-comparator-batch-compare (results-a results-b criteria)
  "Compare batches RESULTS-A and RESULTS-B against CRITERIA.
Returns aggregated comparison statistics."
  (let ((comparisons '())
        (a-wins 0)
        (b-wins 0)
        (ties 0))
    (cl-loop for a in results-a
             for b in results-b
             do (let ((result (gptel-skill-compare-outputs 
                              (plist-get a :output)
                              (plist-get b :output)
                              criteria)))
                  (push result comparisons)
                  (pcase (plist-get result :winner)
                    ('a (cl-incf a-wins))
                    ('b (cl-incf b-wins))
                    ('tie (cl-incf ties)))))
    (list :total (length comparisons)
          :a-wins a-wins
          :b-wins b-wins
          :ties ties
          :a-win-rate (* 100.0 (/ (float a-wins) (length comparisons)))
          :comparisons (reverse comparisons))))

(provide 'gptel-skill-comparator)

;;; gptel-skill-comparator.el ends here