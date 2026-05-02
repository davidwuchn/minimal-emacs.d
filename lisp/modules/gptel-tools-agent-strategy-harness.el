;;; gptel-tools-agent-strategy-harness.el --- Strategy evolution for prompt builders -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split
;; Implements Meta-Harness style harness evolution

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
;;   Returns: plist with :name :version :hypothesis :axis :created :parent-strategies

;;; Strategy Registry

(defvar gptel-auto-workflow--strategy-registry (make-hash-table :test 'equal)
  "Registry mapping strategy names to their metadata and build functions.")

(defvar gptel-auto-workflow--active-strategy "template-default"
  "Currently active prompt-building strategy.")

(defvar gptel-auto-workflow--strategy-evaluations-file
  "assistant/strategies/evaluations.jsonl"
  "File storing strategy evaluation results.")

(defvar gptel-auto-workflow--strategy-evolution-enabled t
  "When non-nil, allow strategy evolution via harness search.")

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

(defun gptel-auto-workflow--load-strategy (strategy-name)
  "Load strategy STRATEGY-NAME from filesystem.
Returns t if loaded successfully."
  (let ((file (expand-file-name (format "strategy-%s.el" strategy-name)
                                (gptel-auto-workflow--strategies-directory))))
    (if (file-exists-p file)
        (condition-case err
            (progn
              (load file nil t t)
              (message "[strategy] Loaded %s" strategy-name)
              t)
          (error
           (message "[strategy] ERROR loading %s: %s" strategy-name err)
           nil))
      (message "[strategy] Strategy file not found: %s" file)
      nil)))

(defun gptel-auto-workflow--register-strategy (name build-fn metadata)
  "Register a strategy with NAME, BUILD-FN, and METADATA plist."
  (puthash name (list :build build-fn :metadata metadata)
           gptel-auto-workflow--strategy-registry))

(defun gptel-auto-workflow--get-strategy-build-fn (name)
  "Get the build function for strategy NAME."
  (plist-get (gethash name gptel-auto-workflow--strategy-registry) :build))

;;; Strategy Evaluation Tracking

(defun gptel-auto-workflow--record-strategy-evaluation (strategy-name target experiment-id score outcome)
  "Record evaluation result for STRATEGY-NAME on TARGET.
SCORE is the experiment score, OUTCOME is 'kept or 'discarded."
  (let ((file (expand-file-name gptel-auto-workflow--strategy-evaluations-file
                                (gptel-auto-workflow--project-root))))
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
                     :outcome (symbol-name outcome)))
              "\n")
      (write-region (point-min) (point-max) file))))

(defun gptel-auto-workflow--get-strategy-performance (strategy-name)
  "Get performance statistics for STRATEGY-NAME.
Returns plist with :total :kept :success-rate :avg-score."
  (let ((file (expand-file-name gptel-auto-workflow--strategy-evaluations-file
                                (gptel-auto-workflow--project-root)))
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
                (error nil)))
            (forward-line 1)))))
    (list :total total
          :kept kept
          :success-rate (if (> total 0) (/ (float kept) total) 0.0)
          :avg-score (if (> total 0) (/ total-score total) 0.0))))

;;; Strategy Selection

(defun gptel-auto-workflow--select-best-strategy (target)
  "Select the best strategy for TARGET based on historical performance.
Returns strategy name."
  (let* ((strategies (gptel-auto-workflow--discover-strategies))
         (evaluated-strategies
          (cl-remove-if
           (lambda (name)
             (let ((perf (gptel-auto-workflow--get-strategy-performance name)))
               (= (plist-get perf :total) 0)))
           strategies)))
    (cond
     ;; If we have evaluated strategies, pick the best one
     (evaluated-strategies
      (let* ((sorted (sort (copy-sequence evaluated-strategies)
                          (lambda (a b)
                            (let ((perf-a (gptel-auto-workflow--get-strategy-performance a))
                                  (perf-b (gptel-auto-workflow--get-strategy-performance b)))
                              (> (plist-get perf-a :avg-score)
                                 (plist-get perf-b :avg-score))))))
             (best (car sorted))
             (best-perf (gptel-auto-workflow--get-strategy-performance best)))
        (message "[strategy] Selected %s (success %.0f%%, avg score %.2f)"
                 best
                 (* 100 (plist-get best-perf :success-rate))
                 (plist-get best-perf :avg-score))
        best))
     ;; Otherwise, use the default
     (t
      (message "[strategy] No evaluated strategies yet, using default")
      "template-default"))))

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

(provide 'gptel-tools-agent-strategy-harness)
;;; gptel-tools-agent-strategy-harness.el ends here