;;; gptel-tools-agent-strategy-harness.el --- Strategy evolution for prompt builders -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split
;; Implements Meta-Harness style harness evolution

;; Forward declarations for dynamic variables
(defvar gptel-auto-workflow--generation-count)
(defvar gptel-auto-workflow--strategy-active-test-set)

(declare-function gptel-auto-workflow--discover-targets "gptel-auto-workflow-strategic" ())

;;; Commentary:
;; This module evolves the PROMPT BUILDING STRATEGY itself, not just filling templates.
;; Strategies are stored as files in assistant/strategies/prompt-builders/
;; and selected based on historical performance per target.
;;
;; Interface: Every strategy must provide:
;;   (defun strategy-<name>-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
;;   Returns: prompt string
;;
;;   (defun strategy-<name>-get-metadata ())
;;   Returns: plist with :name :version :hypothesis :axis :created :parent-strategies :components
;;
;; Extended Interface (optional methods for stateful strategies):
;;   (defun strategy-<name>-analyze-results (target experiment-result)
;;   Optional. Analyze experiment results to inform future strategy behavior.
;;   Called after each experiment completes. EXPERIMENT-RESULT is a plist with
;;   :target :decision :score-after :exploration-axis :comparator-reason.
;;   Returns nil (side-effect only: updates strategy state).
;;
;;   (defun strategy-<name>-get-state ()
;;   Optional. Return a JSON-serializable value representing current strategy state.
;;   Used for persistence across daemon restarts. Returns nil if stateless.
;;
;;   (defun strategy-<name>-set-state (state)
;;   Optional. Restore strategy state from a previous get-state call.
;;   STATE is the same JSON value returned by get-state.

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-base" ())
(declare-function gptel-auto-workflow--parse-all-results "gptel-auto-workflow-evolution" ())
(declare-function gptel-auto-workflow--results-file-path "gptel-tools-agent-base" (&optional run-id))

;;; Strategy Registry

(defvar gptel-auto-workflow--strategy-registry (make-hash-table :test 'equal)
  "Registry mapping strategy names to their metadata and build functions.")

(defvar gptel-auto-workflow--active-strategy "template-default"
  "Currently active prompt-building strategy.")

(defvar gptel-auto-workflow--strategy-evaluations-file
  "var/tmp/evaluations.jsonl"
  "File storing strategy evaluation results.")

(defvar gptel-auto-workflow--strategy-evolution-enabled t
  "When non-nil, allow strategy evolution via harness search.")

(defvar gptel-auto-workflow--suppress-strategy-metadata-persistence nil
  "When non-nil, strategy registration does not write metadata files.")

(defvar gptel-auto-workflow--strategy-run-name nil
  "Run name for isolated strategy evolution outputs.
When non-nil, outputs go to `assistant/strategies/runs/<run-name>/'.
When nil, outputs go to `assistant/strategies/' directly.")

(defvar gptel-auto-workflow--strategy-evolution-summary-file
  "evolution_summary.jsonl"
  "Filename for per-iteration evolution summary.
Relative to the active run directory.")

(defvar gptel-auto-workflow--strategy-interrupted nil
  "Non-nil when strategy evolution was interrupted by signal.")

(defvar gptel-auto-workflow--strategy-test-set-ratio 0.2
  "Fraction of targets held out for final test evaluation.
During evolution, only the search set is used. The test set is
only evaluated after evolution completes to prevent overfitting.
Set to 0 to disable the split and use all targets for both.")

(defun gptel-auto-workflow--strategy-run-directory ()
  "Return the active strategy run directory, respecting the run name."
  (let ((base (expand-file-name "var/tmp/strategy-evaluations"
                                (gptel-auto-workflow--project-root))))
    (if gptel-auto-workflow--strategy-run-name
        (expand-file-name (format "runs/%s" gptel-auto-workflow--strategy-run-name) base)
      base)))

(defun gptel-auto-workflow--strategy-results-file ()
  "Return the full path to evaluations.jsonl for the current run."
  (expand-file-name "evaluations.jsonl"
                    (gptel-auto-workflow--strategy-run-directory)))

(defun gptel-auto-workflow--strategy-evolution-summary-path ()
  "Return the full path to the evolution summary file for the current run."
  (expand-file-name gptel-auto-workflow--strategy-evolution-summary-file
                    (gptel-auto-workflow--strategy-run-directory)))

(defun gptel-auto-workflow--file-tracked-by-git-p (file)
  "Return non-nil if FILE is tracked by git."
  (let ((default-directory (or (gptel-auto-workflow--project-root) default-directory)))
    (condition-case nil
        (eq 0 (call-process "git" nil nil nil "ls-files" "--error-unmatch"
                            (file-relative-name file default-directory)))
      (ignore))))

(defun gptel-auto-workflow--fresh-start-strategies ()
  "Clear generated strategies and reset logs for a fresh run.
Only removes files NOT tracked by git to preserve committed strategies."
  (interactive)
  (let ((strategies-dir (gptel-auto-workflow--strategies-directory))
        (run-dir (gptel-auto-workflow--strategy-run-directory))
        (cleared-strategies 0)
        (cleared-logs 0))
    ;; Clear generated (non-tracked) strategies
    (when (file-directory-p strategies-dir)
      (dolist (file (directory-files strategies-dir t "^strategy-[^.]+\\.el$"))
        (unless (gptel-auto-workflow--file-tracked-by-git-p file)
          (delete-file file)
          (setq cleared-strategies (1+ cleared-strategies))))
      (when (> cleared-strategies 0)
        (message "[strategy] Cleared %d untracked evolved strategy file(s)" cleared-strategies)))
    ;; Clear run logs (only untracked)
    (when (file-directory-p run-dir)
      (dolist (file (directory-files run-dir t "\\.jsonl?$"))
        (unless (gptel-auto-workflow--file-tracked-by-git-p file)
          (delete-file file)
          (setq cleared-logs (1+ cleared-logs))))
      (when (> cleared-logs 0)
        (message "[strategy] Cleared %d untracked log file(s) from %s" cleared-logs run-dir)))
    ;; Reset evolution summary counter
    (setq gptel-auto-workflow--generation-count 0)
    (message "[strategy] Fresh start complete")))



(defun gptel-auto-workflow--ensure-strategy-run-directories ()
  "Create strategy run directories if they don't exist."
  (let ((run-dir (gptel-auto-workflow--strategy-run-directory))
        (reports-dir (expand-file-name "reports"
                                       (gptel-auto-workflow--strategy-run-directory))))
    (make-directory run-dir t)
    (make-directory reports-dir t)))

(defun gptel-auto-workflow--write-evolution-summary (iteration candidates val-scores &optional _timing)
  "Append evolution summary rows for ITERATION to the summary file.
CANDIDATES is a list of candidate plists with :name and :hypothesis.
VAL-SCORES is a hash table mapping strategy name to avg score.
Optional TIMING is a plist with :propose :bench :wall timing info."
  (let* ((summary-file (gptel-auto-workflow--strategy-evolution-summary-path))
         (frontier (gptel-auto-workflow--compute-strategy-frontier))
         (best-strategy (car frontier))
         (best-score (if best-strategy
                         (let ((perf (gptel-auto-workflow--get-strategy-performance best-strategy)))
                           (plist-get perf :avg-score))
                       0)))
    (make-directory (file-name-directory summary-file) t)
    (with-temp-buffer
      (when (file-exists-p summary-file)
        (insert-file-contents summary-file))
      (goto-char (point-max))
      (dolist (candidate candidates)
        (let* ((name (plist-get candidate :name))
               (avg-val (or (gethash name val-scores) 0))
               (row `(:iteration ,iteration
                       :system ,name
                       :avg_val ,avg-val
                       :axis ,(plist-get candidate :axis)
                       :hypothesis ,(plist-get candidate :hypothesis)
                       :delta ,(- avg-val best-score)
                       :outcome ,(format "%.2f (%.2f)" avg-val (- avg-val best-score))
                       :components ,(plist-get candidate :components))))
          (insert (json-encode row) "\n")))
      (write-region (point-min) (point-max) summary-file))
    (message "[strategy] Evolution summary written: %d candidate(s) for iteration %d"
             (length candidates) (round iteration))))

(defun gptel-auto-workflow--strategies-directory ()
  "Return the directory where prompt-building strategies are stored."
  (expand-file-name "assistant/strategies/prompt-builders"
                    (gptel-auto-workflow--project-root)))

;;; Strategy Discovery and Loading

(defun gptel-auto-workflow--discover-strategies ()
  "Discover all available prompt-building strategies from filesystem.
Returns list of strategy names."
  (let ((dir (gptel-auto-workflow--strategies-directory))
        (strategies '()))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.el$"))
        (let ((name (file-name-sans-extension (file-name-nondirectory file))))
          (when (string-match "^strategy-" name)
            (push (substring name (length "strategy-")) strategies)))))
    (nreverse strategies)))

(defun gptel-auto-workflow--file-has-conflict-markers-p (file)
  "Return non-nil if FILE contains unresolved git merge conflict markers.
Scans for <<<<<<<, =======, or >>>>>>> patterns."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (re-search-forward "^\\(<<<<<<< \\|>>>>>>> \\|=======\\)" nil t))))

(defun gptel-auto-workflow--load-strategy (strategy-name)
  "Load strategy STRATEGY-NAME from filesystem.
Also loads persisted metadata if available.
Returns t if loaded successfully."
  (let ((file (expand-file-name (format "strategy-%s.el" strategy-name)
                                 (gptel-auto-workflow--strategies-directory))))
    (if (file-exists-p file)
        (progn
          ;; GUARD: Reject files with unresolved merge conflict markers BEFORE
          ;; the condition-case, so errors propagate to callers.
          (when (gptel-auto-workflow--file-has-conflict-markers-p file)
            (error "Strategy file contains unresolved merge conflict markers: %s" file))
          (condition-case err
              (progn
                (load file nil t t)
              ;; Register loadable strategies even if generated code omits the
              ;; self-registration block.
              (unless (gethash strategy-name gptel-auto-workflow--strategy-registry)
                (let* ((build-fn (intern (format "strategy-%s-build-prompt" strategy-name)))
                       (metadata-fn (intern (format "strategy-%s-get-metadata" strategy-name)))
                       (metadata (or (and (fboundp metadata-fn)
                                          (funcall metadata-fn))
                                     (gptel-auto-workflow--load-strategy-metadata strategy-name))))
                  (when (and (fboundp build-fn) metadata)
                    (gptel-auto-workflow--register-strategy
                     strategy-name
                     build-fn
                     metadata))))
              (message "[strategy] Loaded %s" strategy-name)
              t)
          (error
           (message "[strategy] ERROR loading %s: %s" strategy-name err)
           nil)))
      (message "[strategy] Strategy file not found: %s" file)
      nil)))

(defun gptel-auto-workflow--register-strategy (name build-fn metadata)
  "Register a strategy with NAME, BUILD-FN, and METADATA plist.
Also persists metadata to filesystem for durability across sessions."
  (puthash name (list :build build-fn :metadata metadata)
           gptel-auto-workflow--strategy-registry)
  (unless gptel-auto-workflow--suppress-strategy-metadata-persistence
    (gptel-auto-workflow--persist-strategy-metadata name metadata)))

(defun gptel-auto-workflow--persist-strategy-metadata (name metadata)
  "Persist METADATA for strategy NAME to filesystem.
Saves to assistant/strategies/metadata/NAME.json."
  (let* ((metadata-dir (expand-file-name "assistant/strategies/metadata"
                                         (gptel-auto-workflow--project-root)))
         (metadata-file (expand-file-name (format "%s.json" name) metadata-dir)))
    (make-directory metadata-dir t)
    (with-temp-file metadata-file
      (insert (json-encode metadata)))
    (message "[strategy] Persisted metadata for %s" name)
    ;; Auto-commit strategy files so they survive workspace cleanup
    (gptel-auto-workflow--auto-commit-strategy-files name)))

(defun gptel-auto-workflow--auto-commit-strategy-files (name)
  "Commit strategy NAME's builder and metadata files to git.
Prevents strategy files from being lost during stash/reset operations."
  (let* ((root (or (gptel-auto-workflow--project-root)
                   (gptel-auto-workflow--worktree-base-root)))
         (builder (expand-file-name
                   (format "strategy-%s.el" name)
                   (expand-file-name "assistant/strategies/prompt-builders" root)))
         (metadata (expand-file-name
                    (format "%s.json" name)
                    (expand-file-name "assistant/strategies/metadata" root)))
         (default-directory root))
    (when (and root (file-exists-p builder) (file-exists-p metadata))
      (condition-case nil
          (let ((cmd (format "git add %s %s && git diff --cached --quiet || git commit -m %s"
                             (shell-quote-argument builder)
                             (shell-quote-argument metadata)
                             (shell-quote-argument
                              (format "🔁 strategy: %s (auto-committed by harness)" name)))))
            (shell-command-to-string cmd))
        (error
         (message "[strategy] Auto-commit skipped for %s (git not available)" name))))))

(defun gptel-auto-workflow--load-strategy-metadata (name)
  "Load persisted metadata for strategy NAME from filesystem.
Returns plist or nil if not found."
  (let ((metadata-file (expand-file-name
                        (format "%s.json" name)
                        (expand-file-name "assistant/strategies/metadata"
                                          (gptel-auto-workflow--project-root)))))
    (when (file-exists-p metadata-file)
      (with-temp-buffer
        (insert-file-contents metadata-file)
        (condition-case nil
            (json-read-from-string (buffer-string))
          (ignore))))))

(defun gptel-auto-workflow--get-strategy-build-fn (name)
  "Get the build function for strategy NAME."
  (plist-get (gethash name gptel-auto-workflow--strategy-registry) :build))

;;; Extended Strategy Interface (Meta-Harness Stateful Harness)

(defun gptel-auto-workflow--strategy-analyze-results (name target experiment-result)
  "Call the optional analyze-results method on strategy NAME.
EXPERIMENT-RESULT is a plist with :decision :score-after :exploration-axis.
Returns nil (silently no-ops if method not defined by strategy)."
  (let* ((analyze-fn (intern (format "strategy-%s-analyze-results" name))))
    (when (fboundp analyze-fn)
      (condition-case err
          (funcall analyze-fn target experiment-result)
        (error (message "[strategy] analyze-results error for %s: %s" name err))))))

(defun gptel-auto-workflow--strategy-get-state (name)
  "Get serializable state from strategy NAME.
Returns JSON value or nil if strategy is stateless or method not defined."
  (let* ((state-fn (intern (format "strategy-%s-get-state" name))))
    (when (fboundp state-fn)
      (condition-case err
          (funcall state-fn)
        (error (message "[strategy] get-state error for %s: %s" name err)
               nil)))))





;;; Strategy Evaluation Tracking

(defun gptel-auto-workflow--record-strategy-evaluation (strategy-name target experiment-id score outcome &optional axis)
  "Record evaluation result for STRATEGY-NAME on TARGET.
SCORE is the experiment score, OUTCOME is \='kept or \='discarded.
Optional AXIS records the exploration axis used by the experiment."
  (let ((file (gptel-auto-workflow--strategy-results-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-buffer
      (when (file-exists-p file)
        (insert-file-contents file))
      (goto-char (point-max))
      (insert (json-encode
               (list :timestamp (format-time-string "%Y-%m-%d %H:%M:%S")
                     :strategy strategy-name
                      :target target
                      :experiment-id experiment-id
                      :score score
                      :outcome (symbol-name outcome)
                      :axis axis))
               "\n")
      (write-region (point-min) (point-max) file))))

(defun gptel-auto-workflow--get-strategy-performance (strategy-name)
  "Get performance statistics for STRATEGY-NAME.
Returns plist with :total :kept :success-rate :avg-score."
  (let ((file (gptel-auto-workflow--strategy-results-file))
        (total 0)
        (kept 0)
        (total-score 0.0))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
            (when (not (string-empty-p line))
              (condition-case nil
                  (let* ((entry (json-read-from-string line))
                         (entry-strategy (cdr (assoc 'strategy entry))))
                    (when (equal entry-strategy strategy-name)
                      (setq total (1+ total))
                      (setq total-score (+ total-score
                                          (or (cdr (assoc 'score entry)) 0)))
                      (when (equal (cdr (assoc 'outcome entry)) "kept")
                        (setq kept (1+ kept)))))
                (ignore)))
            (forward-line 1)))))
    (list :total total
          :kept kept
          :success-rate (if (> total 0) (/ (float kept) total) 0.0)
          :avg-score (if (> total 0) (/ total-score total) 0.0))))

;;; Strategy Selection

(defun gptel-auto-workflow--best-strategy-for-axis (strategies axis)
  "Return strategy name best for AXIS, or nil.
Scans TSV results for per-axis strategy performance."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let ((by-strategy (make-hash-table :test 'equal)))
      (dolist (r (gptel-auto-workflow--parse-all-results))
        (let* ((s (plist-get r :strategy))
               (a (plist-get r :kibcm-axis))
               (kept (or (equal (plist-get r :decision) "kept")
                         (eq (plist-get r :decision) t))))
          (when (and s (member s strategies) (equal a axis))
            (let ((entry (or (gethash s by-strategy) (cons 0 0))))
              (setcar entry (1+ (car entry)))
              (when kept (setcdr entry (1+ (cdr entry))))
              (puthash s entry by-strategy)))))
      (let ((best nil) (best-rate 0.0))
        (maphash (lambda (s counts)
                   (let ((rate (/ (float (cdr counts)) (car counts))))
                     (when (and (>= (car counts) 3) (> rate best-rate))
                       (setq best s best-rate rate))))
                 by-strategy)
        (when best
          (message "[strategy-axis] Best for %s: %s (%.0f%%)" axis best (* 100 best-rate))
          best)))))

(defun gptel-auto-workflow--most-common-axis-for-target (target)
  "Return the most frequent KIBC-M axis for TARGET from past experiments.
Used to predict which axis this experiment will target before the
hypothesis is generated, enabling per-axis strategy selection."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let ((counts (make-hash-table :test 'equal)))
      (dolist (r (gptel-auto-workflow--parse-all-results))
        (let* ((tgt (plist-get r :target))
               (axis (plist-get r :kibcm-axis)))
          (when (and tgt axis (not (equal axis "?"))
                     (string-match (regexp-quote (or target "")) tgt))
            (puthash axis (1+ (gethash axis counts 0)) counts))))
      (let ((best nil) (best-n 0))
        (maphash (lambda (a n) (when (> n best-n) (setq best a best-n n))) counts)
        best))))

(defun gptel-auto-workflow--select-best-strategy (&optional target)
  "Select the best strategy for TARGET based on historical performance.
Uses the target's most common historical axis to select a per-axis
strategy champion when available. Falls back to overall champion.
Returns strategy name. Gives newly-evolved strategies a chance by
preferring the active strategy when it has no evaluations yet."
  (let* ((strategies (gptel-auto-workflow--discover-strategies))
         (axis (or (and (boundp 'gptel-auto-workflow--current-experiment-axis)
                         gptel-auto-workflow--current-experiment-axis)
                   (and target
                        (not (equal target ""))
                        (gptel-auto-workflow--most-common-axis-for-target target))))
         (axis-strategy (when (and axis (not (equal axis "?")))
                           (gptel-auto-workflow--best-strategy-for-axis strategies axis)))
         (evaluated-strategies
          (cl-remove-if
           (lambda (name)
             (let ((perf (gptel-auto-workflow--get-strategy-performance name)))
               (= (plist-get perf :total) 0)))
           strategies))
         (unevaluated-strategies
          (cl-remove-if
           (lambda (name) (member name evaluated-strategies))
           strategies)))
    (cond
     ;; Axis-specific champion takes priority
     ((and axis-strategy (member axis-strategy evaluated-strategies))
      (message "[strategy] Selected per-axis champion %s for %s" axis-strategy axis)
      axis-strategy)
      ;; EXPLORATION: If we have unevaluated strategies, randomly try one
      ;; This ensures evolved strategies get their first evaluations
      ((and unevaluated-strategies
            (< (random 100) 40))  ; 40% chance to try an unevaluated strategy
       (let* ((random-idx (random (length unevaluated-strategies)))
              (chosen (nth random-idx unevaluated-strategies)))
         (message "[strategy] Exploring unevaluated strategy %s (%d/%d unevaluated)"
                  chosen random-idx (length unevaluated-strategies))
         chosen))
      ;; If active strategy is unevaluated, use it (exploration)
      ((and (not (equal gptel-auto-workflow--active-strategy "template-default"))
            (member gptel-auto-workflow--active-strategy unevaluated-strategies))
       (message "[strategy] Selected unevaluated active strategy %s for exploration"
                gptel-auto-workflow--active-strategy)
       gptel-auto-workflow--active-strategy)
      ;; If we have evaluated strategies, pick the best one
      (evaluated-strategies
      (let* ((sorted (sort (copy-sequence evaluated-strategies)
                          (lambda (a b)
                            (let ((perf-a (gptel-auto-workflow--get-strategy-performance a))
                                  (perf-b (gptel-auto-workflow--get-strategy-performance b))
                                  ;; Category champion boost: +0.15 for per-category champions
                                  (cat-boost (lambda (name)
                                               (if (and target
                                                        (fboundp 'gptel-auto-workflow--categorize-experiment-target)
                                                        (boundp 'gptel-auto-workflow--category-champions))
                                                   (let* ((cat (gptel-auto-workflow--categorize-experiment-target target))
                                                          (entry (assq cat gptel-auto-workflow--category-champions)))
                                                     (if (and entry (equal (cadr entry) name)) 0.15 0.0))
                                                 0.0))))
                              (> (+ (* 0.5 (plist-get perf-a :success-rate))
                                    (* 0.5 (plist-get perf-a :avg-score))
                                    (funcall cat-boost a))
                                 (+ (* 0.5 (plist-get perf-b :success-rate))
                                    (* 0.5 (plist-get perf-b :avg-score))
                                    (funcall cat-boost b)))))))
             (best (car sorted))
             (best-perf (gptel-auto-workflow--get-strategy-performance best))
             (best-success (plist-get best-perf :success-rate)))
         (let* ((default-perf (gptel-auto-workflow--get-strategy-performance "template-default"))
                (default-success (plist-get default-perf :success-rate))
                (default-avg (plist-get default-perf :avg-score))
                (default-total (plist-get default-perf :total))
                (best-total (plist-get best-perf :total))
                 ;; Require >=5 experiments OR >=25% of template-default's count
                 (sufficient-sample
                  (or (>= best-total 5)
                      (>= (* 4 best-total) default-total)))
                 ;; Exploration: small-sample strategies get 50% random chance
                 (explore (and (< best-total 5)
                               (< (random 100) 50)))
                 (chosen (if (and (not (equal best "template-default"))
                                (not explore)
                                (not sufficient-sample)
                                (< best-success default-success)
                                (< (round (* 100 (- (plist-get best-perf :avg-score) default-avg)))
                                   (round (* 100 0.15))))
                           (progn
                             (message "[strategy] %s underperforms template-default (%.0f%% < %.0f%% success, n=%d %s); falling back"
                                      best (* 100 best-success) (* 100 default-success)
                                      best-total
                                      (if sufficient-sample
                                          (format "avg diff %.2f < 0.15" (- (plist-get best-perf :avg-score) default-avg))
                                        "insufficient sample"))
                            "template-default")
                        best)))
          (let ((chosen-perf (gptel-auto-workflow--get-strategy-performance chosen)))
            (message "[strategy] Selected %s (success %.0f%%, avg score %.2f)"
                     chosen
                     (* 100 (plist-get chosen-perf :success-rate))
                     (plist-get chosen-perf :avg-score)))
          chosen)))
     ;; Otherwise, use the default
     (t
      (message "[strategy] No evaluated strategies yet, using default")
      "template-default"))))

;;; Target Discovery for Cross-Target Strategies

  (defun gptel-auto-workflow--synthesize-global-patterns (_targets)
  "Synthesize patterns across all TARGETS from TSV history.
Returns formatted string of global insights."
  (let ((results-file (gptel-auto-workflow--results-file-path))
        (axis-counts (make-hash-table :test 'equal))
        (axis-successes (make-hash-table :test 'equal))
        (total-kept 0)
        (total-discarded 0))
    (when (file-exists-p results-file)
      (with-temp-buffer
        (insert-file-contents results-file)
        (goto-char (point-min))
        (forward-line 1)
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring (line-beginning-position)
                                           (line-end-position))
                          "\t"))
                 ;; ASSUMPTION: TSV has at least 18 columns (index 0-17)
                 ;; BEHAVIOR: Guard access to prevent nil from short lines
                  (num-fields (length fields))
                  ;; 20/24-col: axis at index 17; 27-col: axis at index 18
                  (axis-idx (if (<= num-fields 24) 17 18))
                  (decision (when (>= num-fields 8) (nth 7 fields)))
                  (axis (when (>= num-fields 18) (or (nth axis-idx fields) "?"))))
            (when (and decision (not (equal axis "?")))
              (puthash axis (1+ (gethash axis axis-counts 0)) axis-counts)
              (when (equal decision "kept")
                (puthash axis (1+ (gethash axis axis-successes 0)) axis-successes)
                (setq total-kept (1+ total-kept)))
              (when (equal decision "discarded")
                (setq total-discarded (1+ total-discarded)))))
          (forward-line 1))))
    (if (= total-kept 0)
        "No global patterns yet."
      (concat "## Global Patterns Across All Targets\n"
              (format "Total experiments: %d kept, %d discarded (%.0f%% success)\n"
                      total-kept total-discarded
                      (* 100 (/ (float total-kept) (+ total-kept total-discarded))))
              "Success rates by axis:\n"
              (let ((results '()))
                (cl-flet ((format-axis-rate (axis count)
                           (let ((successes (gethash axis axis-successes 0)))
                             (push (format "- %s: %.0f%% (%d/%d)"
                                           axis
                                           (* 100 (/ (float successes) count))
                                           successes count)
                                   results))))
                  (maphash #'format-axis-rate axis-counts))
                (mapconcat #'identity (sort results #'string<) "\n"))
              "\n\nRecommendation: Focus on high-success axes globally.\n\n"))))

;;; Strategy Frontier Tracking (Meta-Harness Pareto Frontier)

(defun gptel-auto-workflow--compute-strategy-frontier ()
  "Compute Pareto frontier of strategies.
Returns list of strategy names that are not dominated by any other strategy.
A strategy dominates another if it has >= success rate and >= avg score."
  (let* ((strategies (gptel-auto-workflow--discover-strategies))
         (evaluated-strategies
          (cl-remove-if
           (lambda (name)
             (let ((perf (gptel-auto-workflow--get-strategy-performance name)))
               (= (plist-get perf :total) 0)))
           strategies))
         (frontier '()))
    (dolist (strategy evaluated-strategies)
      (let* ((perf (gptel-auto-workflow--get-strategy-performance strategy))
             (success-rate (plist-get perf :success-rate))
             (avg-score (plist-get perf :avg-score))
             (dominated nil))
        (dolist (other evaluated-strategies)
          (unless (equal strategy other)
            (let* ((other-perf (gptel-auto-workflow--get-strategy-performance other))
                   (other-success (plist-get other-perf :success-rate))
                   (other-score (plist-get other-perf :avg-score)))
              ;; Other dominates strategy if >= on both metrics
              (when (and (>= other-success success-rate)
                         (>= other-score avg-score)
                         ;; Strictly better on at least one
                         (or (> other-success success-rate)
                             (> other-score avg-score)))
                (setq dominated t)))))
        (unless dominated
          (push strategy frontier))))
    (nreverse frontier)))

(defun gptel-auto-workflow--format-strategy-frontier ()
  "Format strategy frontier as string for display."
  (let ((frontier (gptel-auto-workflow--compute-strategy-frontier)))
    (if (null frontier)
        "No strategy frontier yet."
      (concat "## Strategy Pareto Frontier\n"
              "Non-dominated strategies:\n"
              (mapconcat
               (lambda (name)
                 (let ((perf (gptel-auto-workflow--get-strategy-performance name)))
                   (format "- %s: %.0f%% success, avg score %.2f"
                           name
                           (* 100 (plist-get perf :success-rate))
                           (plist-get perf :avg-score))))
               frontier
               "\n")
              "\n\n"))))

;;; Strategy Execution Tracing

(defvar gptel-auto-workflow--strategy-execution-log nil
  "In-memory log of strategy executions for current session.")

(defun gptel-auto-workflow--trace-strategy-execution (strategy-name target prompt-chars sections)
  "Trace a strategy execution.
STRATEGY-NAME: which strategy was used
TARGET: which file was optimized
PROMPT-CHARS: size of generated prompt
SECTIONS: list of sections included"
  (push (list :timestamp (current-time)
              :strategy strategy-name
              :target target
              :prompt-chars prompt-chars
              :sections sections)
        gptel-auto-workflow--strategy-execution-log))



;;; Held-Out Test Set (Meta-Harness Anti-Overfitting)

(defun gptel-auto-workflow--split-targets-search-test (targets &optional test-ratio)
  "Split TARGETS into search and test sets.
TEST-RATIO defaults to `gptel-auto-workflow--strategy-test-set-ratio'.
Returns (search-set . test-set).
When test-ratio is 0, all targets go to the search set."
  (let* ((ratio (or test-ratio gptel-auto-workflow--strategy-test-set-ratio))
         (n (length targets))
         (test-n (max 1 (round (* n ratio))))
         ;; Use deterministic shuffle based on target hash for reproducibility
         (sorted (sort (copy-sequence targets) #'string<))
         (search-set (if (> ratio 0)
                         (butlast sorted test-n)
                       sorted))
         (test-set (if (> ratio 0)
                       (last sorted test-n)
                     '())))
    (message "[strategy] Split %d targets: %d search, %d test (%.0f%% held out)"
             n (length search-set) (length test-set) (* 100 ratio))
    (cons search-set test-set)))





(defvar gptel-auto-workflow--strategy-active-search-set nil
  "The current search set of targets used during evolution.
Test-set targets are excluded from this list.")

(defvar gptel-auto-workflow--strategy-active-test-set nil
  "The current test set of targets held out from evolution.")



;;; Strategy Execution

(defun gptel-auto-experiment-build-prompt-with-strategy (strategy-name target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using STRATEGY-NAME.
Falls back to default template if strategy not found or fails."
  (condition-case err
      (progn
        (gptel-auto-workflow--load-strategy strategy-name)
        (let ((build-fn (gptel-auto-workflow--get-strategy-build-fn strategy-name)))
          (if build-fn
              (funcall build-fn target experiment-id max-experiments analysis baseline previous-results)
            (progn
              (message "[strategy] Build function not found for %s, falling back" strategy-name)
              (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results)))))
    (error
     (message "[strategy] ERROR using %s: %s, falling back to default" strategy-name err)
     (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))))

(declare-function gptel-auto-experiment-build-prompt "gptel-tools-agent-prompt-build")

(provide 'gptel-tools-agent-strategy-harness)
;;; gptel-tools-agent-strategy-harness.el ends here
