;;; gptel-auto-workflow-pipeline-statechart.el --- Markov-chain pipeline statechart from experiment TSV data -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: automation, statechart, markov, pipeline

;;; Commentary:

;; Models the OV5 experiment pipeline as an absorbing Markov chain.
;; Reads historical results.tsv files, classifies each experiment's
;; terminal decision label into the gate that rejected it, computes
;; per-gate transition probabilities, derives expected keep-rate,
;; detects drift vs. historical baseline, and identifies bottlenecks.
;;
;; Pipeline gates (in order):
;;   G1  roi-preflight       — ROI/token-economics check
;;   G2  quota-precondition  — backend quota + hard preconditions
;;   G3  executor            — AI agent execution
;;   G4  hypothesis-uniqueness — duplicate hypothesis + repeated focus
;;   G5  validation          — syntax, byte-compile, diff content
;;   G6  grader              — grader subagent quality assessment
;;   G7  decision            — comparator + decision-gate
;;   G8  complexity          — complexity gate (reject if regresses)
;;   G9  commit              — provisional commit creation
;;   G10 staging             — staging verification, scope, merge
;;   G11 merge               — final merge to target branch
;;
;; Absorbing states: :kept (success), :discarded (failure).
;; Each gate has two possible transitions: pass → next gate, fail → :discarded.
;;
;; Statechart persisted to var/tmp/pipeline-statechart.eld.

;;; Code:

(require 'cl-lib)

(declare-function gptel-auto-workflow--parse-all-results "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")

;; ─── Customization ───

(defgroup gptel-auto-workflow-pipeline-statechart nil
  "Pipeline statechart: Markov-chain transition tracking for experiment gates."
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-statechart-drift-threshold 0.10
  "Minimum drop in P(pass|gate) to flag as drift.
A gate is flagged when its current pass probability drops below
the historical baseline by at least this absolute amount (0.0–1.0)."
  :type 'float
  :group 'gptel-auto-workflow-pipeline-statechart)

(defcustom gptel-auto-workflow-statechart-rebuild-interval 3
  "Rebuild statechart every N experiment completions.
Throttles rebuild frequency in the experiment-complete-hook."
  :type 'integer
  :group 'gptel-auto-workflow-pipeline-statechart)

(defcustom gptel-auto-workflow-statechart-historical-days 30
  "Days of TSV data to use for historical baseline in drift detection.
Current window uses 7 days; historical uses this many days."
  :type 'integer
  :group 'gptel-auto-workflow-pipeline-statechart)

;; ─── Gate Definitions ───

(defconst gptel-auto-workflow--pipeline-gates
  '[roi-preflight
    quota-precondition
    executor
    hypothesis-uniqueness
    validation
    grader
    decision
    complexity
    commit
    staging
    merge]
  "Vector of pipeline gate names in sequential order.
Each gate is a transient state in the absorbing Markov chain.")

(defconst gptel-auto-workflow--decision-to-fail-gate
  '(("roi-below-threshold"      . roi-preflight)
    ("all-backends-quota-exhausted" . quota-precondition)
    ("precondition-blocked"     . quota-precondition)
    ("api-error"                . quota-precondition)
    ("tool-error"               . quota-precondition)
    ("executor-timeout"         . executor)
    ("timeout"                  . executor)
    ("executor-prompt-empty"    . executor)
    ("executor-callback-missing" . executor)
    ("empty-prompt"             . executor)
    ("worktree-creation-failed" . executor)
    ("duplicate-hypothesis"     . hypothesis-uniqueness)
    ("repeated-focus-symbol"    . hypothesis-uniqueness)
    ("inspection-thrash"        . hypothesis-uniqueness)
    ("validation-failed"        . validation)
    ("validation-hard-block"    . validation)
    ("grader-failed"            . grader)
    ("grader-rejected"          . grader)
    ("retry-grade-rejected"     . grader)
    ("retry-grade-failed"       . grader)
    ("discarded"                . decision)
    ("grader-bypass-commit-failed" . commit)
    ("experiment-commit-failed" . commit)
    ("scope-creep-blocked"      . staging)
    ("staging-flow-failed"      . staging)
    ("staging-merge-failed"     . staging)
    ("staging-verification-failed" . staging)
    ("review-failed-max-retries" . staging)
    ("optimize-push-failed"     . staging)
    ("fix-failed"               . merge))
  "Alist mapping TSV decision labels to the gate that rejected them.
Keys are decision strings (col 7 in results.tsv); values are gate symbols.
The gate is the first one that failed — all prior gates were passed.
Decision \"kept\" is handled separately (passed all gates).
Decision \"staging-pending\" is treated as transient (excluded).")

;; ─── Persistence ───

(defun gptel-auto-workflow--statechart-persistence-file ()
  "Return the absolute path to the statechart persistence file."
  (expand-file-name
   "var/tmp/pipeline-statechart.eld"
   (if (fboundp 'gptel-auto-workflow--worktree-base-root)
       (gptel-auto-workflow--worktree-base-root)
     user-emacs-directory)))

(defun gptel-auto-workflow--statechart-persist (statechart)
  "Write STATECHART plist to the persistence file."
  (let ((file (gptel-auto-workflow--statechart-persistence-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (prin1 statechart (current-buffer)))
    file))

(defun gptel-auto-workflow--statechart-load ()
  "Load and return the statechart plist from disk, or nil."
  (let ((file (gptel-auto-workflow--statechart-persistence-file)))
    (when (file-exists-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (read (current-buffer)))
        (error nil)))))

;; ─── Statechart Construction ───

(defun gptel-auto-workflow--build-statechart (&optional max-age-days)
  "Build pipeline statechart from historical TSV data.
Optional MAX-AGE-DAYS limits to recent runs.
Returns plist with :gates, :total, :kept, :discarded, :keep-rate,
:transition-matrix, :computed-at."
  (let* ((records (if (fboundp 'gptel-auto-workflow--parse-all-results)
                      (gptel-auto-workflow--parse-all-results max-age-days)
                    nil))
         (total (length records))
         (kept-count 0)
         (discarded-count 0)
         ;; Per-gate accumulators: passed, failed, unreached
         (gate-stats (make-hash-table :test 'eq))
         (gate-order gptel-auto-workflow--pipeline-gates)
         (num-gates (length gate-order))
         (gate-list (append gate-order nil)))
    ;; Initialize gate stats
    (dolist (gate gate-list)
      (puthash gate (list :passed 0 :failed 0 :unreached 0) gate-stats))
    ;; Classify each experiment
    (dolist (rec records)
      (let* ((decision (plist-get rec :decision))
             (decision-str (if (stringp decision) decision
                             (format "%s" decision))))
        (if (string= decision-str "kept")
            (progn
              (setq kept-count (1+ kept-count))
              ;; Passed all gates
              (dolist (gate gate-list)
                (let* ((s (gethash gate gate-stats))
                       (v (plist-get s :passed)))
                  (puthash gate
                           (plist-put s :passed (1+ v))
                           gate-stats))))
          ;; Exclude transient states
          (if (string= decision-str "staging-pending")
              nil  ; skip transient — neither pass nor fail
            (setq discarded-count (1+ discarded-count))
            (let* ((fail-gate
                    (or (cdr (assoc decision-str
                                    gptel-auto-workflow--decision-to-fail-gate))
                        ;; Fallback: unknown decisions assumed to fail at executor
                        'executor))
                   (before-fail t))
              (dolist (gate gate-list)
                (let* ((s (gethash gate gate-stats)))
                  (cond
                   ((eq gate fail-gate)
                    (let ((v (plist-get s :failed)))
                      (puthash gate
                               (plist-put s :failed (1+ v))
                               gate-stats))
                    (setq before-fail nil))
                   (before-fail
                    (let ((v (plist-get s :passed)))
                      (puthash gate
                               (plist-put s :passed (1+ v))
                               gate-stats)))
                   (t
                    (let ((v (plist-get s :unreached)))
                      (puthash gate
                               (plist-put s :unreached (1+ v))
                               gate-stats)))))))))))
    ;; Build transition matrix with probabilities
    (let ((transition-matrix (make-hash-table :test 'eq))
          (keep-rate 1.0))
      (dolist (gate gate-list)
        (let* ((s (gethash gate gate-stats))
               (passed (plist-get s :passed))
               (failed (plist-get s :failed))
               (entered (+ passed failed))
               (p-pass (if (> entered 0)
                           (/ (float passed) entered)
                         1.0))
               (p-fail (- 1.0 p-pass)))
          (puthash gate
                   (list :name gate
                         :entered entered
                         :passed passed
                         :failed failed
                         :unreached (plist-get s :unreached)
                         :p-pass p-pass
                         :p-fail p-fail)
                   transition-matrix)
          (setq keep-rate (* keep-rate p-pass))))
      (list :gates gate-order
            :total total
            :kept kept-count
            :discarded discarded-count
             :keep-rate keep-rate
             :transition-matrix transition-matrix
             :computed-at (float-time)))))

;; ─── Analysis ───

(defun gptel-auto-workflow--statechart-analyze (&optional statechart)
  "Analyze STATECHART and return bottleneck report.
If STATECHART is nil, builds from all available TSV data.
Returns plist with :bottleneck, :bottlenecks, :expected-keep-rate,
:lossiest-gate, :phi-keep-rate-max, :phi-deviation, :per-gate, :computed-at."
  (let* ((sc (or statechart
                 (gptel-auto-workflow--build-statechart)))
         (gates (plist-get sc :gates))
         (matrix (plist-get sc :transition-matrix))
         (num-gates (length gates))
         (total (plist-get sc :total))
         (keep-rate (plist-get sc :keep-rate))
         ;; Collect per-gate data
         (per-gate nil)
         (bottleneck nil)
         (min-p-pass 1.0)
         (lossiest-gate nil)
          (max-abs-fail 0)
          (bottlenecks nil)
          (gate-list (append gates nil)))
    (dolist (gate gate-list)
      (let* ((entry (gethash gate matrix))
             (p-pass (plist-get entry :p-pass))
             (p-fail (plist-get entry :p-fail))
             (entered (plist-get entry :entered))
             (failed (plist-get entry :failed)))
        (push (list :gate gate
                    :p-pass p-pass
                    :p-fail p-fail
                    :entered entered
                    :failed failed)
              per-gate)
        ;; Bottleneck: lowest p-pass (highest conditional failure rate)
        (when (< p-pass min-p-pass)
          (setq min-p-pass p-pass
                bottleneck gate))
        ;; Bottlenecks: any gate with p-pass < 0.5
        (when (< p-pass 0.5)
          (push gate bottlenecks))
        ;; Lossiest gate: highest absolute failure count
        (when (> failed max-abs-fail)
          (setq max-abs-fail failed
                lossiest-gate gate))))
    (setq per-gate (nreverse per-gate))
    (setq bottlenecks (nreverse bottlenecks))
    ;; φ-test: keep_rate_max ≈ φ^(-n/(n+1)) where φ ≈ 1.618
    (let* ((phi 1.618033988749895)
           (phi-keep-rate-max (expt phi (- (/ (float num-gates)
                                              (1+ num-gates)))))
           (phi-deviation (- phi-keep-rate-max keep-rate)))
      (list :bottleneck bottleneck
            :bottlenecks bottlenecks
            :expected-keep-rate keep-rate
            :lossiest-gate lossiest-gate
            :phi-keep-rate-max phi-keep-rate-max
            :phi-deviation phi-deviation
            :num-gates num-gates
            :total-experiments total
            :per-gate per-gate
            :computed-at (float-time)))))

;; ─── Drift Detection ───

(defun gptel-auto-workflow--statechart-drift-check (&optional current-statechart historical-statechart)
  "Compare CURRENT-STATECHART against HISTORICAL-STATECHART for drift.
Returns plist with :drifted, :drifted-gates, :report.
Uses `gptel-auto-workflow-statechart-drift-threshold' as the minimum
absolute drop in p-pass to flag a drift alert."
  (let* ((current (or current-statechart
                      (gptel-auto-workflow--build-statechart 7)))
         (historical (or historical-statechart
                         (gptel-auto-workflow--build-statechart
                          gptel-auto-workflow-statechart-historical-days)))
         (current-matrix (plist-get current :transition-matrix))
         (historical-matrix (plist-get historical :transition-matrix))
         (gates (plist-get current :gates))
         (threshold gptel-auto-workflow-statechart-drift-threshold)
         (drifted nil)
          (drifted-gates nil)
          (report nil)
          (gate-list (append gates nil)))
    (dolist (gate gate-list)
      (let* ((cur-entry (gethash gate current-matrix))
             (hist-entry (gethash gate historical-matrix))
             (cur-p (if cur-entry (plist-get cur-entry :p-pass) 1.0))
             (hist-p (if hist-entry (plist-get hist-entry :p-pass) 1.0))
             (delta (- cur-p hist-p))
             (alert (when (< delta (- threshold))
                      (format "DRIFT: %s P(pass) dropped from %.3f to %.3f (Δ=%.3f)"
                              gate hist-p cur-p delta))))
        (when alert
          (setq drifted t)
          (push gate drifted-gates))
        (push (list :gate gate
                    :current-p cur-p
                    :historical-p hist-p
                    :delta delta
                    :alert alert)
              report)))
    (list :drifted drifted
          :drifted-gates (nreverse drifted-gates)
          :report (nreverse report)
          :computed-at (float-time))))

;; ─── Convenience Entry Points ───

(defun gptel-auto-workflow--statechart-rebuild-and-persist ()
  "Rebuild statechart from all TSV data and persist to disk."
  (condition-case err
      (let ((sc (gptel-auto-workflow--build-statechart)))
        (gptel-auto-workflow--statechart-persist sc)
        (message "[statechart] Rebuilt: %d experiments, keep-rate=%.2f%%"
                 (plist-get sc :total)
                 (* 100 (plist-get sc :keep-rate))))
    (error
     (message "[statechart] Rebuild error: %s" (error-message-string err)))))

(defun gptel-auto-workflow--statechart-report ()
  "Return a human-readable statechart analysis string.
Suitable for display in a buffer or log."
  (let* ((analysis (gptel-auto-workflow--statechart-analyze))
         (lines nil))
    (push "=== Pipeline Statechart Analysis ===\n" lines)
    (push (format "Total experiments: %d\n" (plist-get analysis :total-experiments)) lines)
    (push (format "Expected keep-rate: %.2f%%\n"
                  (* 100 (plist-get analysis :expected-keep-rate))) lines)
    (push (format "φ keep-rate max (n=%d): %.4f (deviation: %+.4f)\n"
                  (plist-get analysis :num-gates)
                  (plist-get analysis :phi-keep-rate-max)
                  (plist-get analysis :phi-deviation)) lines)
    (let ((bn (plist-get analysis :bottleneck)))
      (when bn
        (push (format "Bottleneck gate: %s\n" bn) lines)))
    (let ((bns (plist-get analysis :bottlenecks)))
      (when bns
        (push (format "Gates with <50%% pass rate: %s\n"
                      (mapconcat #'symbol-name bns ", ")) lines)))
    (push "\nPer-gate transition probabilities:\n" lines)
    (push "  Gate                    P(pass)   Entered    Failed\n" lines)
    (push "  ────                    ───────   ───────    ──────\n" lines)
    (dolist (pg (plist-get analysis :per-gate))
      (push (format "  %-22s %7.3f   %7d   %7d\n"
                    (plist-get pg :gate)
                    (plist-get pg :p-pass)
                    (plist-get pg :entered)
                    (plist-get pg :failed))
            lines))
    (apply #'concat (nreverse lines))))

;; ─── Interactive Commands ───

;;;###autoload
(defun gptel-auto-workflow-statechart-show ()
  "Display pipeline statechart analysis in a buffer."
  (interactive)
  (let ((buf (get-buffer-create "*Pipeline Statechart*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert (gptel-auto-workflow--statechart-report))
      ;; Drift check
      (insert "\n=== Drift Check (7d vs 30d) ===\n")
      (let ((drift (gptel-auto-workflow--statechart-drift-check)))
        (if (plist-get drift :drifted)
            (progn
              (insert (format "⚠ DRIFT DETECTED in %d gates:\n"
                              (length (plist-get drift :drifted-gates))))
              (dolist (gate (plist-get drift :drifted-gates))
                (insert (format "  - %s\n" gate))))
          (insert "No drift detected.\n"))
        (dolist (r (plist-get drift :report))
          (when (plist-get r :alert)
            (insert (format "  %s\n" (plist-get r :alert))))))
      (goto-char (point-min))
      (local-set-key (kbd "q") #'kill-buffer-and-window))
    (pop-to-buffer buf)))

(provide 'gptel-auto-workflow-pipeline-statechart)
;;; gptel-auto-workflow-pipeline-statechart.el ends here
