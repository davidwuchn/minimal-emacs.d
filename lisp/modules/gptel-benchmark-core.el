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

(defun gptel-benchmark--plist-to-alist (plist)
  "Convert PLIST to alist format for JSON encoding."
  (let (alist)
    (while plist
      (let ((key (car plist))
            (val (cadr plist)))
        (when (keywordp key)
          (setq key (intern (substring (symbol-name key) 1))))
        (push (cons key (gptel-benchmark--to-json-format val)) alist)
        (setq plist (cddr plist))))
    (nreverse alist)))

(defun gptel-benchmark--get-field (obj field)
  "Get FIELD from OBJ, handling both plist and alist formats.
FIELD should be a keyword like :score."
  (or (plist-get obj field)
      (cdr (assq (intern (substring (symbol-name field) 1)) obj))))

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
    (let ((history (if (vectorp existing) (append existing nil) existing)))
      (gptel-benchmark-write-json (cons entry history) history-file)
      entry)))

(defun gptel-benchmark-load-history (name &optional results-dir)
  "Load historical benchmark data for NAME from RESULTS-DIR."
  (let* ((dir (or results-dir gptel-benchmark-default-dir))
         (history-file (expand-file-name (format "%s-history.json" name) dir)))
    (when (file-exists-p history-file)
      (let ((data (gptel-benchmark-read-json history-file)))
        (if (vectorp data) (append data nil) data)))))

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
        (dolist (entry (nreverse history))
          (let* ((summary (plist-get entry :summary))
                 (timestamp (or (plist-get entry :timestamp) "unknown"))
                 (avg-score (plist-get summary :avg-overall))
                 (total (or (plist-get summary :total-tests) 0)))
            (princ (format "%-25s %6.1f%%      %d\n"
                           timestamp
                           (* 100 (or avg-score 0))
                           total))))
        (princ "\n")))))

;;; Result Summarization

(defun gptel-benchmark-summarize-results (results)
  "Create summary of RESULTS.
RESULTS is a list of (run . scores) cons cells or plists with :scores."
  (let ((total 0)
        (avg-overall 0.0)
        (avg-efficiency 0.0)
        (avg-completion 0.0)
        (avg-constraints 0.0)
        (passed 0))
    (dolist (r results)
      (let* ((scores (cond
                      ((and (consp r) (listp (cdr r))) (cdr r))
                      ((listp r) (plist-get r :scores))
                      (t nil)))
             (overall (and scores (plist-get scores :overall-score)))
             (efficiency (and scores (plist-get scores :efficiency-score)))
             (completion (and scores (plist-get scores :completion-score)))
             (constraints (and scores (plist-get scores :constraint-score))))
        (when scores
          (cl-incf total)
          (cl-incf avg-overall (or overall 0))
          (cl-incf avg-efficiency (or efficiency 0))
          (cl-incf avg-completion (or completion 0))
          (cl-incf avg-constraints (or constraints 0))
          (when (>= (or overall 0) 0.7)
            (cl-incf passed)))))
    (list :total-tests total
          :passed-tests passed
          :avg-overall (if (> total 0) (/ avg-overall total) 0.0)
          :avg-efficiency (if (> total 0) (/ avg-efficiency total) 0.0)
          :avg-completion (if (> total 0) (/ avg-completion total) 0.0)
          :avg-constraints (if (> total 0) (/ avg-constraints total) 0.0))))

;;; Eight Keys Integration

(defun gptel-benchmark-eight-keys-breakdown (results)
  "Generate Eight Keys breakdown from RESULTS.
RESULTS should contain :eight-keys-scores in each entry."
  (let ((key-totals (make-vector 8 0.0))
        (key-counts (make-vector 8 0))
        (key-names [phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                                 pi-synthesis mu-directness exists-truth forall-vigilance]))
    (dolist (r results)
      (let ((eight-keys (if (consp r)
                            (when (fboundp 'gptel-workflow-run-eight-keys-scores)
                              (gptel-workflow-run-eight-keys-scores (car r)))
                          (plist-get r :eight-keys-scores))))
        (when eight-keys
          (cl-loop for key across key-names
                   for i from 0
                   for score = (alist-get key eight-keys)
                   when (numberp score)
                   do (progn
                        (aset key-totals i (+ (aref key-totals i) score))
                        (aset key-counts i (1+ (aref key-counts i))))))))
    (let ((breakdown '()))
      (cl-loop for key across key-names
               for i from 0
               for total = (aref key-totals i)
               for count = (aref key-counts i)
               for avg = (if (> count 0) (/ total count) 0.0)
               do (push (cons key avg) breakdown))
      (nreverse breakdown))))

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

(defun gptel-benchmark-analyze-patterns (results &rest _)
  "Analyze RESULTS for patterns, issues, and generate recommendations."
  (let ((issues (make-hash-table :test 'equal))
        (recommendations '())
        (total (length results))
        (low-scores 0)
        (high-scores 0)
        (score-types '(:completion-score :efficiency-score :constraint-score :tool-score))
        (threshold 0.7))
    (dolist (r results)
      (let ((scores (if (consp r) (cdr r) (plist-get r :scores))))
        (when scores
          (let ((overall (or (plist-get scores :overall-score) 0)))
            (cond
             ((< overall threshold) (cl-incf low-scores))
             ((>= overall 0.9) (cl-incf high-scores))))
          (dolist (score-type score-types)
            (let ((score (plist-get scores score-type)))
              (when (and score (< score threshold))
                (let ((issue-type (replace-regexp-in-string "-score$" "" (symbol-name score-type))))
                  (puthash issue-type (1+ (gethash issue-type issues 0)) issues))))))))
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
Returns new score clamped to 0.0-1.0."
  (let ((d (or delta 0.05)))
    (let ((new-score
           (pcase outcome
             (:validated (+ current-score d))
             (:corrected (- current-score (/ d 2.0)))
             (_ current-score))))
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
             (avg-scores (mapcar (lambda (h)
                                   (plist-get (plist-get h :summary) :avg-overall))
                                 recent))
             (avg (apply #'+ avg-scores))
             (count (length avg-scores))
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
                :current-avg overall-avg)))))))

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
