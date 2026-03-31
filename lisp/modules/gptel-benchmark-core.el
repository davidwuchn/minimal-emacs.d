;;; gptel-benchmark-core.el --- Core utilities for benchmarking -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, utilities

;;; Commentary:

;; Core utilities shared between skill benchmark, workflow benchmark, and
;; continuous learning. Extracts common patterns for:
;; - Historical tracking (save, load, trend)
;; - Eight Keys integration (breakdown, summary)
;; - Feedback logging
;; - Cancel support
;; - Result analysis
;;
;; Usage:
;;   (require 'gptel-benchmark-core)
;;   (gptel-benchmark-save-historical "skill-name" results)
;;   (gptel-benchmark-load-history "skill-name")

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-benchmark-principles)

;;; Customization

(defgroup gptel-benchmark-core nil
  "Core utilities for benchmarking."
  :group 'gptel)

(defcustom gptel-benchmark-default-dir "./benchmarks/"
  "Default directory for benchmark results."
  :type 'directory
  :group 'gptel-benchmark-core)

;;; Cancel Support

(defvar gptel-benchmark--cancelled nil
  "Flag to cancel running benchmark.")

(defun gptel-benchmark-cancel ()
  "Cancel running benchmark."
  (interactive)
  (setq gptel-benchmark--cancelled t)
  (message "[benchmark] Cancellation requested..."))

(defun gptel-benchmark-reset-cancel ()
  "Reset cancel flag before starting new benchmark."
  (setq gptel-benchmark--cancelled nil))

(defmacro gptel-benchmark-with-cancel (&rest body)
  "Execute BODY with cancel support.
Use `gptel-benchmark--cancelled' to check if cancelled."
  (declare (indent 0))
  `(progn
     (gptel-benchmark-reset-cancel)
     ,@body))

;;; JSON I/O

(defun gptel-benchmark-read-json (file)
  "Read and parse JSON from FILE.
Returns nil if file does not exist or contains invalid JSON."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (json-read))
    (file-error nil)
    (json-error nil)
    (end-of-file nil)))

(defun gptel-benchmark-write-json (data file)
  "Write DATA as JSON to FILE with pretty printing.
DATA should be an alist or list of alists for proper JSON encoding.
Plists are converted to alists automatically."
  (let ((json-data (gptel-benchmark--to-json-format data)))
    (with-temp-file file
      (let ((json-encoding-pretty-print t))
        (insert (json-encode json-data))))))

(defun gptel-benchmark--to-json-format (data)
  "Convert DATA to JSON-serializable format.
Handles plists by converting to alists."
  (cond
   ((null data) nil)
   ((and (listp data) (keywordp (car data)) (not (consp (cadr data))))
    (gptel-benchmark--plist-to-alist data))
   ((listp data)
    (mapcar #'gptel-benchmark--to-json-format data))
   (t data)))

(defun gptel-benchmark--keyword-to-alist-key (key)
  "Convert KEY (keyword or symbol) to alist key symbol.
For keywords like :score, returns \\='score.
For non-keywords, returns KEY unchanged."
  (if (keywordp key)
      (intern (substring (symbol-name key) 1))
    key))

(defun gptel-benchmark--plist-to-alist (plist)
  "Convert PLIST to alist format for JSON encoding.
Validates that PLIST has even number of elements.
Returns nil for empty or malformed input."
  (when (and plist (zerop (mod (length plist) 2)))
    (let (alist)
      (while plist
        (let ((key (gptel-benchmark--keyword-to-alist-key (car plist)))
              (val (cadr plist)))
          (push (cons key (gptel-benchmark--to-json-format val)) alist)
          (setq plist (cddr plist))))
      (reverse alist))))

(defun gptel-benchmark--ensure-list (data)
  "Ensure DATA is a list, converting vectors if necessary.
JSON parsing returns vectors for arrays; this normalizes to lists."
  (if (vectorp data) (append data nil) data))

(defun gptel-benchmark--get-field (obj field)
  "Get FIELD from OBJ, handling both plist and alist formats.
FIELD should be a keyword like :score.
For alist lookup, converts :score to \\='score symbol."
  (or (plist-get obj field)
      (let ((alist-key (gptel-benchmark--keyword-to-alist-key field)))
        (cdr (assq alist-key obj)))))

(defun gptel-benchmark--plist-get (plist field &optional default)
  "Get FIELD from PLIST with optional DEFAULT value.
Returns DEFAULT if FIELD is not present or value is nil.
FIELD should be a keyword like :score."
  (let ((val (plist-get plist field)))
    (if val val default)))

;;; Historical Tracking

(defun gptel-benchmark-save-historical (name results &optional results-dir)
  "Save RESULTS to historical file for NAME in RESULTS-DIR.
Creates a history entry with timestamp and summary."
  (let* ((dir (or results-dir gptel-benchmark-default-dir))
         (history-file (expand-file-name (format "%s-history.json" name) dir))
         (existing (when (file-exists-p history-file)
                     (condition-case nil
                         (gptel-benchmark-read-json history-file)
                       (error nil))))
         (run-id (format-time-string "%Y%m%d-%H%M%S"))
         (summary (gptel-benchmark-summarize-results results))
         (entry (list :run-id run-id
                      :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
                      :summary summary)))
    (unless (file-exists-p dir)
      (make-directory dir t))
    (let ((history (gptel-benchmark--ensure-list existing)))
      (gptel-benchmark-write-json (cons entry history) history-file)
      entry)))

(defun gptel-benchmark-load-history (name &optional results-dir)
  "Load historical benchmark data for NAME from RESULTS-DIR."
  (let* ((dir (or results-dir gptel-benchmark-default-dir))
         (history-file (expand-file-name (format "%s-history.json" name) dir)))
    (when (file-exists-p history-file)
      (let ((data (gptel-benchmark-read-json history-file)))
        (gptel-benchmark--ensure-list data)))))

(defun gptel-benchmark-trend (name &optional results-dir)
  "Show trend of benchmark scores over time for NAME."
  (interactive
   (list (read-string "Name: ")))
  (let ((history (gptel-benchmark-load-history name results-dir)))
    (if (not history)
        (message "[benchmark] No historical data for %s" name)
      (with-output-to-temp-buffer (format "*Benchmark Trend: %s*" name)
        (princ (format "=== Benchmark Trend: %s ===\n\n" name))
        (princ "Timestamp                 Avg Score    Total Tests\n")
        (princ "--------------------------------------------------\n")
        (dolist (entry (reverse history))
          (let* ((summary (gptel-benchmark--plist-get entry :summary))
                 (timestamp (gptel-benchmark--plist-get entry :timestamp "unknown"))
                 (avg-score (gptel-benchmark--plist-get summary :avg-overall 0.0))
                 (total (gptel-benchmark--plist-get summary :total-tests 0)))
            (princ (format "%-25s %6.1f%%      %d\n"
                           timestamp
                           (* 100 (or avg-score 0))
                           total))))
        (princ "\n")))))

;;; Result Summarization

(defun gptel-benchmark--extract-scores (r)
  "Extract scores plist from result entry R.
Handles both (run . scores) cons cells and plists with :scores key."
  (cond
   ((and (consp r) (listp (cdr r))) (cdr r))
   ((listp r) (plist-get r :scores))
   (t nil)))

(defun gptel-benchmark--get-score (r field)
  "Extract FIELD from scores in result entry R.
Returns nil if R has no scores or FIELD is not present.
FIELD should be a keyword like :overall-score."
  (let ((scores (gptel-benchmark--extract-scores r)))
    (and scores (plist-get scores field))))

(defun gptel-benchmark--accumulate-score (total score)
  "Accumulate SCORE into TOTAL, treating nil as 0.
Returns the new accumulated total."
  (+ total (or score 0)))

(defun gptel-benchmark--accumulate-scores (totals scores-alist)
  "Accumulate multiple SCORES into TOTALS alist.
TOTALS is an alist of (score-type . accumulated-value).
SCORES-ALIST is an alist of (score-type . current-score).
Returns updated TOTALS alist with all scores accumulated.
Handles nil scores by treating them as 0."
  (dolist (pair totals totals)
    (let ((type (car pair))
          (value (cdr pair)))
      (setcdr pair (gptel-benchmark--accumulate-score
                    value
                    (alist-get type scores-alist))))))

(defun gptel-benchmark--extract-score-types (scores)
  "Extract all score types from SCORES as an alist.
Returns alist of (score-type . value) for all four score types.
Handles nil values gracefully."
  (when scores
    (list (cons :overall-score (plist-get scores :overall-score))
          (cons :efficiency-score (plist-get scores :efficiency-score))
          (cons :completion-score (plist-get scores :completion-score))
          (cons :constraint-score (plist-get scores :constraint-score)))))

(defun gptel-benchmark--calculate-average (score-totals score-type total)
  "Calculate average for SCORE-TYPE from SCORE-TOTALS given TOTAL count.
Returns 0.0 if TOTAL is zero to avoid division by zero."
  (if (> total 0)
      (/ (alist-get score-type score-totals) (float total))
    0.0))

(defun gptel-benchmark-summarize-results (results)
  "Create summary of RESULTS.
RESULTS is a list of (run . scores) cons cells or plists with :scores."
  (let ((total 0)
        (passed 0)
        (score-totals '((:overall-score . 0.0)
                        (:efficiency-score . 0.0)
                        (:completion-score . 0.0)
                        (:constraint-score . 0.0))))
    (dolist (r results)
      (let* ((scores (gptel-benchmark--extract-scores r))
             (overall (and scores (plist-get scores :overall-score)))
             (efficiency (and scores (plist-get scores :efficiency-score)))
             (completion (and scores (plist-get scores :completion-score)))
             (constraints (and scores (plist-get scores :constraint-score))))
        (cl-incf total)
        (when scores
          (setq score-totals
                (gptel-benchmark--accumulate-scores
                 score-totals
                 (gptel-benchmark--extract-score-types scores))))
        (when (>= (or overall 0) 0.7)
          (cl-incf passed))))
    (let ((reciprocal (if (> total 0) (/ 1.0 (float total)) 0.0)))
      (list :total-tests total
            :passed-tests passed
            :avg-overall (* (alist-get :overall-score score-totals) reciprocal)
            :avg-efficiency (* (alist-get :efficiency-score score-totals) reciprocal)
            :avg-completion (* (alist-get :completion-score score-totals) reciprocal)
            :avg-constraints (* (alist-get :constraint-score score-totals) reciprocal)))))

;;; Eight Keys Integration

(defun gptel-benchmark-eight-keys-breakdown (results)
  "Generate Eight Keys breakdown from RESULTS.
RESULTS should contain :eight-keys-scores in each entry."
  (let ((key-totals (make-vector 8 0.0))
        (key-counts (make-vector 8 0))
        (key-names [phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                                 pi-synthesis mu-directness exists-truth forall-vigilance]))
    (dolist (r results)
      (let ((eight-keys (gptel-benchmark--get-score r :eight-keys-scores)))
        (when eight-keys
          (dotimes (i 8)
            (let* ((key (aref key-names i))
                   (score (plist-get eight-keys key)))
              (when (numberp score)
                (aset key-totals i (+ (aref key-totals i) score))
                (aset key-counts i (1+ (aref key-counts i)))))))))
    (let ((breakdown '()))
      (dotimes (i 8)
        (let* ((key (aref key-names i))
               (total (aref key-totals i))
               (count (aref key-counts i))
               (avg (if (> count 0) (/ total count) 0.0)))
          (push (cons key avg) breakdown)))
      (reverse breakdown))))

(defun gptel-benchmark-show-eight-keys (name results)
  "Show Eight Keys breakdown for NAME with RESULTS."
  (let ((breakdown (gptel-benchmark-eight-keys-breakdown results)))
    (if (not (boundp 'gptel-benchmark-eight-keys-definitions))
        (message "[benchmark] Eight Keys definitions not loaded")
      (with-output-to-temp-buffer (format "*Eight Keys: %s*" name)
        (princ (format "=== Eight Keys Breakdown: %s ===\n\n" name))
        (dolist (key-def gptel-benchmark-eight-keys-definitions)
          (let* ((key (car key-def))
                 (symbol (plist-get key-def :symbol))
                 (name-str (plist-get key-def :name))
                 (score (alist-get key breakdown)))
            (princ (format "%s %s: %.1f%%\n" symbol name-str (* 100 (or score 0))))))
        (princ "\n")))))

;;; Feedback Logging

(defun gptel-benchmark-log (stage feedback &optional log-file)
  "Log FEEDBACK for STAGE to LOG-FILE."
  (let* ((default-log (expand-file-name "benchmark-feedback.log"
                                        gptel-benchmark-default-dir))
         (file (or log-file default-log))
         (dir (file-name-directory file)))
    (unless (file-exists-p dir)
      (make-directory dir t))
    (let ((log-entry (format "[%s] %s: %s\n"
                             (format-time-string "%Y-%m-%d %H:%M:%S")
                             stage
                             feedback)))
      (with-temp-buffer
        (insert log-entry)
        (write-region (point-min) (point-max) file t)))))

;;; Pattern Analysis

(defconst gptel-benchmark--score-type-map
  '((:completion-score . "completion")
    (:efficiency-score . "efficiency")
    (:constraint-score . "constraint")
    (:tool-score . "tool"))
  "Mapping from score type keywords to issue type strings.")

(defun gptel-benchmark-analyze-patterns (results)
  "Analyze RESULTS for patterns, issues, and generate recommendations."
  (let ((issues (make-hash-table :test 'equal))
        (recommendations '())
        (total (length results))
        (low-scores 0)
        (high-scores 0)
        (threshold 0.7))
    (dolist (r results)
      (let* ((scores (gptel-benchmark--extract-scores r))
             (overall (gptel-benchmark--plist-get scores :overall-score 0)))
        (cond
         ((< overall threshold) (cl-incf low-scores))
         ((>= overall 0.9) (cl-incf high-scores)))
        (when scores
          (dolist (mapping gptel-benchmark--score-type-map)
            (let* ((score-type (car mapping))
                   (issue-type (cdr mapping))
                   (score (plist-get scores score-type)))
              (when (and score (< score threshold))
                (puthash issue-type (1+ (gethash issue-type issues 0)) issues)))))))
    (when (> low-scores 0)
      (push (format "Review %d tests with low scores (< 70%%)" low-scores) recommendations))
    (when (= high-scores total)
      (push "All tests passing - consider increasing difficulty" recommendations))
    (let ((issues-alist '()))
      (maphash (lambda (issue-type count)
                 (push (cons issue-type count) issues-alist)
                 (push (format "Address %s issues in %d test(s)" issue-type count)
                       recommendations))
               issues)
      (list :issues issues-alist
            :recommendations (delete-dups recommendations)
            :total-tests total
            :low-scores low-scores
            :high-scores high-scores
            :analysis-timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")))))

;;; φ-Based Evolution (inspired by continuous-learning)

(defun gptel-benchmark-evolve-score (current-score outcome &optional delta)
  "Evolve CURRENT-SCORE based on OUTCOME.
OUTCOME is :validated or :corrected.
DELTA is the change amount (default 0.05).
Returns new score clamped to 0.0-1.0.
Signals error if CURRENT-SCORE is not a number or OUTCOME is invalid."
  (unless (numberp current-score)
    (error "gptel-benchmark-evolve-score: CURRENT-SCORE must be a number, got %S" current-score))
  (unless (memq outcome '(:validated :corrected))
    (error "gptel-benchmark-evolve-score: OUTCOME must be :validated or :corrected, got %S" outcome))
  (let ((d (or delta 0.05)))
    (let ((new-score
           (pcase outcome
             (:validated (+ current-score d))
             (:corrected (- current-score (/ d 2.0))))))
      (max 0.0 (min 1.0 new-score)))))

(defun gptel-benchmark-evolve-thresholds (history &key min-runs)
  "Analyze HISTORY and suggest evolved thresholds.
MIN-RUNS is minimum runs before suggesting changes (default 5).
Returns plist with suggested threshold adjustments."
  (let ((runs (or min-runs 5)))
    (if (< (length history) runs)
        (list :status :insufficient-data
              :message (format "Need %d runs, have %d" runs (length history)))
      (let* ((recent (cl-subseq history 0 (min runs (length history))))
             (raw-scores (mapcar (lambda (h)
                                   (gptel-benchmark--plist-get
                                    (gptel-benchmark--plist-get h :summary)
                                    :avg-overall))
                                 recent))
             (avg-scores (cl-remove-if-not #'numberp raw-scores))
             (count (length avg-scores)))
        (if (zerop count)
            (list :status :insufficient-data
                  :message "No valid scores found in history")
          (let* ((avg (apply #'+ avg-scores))
                 (overall-avg (/ avg count)))
            (cond
             ((> overall-avg 0.9)
              (list :status :increase-difficulty
                    :suggestion "Consider tightening thresholds or adding harder tests"
                    :current-avg overall-avg))
             ((< overall-avg 0.6)
              (list :status :decrease-difficulty
                    :suggestion "Consider relaxing thresholds or simplifying tests"
                    :current-avg overall-avg))
             (t
              (list :status :stable
                    :message "Thresholds are well-calibrated"
                    :current-avg overall-avg)))))))))

;;; Temp File Helper

(defun gptel-benchmark--temp-dir ()
  "Return the temp directory in user-emacs-directory."
  (let ((dir (expand-file-name "tmp/" (or user-emacs-directory default-directory))))
    (unless (file-directory-p dir) (make-directory dir t))
    dir))

(defun gptel-benchmark-make-temp-file (prefix &optional dir-flag suffix)
  "Like `make-temp-file' but in project var/tmp/ directory.
PREFIX, DIR-FLAG, and SUFFIX are passed to `make-temp-file'."
  (let ((temporary-file-directory (gptel-benchmark--temp-dir)))
    (make-temp-file prefix dir-flag suffix)))

;;; Provide

(provide 'gptel-benchmark-core)

;;; gptel-benchmark-core.el ends here
