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

(defconst gptel-benchmark--score-types
  '(:overall-score :efficiency-score :completion-score :constraint-score)
  "Standard score types tracked across all benchmark runs.")

(defconst gptel-benchmark--score-type-averages
  '((:overall-score . :avg-overall)
    (:efficiency-score . :avg-efficiency)
    (:completion-score . :avg-completion)
    (:constraint-score . :avg-constraints))
  "Mapping from score types to their corresponding average keys in summary output.")

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
Returns nil if file does not exist or contains invalid JSON.
JSON arrays are normalized to lists for consistent handling."
  (condition-case nil
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (gptel-benchmark--ensure-list (json-read)))
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
   ((and (listp data)
         (consp data)
         (keywordp (car data))
         (proper-list-p data)
         (zerop (mod (length data) 2)))
    (gptel-benchmark--plist-to-alist data))
   ((and (consp data) (not (proper-list-p data)))
    (cons (car data) (gptel-benchmark--to-json-format (cdr data))))
   ((and (consp data)
         (cl-every (lambda (x)
                     (and (consp x)
                          (or (stringp (car x))
                              (and (symbolp (car x))
                                   (not (keywordp (car x)))))))
                   data))
    (mapcar (lambda (pair)
              (cons (car pair) (gptel-benchmark--to-json-format (cdr pair))))
            data))
   ((listp data)
    (mapcar #'gptel-benchmark--to-json-format data))
   ((vectorp data)
    (vconcat (mapcar #'gptel-benchmark--to-json-format data)))
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
FIELD should be a keyword like :score or a symbol like 'score.
For alist lookup, tries both keyword and symbol keys.
Returns nil if OBJ is not a valid plist or alist, or if FIELD is nil."
  (when (and (listp obj) field)
    (or (plist-get obj field)
        (cdr (assoc field obj))
        (let ((alist-key (gptel-benchmark--keyword-to-alist-key field)))
          (unless (eq alist-key field)
            (cdr (assoc alist-key obj))))
        (when (symbolp field)
          (let ((keyword-key (intern (concat ":" (symbol-name field)))))
            (or (plist-get obj keyword-key)
                (cdr (assoc keyword-key obj))))))))

(defun gptel-benchmark--plist-get (obj field &optional default)
  "Get FIELD from OBJ with optional DEFAULT value.
Returns DEFAULT if FIELD is not present or value is nil.
FIELD should be a keyword like :score.
Handles both plist and alist formats (for JSON round-trip compatibility)."
  (let ((val (gptel-benchmark--get-field obj field)))
    (if (null val) default val)))

;;; Historical Tracking

(defun gptel-benchmark--ensure-dir (dir)
  "Ensure DIR exists, creating it recursively if necessary.
Returns DIR for chaining convenience."
  (unless (file-directory-p dir)
    (make-directory dir t))
  dir)

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
    (gptel-benchmark--ensure-dir dir)
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
Handles both (run . scores) cons cells and plists with :scores key.
Returns nil for nil or malformed input."
  (cond
   ((null r) nil)
   ((and (listp r) (keywordp (car r)) (zerop (mod (length r) 2)))
    (let ((scores (plist-get r :scores)))
      (when (listp scores) scores)))
   ((consp r)
    (let ((scores (cdr r)))
      (when (listp scores) scores)))
   (t nil)))

(defun gptel-benchmark--get-score (r field &optional scores)
  "Extract FIELD from scores in result entry R.
Returns nil if R has no scores or FIELD is not present.
FIELD should be a keyword like :overall-score.
If SCORES is provided, uses it directly instead of re-extracting from R."
  (let ((scores (or scores (gptel-benchmark--extract-scores r))))
    (and scores (gptel-benchmark--get-field scores field))))

(defun gptel-benchmark--accumulate-score (total score)
  "Accumulate SCORE into TOTAL.
Returns the new accumulated total.
SCORE must be a number or nil; non-numeric values are treated as 0
with a warning logged for debugging."
  (if (numberp score)
      (+ total score)
    (when score
      (message "[benchmark] Non-numeric score %S treated as 0" score))
    total))

(defun gptel-benchmark--accumulate-scores (totals scores-alist)
  "Accumulate scores from SCORES-ALIST into TOTALS.
Returns a new alist with accumulated values.
TOTALS is an alist of (score-type . accumulated-value).
SCORES-ALIST is an alist of (score-type . current-score).
Handles nil or non-numeric scores by treating them as 0.
Returns TOTALS unchanged if SCORES-ALIST is nil."
  (if (null scores-alist)
      totals
    (cl-loop for (score-type . current) in totals
             for raw-score = (alist-get score-type scores-alist)
             for score = (if (numberp raw-score) raw-score 0.0)
             collect (cons score-type (+ current score)))))

(defun gptel-benchmark--extract-score-types (scores)
  "Extract standard score types from SCORES plist or alist.
Returns alist of (score-type . value) for the standard scores.
Handles nil values gracefully by returning 0.0 for missing scores.
Handles both plist format (keyword keys) and alist format (symbol or keyword keys).
Returns nil if SCORES is not a list."
  (when (listp scores)
    (mapcar (lambda (score-type)
              (cons score-type (or (gptel-benchmark--get-field scores score-type) 0.0)))
            gptel-benchmark--score-types)))

(defun gptel-benchmark--calculate-average (score-totals total score-type)
  "Calculate average for SCORE-TYPE from SCORE-TOTALS over TOTAL items.
Returns 0.0 if TOTAL is zero to avoid division by zero."
  (if (> total 0)
      (/ (alist-get score-type score-totals) (float total))
    0.0))

(defun gptel-benchmark-summarize-results (results)
  "Create summary of RESULTS.
RESULTS is a list of (run . scores) cons cells or plists with :scores.
Returns plist with :total-tests, :passed-tests, and average scores."
  (if (or gptel-benchmark--cancelled (null results))
      (append (list :total-tests 0 :passed-tests 0)
              (mapcan (lambda (m) (list (cdr m) 0.0))
                      gptel-benchmark--score-type-averages))
    (let ((total 0)
          (passed 0)
          (score-totals (mapcar (lambda (st) (cons st 0.0)) gptel-benchmark--score-types)))
      (dolist (r results)
        (let* ((scores (gptel-benchmark--extract-scores r))
               (overall-score (gptel-benchmark--get-score r :overall-score scores)))
          (cl-incf total)
          (when scores
            (setq score-totals
                  (gptel-benchmark--accumulate-scores
                   score-totals
                   (gptel-benchmark--extract-score-types scores))))
          (when (>= (or overall-score 0) 0.7)
            (cl-incf passed))))
      (append (list :total-tests total :passed-tests passed)
              (mapcan (lambda (m)
                        (list (cdr m)
                              (gptel-benchmark--calculate-average score-totals total (car m))))
                      gptel-benchmark--score-type-averages)))))

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
                   (score (gptel-benchmark--get-field eight-keys key)))
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
    (gptel-benchmark--ensure-dir dir)
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
      (let ((overall (gptel-benchmark--get-score r :overall-score)))
        (when overall
          (cond
           ((< overall threshold) (cl-incf low-scores))
           ((>= overall 0.9) (cl-incf high-scores)))
          (dolist (mapping gptel-benchmark--score-type-map)
            (let* ((score-type (car mapping))
                   (issue-type (cdr mapping))
                   (score (gptel-benchmark--get-score r score-type)))
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
  (gptel-benchmark--ensure-dir
   (expand-file-name "tmp/" (or user-emacs-directory default-directory))))

(defun gptel-benchmark-make-temp-file (prefix &optional dir-flag suffix)
  "Like `make-temp-file' but in project var/tmp/ directory.
PREFIX, DIR-FLAG, and SUFFIX are passed to `make-temp-file'."
  (let ((temporary-file-directory (gptel-benchmark--temp-dir)))
    (make-temp-file prefix dir-flag suffix)))

;;; Provide

(provide 'gptel-benchmark-core)

;;; gptel-benchmark-core.el ends here
