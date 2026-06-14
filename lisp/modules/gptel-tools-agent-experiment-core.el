; -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'parseedn)
(eval-when-compile
  (require 'gptel-tools-agent-base nil t)
  (require 'gptel-tools-agent-prompt-build nil t)
  (require 'gptel-tools-agent-benchmark nil t)
  (require 'gptel-tools-agent-experiment-loop nil t)
  (require 'gptel-tools-agent-error nil t)
  (require 'gptel-tools-agent-validation nil t)
  (require 'gptel-ext-world-store nil t))
(declare-function gptel-auto-workflow--current-head-hash "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--kibcm-axis "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment--prompt-structure-score "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment--agent-error-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--count-consecutive-strategy "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--executor-timeout-p "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--target-keep-rate "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--validate-diff-content "gptel-tools-agent-validation")
(declare-function gptel-auto-workflow--safe-backend-name "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--promote-correctness-fix-decision "gptel-tools-agent-prompt-analyze")
(declare-function magit-git-success "magit-git")
(declare-function gptel-auto-experiment--extract-axis "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--stale-run-p "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--stale-run-result "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--hash-get-bound "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--resolve-run-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--track-commit "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--truncate-hash "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--call-in-context "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--code-quality-score "gptel-tools-agent-benchmark")
(declare-function gptel-prefix-cache-sync-from-backend "gptel-ext-prefix-cache" (backend model))
(declare-function gptel-benchmark--complexity-penalty "gptel-benchmark-subagent")
(declare-function gptel-benchmark--calculate-complexity-before-after "gptel-benchmark-subagent")
(declare-function gptel-auto-experiment--repeated-focus-match "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--timeout-salvage-output "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment-analyze "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment-benchmark "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--categorize-error "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grade-failure-error-output "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grade-with-retry "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grader-only-error-label "gptel-tools-agent-error")
(declare-function gptel-auto-experiment--grader-only-failure-p "gptel-tools-agent-error")
(declare-function gptel-auto-workflow--compute-gate-score-vector "gptel-auto-workflow-pipeline-statechart")
(declare-function gptel-auto-experiment--shell-command-to-string-timeboxed "gptel-tools-agent-validation")
(declare-function gptel-auto-experiment--extract-hypothesis "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--make-retry-prompt "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--prepare-validation-retry-worktree "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--summarize "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment--teachable-validation-error-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--create-provisional-experiment-commit "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--drop-provisional-commit "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--promote-provisional-commit "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--stage-worktree-changes "gptel-tools-agent-experiment-loop")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")
(declare-function gptel-auto-experiment--normal-grade-details-p "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment-decide "gptel-tools-agent-prompt-analyze")
(declare-function gptel-auto-experiment--make-kept-result-callback "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment--maybe-log-staging-pending "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment-build-prompt "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-experiment-log-tsv "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--push-branch-with-lease "gptel-tools-agent-staging-merge")
(declare-function gptel-auto-workflow--staging-flow "gptel-tools-agent-staging-merge")
(declare-function gptel-auto-workflow--branch-name "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--get-current-branch "gptel-tools-agent-subagent")
(declare-function my/gptel--run-agent-tool-with-timeout "gptel-tools-agent-subagent")
(declare-function gptel-auto-experiment--validate-code "gptel-tools-agent-validation")
(declare-function gptel-auto-workflow--assert-main-untouched "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--risk-node-types-in-file "gptel-auto-workflow-self-heal-semantic")
(declare-function gptel-token-economics--predict-roi "gptel-token-economics")
(declare-function gptel-auto-workflow-create-worktree "gptel-tools-agent-worktree")
(declare-function ov5-world-store-branch-switch "gptel-ext-world-store-branch")
(declare-function gptel-auto-workflow--weight-score-with-production-metrics "gptel-auto-workflow-production-metrics")
;;; gptel-tools-agent-experiment-core.el --- Single experiment execution -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defvar gptel-auto-workflow--current-target nil)
(defvar gptel-auto-experiment-time-budget nil)
(defvar gptel-auto-workflow--run-id nil)
(defvar gptel-auto-experiment--no-improvement-count nil)
(defvar gptel-auto-experiment--grading-target nil)
(defvar gptel-auto-experiment--grading-worktree nil)
(defvar gptel-auto-experiment-validation-retry-active-grace nil)
(defvar gptel-auto-experiment-validation-retry-time-budget nil)
(defvar gptel-auto-workflow-git-timeout nil)
(defvar gptel-auto-experiment--best-score nil)
(defvar gptel-auto-experiment-auto-push nil)
;; gptel-auto-workflow-use-staging: declared via defcustom in subagent.el (default t).
;; Do NOT re-declare here — defvar would override the defcustom default.
;; Staging gate (verify-staging) must always be active for experiments.
(defvar gptel-auto-experiment--in-retry nil)
(defvar gptel-auto-experiment--in-refine nil)
(defvar gptel-auto-experiment--think-intel nil
  "Think-block intelligence from last experiment's agent output.
Set by executor callback, contains plist with :verdict :acts :explores etc.")
(defvar gptel-auto-experiment--refine-convergence-stats (list :total 0 :success 0 :failure 0)
  "Convergence statistics for the Generate→Validate→Refine cycle.
Updated by the refine loop, consumed by the evolution cycle.")
(defvar gptel-auto-experiment--target-state-cache (make-hash-table :test 'equal)
  "Cache of target file state before experiments: (:byte-compiles :syntax-ok).
Checked before each run to detect pre-existing breakage.")
(defvar gptel-auto-experiment-active-grace nil)
(defvar gptel-auto-experiment--loaded-skills nil
  "Dynamic variable. Accumulates skill names loaded during an experiment.
Pushed to by gptel-auto-workflow--load-skill, captured in experiment :skills.
Cleared at experiment start by gptel-auto-experiment-run.")

(defvar gptel-auto-experiment--suggested-workflow nil
  "Dynamic variable. Molecule recommended by skill graph for current target.
Set by gptel-auto-experiment-build-prompt, used in prompt WORKFLOW: line.
List of atom symbol names, e.g. (elisp-discover elisp-expert elisp-validator).")

(defvar gptel-auto-workflow--experiment-prompt-override nil
  "When non-nil, this string overrides the experiment prompt entirely.
Set by the regeneration workflow to inject a regeneration-specific prompt.
Cleared after each experiment run.  Must be a non-empty string to take effect.
Defined also in gptel-auto-workflow-code-regeneration.el — both definitions
are equivalent; this one ensures the var exists even when that module is not
loaded.")

(defun gptel-auto-experiment--pre-existing-breakage-p (target)
  "Return non-nil if TARGET was already broken before this experiment.
Uses the cached target state to detect pre-existing breakage.
This helps avoid wasted retry attempts on files that were already invalid."
  (when (and (stringp target) (not (string-empty-p target)))
    (let ((state (when (hash-table-p gptel-auto-experiment--target-state-cache)
                   (gethash target gptel-auto-experiment--target-state-cache))))
      (when state
        ;; If either byte-compiles or syntax-ok was already nil before experiment,
        ;; the file was pre-existing broken and retry won't help.
        (or (null (plist-get state :byte-compiles))
            (null (plist-get state :syntax-ok)))))))
(defvar gptel-auto-workflow-executor-rate-limit-fallbacks nil)
(defvar gptel-auto-workflow--rate-limited-backends nil)
(defvar gptel-model nil)
(defvar gptel-backend nil)
(defun gptel-auto-experiment--git-timeout (&optional minimum)
  "Return a numeric git timeout no lower than MINIMUM seconds."
  (let ((minimum (or minimum 300))
        (configured (and (boundp 'gptel-auto-workflow-git-timeout)
                         gptel-auto-workflow-git-timeout)))
    (max minimum (if (numberp configured) configured minimum))))

(defun gptel-auto-experiment--increment-no-improvement-count ()
  "Increment the no-improvement counter, treating nil/unbound as zero."
  (let ((current (and (boundp 'gptel-auto-experiment--no-improvement-count)
                      gptel-auto-experiment--no-improvement-count)))
    (setq gptel-auto-experiment--no-improvement-count
          (1+ (if (numberp current) current 0)))))

(defun gptel-auto-experiment--modified-files (worktree)
  "Return files modified against HEAD in WORKTREE using a bounded git diff."
  (when (and (stringp worktree) (file-directory-p worktree))
    (let ((default-directory worktree))
      (ignore-errors
        (split-string
         (if (fboundp 'gptel-auto-experiment--shell-command-to-string-timeboxed)
             (gptel-auto-experiment--shell-command-to-string-timeboxed
              "git diff --name-only HEAD 2>/dev/null")
                       (condition-case nil
                (shell-command-to-string "git diff --name-only HEAD 2>/dev/null")
              (error nil)))
         "\n" t)))))

(defun gptel-auto-experiment--validate-all-modified-files (worktree)
  "Validate all modified .el files in WORKTREE.
Returns nil if all pass, or error message string for first failure.
Also fails if NO files were modified (agent made no actual edits)."
  (let ((default-directory worktree)
        (modified-files (gptel-auto-experiment--modified-files worktree)))
    ;; CRITICAL: Agent must actually make file edits, not just output text
    (if (null modified-files)
        (progn
          (message "[auto-exp] ✗ Validation failed: agent made no file modifications")
          "Agent made no code changes. Use Edit or Write tools to modify files.")
      (catch 'validation-error
        (dolist (file modified-files)
          ;; WORKTREE BOUNDARY GUARD: ensure file is inside worktree
          (let ((full-path (expand-file-name file worktree)))
            (when (and (file-name-absolute-p full-path)
                       (not (condition-case nil
                                (file-in-directory-p full-path worktree)
                              (error nil))))
              (message "[auto-exp] ✗ WORKTREE BOUNDARY VIOLATION: %s is outside worktree %s"
                       full-path worktree)
              (throw 'validation-error
                     (format "File %s outside worktree — possible mayor checkout contamination" file))))
          (when (and (string-suffix-p ".el" file)
                     (not (string-suffix-p "-autoloads.el" file)))
            (let ((full-path (expand-file-name file worktree)))
              (when (file-exists-p full-path)
                (let ((validation-err (gptel-auto-experiment--validate-code full-path)))
                  (when validation-err
                    (message "[auto-exp] ✗ Validation failed for %s: %s"
                             file
                             (my/gptel--sanitize-for-logging validation-err 120))
                    (throw 'validation-error
                           (format "%s in %s" validation-err file))))))))))))

(defun gptel-auto-experiment--maybe-failover-main-backend ()
  "Switch `gptel-backend' to a fallback if the current one is rate-limited.
Checks `gptel-auto-workflow--rate-limited-backends' and uses
`gptel-auto-workflow-executor-rate-limit-fallbacks' to find an alternative."
  (when (and (boundp 'gptel-backend) gptel-backend
             (fboundp 'gptel-backend-name)
             (fboundp 'gptel-auto-workflow--backend-rate-limited-p)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate)
             (fboundp 'gptel-auto-workflow--backend-object))
    (let* ((current-name (gptel-auto-workflow--safe-backend-name gptel-backend))
           (is-limited (gptel-auto-workflow--backend-rate-limited-p current-name)))
      (when is-limited
        (if-let* ((fallback (gptel-auto-workflow--first-available-provider-candidate
                             gptel-auto-workflow-executor-rate-limit-fallbacks
                             gptel-auto-workflow--rate-limited-backends))
                  (new-backend (gptel-auto-workflow--backend-object (car fallback)))
                  (new-model (intern (cdr fallback))))
            (progn
              (setq gptel-backend new-backend
                    gptel-model new-model)
              (message "[auto-experiment] Main backend switched from %s to %s/%s (rate-limited)"
                       current-name (car fallback) (cdr fallback)))
          (message "[auto-experiment] Main backend %s is rate-limited but no fallback available"
                   current-name))))))

(defvar gptel-auto-experiment-run nil)
(cl-defun gptel-auto-experiment-run (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional log-fn)
  "Run single experiment. Call CALLBACK with result plist.
BASELINE-CODE-QUALITY is the initial code quality score.
LOG-FN receives deferred results as (RUN-ID EXPERIMENT)."
  ;; Clear per-experiment provider overrides so MiniMax gets first crack
  ;; at each new experiment. Rate-limited backends still stay blacklisted.
  (when (fboundp 'gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
    (gptel-auto-workflow--clear-runtime-subagent-provider-overrides))
  ;; Switch main backend if it's been rate-limited, or switch BACK if quota
  ;; reset window has elapsed while this daemon was running.
  (gptel-auto-experiment--maybe-failover-main-backend)
  (when (fboundp 'gptel-auto-experiment--check-quota-reset-and-switch-back)
    (gptel-auto-experiment--check-quota-reset-and-switch-back))
  ;; Global quota exhaustion check — stop early if all backends are dry
  (when (and (boundp 'gptel-auto-experiment--quota-exhausted)
             gptel-auto-experiment--quota-exhausted)
    (message "[auto-experiment] ⏹ All backends quota exhausted — aborting experiment %d/%d for %s"
             experiment-id max-experiments target)
    (let ((result (list :target target :id experiment-id :kept nil :error "all-backends-quota-exhausted")))
      (gptel-auto-experiment-log-tsv gptel-auto-workflow--run-id result)
      (when (functionp callback)
        (funcall callback result)))
    (cl-return-from gptel-auto-experiment-run))
  ;; ROI pre-flight check — reject experiments where predicted ROI < threshold
  ;; Categories with no history or zero ROI get 1.0 (break-even default),
  ;; which passes the default threshold of 1.0 and allows data collection.
  (when (fboundp 'gptel-token-economics--predict-roi)
    (let* ((category (when (and target
                                (fboundp 'gptel-auto-workflow--categorize-target))
                       (gptel-auto-workflow--categorize-target target)))
           (predicted-roi (gptel-token-economics--predict-roi category))
           (threshold (if (boundp 'gptel-token-economics-roi-threshold)
                          gptel-token-economics-roi-threshold 1.0)))
      (when (and predicted-roi (< predicted-roi threshold))
        (message "[auto-experiment] ⏹ ROI pre-flight rejected: category %s predicted ROI %.2f <
threshold %.2f — aborting experiment %d/%d for %s"
                 (or category "unknown") predicted-roi threshold
                 experiment-id max-experiments target)
        (let ((result (list :target target :id experiment-id :kept nil
                            :error "roi-below-threshold"
                            :category category
                            :predicted-roi predicted-roi
                            :roi-threshold threshold)))
          (gptel-auto-experiment-log-tsv gptel-auto-workflow--run-id result)
          (when (fboundp 'gptel-token-economics--track-experiment)
            (gptel-token-economics--track-experiment result))
          (when (functionp callback)
            (funcall callback result)))
        (cl-return-from gptel-auto-experiment-run))))
  (message "[auto-experiment] Starting %d/%d for %s" experiment-id max-experiments target)
  (setq gptel-auto-experiment--loaded-skills nil)
  (setq gptel-auto-experiment--suggested-workflow nil)
  (setq gptel-auto-workflow--current-target target)
  (let* ((worktree (gptel-auto-workflow-create-worktree target experiment-id))
         (experiment-worktree (or worktree default-directory))
          (experiment-buffer (and worktree
                                  (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                                  (ignore-errors
                                    (gptel-auto-workflow--get-worktree-buffer
                                     experiment-worktree))))
           (experiment-branch (or (gptel-auto-workflow--get-current-branch target)
                                  (gptel-auto-workflow--branch-name target experiment-id)))
          ;; Track target state before experiment (lightweight digital twin)
           (_target-state
            (when target
              (let* ((source (expand-file-name target (or worktree default-directory)))
                     (byte-compile-script (expand-file-name "scripts/byte-compile-check.sh"
                                                            (gptel-auto-workflow--worktree-base-root)))
                     (byte-compiles (when (and (file-exists-p source)
                                               (file-exists-p byte-compile-script))
                                      (zerop (condition-case nil (call-process "bash" nil nil nil
                                                           byte-compile-script source)
                                               (error nil)))))
                     (syntax-ok (when (file-exists-p source)
                                  (with-temp-buffer
                                    (ignore-errors (insert-file-contents source))
                                    (condition-case nil
                                        (progn (check-parens) t)
                                      (error nil))))))
                (when (hash-table-p gptel-auto-experiment--target-state-cache)
                  (puthash target (list :byte-compiles byte-compiles :syntax-ok syntax-ok)
                           gptel-auto-experiment--target-state-cache)))))
          ;; CRITICAL: Set default-directory to worktree so all subagents
         ;; operate in the correct context. Each worktree = one session.
         (default-directory experiment-worktree)
         (log-fn (or log-fn #'gptel-auto-experiment-log-tsv))
          ;; Get project buffer for overlay routing (ensure hash table exists)
          (_project-buf (when (and (boundp 'gptel-auto-workflow--current-project)
                                   gptel-auto-workflow--current-project)
                          (gptel-auto-workflow--hash-get-bound
                           'gptel-auto-workflow--project-buffers
                           (expand-file-name gptel-auto-workflow--current-project))))
          ;; Disable preview for headless auto-workflow
          (_gptel-tools-preview-enabled nil)
          ;; Disable tool confirmations for headless auto-workflow
          (_gptel-confirm-tool-calls nil)
         ;; Capture the experiment timeout lexically because later analyzer
         ;; callbacks run after this outer let frame exits.
         (experiment-timeout gptel-auto-experiment-time-budget)
           (run-id gptel-auto-workflow--run-id)
          ;; Switch World Store to experiment branch for isolated writes
          (_ws-branch-switch
           (when (and experiment-branch
                      (fboundp 'ov5-world-store-branch-switch))
             (condition-case ws-err
                 (ov5-world-store-branch-switch experiment-branch)
               (error
                (message "[world-store] Branch switch failed (non-fatal): %s"
                         (error-message-string ws-err))))))
          (_workflow-root (gptel-auto-workflow--resolve-run-root))
          (raw-callback callback)
           (result-callback-called nil)
          ;; TSP-inspired: capture risk nodes in target file so outcomes can be
          ;; correlated with fine-grained risk-node types.
          (risk-nodes (when (and target (fboundp 'gptel-auto-workflow--risk-node-types-in-file))
                        (let ((source (expand-file-name target experiment-worktree)))
                          (gptel-auto-workflow--risk-node-types-in-file source))))
           (callback (lambda (result)
                      (let ((enriched (if risk-nodes
                                          (append result (list :risk-nodes risk-nodes))
                                        result)))
                         (prog1 (funcall raw-callback enriched)
                           (setq result-callback-called t)))))
           ;; The subagent timeout wrapper owns executor timeout/abort behavior.
          (_my/gptel-agent-task-timeout experiment-timeout)
           (start-time (float-time))
           (finished nil)
           (provisional-commit-hash nil)
           (executor-prompt nil)
           (executor-callback nil)
           (effective-agent-output nil)
           (actual-backend nil)
           (actual-model nil)
           (candidate-validation nil)
           (repeated-focus nil)
           (duplicate-hypothesis nil)
           (pre-existing-breakage nil)
           (validation-retry-active nil)
           (grader-retry-active nil)
           (experiment-backend nil)
           (experiment-model nil)
            (launch-executor nil))
    (setq launch-executor
          (lambda ()
            (cond
             ((not (functionp executor-callback))
              (unless finished
                (setq finished t)
                (message "[auto-exp] Executor callback missing for %s experiment %d"
                         target experiment-id)
                (when (functionp callback)
                  (funcall callback
                           (list :target target :id experiment-id :kept nil
                                 :duration (- (float-time) start-time)
                                 :error "executor-callback-missing"
                                 :grader-reason "executor-callback-missing"
                                 :comparator-reason "executor-callback-missing"
                                 :backend (or experiment-backend "none")
                                 :model (or experiment-model "unknown"))))))
             ((or (not (stringp executor-prompt))
                  (= (length executor-prompt) 0))
              (unless finished
                (setq finished t)
                (message "[auto-exp] Executor prompt empty for %s experiment %d"
                         target experiment-id)
                (when (functionp callback)
                  (funcall callback
                           (list :target target :id experiment-id :kept nil
                                 :duration (- (float-time) start-time)
                                 :error "executor-prompt-empty"
                                 :grader-reason "executor-prompt-empty"
                                 :comparator-reason "executor-prompt-empty"
                                 :backend (or experiment-backend "none")
                                 :model (or experiment-model "unknown"))))))
             (t
              ;; Capture the backend and model that will actually be used by the
              ;; executor, including any subagent provider override.
              ;; Note: gptel-auto-workflow--get-active-agent-preset does not exist.
              ;; Use agent-base-preset + maybe-override-subagent-provider directly.
              ;; Wrap in condition-case: agent-base-preset calls into the ranked
              ;; backend chain which may fail if ontology hash tables are unbound.
              (condition-case err
                  (setq experiment-backend
                        (let* ((base-preset
                                (when (fboundp 'gptel-auto-workflow--agent-base-preset)
                                  (gptel-auto-workflow--agent-base-preset "executor")))
                               (override-preset
                                (when (and base-preset
                                           (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider))
                                  (gptel-auto-workflow--maybe-override-subagent-provider "executor" base-preset)))
                               (effective-preset (or override-preset base-preset))
                           (effective-backend
                            (or (and effective-preset
                                     (fboundp 'gptel-auto-workflow--preset-backend-name)
                                     (gptel-auto-workflow--preset-backend-name
                                      (plist-get effective-preset :backend)))
                                (and (boundp 'gptel-backend) gptel-backend
                                     (fboundp 'gptel-backend-name)
                                     (gptel-auto-workflow--safe-backend-name gptel-backend))
                                (and (boundp 'gptel-model) gptel-model
                                     (fboundp 'gptel-auto-workflow--backend-for-model)
                                     (gptel-auto-workflow--backend-for-model gptel-model))
                                "unknown")))
                          effective-backend))
                (error
                  (message "[auto-exp] Backend capture failed: %s" (error-message-string err))
                  (setq experiment-backend
                        (or (and (boundp 'gptel-backend) gptel-backend
                                 (fboundp 'gptel-backend-name)
                                 (gptel-auto-workflow--safe-backend-name gptel-backend))
                            (and (boundp 'gptel-model) gptel-model
                                 (fboundp 'gptel-auto-workflow--backend-for-model)
                                 (gptel-auto-workflow--backend-for-model gptel-model))
                            "unknown"))))
              (condition-case err
                  (setq experiment-model
                        (let* ((base-preset
                                (when (fboundp 'gptel-auto-workflow--agent-base-preset)
                                  (gptel-auto-workflow--agent-base-preset "executor")))
                               (override-preset
                                (when (and base-preset
                                           (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider))
                                  (gptel-auto-workflow--maybe-override-subagent-provider "executor" base-preset)))
                               (effective-preset (or override-preset base-preset))
                               (effective-model
                                (or (and (boundp 'gptel-model) gptel-model)
                                    (and effective-preset (plist-get effective-preset :model))
                                    "unknown")))
                          (if (stringp effective-model) effective-model
                            (format "%s" effective-model))))
                 (error
                  (message "[auto-exp] Model capture failed: %s" (error-message-string err))
                  (setq experiment-model
                        (and (boundp 'gptel-model) gptel-model
                             (symbol-name gptel-model)))))
               ;; Gap 2: Sync context window from backend registry for prefix-cache tracking
               (when (and experiment-backend experiment-model
                          (fboundp 'gptel-prefix-cache-sync-from-backend))
                 (condition-case err
                     (let ((backend-sym (intern experiment-backend))
                           (model-sym (intern experiment-model)))
                       (gptel-prefix-cache-sync-from-backend backend-sym model-sym))
                   (error
                    (message "[prefix-cache] Context window sync failed: %s"
                             (error-message-string err)))))
               ;; Layer 1 — Hard Block: Check action preconditions before execution
              (let ((precondition-error
                     (when (fboundp 'gptel-auto-workflow--check-action-preconditions)
                       (gptel-auto-workflow--check-action-preconditions target))))
                 (if precondition-error
                     (let ((default-directory experiment-worktree)
                           (precondition-result (list :target target :id experiment-id :kept nil
                                                     :duration (- (float-time start-time))
                                                     :grader-reason precondition-error
                                                     :comparator-reason "precondition-blocked")))
                        (message "[auto-exp] 🚫 %s" precondition-error)
                        (magit-git-success "checkout" "--" ".")
                        (setq finished t)
                        (funcall log-fn run-id precondition-result)
                        ;; Track token economics for this experiment
                        (when (fboundp 'gptel-token-economics--track-experiment)
                          (gptel-token-economics--track-experiment precondition-result))
                        (funcall callback precondition-result))
                  ;; Routing handled by gptel-auto-workflow--advice-task-override
                  (my/gptel--run-agent-tool-with-timeout
                   experiment-timeout
                   executor-callback
                   "executor"
                   (format "Experiment %d: optimize %s" experiment-id target)
                   executor-prompt
                   nil "false" nil)))))))
     (if (not worktree)
          (let ((worktree-fail-result (list :target target :id experiment-id :kept nil
                                           :error "Failed to create worktree" :backend "none")))
            (setq finished t)
            (funcall log-fn run-id worktree-fail-result)
            ;; Track token economics for this experiment
            (when (fboundp 'gptel-token-economics--track-experiment)
              (gptel-token-economics--track-experiment worktree-fail-result))
            (when (functionp callback)
              (funcall callback worktree-fail-result)))
      (gptel-auto-experiment--call-in-context
       experiment-buffer experiment-worktree
       (lambda ()
         (gptel-auto-experiment-analyze
          previous-results
          (lambda (analysis)
            (gptel-auto-experiment--call-in-context
             experiment-buffer experiment-worktree
             (lambda ()
                  (let* ((patterns (when (proper-list-p analysis) (plist-get analysis :patterns)))
                        ;; Select prompt-building strategy based on historical performance
                        (strategy-name (if (and (boundp 'gptel-auto-workflow--strategy-evolution-enabled)
                                                gptel-auto-workflow--strategy-evolution-enabled
                                                (fboundp 'gptel-auto-workflow--select-best-strategy))
                                           (let* ((selected (gptel-auto-workflow--select-best-strategy target))
                                                  (keep-rate (gptel-auto-experiment--target-keep-rate
                                                              target previous-results))
                                                  (tries-with-strategy
                                                   (gptel-auto-experiment--count-consecutive-strategy
                                                    target selected previous-results)))
                                             ;; Strategy rotation: if 0% keep-rate and same strategy
                                              ;; used 3+ times, force rotation to NEXT strategy
                                              ;; (not back to template-default — that creates a death spiral)
                                              (if (and keep-rate (= keep-rate 0.0)
                                                    (>= tries-with-strategy 3))
                                                   (let* ((all-strategies (if (fboundp 'gptel-auto-workflow--discover-strategies)
                                                                               (gptel-auto-workflow--discover-strategies)
                                                                             '("template-default")))
                                                          (other-strategies (cl-remove-if
                                                                             (lambda (s) (equal s selected))
                                                                             all-strategies))
                                                          (next-strategy (if other-strategies
                                                                             (nth (random (length other-strategies)) other-strategies)
                                                                           "template-default")))
                                                     (message "[strategy-rotate] ⚠ %s: 0%% keep-rate after %d× with %s — rotating to %s"
                                                              target tries-with-strategy selected next-strategy)
                                                     next-strategy)
                                               selected))
                                         "template-default"))
                        (strategy-prompt (when (and (fboundp 'gptel-auto-experiment-build-prompt-with-strategy)
                                                   (not (equal strategy-name "template-default")))
                                              (gptel-auto-experiment-build-prompt-with-strategy
                                               strategy-name target experiment-id max-experiments analysis baseline previous-results)))
                        (prompt (or gptel-auto-workflow--experiment-prompt-override
                                    (and (stringp strategy-prompt)
                                         (> (length strategy-prompt) 0)
                                         strategy-prompt)
                                    (gptel-auto-experiment-build-prompt
                                     target experiment-id max-experiments analysis baseline previous-results))))
                   (when (and (stringp prompt) (> (length prompt) 0))
                     (message "[strategy] Using strategy '%s' for %s experiment %d" strategy-name target experiment-id))
                  ;; Trace strategy execution
                  (when (fboundp 'gptel-auto-workflow--trace-strategy-execution)
                    (gptel-auto-workflow--trace-strategy-execution
                     strategy-name
                     target
                     (length prompt)
                       (and (boundp 'gptel-auto-workflow--last-prompt-sections)
                            (stringp gptel-auto-workflow--last-prompt-sections)
                            (not (string-empty-p gptel-auto-workflow--last-prompt-sections))
                            (split-string gptel-auto-workflow--last-prompt-sections ","))))
                   (setq executor-prompt prompt)
                    ;; Clear prompt override after consumption (one-shot mechanism)
                    (setq gptel-auto-workflow--experiment-prompt-override nil)
                   (unless (and (stringp prompt) (> (length prompt) 0))
                     (message "[auto-exp] ⚠ Empty prompt for %s experiment %d — skipping" target experiment-id)
                     (setq finished t)
                     (funcall callback
                              (list :target target :id experiment-id :kept nil
                                    :score-after 0
                                    :error "empty-prompt"))
                      (cl-return-from gptel-auto-experiment-run))
                (setq executor-callback
                      (lambda (agent-output)
                   (gptel-auto-experiment--call-in-context
                    experiment-buffer experiment-worktree
                    (lambda ()
                      (if (gptel-auto-experiment--stale-run-p run-id)
                        (unless finished
                          (setq finished t)
                          (message "[auto-experiment] Ignoring stale executor callback for %s experiment %d; run %s is no longer active"
                                   target experiment-id run-id)
                          (funcall callback
                                   (gptel-auto-experiment--stale-run-result
                                    target experiment-id)))
                      (let ((salvaged-agent-output
                             (gptel-auto-experiment--timeout-salvage-output
                              agent-output executor-prompt target experiment-worktree)))
                        (setq effective-agent-output
                              (or salvaged-agent-output agent-output)
                              ;; Capture actual backend AFTER executor completes.
                              ;; gptel-backend may have been dynamically rebound by
                              ;; cl-progv inside the subagent task override — after
                              ;; the callback runs, the global default (MiniMax) is
                              ;; restored. Fall back to the pre-computed
                              ;; experiment-backend when gptel-backend is MiniMax
                              ;; (the interactive default, not the routed one).
                               actual-backend
                               (or (and (boundp 'gptel-auto-experiment--last-subagent-backend)
                                        gptel-auto-experiment--last-subagent-backend)
                                   (let* ((post-backend (and (boundp 'gptel-backend) gptel-backend
                                                            (fboundp 'gptel-backend-name)
                                                            (gptel-auto-workflow--safe-backend-name gptel-backend)))
                                          (pre-backend (and (stringp experiment-backend)
                                                            experiment-backend))
                                          (global-default "MiniMax"))
                                     (if (and (stringp post-backend)
                                              (not (string= post-backend global-default)))
                                         post-backend
                                       (or pre-backend post-backend global-default))))
                               actual-model
                               (or (and (boundp 'gptel-auto-experiment--last-subagent-model)
                                        gptel-auto-experiment--last-subagent-model)
                                   (and (boundp 'gptel-model) gptel-model)
                                   experiment-model)
                              candidate-validation
                              (when (fboundp 'gptel-auto-experiment--batch-validate-candidates)
                                (condition-case err
                                    (gptel-auto-experiment--batch-validate-candidates
                                     effective-agent-output
                                     (expand-file-name target experiment-worktree))
                                  (error
                                   (message "[auto-exp] Candidate validation error: %s" err)
                                   nil)))
                              repeated-focus
                              (gptel-auto-experiment--repeated-focus-match
                               effective-agent-output previous-results target)
                              duplicate-hypothesis
                              (and previous-results
                                   (fboundp 'gptel-auto-experiment--hypothesis-already-tested-p)
                                   (gptel-auto-experiment--hypothesis-already-tested-p
                                    (gptel-auto-experiment--extract-hypothesis effective-agent-output)
                                    previous-results))
                              pre-existing-breakage
                              (gptel-auto-experiment--pre-existing-breakage-p target))
                           (when candidate-validation
                             (let* ((raw-best-score (plist-get (cdar candidate-validation) :score))
                                    (best-score (if (numberp raw-best-score) raw-best-score 0.0)))
                               (message "[auto-exp] Validated %d candidates for %s, best score: %.2f"
                                        (length candidate-validation) target best-score)))
                         (when salvaged-agent-output
                          (message "[auto-exp] Executor timed out after partial changes for %s; evaluating actual worktree diff"
                                   target))
                          (message "[auto-exp] Agent output (first 150 chars): %s"
                                   (my/gptel--sanitize-for-logging effective-agent-output 150))
                          ;; Parse reasoning patterns from this output for behavior learning
                          (let ((category
                                 (condition-case err
                                     (and target
                                          (fboundp 'gptel-auto-workflow--categorize-target)
                                          (gptel-auto-workflow--categorize-target target))
                                   (error
                                    (message "[auto-exp] Target categorization skipped after executor callback: %s"
                                             (my/gptel--sanitize-for-logging
                                              (error-message-string err) 200))
                                    nil))))
                            (when (and category (fboundp 'gptel-ai-behaviors--parse-reasoning))
                              (condition-case err
                                  (gptel-ai-behaviors--parse-reasoning
                                   effective-agent-output category)
                                (error
                                 (message "[auto-exp] Reasoning parse skipped after executor callback: %s"
                                          (my/gptel--sanitize-for-logging
                                           (error-message-string err) 200))))))
                          ;; Think-block intelligence: analyze agent reasoning for verdict
                          (unless (bound-and-true-p gptel-auto-experiment--think-intel)
                            (let ((intel
                                   (condition-case err
                                       (when (and effective-agent-output
                                                  (fboundp 'gptel-auto-experiment--analyze-agent-output))
                                         (gptel-auto-experiment--analyze-agent-output
                                          effective-agent-output))
                                     (error
                                      (message "[auto-exp] Think analysis skipped after executor callback: %s"
                                               (my/gptel--sanitize-for-logging
                                                (error-message-string err) 200))
                                      nil))))
                              (setq-local gptel-auto-experiment--think-intel intel)
                              ;; Feed verdict to ai-behaviors evolution for behavior optimization
                              (when intel
                                (let ((verdict (plist-get intel :verdict))
                                      (score (plist-get intel :score))
                                      (category (and target (fboundp 'gptel-auto-workflow--categorize-target)
                                                     (gptel-auto-workflow--categorize-target target))))
                                  (when (and category verdict)
                                    (message "[think-intel] %s|%s|%s|acts=%d|expl=%d|score=%.1f"
                                             (or category "unknown") (or target "unknown") (or verdict "none")
                                             (or (plist-get intel :acts) 0)
                                             (or (plist-get intel :explores) 0)
                                             (or score 0.0)))))))
                          (unless finished
                           (if duplicate-hypothesis
                               (let* ((hypothesis
                                       (gptel-auto-experiment--extract-hypothesis
                                        effective-agent-output))
                                      (reason
                                       (format "Duplicate hypothesis: \"%s\" — already tested on %s"
                                               (substring hypothesis 0 (min 60 (length hypothesis))) target))
                                      (exp-result
                                       (list :target target
                                             :id experiment-id
                                             :hypothesis hypothesis
                                             :score-before baseline
                                             :score-after 0
                                             :code-quality baseline-code-quality
                                             :kept nil
                                             :duration (- (float-time) start-time)
                                             :grader-quality 0
                                             :grader-reason reason
                                             :comparator-reason "duplicate-hypothesis"
                                                                        :analyzer-patterns (format "%s" patterns)
                                                                        :agent-output effective-agent-output
                                                                        :backend actual-backend
                                                                       :model actual-model
                                                                        :edit-mode (or (bound-and-true-p gptel-tools-edit--mode-used) "none")
                                                                        :skills (or (and gptel-auto-experiment--loaded-skills
                                                                                         (mapconcat #'identity
                                                                                                    (delete-dups gptel-auto-experiment--loaded-skills)
                                                                                                    " "))
                                                                                    (bound-and-true-p gptel-ai-behaviors--current-hashtags)
                                                                                    ""))))
                                 (setq finished t)
                                 (message "[auto-exp] ⏭ Duplicate hypothesis: %s"
                                          (substring hypothesis 0 (min 80 (length hypothesis))))
                                  (let ((default-directory experiment-worktree))
                                    (magit-git-success "checkout" "--" "."))
                                  (funcall log-fn run-id exp-result)
                                  ;; Track token economics for this experiment
                                  (when (fboundp 'gptel-token-economics--track-experiment)
                                    (gptel-token-economics--track-experiment exp-result))
                                  (funcall callback exp-result)))
                            (if repeated-focus
                              (let* ((hypothesis
                                      (gptel-auto-experiment--extract-hypothesis
                                       effective-agent-output))
                                     (symbol (plist-get repeated-focus :symbol))
                                     (count (plist-get repeated-focus :count))
                                     (reason
                                      (format "Repeated focus on `%s` after %d prior non-kept attempts; choose a different function or subsystem."
                                              symbol count))
                                      (exp-result
                                       (list :target target
                                             :id experiment-id
                                             :hypothesis hypothesis
                                             :score-before baseline
                                             :score-after 0
                                             :code-quality baseline-code-quality
                                             :kept nil
                                             :duration (- (float-time) start-time)
                                             :grader-quality 0
                                             :grader-reason reason
                                             :comparator-reason "repeated-focus-symbol"
                                             :analyzer-patterns (format "%s" patterns)
                                             :agent-output effective-agent-output
                                             :backend actual-backend
                          :model actual-model)))
                                (setq finished t)
                                (let ((default-directory experiment-worktree))
                                  (message "[auto-exp] Repeated focus on %s after %d prior non-kept attempts; discarding without grading"
                                           symbol count)
                                  (magit-git-success "checkout" "--" "."))
                                   (gptel-auto-experiment--increment-no-improvement-count)
                                   (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                     (gptel-auto-workflow--apply-category-vigilance target 'discarded))
                                   (funcall log-fn run-id exp-result)
                                   ;; Track token economics for this experiment
                                   (when (fboundp 'gptel-token-economics--track-experiment)
                                     (gptel-token-economics--track-experiment exp-result))
                                   (funcall callback exp-result))
                               ;; Agent error early abort: if executor returned a timeout/curl
                               ;; error, any partial file changes are corrupted. Revert and
                               ;; fail fast — don't waste 300s on a teachable retry.
                               ;; Setting finished=t skips validation, grade, and retry below.
                               (when (and (gptel-auto-experiment--agent-error-p effective-agent-output)
                                          (gptel-auto-experiment--executor-timeout-p effective-agent-output))
                                 (let ((default-directory experiment-worktree))
                                   (message "[auto-exp] ⏱ Executor timed out on %s experiment %d; reverting partial changes, failing fast"
                                            target experiment-id)
                                   (magit-git-success "checkout" "--" "."))
                                 (let ((error-result
                                        (list :target target
                                              :id experiment-id
                                              :hypothesis (gptel-auto-experiment--extract-hypothesis
                                                           effective-agent-output)
                                              :score-before baseline
                                              :score-after 0
                                              :code-quality baseline-code-quality
                                              :kept nil
                                              :duration (- (float-time) start-time)
                                              :grader-quality 0
                                              :grader-reason (format "executor-timeout: %s"
                                                                     (my/gptel--sanitize-for-logging
                                                                      effective-agent-output 200))
                                              :comparator-reason "executor-timeout"
                                              :analyzer-patterns (format "%s" patterns)
                                              :agent-output effective-agent-output
                                              :backend actual-backend
                                              :model actual-model)))
                                     (gptel-auto-experiment--increment-no-improvement-count)
                                    (funcall log-fn run-id error-result)
                                    ;; Track token economics for this experiment
                                    (when (fboundp 'gptel-token-economics--track-experiment)
                                      (gptel-token-economics--track-experiment error-result))
                                    (funcall callback error-result))
                                 (setq finished t))
                               ;; Validate syntax BEFORE calling grader to avoid wasting API calls
                               ;; Check ALL modified files, not just target — agent may edit dependencies
                                    (let ((validation-error
                                           (when target
                                             (or (gptel-auto-experiment--validate-all-modified-files experiment-worktree)
                                                 (gptel-auto-experiment--validate-code
                                                  (expand-file-name target experiment-worktree))
                                                 ;; Cheap diff content check — catches trivial/nonsense diffs
                                                 ;; before expensive grader call
                                                 (gptel-auto-experiment--validate-diff-content experiment-worktree))))
                                          (defer-grading nil))
                                  (when validation-error
                                    (progn
                                      (message "[auto-exp] ✗ Pre-grade validation failed: %s"
                                               (my/gptel--sanitize-for-logging validation-error 200))
                                     ;; Trigger retry or fail immediately without grader
                                        (let ((default-directory experiment-worktree)
                                              (_gptel-auto-experiment--grading-target target)
                                              (_gptel-auto-experiment--grading-worktree experiment-worktree))
                                        ;; Skip retry if file was already broken before experiment
                                        (when pre-existing-breakage
                                          (message "[auto-exp] ⚠ Pre-existing breakage detected for %s, skipping retry"
                                                   target))
                                        (if (and (gptel-auto-experiment--teachable-validation-error-p
                                                  target validation-error)
                                                 (not validation-retry-active)
                                                 (not pre-existing-breakage))
                                             (progn
                                               (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                               (setq defer-grading t)
                                               (gptel-auto-experiment--prepare-validation-retry-worktree
                                                target provisional-commit-hash)
                                              (setq provisional-commit-hash nil)
                                              (setq validation-retry-active t)
                                               (let* ((_gptel-auto-experiment-active-grace
                                                       gptel-auto-experiment-validation-retry-active-grace)
                                                      (retry-prompt
                                                       (if candidate-validation
                                                           (concat executor-prompt
                                                                   "\n\n## PREVIOUS ATTEMPT FAILED\n"
                                                                   "Validation error: " validation-error "\n"
                                                                   "Candidate validation results:\n"
                                                                   (mapconcat
                                                                    (lambda (pair)
                                                                      (format "- %s: score=%.1f, valid=%s"
                                                                              (substring (car pair) 0 (min 30 (length (car pair))))
                                                                              (let ((score (plist-get (cdr pair) :score)))
                                                                                (if (numberp score) score 0.0))
                                                                              (if (plist-get (cdr pair) :valid) "yes" "no")))
                                                                    candidate-validation
                                                                    "\n")
                                                                    "\n## Retry\n"
                                                                    "Validation failed. Use remaining candidate or fix error.\n\n"
                                                                    "λ ¬thrash: reads ≤ 2 → write_next | fix(specific) > re-read(all)"
                                                                    " | ∀cl-return-from: ∃cl-block ∧ name_match\n")
                                                            (concat executor-prompt
                                                                   "\n\nλ ¬thrash: reads ≤ 2 → write_next | fix(specific) > re-read(all)"
                                                                   " | ∀cl-return-from: ∃cl-block ∧ name_match\n"))))
                                                  (my/gptel--run-agent-tool-with-timeout
                                                  gptel-auto-experiment-validation-retry-time-budget
                                                  (lambda (retry-output)
                                                   (if (and (stringp retry-output)
                                                            (string-match-p "\\`Error:" retry-output))
                                                       ;; Retry failed: fail experiment immediately, skip grading/staging
                                                       (let* ((hypothesis
                                                               (gptel-auto-experiment--extract-hypothesis
                                                                effective-agent-output))
                                                              (retry-exp-result
                                                               (list :target target
                                                                     :id experiment-id
                                                                     :hypothesis hypothesis
                                                                     :score-before baseline
                                                                     :score-after 0
                                                                     :code-quality baseline-code-quality
                                                                     :kept nil
                                                                     :duration (- (float-time) start-time)
                                                                     :grader-quality 0
                                                                     :grader-reason (format "validation-retry-failed: %s"
                                                                                           retry-output)
                                                                     :comparator-reason "validation-retry-failed"
                                                                     :analyzer-patterns (format "%s" patterns)
                                                                     :agent-output effective-agent-output
                                                                     :validation-error validation-error
                                                                     :backend actual-backend
                          :model actual-model)))
                                                          (setq finished t)
                                                           (gptel-auto-experiment--increment-no-improvement-count)
                                                           (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                                             (gptel-auto-workflow--apply-category-vigilance target 'validation-failed))
                                                           (funcall log-fn run-id retry-exp-result)
                                                           ;; Track token economics for this experiment
                                                           (when (fboundp 'gptel-token-economics--track-experiment)
                                                             (gptel-token-economics--track-experiment retry-exp-result))
                                                           (funcall callback retry-exp-result))
                                                      ;; Retry succeeded: treat output as new executor output
                                                      (if (functionp executor-callback)
                                                          (funcall executor-callback retry-output)
                                                        (message "[auto-exp] exec-callback nil after retry, calling callback directly")
                                                        (funcall callback
                                                                 (list :target target :id experiment-id
                                                                       :kept nil :score-after 0
                                                                       :error "executor-callback-nil-after-retry")))))
                                                 "executor"
                                                 "Validation retry"
                                                 retry-prompt
                                                 nil nil nil
                                                   gptel-auto-experiment-validation-retry-active-grace)))
                                           ;; Non-teachable or already retrying: check if it's a hard block
                                           ;; CRITICAL / ARCHITECTURAL DESTRUCTION / SCOPE CREEP = fail immediately
                                           (if (and validation-error
                                                    (string-match-p "^\\(CRITICAL\\|ARCHITECTURAL DESTRUCTION\\|SCOPE CREEP\\):"
                                                                    validation-error))
                                               (progn
                                                 (message "[auto-exp] ✗ Hard-block validation: %s — failing immediately"
                                                          validation-error)
                                                 (setq finished t)
                                                 (let ((fail-result
                                                        (list :target target
                                                              :id experiment-id
                                                              :hypothesis (gptel-auto-experiment--extract-hypothesis
                                                                           effective-agent-output)
                                                              :score-before baseline
                                                              :score-after 0
                                                              :code-quality baseline-code-quality
                                                              :kept nil
                                                              :duration (- (float-time) start-time)
                                                              :grader-quality 0
                                                              :grader-reason validation-error
                                                              :comparator-reason "validation-hard-block"
                                                              :analyzer-patterns (format "%s" patterns)
                                                              :agent-output effective-agent-output
                                                              :validation-error validation-error
                                                              :backend actual-backend
                                                              :model actual-model)))
                                                    (funcall log-fn run-id fail-result)
                                                    ;; Track token economics for this experiment
                                                    (when (fboundp 'gptel-token-economics--track-experiment)
                                                      (gptel-token-economics--track-experiment fail-result))
                                                    (funcall callback fail-result)))
                                             ;; Record validation error for self-evolution
                                             (when (and target validation-error
                                                        (fboundp 'gptel-ai-behaviors--record-validation-error))
                                               (gptel-ai-behaviors--record-validation-error target validation-error))
                                             (message "[auto-exp] ⚠ Non-teachable validation: %s — grader will evaluate anyway"
                                                      validation-error))))))
                                    (unless defer-grading
                                      (let ((gptel-auto-experiment--grading-target target)
                                          (gptel-auto-experiment--grading-worktree experiment-worktree)
                                           (_gptel-auto-experiment--grading-hypothesis
                                            (gptel-auto-experiment--extract-hypothesis effective-agent-output)))
                                    (gptel-auto-experiment--grade-with-retry
                                effective-agent-output
                                (lambda (grade)
                                  (gptel-auto-experiment--call-in-context
                                   experiment-buffer experiment-worktree
                                   (lambda ()
                                     (if (gptel-auto-experiment--stale-run-p run-id)
                                       (unless finished
                                         (setq finished t)
                                         (message "[auto-experiment] Ignoring stale grader callback for %s experiment %d; run %s is no longer active"
                                                  target experiment-id run-id)
                                         (funcall callback
                                                  (gptel-auto-experiment--stale-run-result
                                                   target experiment-id)))
                                      (let* ((raw-grade-score (plist-get grade :score))
                                             (raw-grade-total (plist-get grade :total))
                                             (grade-score (if (numberp raw-grade-score) raw-grade-score 0))
                                             (grade-total (if (and (numberp raw-grade-total)
                                                                  (> raw-grade-total 0))
                                                              raw-grade-total
                                                            1))
                                             (grade-passed (eq (plist-get grade :passed) t))
                                              (grade-details (plist-get grade :details))
                                              (hypothesis (gptel-auto-experiment--extract-hypothesis effective-agent-output)))
                                        ;; Extract grader insights for self-evolution feedback
                                        (when (and target (stringp grade-details)
                                                   (fboundp 'gptel-auto-experiment--parse-grader-output))
                                          (gptel-auto-experiment--parse-grader-output target grade-details))
                                        (message "[auto-exp] Grade result: score=%s/%s passed=%s"
                                                 grade-score grade-total grade-passed)
                                       (when (and effective-agent-output (> (length effective-agent-output) 0))
                                         (message "[auto-exp] Agent preview: %s"
                                                  (my/gptel--sanitize-for-logging effective-agent-output 100)))
                                       ;; Check if grader passed
                                       (if (not grade-passed)
                                           ;; Grader failures should classify from grader details when
                                           ;; they carry the real transient/API error instead of the
                                           ;; executor's normal success output.
                                           (let* ((normal-grade-rejection
                                                   (gptel-auto-experiment--normal-grade-details-p
                                                    grade-details))
                                                  (grade-error-output
                                                   (and (not normal-grade-rejection)
                                                        (or (plist-get grade :error-source)
                                                            (gptel-auto-experiment--grade-failure-error-output
                                                             grade-details effective-agent-output))))
                                                  (error-source (and (not normal-grade-rejection)
                                                                     (or grade-error-output effective-agent-output)))
                                                  (error-info (and error-source
                                                                   (gptel-auto-experiment--categorize-error
                                                                    error-source)))
                                                  (error-category (car-safe error-info))
                                                  (grader-only-failure
                                                   (and (not normal-grade-rejection)
                                                        (plist-get grade :grader-only-failure)))
                                                  (exp-result
                                                   (let ((result (list :target target
                                                                       :id experiment-id
                                                                       :hypothesis hypothesis
                                                                       :score-before baseline
                                                                       :score-after 0
                                                                       :kept nil
                                                                       :duration (- (float-time) start-time)
                                                                       :grader-quality grade-score
                                                                       :grader-reason grade-details
                                                                       :comparator-reason
                                                                       (cond
                                                                        (normal-grade-rejection "grader-rejected")
                                                                        (grader-only-failure
                                                                         (gptel-auto-experiment--grader-only-error-label error-category))
                                                                        (t (symbol-name (or error-category :unknown))))
                                                                       :analyzer-patterns (format "%s" patterns)
                                                                       :agent-output effective-agent-output
                                                                       :backend actual-backend
                                                                       :model actual-model)))
                                                     (when grade-error-output
                                                       (setq result
                                                             (plist-put result :error grade-error-output)))
                                                     (when grader-only-failure
                                                       (setq result
                                                             (plist-put result :grader-only-failure t)))
                                                     result)))
                                              (setq finished t)
                                              ;; Grader rejection retry: specific feedback → one fix shot
                                              (if (and normal-grade-rejection
                                                       (not grader-retry-active)
                                                       (not pre-existing-breakage)
                                                       (stringp grade-details)
                                                       (> (length grade-details) 60))
                                                  (let ((default-directory experiment-worktree))
                                                    (message "[auto-exp] 🔄 Grader rejection retry: %s"
                                                             (my/gptel--sanitize-for-logging grade-details 200))
                                                    (setq grader-retry-active t finished nil)
                                                    (gptel-auto-experiment--prepare-validation-retry-worktree
                                                     target provisional-commit-hash)
                                                    (setq provisional-commit-hash nil)
                                                    (let* ((_gptel-auto-experiment-active-grace
                                                            gptel-auto-experiment-validation-retry-active-grace)
                                                           (retry-prompt
                                                            (concat executor-prompt
                                                                    "\n\n## PREVIOUS ATTEMPT REJECTED BY GRADER\n"
                                                                    "Grader feedback: " grade-details "\n\n"
                                                                    "λ fix(specific) > re-read(all) | ¬thrash\n"
                                                                    "Address each FAIL criterion.\n")))
                                                      (my/gptel--run-agent-tool-with-timeout
                                                       gptel-auto-experiment-validation-retry-time-budget
                                                       (lambda (retry-output)
                                                         (if (and (stringp retry-output)
                                                                  (string-match-p "\\`Error:" retry-output))
                                                             (progn
                                                               (setq finished t)
                                                                (message "[auto-exp] ✗ Grader retry failed")
                                                                (funcall log-fn run-id exp-result)
                                                                ;; Track token economics for this experiment
                                                                (when (fboundp 'gptel-token-economics--track-experiment)
                                                                  (gptel-token-economics--track-experiment exp-result))
                                                                (funcall callback exp-result))
                                                           (if (functionp executor-callback)
                                                               (funcall executor-callback retry-output)
                                                             (message "[auto-exp] exec-callback nil after grader retry")
                                                             (funcall callback
                                                                      (list :target target :id experiment-id
                                                                            :kept nil :score-after 0
                                                                            :error "executor-callback-nil-grader-retry")))))
                                                       "executor" "Grader rejection retry"
                                                       retry-prompt nil nil nil
                                                       gptel-auto-experiment-validation-retry-active-grace)))
                                                 ;; Non-teachable: fail normally
                                                   (funcall log-fn run-id exp-result)
                                                   ;; Track token economics for this experiment
                                                   (when (fboundp 'gptel-token-economics--track-experiment)
                                                     (gptel-token-economics--track-experiment exp-result))
                                                   (funcall callback exp-result))))
                                         (when grade-passed
                                           ;; Grader passed - create a provisional commit so the
                                           ;; benchmark/scope logic can diff against HEAD~1.
                                           (let ((default-directory experiment-worktree))
                                              (setq provisional-commit-hash
                                                    (gptel-auto-workflow--create-provisional-experiment-commit
                                                     target hypothesis
                                                     (gptel-auto-experiment--git-timeout))))
                                           (let* ((bench (gptel-auto-experiment-benchmark t hypothesis))
                                                  (passed (plist-get bench :passed))
                                                  (validation-error (plist-get bench :validation-error))
                                                  (tests-passed (plist-get bench :tests-passed))
                                                  (score-after (plist-get bench :eight-keys))
                                                  ;; When the grader passed but the structural eight-keys score
                                                  ;; is nil or near-zero, use the normalized grader score instead.
                                                  ;; This prevents valid changes from being rejected because
                                                   ;; the structural scorer failed to compute.
                                                   (effective-score
                                                    (let ((raw-score
                                                           (if (and grade-passed
                                                                    (or (null score-after) (< score-after 0.1))
                                                                    grade-score grade-total (> grade-total 0))
                                                               (/ (float grade-score) grade-total)
                                                             (or score-after 0))))
                                                      (if (fboundp 'gptel-auto-workflow--weight-score-with-production-metrics)
                                                          (gptel-auto-workflow--weight-score-with-production-metrics raw-score target)
                                                        raw-score))))
                                                   (message "[auto-experiment] DEBUG benchmark: passed=%s tests-passed=%s validation-error=%s nucleus-passed=%s debug=%s eight-keys=%s→%s"
                                                             passed tests-passed validation-error (plist-get bench :nucleus-passed) (plist-get bench :debug-info)
                                                             score-after effective-score)
                                             (if (or passed
                                                     (and effective-score
                                                          (> effective-score baseline)))
                                                (let
 	                                               ((code-quality
 	                                                 (or (gptel-auto-experiment--code-quality-score) 0.5)))
                                                  (gptel-auto-experiment-decide
                                                   (list :score baseline :code-quality baseline-code-quality)
                                                   (list :score effective-score :code-quality code-quality :output
 	                                                    effective-agent-output)
                                                  (lambda (decision)
	                                                (unless finished
	                                                  (setq finished t)
	                                                  (let*
	                                                      ((decision
	                                                        (gptel-auto-experiment--promote-correctness-fix-decision
	                                                         decision
	                                                         tests-passed
	                                                         grade-score
	                                                         grade-total
	                                                         grade-details
	                                                         hypothesis))
                                                      (keep (plist-get decision :keep))
                                                      (reasoning (plist-get decision :reasoning))
                                                      ;; Gate 3.5: Complexity gate
                                                      (complexity-metrics
                                                       (when (and keep (fboundp 'gptel-benchmark--calculate-complexity-before-after))
                                                         (gptel-benchmark--calculate-complexity-before-after
                                                          (list :target target :agent-output effective-agent-output))))
                                                      (complexity-passed
                                                       (if (and keep complexity-metrics)
                                                           (let ((penalty (gptel-benchmark--complexity-penalty
                                                                          (plist-get complexity-metrics :complexity-before)
                                                                          (plist-get complexity-metrics :complexity-after))))
                                                             (>= penalty 0.5))
                                                         t))
                                                      (keep (if complexity-passed keep nil))
                                                      (reasoning (if complexity-passed
                                                                     reasoning
                                                                   (concat reasoning "\n[Complexity Gate] Experiment rejected: complexity increased beyond
threshold.")))
                                                      (exp-result
												    (list :target target :id experiment-id :hypothesis
												          hypothesis :score-before baseline :score-after
												          effective-score :code-quality code-quality :kept
												          keep :duration (- (float-time) start-time)
												          :grader-quality grade-score :grader-reason
												          (plist-get grade :details) :comparator-reason
												          reasoning :analyzer-patterns
												          (format "%s" patterns) :agent-output
												          effective-agent-output
                          :backend actual-backend
                           :model actual-model
                           :edit-mode (or (bound-and-true-p gptel-tools-edit--mode-used) "none")
                            :skills (or (and gptel-auto-experiment--loaded-skills
                                            (mapconcat #'identity
                                                       (delete-dups gptel-auto-experiment--loaded-skills)
                                                       " "))
                                       (bound-and-true-p gptel-ai-behaviors--current-hashtags)
                                       "")
                           :prompt-chars (length executor-prompt)
                          :output-chars (length (or effective-agent-output ""))
                          :input-tokens (/ (length executor-prompt) 4.0)
                          :output-tokens (/ (length (or effective-agent-output "")) 4.0)
                          :category (or (and (fboundp 'gptel-auto-workflow--categorize-target)
                                             (gptel-auto-workflow--categorize-target target))
                                        :unknown)
                           :decision (if keep "kept" "discarded")
                           :complexity-before (or (plist-get complexity-metrics :complexity-before) 0)
                           :complexity-after (or (plist-get complexity-metrics :complexity-after) 0)
                           :prompt-structure (gptel-auto-experiment--prompt-structure-score executor-prompt)
                           :kibcm-axis (gptel-auto-experiment--kibcm-axis hypothesis)
                          :sections-included (or (and (boundp 'gptel-auto-workflow--last-prompt-sections)
                                                      gptel-auto-workflow--last-prompt-sections)
                                                "all")
                          :exploration-axis (gptel-auto-experiment--extract-axis effective-agent-output)
                           :candidate-validation (when candidate-validation
                                                   (mapcar (lambda (pair)
                                                             (list (car pair)
                                                                    :score (let ((score (plist-get (cdr pair) :score)))
                                                                             (if (numberp score) score 0.0))
                                                                    :valid (plist-get (cdr pair) :valid)))
                                                           candidate-validation))
                           :strategy strategy-name
                           :research-strategy (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                                       (plist-get gptel-auto-workflow--current-research-context :strategy))
                                                  "none")
                            :research-hash (let ((ctx-hash (and (boundp 'gptel-auto-workflow--current-research-context)
                                                                 (plist-get gptel-auto-workflow--current-research-context :hash))))
                                             (if (and ctx-hash (not (equal ctx-hash "none")))
                                                 ctx-hash
                                               ;; ASSUMPTION: missing research context is a pipeline defect
                                               ;; BEHAVIOR: generate traceable fallback hash so AutoTTS can link
                                               ;; EDGE CASE: hash is always non-empty so feedback loop is preserved
                                               (prog1 (sha1 (format "pipeline-defect-%s-%s" target (format-time-string "%s")))
                                                 (message "[auto-workflow] WARNING: pipeline defect - no research context for %s, using
fallback hash" (or target "unknown")))))
                            :research-quality (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                                       (plist-get gptel-auto-workflow--current-research-context :source))
                                                   "none")
                             :eight-keys-scores (plist-get bench :eight-keys-scores))))
	                                                    (if keep
		                                                    (let* ((msg
			                                                        (format
			                                                         "◈ Optimize %s: %s\n\nHYPOTHESIS: %s\n\nEVIDENCE: Nucleus valid, tests in staging\nScore: %.2f → %.2f (+%.0f%%)"
			                                                         target
			                                                         (gptel-auto-experiment--summarize hypothesis)
			                                                         hypothesis baseline score-after
			                                                         (if (> baseline 0)
			                                                             (* 100
				                                                            (/ (- score-after baseline) baseline))
			                                                           0)))
					                                                       (default-directory experiment-worktree)
					                                                       (commit-timeout
					                                                        (gptel-auto-experiment--git-timeout))
			                                                       (finalize
			                                                        (gptel-auto-experiment--make-kept-result-callback
			                                                         run-id exp-result log-fn callback)))
		                                                      (gptel-auto-workflow--assert-main-untouched)
		                                                      (message "[auto-experiment] ✓ Committing improvement for %s" target)
		                                                      (message "[auto-exp] About to stage and commit (auto-push=%s, use-staging=%s)"
		                                                               gptel-auto-experiment-auto-push
		                                                               gptel-auto-workflow-use-staging)
		                                                      (if (and (gptel-auto-workflow--stage-worktree-changes
			                                                            (format "Stage experiment changes for %s" target)
			                                                            60)
			                                                           (gptel-auto-workflow--promote-provisional-commit
			                                                            msg
			                                                            (format "Commit experiment changes for %s" target)
			                                                            provisional-commit-hash
			                                                            commit-timeout))
                                                          (progn
                                                        (setq provisional-commit-hash nil)
                                                        (gptel-auto-workflow--track-commit experiment-id
								                                           target
								                                           experiment-worktree)
                                                        (gptel-auto-experiment--maybe-log-staging-pending
								                                     run-id exp-result log-fn)
                                                        (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                                          (gptel-auto-workflow--apply-category-vigilance target 'kept))
                                                        ;; π Synthesis: queue similar targets with inherited strategy
                                                        (when (fboundp 'gptel-auto-workflow--queue-cluster-experiments)
                                                          (gptel-auto-workflow--queue-cluster-experiments target))
                                                         (setq gptel-auto-experiment--best-score score-after
                                                               gptel-auto-experiment--no-improvement-count 0)
                                                         (message "[auto-exp] Commit successful, proceeding with push/staging")
                                                        ;; QUARANTINE: do not push optimize branches to origin until
                                                        ;; staging verification has passed.  If staging is disabled, push
                                                        ;; is blocked entirely to prevent unreviewed optimize branches
                                                        ;; from leaking to the shared remote.
                                                        (if gptel-auto-workflow-use-staging
                                                            (if gptel-auto-experiment-auto-push
                                                                (progn
                                                                  (message "[auto-experiment] Pushing to %s" experiment-branch)
                                                                  (if (gptel-auto-workflow--push-branch-with-lease
                                                                       experiment-branch
                                                                       (format "Push optimize branch %s" experiment-branch)
                                                                       180)
                                                                      (gptel-auto-workflow--staging-flow
                                                                       experiment-branch
                                                                       finalize)
                                                                    (let ((failed-result
                                                                           (plist-put (copy-sequence exp-result)
                                                                                      :comparator-reason
                                                                                      "optimize-push-failed")))
                                                                      (setq failed-result (plist-put failed-result :kept nil))
                                                                      (funcall log-fn run-id failed-result)
                                                                      ;; Track token economics for this experiment
                                                                      (when (fboundp 'gptel-token-economics--track-experiment)
                                                                        (gptel-token-economics--track-experiment failed-result))
                                                                      (funcall callback failed-result))))
                                                              (funcall finalize))
                                                          (let ((failed-result
                                                                 (plist-put (copy-sequence exp-result)
                                                                            :comparator-reason
                                                                            "staging-disabled-push-blocked")))
                                                            (setq failed-result (plist-put failed-result :kept nil))
                                                            (message "[auto-experiment] ✗ Push blocked for %s: staging is disabled" experiment-branch)
                                                            (funcall log-fn run-id failed-result)
                                                            (when (fboundp 'gptel-token-economics--track-experiment)
                                                              (gptel-token-economics--track-experiment failed-result))
                                                            (funcall callback failed-result))))
		                                                        (let ((failed-result
			                                                           (plist-put (copy-sequence exp-result)
				                                                                  :comparator-reason
				                                                                  "experiment-commit-failed")))
		                                                          (gptel-auto-workflow--drop-provisional-commit
			                                                       provisional-commit-hash
			                                                       (format "Drop provisional commit for %s" target))
		                                                          (setq provisional-commit-hash nil)
		                                                          (setq failed-result (plist-put failed-result :kept nil))
		                                                          (funcall log-fn run-id failed-result)
		                                                          ;; Track token economics for this experiment
		                                                          (when (fboundp 'gptel-token-economics--track-experiment)
		                                                            (gptel-token-economics--track-experiment failed-result))
		                                                          (funcall callback failed-result))))
	                                                      (let ((default-directory experiment-worktree))
		                                                    (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
		                                                    (magit-git-success "checkout" "--" ".")
		                                                    (gptel-auto-workflow--drop-provisional-commit
		                                                     provisional-commit-hash
		                                                     (format "Discard provisional commit for %s" target))
		                                                    (setq provisional-commit-hash nil)
		                                                    (gptel-auto-experiment--increment-no-improvement-count)
		                                                    (funcall log-fn
			                                                         run-id exp-result)
		                                                    ;; Track token economics for this experiment
		                                                    (when (fboundp 'gptel-token-economics--track-experiment)
		                                                      (gptel-token-economics--track-experiment exp-result))
																(funcall callback exp-result)))))))))
                                              (if (and (gptel-auto-experiment--teachable-validation-error-p
                                                       target validation-error)
                                                      (not (bound-and-true-p gptel-auto-experiment--in-retry)))
                                                 (let ((default-directory experiment-worktree)
                                                       (gptel-auto-experiment--in-retry t))
                                                   (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                                   (message "[auto-experiment] ✗ %s"
                                                            (my/gptel--sanitize-for-logging validation-error 200))
                                                   (gptel-auto-experiment--prepare-validation-retry-worktree
                                                    target provisional-commit-hash)
                                                   (setq provisional-commit-hash nil)
                                                   (let ((gptel-auto-experiment-active-grace
                                                          gptel-auto-experiment-validation-retry-active-grace))
                                                     (my/gptel--run-agent-tool-with-timeout
                                                      gptel-auto-experiment-validation-retry-time-budget
                                                      (lambda (retry-output)
                                                        (let ((gptel-auto-experiment--grading-target target)
                                                              (gptel-auto-experiment--grading-worktree experiment-worktree))
                                                          (gptel-auto-experiment--grade-with-retry
                                                           retry-output
                                                           (lambda (retry-grade)
                                                              (if (plist-get retry-grade :passed)
                                                                   (let* ((retry-hypothesis
                                                                           (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                          (retry-bench (gptel-auto-experiment-benchmark t retry-hypothesis)))
                                                                     (if (plist-get retry-bench :passed)
                                                                         (let* ((retry-score (plist-get retry-bench :eight-keys))
                                                                                (retry-quality
                                                                                 (or (gptel-auto-experiment--code-quality-score) 0.5))
                                                                                ;; Same eight-keys → grader fallback as initial path
                                                                                (effective-retry-score
                                                                                 (if (and (plist-get retry-grade :passed)
                                                                                          (or (null retry-score) (< retry-score 0.1))
                                                                                          (plist-get retry-grade :score)
                                                                                          (plist-get retry-grade :total)
                                                                                          (> (plist-get retry-grade :total) 0))
                                                                                     (/ (float (plist-get retry-grade :score))
                                                                                        (plist-get retry-grade :total))
                                                                                   (or retry-score 0))))
                                                                          (message "[auto-experiment] ✓ Retry succeeded (eight-keys=%s→%s)"
                                                                                   retry-score effective-retry-score)
                                                                          (gptel-auto-experiment-decide
                                                                           (list :score baseline
                                                                                 :code-quality baseline-code-quality)
                                                                           (list :score effective-retry-score
                                                                                 :code-quality retry-quality
                                                                                 :output retry-output)
                                                                           (lambda (decision)
                                                                             (unless finished
                                                                               (setq finished t)
 		                                                                      (let* ((decision
 		                                                                              (gptel-auto-experiment--promote-correctness-fix-decision
 		                                                                               decision
 		                                                                               (plist-get retry-bench :tests-passed)
 		                                                                               (plist-get retry-grade :score)
 		                                                                               (plist-get retry-grade :total)
 		                                                                               (plist-get retry-grade :details)
 		                                                                               retry-hypothesis))
 		                                                                             (keep (plist-get decision :keep))
 		                                                                             (reasoning (plist-get decision :reasoning))
                                                                                              (exp-result
                                                                                               (list :target target
                                                                                              :id experiment-id
                                                                                              :hypothesis retry-hypothesis
                                                                                              :score-before baseline
                                                                                              :score-after effective-retry-score
                                                                                             :code-quality retry-quality
                                                                                             :validation-retry t
                                                                                             :kept keep
                                                                                             :duration (- (float-time) start-time)
                                                                                             :grader-quality (plist-get retry-grade :score)
                                                                                             :grader-reason (plist-get retry-grade :details)
                                                                                             :comparator-reason reasoning
                                                                                             :analyzer-patterns (format "%s" patterns)
                                                                                             :agent-output retry-output
                                                                                             :retries 1
                          :backend actual-backend
                          :model actual-model
                                                                                             :prompt-chars (length executor-prompt)
                           :output-chars (length (or effective-agent-output ""))
                                                                                             :prompt-structure (gptel-auto-experiment--prompt-structure-score executor-prompt)
                           :kibcm-axis (gptel-auto-experiment--kibcm-axis hypothesis)
                                                                                             :exploration-axis (gptel-auto-experiment--extract-axis retry-output)
                                                                                              :candidate-validation (when candidate-validation
                                                                                                                      (mapcar (lambda (pair)
                                                                                                                                (list (car pair)
                                                                                                                                      :score (let ((score (plist-get (cdr pair) :score)))
                                                                                                                                                (if (numberp score) score 0.0))
                                                                                                                                       :valid (plist-get (cdr pair) :valid)))
                                                                                                                              candidate-validation))
                                                                                               :strategy strategy-name)))
                                                                                  (if keep
                                                                                    (let* ((msg (format "◈ Retry: fix validation in %s"
								                                                                        target))
							                                                       (default-directory experiment-worktree)
							                                                       (commit-timeout
							                                                        (gptel-auto-experiment--git-timeout))
									                                                       (finalize
									                                                        (gptel-auto-experiment--make-kept-result-callback
									                                                         run-id exp-result log-fn callback)))
								                                                      (gptel-auto-workflow--assert-main-untouched)
								                                                      (if (and (gptel-auto-workflow--stage-worktree-changes
									                                                            (format "Stage retry changes for %s" target)
									                                                            60)
									                                                           (gptel-auto-workflow--promote-provisional-commit
									                                                            msg
									                                                            (format "Commit retry changes for %s" target)
									                                                            provisional-commit-hash
									                                                            commit-timeout))
						                                                      (progn
		                                                        (setq provisional-commit-hash nil)
		                                                        (gptel-auto-workflow--track-commit experiment-id
							                                                                               target
							                                                                               experiment-worktree)
                                                                                            (gptel-auto-experiment--maybe-log-staging-pending
                                                                                             run-id exp-result log-fn)
                                                                                            (setq gptel-auto-experiment--best-score retry-score
                                                                                                  gptel-auto-experiment--no-improvement-count 0)
                                                                                            (if gptel-auto-experiment-auto-push
                                                                                                (progn
                                                                                                  (message "[auto-experiment] Pushing to %s" experiment-branch)
                                                                                                  (if (gptel-auto-workflow--push-branch-with-lease
                                                                                                       experiment-branch
                                                                                                       (format "Push optimize branch %s" experiment-branch)
                                                                                                       180)
                                                                                                      (if gptel-auto-workflow-use-staging
                                                                                                          (gptel-auto-workflow--staging-flow
                                                                                                           experiment-branch
                                                                                                           finalize)
                                                                                                        (funcall finalize))
                                                                                                    (let ((failed-result
                                                                                                           (plist-put (copy-sequence exp-result)
                                                                                                                      :comparator-reason
                                                                                                                      "retry-push-failed")))
                                                                                                       (setq failed-result (plist-put failed-result :kept nil))
                                                                                                       (funcall log-fn run-id failed-result)
                                                                                                       ;; Track token economics for this experiment
                                                                                                       (when (fboundp 'gptel-token-economics--track-experiment)
                                                                                                         (gptel-token-economics--track-experiment failed-result))
                                                                                                       (funcall callback failed-result))))
                                                                                              (funcall finalize)))
								                                                        (let ((failed-result
									                                                           (plist-put (copy-sequence exp-result)
											                                                              :comparator-reason
											                                                              "retry-commit-failed")))
									                                                      (gptel-auto-workflow--drop-provisional-commit
									                                                       provisional-commit-hash
									                                                       (format "Drop provisional commit for %s" target))
									                                                      (setq provisional-commit-hash nil)
									                                                      (setq failed-result (plist-put failed-result :kept nil))
									                                                      (funcall log-fn run-id failed-result)
									                                                      ;; Track token economics for this experiment
									                                                      (when (fboundp 'gptel-token-economics--track-experiment)
									                                                        (gptel-token-economics--track-experiment failed-result))
									                                                      (funcall callback failed-result))))
							                                                      (let ((default-directory experiment-worktree))
								                                                    (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
								                                                    (magit-git-success "checkout" "--" ".")
								                                                    (gptel-auto-workflow--drop-provisional-commit
								                                                     provisional-commit-hash
								                                                     (format "Discard provisional commit for %s" target))
								                                                    (setq provisional-commit-hash nil)
				                                                    (gptel-auto-experiment--increment-no-improvement-count)
								                                                    (funcall log-fn
									                                                         run-id exp-result)
                                                                                    (funcall callback exp-result))))))))
                                                                     (setq finished t)
                                                                     (message "[auto-experiment] ✗ Retry still failed validation")
                                                                     (let* ((retry-hypothesis
                                                                             (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                            (retry-validation-error
                                                                             (plist-get retry-bench :validation-error))
                                                                            (retry-tests-passed
                                                                             (plist-get retry-bench :tests-passed))
                                                                            (reason
                                                                             (cond
                                                                              (retry-validation-error retry-validation-error)
                                                                              ((not (plist-get retry-bench :nucleus-passed))
                                                                               "nucleus-validation-failed")
                                                                              ((not retry-tests-passed)
                                                                               "tests-failed")
                                                                              (t "verification-failed")))
                                                                            (exp-result
                                                                             (list :target target
                                                                                   :id experiment-id
                                                                                   :hypothesis retry-hypothesis
                                                                                   :score-before baseline
                                                                                   :score-after 0
                                                                                   :validation-retry t
                                                                                   :kept nil
                                                                                   :duration (- (float-time) start-time)
                                                                                   :grader-quality (plist-get retry-grade :score)
                                                                                   :grader-reason (plist-get retry-grade :details)
                                                                                   :comparator-reason reason
                                                                                   :analyzer-patterns (format "%s" patterns)
                                                                                   :agent-output retry-output
                                                                                    :retries 1
                                                                                    :validation-error retry-validation-error
                                                                                    :backend actual-backend
                          :model actual-model)))
                                                                       (funcall log-fn
                                                                                run-id exp-result)
                                                                       (gptel-auto-workflow--drop-provisional-commit
                                                                        provisional-commit-hash
                                                                        (format "Drop provisional commit for %s" target))
                                                                       (setq provisional-commit-hash nil)
                                                                       (funcall callback exp-result))))
                                                               (setq finished t)
                                                               (let* ((retry-hypothesis
                                                                       (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                      (retry-grade-details
                                                                       (plist-get retry-grade :details))
                                                                      (normal-grade-rejection
                                                                       (gptel-auto-experiment--normal-grade-details-p
                                                                        retry-grade-details))
                                                                      (retry-grade-error-output
                                                                       (and (not normal-grade-rejection)
                                                                            (or (plist-get retry-grade :error-source)
                                                                                (gptel-auto-experiment--grade-failure-error-output
                                                                                 retry-grade-details retry-output))))
                                                                      (grader-only-failure
                                                                       (and (not normal-grade-rejection)
                                                                            (or (plist-get retry-grade :grader-only-failure)
                                                                                (gptel-auto-experiment--grader-only-failure-p
                                                                                 retry-output retry-grade-error-output))))
                                                                      (retry-error-category
                                                                       (and retry-grade-error-output
                                                                            (car (gptel-auto-experiment--categorize-error
                                                                                  retry-grade-error-output))))
                                                                      (reason
                                                                       (if retry-grade-error-output
                                                                           (if grader-only-failure
                                                                               (gptel-auto-experiment--grader-only-error-label
                                                                                retry-error-category)
                                                                             (symbol-name (or retry-error-category :unknown)))
                                                                         "retry-grade-rejected"))
                                                                      (exp-result
                                                                       (list :target target
                                                                             :id experiment-id
                                                                             :hypothesis retry-hypothesis
                                                                             :score-before baseline
                                                                             :score-after 0
                                                                             :validation-retry t
                                                                             :kept nil
                                                                             :duration (- (float-time) start-time)
                                                                             :grader-quality (plist-get retry-grade :score)
                                                                             :grader-reason retry-grade-details
                                                                             :comparator-reason reason
                                                                             :analyzer-patterns (format "%s" patterns)
                                                                              :agent-output retry-output
                                                                              :retries 1
                                                                              :backend actual-backend
                          :model actual-model)))
                                                                 (when retry-grade-error-output
                                                                   (setq exp-result
                                                                         (plist-put exp-result :error retry-grade-error-output)))
                                                                 (when grader-only-failure
                                                                   (setq exp-result
                                                                         (plist-put exp-result :grader-only-failure t)))
                                                                 (funcall log-fn
                                                                          run-id exp-result)
                                                                 (gptel-auto-workflow--drop-provisional-commit
                                                                  provisional-commit-hash
                                                                  (format "Drop provisional commit for %s" target))
                                                                 (setq provisional-commit-hash nil)
                                                                 (funcall callback exp-result)))))))
                                                      "executor"
                                                      (format "Retry: fix validation error in %s" target)
                                                      (gptel-auto-experiment--make-retry-prompt
                                                       target validation-error executor-prompt)
								   nil "false" nil
								   gptel-auto-experiment-validation-retry-active-grace)))
                                               (let ((default-directory experiment-worktree))
                                                   ;; NOTE: _grade-genuine dummy bindings preserve
                                                   ;; the paren balance of the original let* after
                                                   ;; the grade-genuine-p check was extracted into
                                                   ;; `gptel-auto-experiment--grader-bypass-p'.
                                                   (let* ((_grade-genuine nil)
                                                          (_grade-genuine2 nil)
                                                          (grader-bypass
                                                           (gptel-auto-experiment--grader-bypass-p
                                                            grade-passed grade-score grade-total grade bench
                                                            validation-error tests-passed))
                                                          (reason
                                                           (if grader-bypass
                                                               (format "grader-bypass:%s"
                                                                       "benchmark failed but genuine grader passed strongly")
                                                             (cond (validation-error validation-error)
                                                                   ((not tests-passed) "tests-failed")
                                                                   ((not (plist-get bench :nucleus-passed))
                                                                    "nucleus-validation-failed")
                                                                   (t "verification-failed"))))
                                                         (exp-result
                                                          (list :target target
                                                                :id experiment-id
                                                                :hypothesis hypothesis
                                                                :score-before baseline
                                                                :score-after (if grader-bypass (/ (float grade-score) grade-total) 0)
                                                                :kept (and grader-bypass t)
                                                                :duration (- (float-time) start-time)
                                                                :grader-quality grade-score
                                                                :grader-reason (plist-get grade :details)
                                                                :comparator-reason reason
                                                                :analyzer-patterns (format "%s" patterns)
                                                                :agent-output agent-output
                                                                :backend actual-backend
                                                                :model actual-model
                                                                :prompt-chars (length executor-prompt)
                                                                :output-chars (length (or effective-agent-output ""))
                                                                  :prompt-structure (gptel-auto-experiment--prompt-structure-score executor-prompt)
                                                                  :kibcm-axis (gptel-auto-experiment--kibcm-axis hypothesis))))
                                                    ;; Don't discard changes when grader bypasses
                                                     (if grader-bypass
                                                         (let* ((msg (format "◈ Grader-bypass %s: %.2f → %.2f (+%.0f%%)"
                                                                              target baseline
                                                                              (/ (float grade-score) grade-total)
                                                                              (if (> baseline 0)
                                                                                  (* 100 (/ (- (/ (float grade-score) grade-total) baseline) baseline))
                                                                                0)))
                                                                (finalize (gptel-auto-experiment--make-kept-result-callback
                                                                           run-id exp-result log-fn callback)))
                                                           (message "[auto-experiment] ✓ grader-bypass committing changes for %s"
                                                                    target)
                                                             (gptel-auto-workflow--assert-main-untouched)
                                                              (let ((commit-ok
                                                                     (or
                                                                      ;; Attempt 1: promote provisional commit
                                                                      (and (gptel-auto-workflow--stage-worktree-changes "Stage grader-bypass" 60)
                                                                           (gptel-auto-workflow--promote-provisional-commit
                                                                            msg "Commit grader-bypass" provisional-commit-hash
                                                                            (gptel-auto-experiment--git-timeout)))
                                                                      ;; Attempt 2: fresh stage + commit (provisional hash mismatch retry)
                                                                      (progn
                                                                        (message "[auto-experiment] Retrying grader-bypass commit for %s with fresh stage" target)
                                                                        (and (gptel-auto-workflow--stage-worktree-changes "Stage grader-bypass retry" 60)
                                                                             (gptel-auto-workflow--promote-provisional-commit
                                                                              msg "Commit grader-bypass retry" nil
                                                                              (gptel-auto-experiment--git-timeout)))))))
                                                               (if commit-ok
                                                                   (progn
                                                                     (setq provisional-commit-hash nil)
                                                                     (gptel-auto-workflow--track-commit experiment-id target experiment-worktree)
                                                                     (gptel-auto-experiment--maybe-log-staging-pending run-id exp-result log-fn)
                                                                     (when (fboundp 'gptel-auto-workflow--apply-category-vigilance)
                                                                       (gptel-auto-workflow--apply-category-vigilance target 'kept))
                                                                     (setq gptel-auto-experiment--best-score
                                                                           (/ (float grade-score) grade-total)
                                                                           gptel-auto-experiment--no-improvement-count 0)
                                                                     (if gptel-auto-workflow-use-staging
                                                                     (if gptel-auto-experiment-auto-push
                                                                         (if (gptel-auto-workflow--push-branch-with-lease
                                                                              experiment-branch "Push grader-bypass" 180)
                                                                             (gptel-auto-workflow--staging-flow experiment-branch finalize)
                                                                           (let ((failed (plist-put (copy-sequence exp-result) :comparator-reason "grader-bypass-push-failed")))
                                                                             (setq failed (plist-put failed :kept nil))
                                                                             (funcall log-fn run-id failed)
                                                                             ;; Track token economics for this experiment
                                                                             (when (fboundp 'gptel-token-economics--track-experiment)
                                                                               (gptel-token-economics--track-experiment failed))
                                                                             (funcall callback failed)))
                                                                       (funcall finalize))
                                                                   (let ((failed (plist-put (copy-sequence exp-result)
                                                                                           :comparator-reason "staging-disabled-grader-bypass-push-blocked")))
                                                                     (setq failed (plist-put failed :kept nil))
                                                                     (message "[auto-experiment] ✗ Grader-bypass push blocked for %s: staging is disabled" experiment-branch)
                                                                     (funcall log-fn run-id failed)
                                                                     (when (fboundp 'gptel-token-economics--track-experiment)
                                                                       (gptel-token-economics--track-experiment failed))
                                                                     (funcall callback failed))))
                                                                 (let ((failed (plist-put (copy-sequence exp-result)
                                                                                          :comparator-reason
                                                                                          (if stage-ok
                                                                                              "grader-bypass-promote-failed"
                                                                                            "grader-bypass-stage-failed"))))
                                                                   (gptel-auto-workflow--drop-provisional-commit provisional-commit-hash "Drop grader-bypass")
                                                                   (setq provisional-commit-hash nil)
                                                                   (setq failed (plist-put failed :kept nil))
                                                                   (funcall log-fn run-id failed)
                                                                   ;; Track token economics for this experiment
                                                                   (when (fboundp 'gptel-token-economics--track-experiment)
                                                                     (gptel-token-economics--track-experiment failed))
                                                                   (funcall callback failed)))))
                                                       ;; Not a bypass — discard normally
                                                       (progn
                                                         (setq finished t)
                                                         (magit-git-success "checkout" "--" ".")
                                                         (gptel-auto-workflow--drop-provisional-commit
                                                          provisional-commit-hash
                                                          (format "Discard provisional commit for %s" target))
                                                         (setq provisional-commit-hash nil)
                                                          (message "[auto-experiment] ✗ %s for %s (passed=%s tests-passed=%s validation-error=%s)"
                                                                   reason target passed tests-passed validation-error)
                                                          (funcall log-fn run-id exp-result)
                                                          ;; Track token economics for this experiment
                                                          (when (fboundp 'gptel-token-economics--track-experiment)
                                                            (gptel-token-economics--track-experiment exp-result))
                                                          (funcall callback exp-result)))))))))
                                           ))))))))))))))))
                   (let ((raw-executor-callback executor-callback))
                     (setq executor-callback
                            (lambda (agent-output)
                              (condition-case err
                                  (funcall raw-executor-callback agent-output)
                                (error
                                 (unless result-callback-called
                                   (setq finished t)
                                   (let* ((error-message (error-message-string err))
                                         (output (if (stringp agent-output)
                                                     agent-output
                                                   (format "%S" agent-output)))
                                         (hypothesis
                                          (condition-case nil
                                              (gptel-auto-experiment--extract-hypothesis output)
                                            (error "executor-callback-error")))
                                         (reason (format "executor-callback-error: %s"
                                                         error-message))
                                         (exp-result
                                          (list :target target
                                                :id experiment-id
                                                :hypothesis hypothesis
                                                :score-before baseline
                                                :score-after 0
                                                :code-quality baseline-code-quality
                                                :kept nil
                                                :duration (- (float-time) start-time)
                                                :grader-quality 0
                                                :grader-reason reason
                                                :comparator-reason "executor-callback-error"
                                                :analyzer-patterns (format "%s" (and (proper-list-p analysis)
                                                                                       (plist-get analysis :patterns)))
                                                :agent-output output
                                                :error reason
                                                :backend (or actual-backend experiment-backend)
                                                :model (or actual-model experiment-model)
                                                :output-chars (length output))))
                                    (message "[auto-exp] ✗ Executor callback error for %s experiment %d: %s"
                                             target experiment-id
                                             (my/gptel--sanitize-for-logging error-message 200))
                                    (condition-case cleanup-err
                                        (let ((default-directory experiment-worktree))
                                          (magit-git-success "checkout" "--" ".")
                                          (when provisional-commit-hash
                                            (gptel-auto-workflow--drop-provisional-commit
                                             provisional-commit-hash
                                             (format "Drop provisional commit after callback error for %s" target))
                                            (setq provisional-commit-hash nil)))
                                      (error
                                       (message "[auto-exp] Cleanup after executor callback error failed: %s"
                                                (error-message-string cleanup-err))))
                                     (condition-case log-err
                                         (funcall log-fn run-id exp-result)
                                       (error
                                        (message "[auto-exp] Failed to log executor callback error result: %s"
                                                 (error-message-string log-err))))
                                     ;; Track token economics for this experiment
                                     (when (fboundp 'gptel-token-economics--track-experiment)
                                       (gptel-token-economics--track-experiment exp-result))
                                     (funcall callback exp-result))))))))
                   (funcall launch-executor))))))))))


(defun gptel-auto-experiment--refine (target validation-error grade-details
                                       _executor-prompt experiment-worktree
                                       baseline patterns actual-backend actual-model
                                       strategy-name _run-id _log-fn provisional-commit-hash
                                       experiment-branch experiment-id start-time callback)
  "Run a refine cycle on the current worktree changes.
Called when the grader passed but the benchmark/validation failed."
  (let* ((refine-error (or validation-error "tests-failed"))
         (refine-timeout (min gptel-auto-experiment-time-budget
                              (or (bound-and-true-p gptel-auto-experiment-validation-retry-time-budget) 480)))
         (refine-prompt
          (concat "λ refine(previous_attempt).\n"
                  "The changes above are valid (grader passed) but have issues.\n"
                  "ERROR: " refine-error "\n\n"
                  "Fix ONLY the specific issue. Do not rewrite or undo existing changes.\n"
                  "| MANDATORY: emacs --batch -f batch-byte-compile before finishing\n")))
    (my/gptel--run-agent-tool-with-timeout
     refine-timeout
     (lambda (agent-output)
       (if (gptel-auto-experiment--agent-error-p agent-output)
           (progn
             (setq gptel-auto-experiment--refine-convergence-stats
                   (plist-put gptel-auto-experiment--refine-convergence-stats :total
                              (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :total) 0))))
             (setq gptel-auto-experiment--refine-convergence-stats
                   (plist-put gptel-auto-experiment--refine-convergence-stats :failure
                              (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :failure) 0))))
             (message "[auto-experiment] ✗ Refine agent error")
             (let ((default-directory experiment-worktree))
               (magit-git-success "checkout" "--" "."))
             (funcall callback (list :refined nil :reason "agent-error")))
         (gptel-auto-experiment--grade-with-retry
          agent-output
          (lambda (refine-grade)
            (if (not (plist-get refine-grade :passed))
                (progn
                  (setq gptel-auto-experiment--refine-convergence-stats
                        (plist-put gptel-auto-experiment--refine-convergence-stats :total
                                   (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :total) 0))))
                  (setq gptel-auto-experiment--refine-convergence-stats
                        (plist-put gptel-auto-experiment--refine-convergence-stats :failure
                                   (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :failure) 0))))
                  (message "[auto-experiment] ✗ Refine grade failed")
                  (let ((default-directory experiment-worktree))
                    (magit-git-success "checkout" "--" "."))
                  (funcall callback (list :refined nil :reason "grade-failed")))
              (let* ((hypothesis (gptel-auto-experiment--extract-hypothesis agent-output))
                     (bench (gptel-auto-experiment-benchmark t hypothesis)))
                (if (not (plist-get bench :passed))
                    (progn
                      (setq gptel-auto-experiment--refine-convergence-stats
                            (plist-put gptel-auto-experiment--refine-convergence-stats :total
                                       (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :total) 0))))
                      (setq gptel-auto-experiment--refine-convergence-stats
                            (plist-put gptel-auto-experiment--refine-convergence-stats :failure
                                       (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :failure) 0))))
                      (message "[auto-experiment] ✗ Refine benchmark still failed")
                      (let ((default-directory experiment-worktree))
                        (magit-git-success "checkout" "--" "."))
                      (funcall callback (list :refined nil :reason "benchmark-failed")))
                  (let* ((score-after (plist-get bench :eight-keys))
                         (grade-score (plist-get refine-grade :score))
                         (grade-total (plist-get refine-grade :total))
                         (effective-score
                           (let ((raw-score
                                  (if (and (plist-get refine-grade :passed)
                                           (or (null score-after) (< score-after 0.1))
                                           grade-score grade-total (> grade-total 0))
                                      (/ (float grade-score) grade-total)
                                    (or score-after 0))))
                             (if (fboundp 'gptel-auto-workflow--weight-score-with-production-metrics)
                                 (gptel-auto-workflow--weight-score-with-production-metrics raw-score target)
                               raw-score)))
                          (quality (or (gptel-auto-experiment--code-quality-score) 0.5))
                         (exp-result
                          (list :target target :id experiment-id
                                :hypothesis hypothesis
                                :score-before baseline :score-after effective-score
                                :code-quality quality :refined t
                                :duration (- (float-time) start-time)
                                :grader-quality grade-score
                                :grader-reason grade-details
                                :analyzer-patterns (format "%s" patterns)
                                :agent-output agent-output
                                :backend actual-backend :model actual-model
                                :strategy strategy-name)))
                    (setq gptel-auto-experiment--refine-convergence-stats
                          (plist-put gptel-auto-experiment--refine-convergence-stats :total
                                     (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :total) 0))))
                    (setq gptel-auto-experiment--refine-convergence-stats
                          (plist-put gptel-auto-experiment--refine-convergence-stats :success
                                     (1+ (or (plist-get gptel-auto-experiment--refine-convergence-stats :success) 0))))
                    ;; Postcondition check: verify commit criteria from action schema
                    (when (and target (fboundp 'gptel-auto-workflow--schema-for-target))
                      (let* ((schema (gptel-auto-workflow--schema-for-target target))
                             (commit-failed (cl-find-if
                                             (lambda (c)
                                               (string-match-p "all-tests-pass\\|no-regressions" c))
                                             (plist-get schema :commit-criteria))))
                        (when commit-failed
                          (message "[auto-exp] ⚠ Postcondition %s not verified for %s" commit-failed target))))
                    ;; Record convergence score for monotonic improvement check
                    (when (fboundp 'gptel-ai-behaviors--record-refine-score)
                      (gptel-ai-behaviors--record-refine-score target effective-score))
                    (message "[auto-experiment] ✓ Refine passed (score=%s)" effective-score)
                    (funcall callback (list :refined t :exp-result exp-result
                                           :effective-score effective-score
                                           :hypothesis hypothesis
                                           :grade-score grade-score :grade-total grade-total
                                           :grade-details grade-details
                                           :provisional-commit-hash provisional-commit-hash
                                           :experiment-branch experiment-branch))))))))))
     refine-prompt target experiment-worktree nil nil nil
       (bound-and-true-p gptel-auto-experiment-active-grace)))))

(defconst gptel-auto-experiment--placeholder-hypothesis-exact-patterns
  '("[What CODE change and why]"
    "What CODE change and why")
  "Exact hypothesis strings that indicate unresolved placeholder prompts.")

(defun gptel-auto-experiment--placeholder-hypothesis-p (hypothesis)
  "Return non-nil when HYPOTHESIS is still an unresolved prompt template."
  (cond
   ((not (stringp hypothesis)) t)
   (t
    (let ((trimmed (string-trim hypothesis)))
      (or (string-empty-p trimmed)
          (string-match-p "\\`\\[What\\b.*\\]\\'" trimmed)
          (member trimmed gptel-auto-experiment--placeholder-hypothesis-exact-patterns))))))

;; ─── Staging Recovery Sweep ───

(defconst gptel-auto-experiment--staging-recovery-max-age-hours 72
  "Maximum age (hours) for staging-pending recovery. Older experiments have
likely been merged or abandoned — skip to avoid noise.")

(defun gptel-auto-experiment--recover-stale-staging-pending ()
  "Retry staging flow for experiments stuck in `staging-pending`.
Queries the Datahike World Store for experiments still in `staging-pending`
between 1h and `gptel-auto-experiment--staging-recovery-max-age-hours` old.
Older entries are skipped (branches likely deleted/merged).
Safe to call multiple times: already-merged branches are skipped."
  (interactive)
  (when (and gptel-auto-workflow-use-staging
             (fboundp 'gptel-auto-workflow--staging-flow)
             (fboundp 'ov5-world-store--brepl-eval))
    (let ((recovered 0)
          (skipped 0)
          (_gptel-auto-workflow--recovering-stale-staging t)
          (min-age 1.0)
          (max-age (float gptel-auto-experiment--staging-recovery-max-age-hours)))
      ;; Query World Store for staging-pending experiments within age range
      (condition-case ws-err
          (let* ((edn-str (ov5-world-store--brepl-eval
                           (format "(ns ov5.world-store) (staging-pending-by-age %s %s)"
                                   min-age max-age)))
                 (stale-results (when (and edn-str (not (string-empty-p edn-str)))
                                  (ignore-errors (parseedn-read-str edn-str)))))
            (dolist (entity stale-results)
              (let* ((id (plist-get entity :id))
                     (target (plist-get entity :target))
                     ;; Extract experiment numeric id from composite id "run-id#exp-id"
                     (exp-id-str (when (stringp id)
                                   (if (string-match "#\\([0-9]+\\)\\'" id)
                                       (match-string 1 id)
                                     id)))
                     (exp-id (when exp-id-str
                               (ignore-errors (string-to-number exp-id-str))))
                     (run-id (when (stringp id)
                               (if (string-match "\\`\\([^#]+\\)#" id)
                                   (match-string 1 id)
                                 nil))))
                (when (and (stringp target) exp-id)
                  (let ((gptel-auto-workflow--run-id run-id)
                        (branch (when (fboundp 'gptel-auto-workflow--branch-name)
                                  (gptel-auto-workflow--branch-name target exp-id))))
                    (if (and branch
                             (zerop (call-process "git" nil nil nil
                                                 "rev-parse" "--verify" branch)))
                        (progn
                          (message "[staging-recovery] Retrying stale staging-pending: %s"
                                   branch)
                          (condition-case err
                              (progn
                                (gptel-auto-workflow--staging-flow branch)
                                (setq recovered (1+ recovered)))
                            (error
                             (message "[staging-recovery] Recovery failed for %s/exp%s: %s"
                                      target exp-id (error-message-string err)))))
                      (message "[staging-recovery] Branch %s does not exist, skipping"
                               (or branch (format "%s/exp%s" target exp-id)))
                      (setq skipped (1+ skipped))))))))
        (error
         (message "[staging-recovery] World Store query failed: %s"
                  (error-message-string ws-err))))
      (when (> recovered 0)
        (message "[staging-recovery] Recovered %d stale staging-pending experiments (skipped %d too old)"
                 recovered skipped))
      (when (> skipped 0)
        (message "[staging-recovery] %d staging-pending branches not found (likely deleted)"
                 skipped)))))

(defun gptel-auto-experiment--grader-bypass-p
    (grade-passed grade-score grade-total grade bench
                  validation-error tests-passed)
  "Return t if the grade qualifies for grader-bypass.
GRADE-PASSED is the boolean result from the grader.
GRADE-SCORE and GRADE-TOTAL are the numeric score and total.
GRADE is a plist with keys :grader-only-failure, :quota-exhausted,
:blind-mode, :details.
BENCH is a plist with key :nucleus-passed.
VALIDATION-ERROR is non-nil if validation failed.
TESTS-PASSED is the boolean test result from the benchmark.
Requires: genuine grade result (no grader-only-failure, quota-exhausted,
blind-mode, or auto-pass details), score >= 0.75, no validation error,
tests passed, and nucleus passed."
  (and grade-passed
       (not (plist-get grade :grader-only-failure))
       (not (plist-get grade :quota-exhausted))
       (not (plist-get grade :blind-mode))
       (not (string-match-p "auto-pass"
                            (or (plist-get grade :details) "")))
       grade-score grade-total (> grade-total 0)
       (>= (/ (float grade-score) grade-total) 0.75)
       (not validation-error)
       tests-passed
       (plist-get bench :nucleus-passed)))

(defun gptel-auto-experiment--grader-bypass-commit-and-push
    (target hypothesis grade-score grade-total _baseline
     experiment-id experiment-worktree experiment-branch
     provisional-commit-hash run-id exp-result log-fn callback)
  "Commit+push a grader-bypassed experiment. Handles its own callbacks.
Includes retry logic: if the initial promote-provisional-commit fails
(provisional hash mismatch from worktree changes), retries with a
fresh stage+commit cycle before giving up."
  (message "[auto-experiment] ✓ grader-bypass committing %s (grade=%d/%d)" target grade-score grade-total)
  (let* ((default-directory experiment-worktree)
         (msg (format "◈ Optimize %s (grader bypass)\n\nGrade: %d/%d\n\nHYPOTHESIS: %s"
                      target grade-score grade-total hypothesis))
         (commit-timeout (gptel-auto-experiment--git-timeout))
         (finalize (gptel-auto-experiment--make-kept-result-callback
                    run-id exp-result log-fn callback)))
    (gptel-auto-workflow--assert-main-untouched)
    (let ((commit-ok
           (or
            ;; Attempt 1: promote provisional commit (amend existing)
            (and (gptel-auto-workflow--stage-worktree-changes
                  (format "Stage bypass changes for %s" target) 60)
                 (gptel-auto-workflow--promote-provisional-commit
                  msg (format "Commit bypass changes for %s" target)
                  provisional-commit-hash commit-timeout))
            ;; Attempt 2: fresh stage + commit (provisional hash mismatch retry)
            (progn
              (message "[auto-experiment] Retrying bypass commit for %s with fresh stage" target)
              (and (gptel-auto-workflow--stage-worktree-changes
                    (format "Retry stage bypass for %s" target) 60)
                   (gptel-auto-workflow--promote-provisional-commit
                    msg (format "Retry commit bypass for %s" target)
                    nil commit-timeout))))))
      (if commit-ok
          (progn
            (setq provisional-commit-hash nil)
            (gptel-auto-workflow--track-commit experiment-id target experiment-worktree)
            (gptel-auto-experiment--maybe-log-staging-pending run-id exp-result log-fn)
            (setq gptel-auto-experiment--no-improvement-count 0)
            (if gptel-auto-workflow-use-staging
                (if gptel-auto-experiment-auto-push
                    (if (gptel-auto-workflow--push-branch-with-lease
                         experiment-branch (format "Push bypass branch %s" experiment-branch) 180)
                        (gptel-auto-workflow--staging-flow experiment-branch finalize)
                      (let ((failed-result (plist-put (plist-put (copy-sequence exp-result) :comparator-reason "bypass-push-failed") :kept nil)))
                        (funcall log-fn run-id failed-result)
                        (when (fboundp 'gptel-token-economics--track-experiment)
                          (gptel-token-economics--track-experiment failed-result))))
                  (funcall finalize))
              (let ((failed-result (plist-put (plist-put (copy-sequence exp-result)
                                                         :comparator-reason "staging-disabled-bypass-push-blocked")
                                              :kept nil)))
                (message "[auto-experiment] ✗ Bypass push blocked for %s: staging is disabled" experiment-branch)
                (funcall log-fn run-id failed-result)
                (when (fboundp 'gptel-token-economics--track-experiment)
                  (gptel-token-economics--track-experiment failed-result)))))
        (progn
          (gptel-auto-workflow--drop-provisional-commit
           provisional-commit-hash (format "Drop bypass commit for %s" target))
          (let ((failed-result (plist-put (plist-put (copy-sequence exp-result) :comparator-reason "bypass-commit-failed") :kept nil)))
            (funcall log-fn run-id failed-result)
            (when (fboundp 'gptel-token-economics--track-experiment)
              (gptel-token-economics--track-experiment failed-result))))))))

(provide 'gptel-tools-agent-experiment-core)
;;; gptel-tools-agent-experiment-core.el ends here
