;;; gptel-workflow-benchmark.el --- Agent workflow benchmarking -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 0.1.0
;; Keywords: ai, benchmark, agent, workflow

;;; Commentary:

;; Benchmark framework for gptel plan and gptel agent with subagent workflow (RunAgent).
;; Measures: completion, efficiency, constraint satisfaction, Eight Keys alignment.
;;
;; Usage:
;;   M-x gptel-workflow-benchmark-run
;;   M-x gptel-workflow-benchmark-run-all
;;   M-x gptel-workflow-benchmark-report

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(declare-function gptel-agent--task "gptel-tools-agent")
(declare-function gptel-benchmark-eight-keys-score "gptel-benchmark-principles")
(declare-function gptel-benchmark-memory-search "gptel-benchmark-memory")
(declare-function gptel-benchmark-memory-read "gptel-benchmark-memory")

(defvar gptel-agent-loop--state)
(defvar gptel-agent-loop--task-step-count)
(defvar gptel-benchmark-eight-keys-definitions)
(defvar gptel-agent-loop--task-continuation-count)

;;; Helpers

(defun gptel-workflow--tool-calls-list (run)
  "Return tool-calls from RUN as a list (handles vector)."
  (let ((tc (gptel-workflow-run-tool-calls run)))
    (if (vectorp tc) (append tc nil) tc)))

(defun gptel-workflow--tool-names (run)
  "Return list of tool names from RUN as strings."
  (mapcar (lambda (tc)
            (let ((tool (plist-get tc :tool)))
              (if (symbolp tool) (symbol-name tool) tool)))
          (gptel-workflow--tool-calls-list run)))

(defun gptel-workflow--phase-active-p (run phase)
  "Return non-nil if PHASE is active in RUN's phase trace."
  (cl-find phase (gptel-workflow-run-phase-trace run)
           :key (lambda (p) (plist-get p :phase))
           :test #'eq))

;;; Customization

(defgroup gptel-workflow-benchmark nil
  "Benchmarking for agent workflows."
  :group 'gptel)

(defcustom gptel-workflow-tests-dir "./benchmarks/workflow-tests/"
  "Directory where workflow test definitions are stored."
  :type 'directory
  :group 'gptel-workflow-benchmark)

(defcustom gptel-workflow-results-dir "./benchmarks/workflows/"
  "Directory where benchmark results are stored."
  :type 'directory
  :group 'gptel-workflow-benchmark)

(defcustom gptel-workflow-default-timeout 120
  "Default timeout in seconds for workflow tests."
  :type 'integer
  :group 'gptel-workflow-benchmark)

;;; Data Structures

(cl-defstruct (gptel-workflow-run (:constructor gptel-workflow-run-create))
  test-id
  workflow
  task
  start-time
  end-time
  tool-calls
  step-count
  continuation-count
  completed-p
  aborted-p
  timeout-p
  output
  error-message
  phase-trace
  constraint-violations
  eight-keys-scores)

;;; State

(defvar gptel-workflow--current-run nil
  "Current workflow run being collected.")

(defvar gptel-workflow--runs nil
  "List of completed workflow runs.")

(defvar gptel-workflow--tool-call-hook nil
  "Hook called on each tool call. Functions receive (tool-name args timestamp).")

;;; Test Loading

(defun gptel-workflow-load-tests (workflow-name)
  "Load test definitions for WORKFLOW-NAME.
Returns list of test plists."
  (let ((test-file (expand-file-name (format "%s.json" workflow-name)
                                     gptel-workflow-tests-dir)))
    (if (file-exists-p test-file)
        (let* ((data (gptel-workflow--read-json test-file))
               (test-cases (cdr (assq 'test_cases data))))
          (mapcar #'gptel-workflow--normalize-test test-cases))
      (progn
        (message "[workflow-bench] No test file found: %s" test-file)
        '()))))

(defun gptel-workflow--normalize-test (test)
  "Normalize TEST alist to plist format."
  (list :id (cdr (assq 'id test))
        :name (cdr (assq 'name test))
        :task (cdr (assq 'task test))
        :context (cdr (assq 'context test))
        :success-criteria (cdr (assq 'success_criteria test))
        :expected-outputs (cdr (assq 'expected_outputs test))))

(defun gptel-workflow--read-json (file)
  "Read JSON from FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (json-read)))

;;; Tool Call Collection

(defun gptel-workflow--collect-tool-call (tool-name args)
  "Collect TOOL-NAME with ARGS into current run if active."
  (when gptel-workflow--current-run
    (let ((entry (list tool-name args (float-time))))
      (push entry (gptel-workflow-run-tool-calls gptel-workflow--current-run))
      (run-hook-with-args 'gptel-workflow--tool-call-hook tool-name args))))

(defun gptel-workflow--setup-hooks ()
  "Setup hooks to collect tool calls."
  (advice-add 'gptel--handle-tool-use :before
              #'gptel-workflow--tool-use-advice))

(defun gptel-workflow--teardown-hooks ()
  "Remove hooks."
  (advice-remove 'gptel--handle-tool-use
                 #'gptel-workflow--tool-use-advice))

(defun gptel-workflow--tool-use-advice (fsm &rest _)
  "Advice to collect tool calls from FSM state.
FSM is the finite state machine object containing tool-use information.
Extracts tool calls from the FSM's :tool-use plist and records them."
  (when (and gptel-workflow--current-run fsm
             (fboundp 'gptel-fsm-info))
    (when-let* ((info (gptel-fsm-info fsm))
                (tool-use (plist-get info :tool-use)))
      (dolist (call (if (listp tool-use) tool-use (list tool-use)))
        (when (plistp call)
          (let* ((tool-name (plist-get call :name))
                 (args (plist-get call :args)))
            (when tool-name
              (gptel-workflow--collect-tool-call tool-name args))))))))

;;; Memory Integration

(defun gptel-workflow-retrieve-memories (workflow-name)
  "Retrieve relevant memories for WORKFLOW-NAME.
Returns list of relevant memory content strings."
  (when (fboundp 'gptel-benchmark-memory-search)
    (let* ((keywords (list workflow-name "workflow" "agent" "phase" "tool"))
           (memories '()))
      (dolist (kw keywords)
        (let ((files (gptel-benchmark-memory-search kw 1)))
          (dolist (f files)
            (when (and (stringp f) (file-exists-p f))
              (let ((content (gptel-benchmark-memory-read f)))
                (when (and content (not (member content memories)))
                  (push content memories)))))))
      (when memories
        (message "[workflow-bench] Retrieved %d relevant memories" (length memories)))
      memories)))

(defun gptel-workflow--format-memories-for-context (memories)
  "Format MEMORIES for inclusion in task context."
  (when memories
    (format "\n\n;; Relevant memories from past runs:\n%s\n"
            (mapconcat (lambda (m)
                         (format ";; - %s" (substring m 0 (min 100 (length m)))))
                       memories "\n"))))

;;; Phase Detection

(defun gptel-workflow-detect-phases (run)
  "Detect phase transitions for RUN based on tool calls and output.
Returns list of phase entries."
  (let ((tool-calls (gptel-workflow--tool-calls-list run))
        (output (or (gptel-workflow-run-output run) ""))
        (phases '()))
    (let ((p1-entry (gptel-workflow--detect-p1 tool-calls))
          (p2-entry (gptel-workflow--detect-p2 tool-calls output))
          (p3-entry (gptel-workflow--detect-p3 tool-calls)))
      (when p1-entry (push p1-entry phases))
      (when p2-entry (push p2-entry phases))
      (when p3-entry (push p3-entry phases)))
    (reverse phases)))

(defun gptel-workflow--detect-p1 (tool-calls)
  "Detect P1 phase from TOOL-CALLS.
P1 = Understand → Explore → Decide → Present
Indicators: grep/read tools used, no edit/write yet."
  (let ((tools (mapcar (lambda (tc) (plist-get tc :tool)) tool-calls)))
    (when (and (or (memq 'grep tools)
                   (memq 'Grep tools)
                   (cl-member "grep" tools :test #'equal :key #'symbol-name))
               (or (memq 'read tools)
                   (memq 'Read tools)
                   (cl-member "read" tools :test #'equal :key #'symbol-name)))
      (list :phase 'P1
            :entered t
            :timestamp (float-time)
            :tools-used (delete-dups tools)))))

(defun gptel-workflow--detect-p2 (tool-calls output)
  "Detect P2 phase from TOOL-CALLS and OUTPUT.
P2 = refine (plan created, updates made)
Indicators: plan file mentioned, Updates in output, or edit tools used."
  (let ((tools (mapcar (lambda (tc) (plist-get tc :tool)) tool-calls)))
    (when (or (string-match-p "[Pp]lan" output)
              (string-match-p "[Uu]pdates" output)
              (memq 'edit tools)
              (memq 'Edit tools)
              (cl-member "edit" tools :test #'equal :key #'symbol-name))
      (list :phase 'P2
            :entered t
            :timestamp (float-time)
            :indicators (delq nil
                              (list (when (string-match-p "[Pp]lan" output) "plan-mentioned")
                                    (when (string-match-p "[Uu]pdates" output) "updates-mentioned")
                                    (when (memq 'edit tools) "edit-used")))))))

(defun gptel-workflow--detect-p3 (tool-calls)
  "Detect P3 phase from TOOL-CALLS.
P3 = preview (preview_file_change tool called)
Indicators: preview tool used."
  (let ((tools (mapcar (lambda (tc) (plist-get tc :tool)) tool-calls)))
    (when (or (memq 'preview_file_change tools)
              (memq 'Preview tools)
              (cl-member "preview" tools :test #'equal :key #'symbol-name)
              (cl-member "preview_file_change" tools :test #'equal :key #'symbol-name))
      (list :phase 'P3
            :entered t
            :timestamp (float-time)))))

;;; Test Execution

(defun gptel-workflow--agent-type (workflow-name)
  "Convert WORKFLOW-NAME to agent type for gptel-agent--task.
E.g., plan_agent -> plan, code_agent -> code."
  (let ((name (if (symbolp workflow-name) (symbol-name workflow-name) workflow-name)))
    (replace-regexp-in-string "_agent$" "" name)))

(defun gptel-workflow-run-test (test-case callback &optional workflow-name)
  "Run TEST-CASE against WORKFLOW-NAME agent.
Calls CALLBACK with gptel-workflow-run struct when complete.
WORKFLOW-NAME defaults to \"plan\" if not specified."
  (let* ((test-id (plist-get test-case :id))
         (task (plist-get test-case :task))
         (workflow (or workflow-name "plan"))
         (success-criteria (plist-get test-case :success-criteria))
         (completion-cfg (cdr (assq 'completion success-criteria)))
         (timeout (or (cdr (assq 'timeout_seconds completion-cfg))
                      gptel-workflow-default-timeout))
         (run (gptel-workflow-run-create
               :test-id test-id
               :workflow workflow
               :task task
               :start-time (float-time)
               :tool-calls nil
               :step-count 0
               :continuation-count 0
               :completed-p nil
               :aborted-p nil
               :timeout-p nil
               :output nil
               :error-message nil
               :phase-trace nil
               :constraint-violations nil
               :eight-keys-scores nil))
         (timeout-timer nil)
         (finished nil))
    (setq gptel-workflow--current-run run)
    (gptel-workflow--setup-hooks)
    (setq timeout-timer
          (run-with-timer timeout nil
                          (lambda ()
                            (unless finished
                              (setq finished t)
                              (setf (gptel-workflow-run-timeout-p run) t
                                    (gptel-workflow-run-completed-p run) nil
                                    (gptel-workflow-run-end-time run) (float-time))
                              (setq gptel-workflow--current-run nil)
                              (gptel-workflow--teardown-hooks)
                              (funcall callback run)))))
    (condition-case err
        (progn
          (message "[workflow-bench] Starting test: %s" test-id)
          (gptel-agent--task
           (lambda (result)
             (unless finished
               (setq finished t)
               (when timeout-timer (cancel-timer timeout-timer))
               (setf (gptel-workflow-run-output run) result
                     (gptel-workflow-run-completed-p run) (not (gptel-workflow-run-timeout-p run))
                     (gptel-workflow-run-end-time run) (float-time))
               (when (and (boundp 'gptel-agent-loop--state)
                          gptel-agent-loop--state)
                 (setf (gptel-workflow-run-step-count run)
                       (or (gptel-agent-loop--task-step-count gptel-agent-loop--state) 0)
                       (gptel-workflow-run-continuation-count run)
                       (or (gptel-agent-loop--task-continuation-count gptel-agent-loop--state) 0)))
               (setf (gptel-workflow-run-phase-trace run)
                     (gptel-workflow-detect-phases run))
               (setq gptel-workflow--current-run nil)
               (gptel-workflow--teardown-hooks)
               (funcall callback run)))
           workflow
           (format "Benchmark test: %s" test-id)
           task))
      (error
       (unless finished
         (setq finished t)
         (when timeout-timer (cancel-timer timeout-timer))
         (setf (gptel-workflow-run-error-message run) (error-message-string err)
               (gptel-workflow-run-completed-p run) nil
               (gptel-workflow-run-end-time run) (float-time))
         (setq gptel-workflow--current-run nil)
         (gptel-workflow--teardown-hooks)
         (funcall callback run))))))

;;; Scoring

(defun gptel-workflow-score (run expected)
  "Score RUN against EXPECTED criteria.
Returns plist with :completion-score, :efficiency-score, :constraint-score,
:tool-score, :eight-keys-score, :overall-score."
  (let* ((success-criteria expected)
         (completion-cfg (cdr (assq 'completion success-criteria)))
         (efficiency-cfg (cdr (assq 'efficiency success-criteria)))
         (tools-cfg (cdr (assq 'tools success-criteria)))
         (phases-cfg (cdr (assq 'phases success-criteria)))
         (eight-keys-cfg (cdr (assq 'eight_keys success-criteria)))
         (completion-score (gptel-workflow--score-completion run completion-cfg))
         (efficiency-score (gptel-workflow--score-efficiency run efficiency-cfg))
         (constraint-score (gptel-workflow--score-constraints run phases-cfg))
         (tool-score (gptel-workflow--score-tools run tools-cfg))
         (eight-keys-score (gptel-workflow--score-eight-keys run eight-keys-cfg))
         (overall-score (+ (* 0.25 completion-score)
                           (* 0.25 efficiency-score)
                           (* 0.25 constraint-score)
                           (* 0.15 tool-score)
                           (* 0.10 eight-keys-score))))
    (list :completion-score completion-score
          :efficiency-score efficiency-score
          :constraint-score constraint-score
          :tool-score tool-score
          :eight-keys-score eight-keys-score
          :overall-score overall-score)))

(defun gptel-workflow--score-completion (run _completion-cfg)
  "Score completion of RUN against COMPLETION-CFG."
  (cond
   ((gptel-workflow-run-aborted-p run) 0.0)
   ((gptel-workflow-run-timeout-p run) 0.0)
   ((gptel-workflow-run-error-message run) 0.0)
   ((and (gptel-workflow-run-completed-p run)
         (not (gptel-workflow-run-timeout-p run))
         (not (gptel-workflow-run-aborted-p run)))
    1.0)
   (t 0.5)))

(defun gptel-workflow--score-efficiency (run efficiency-cfg)
  "Score efficiency of RUN against EFFICIENCY-CFG."
  (let* ((steps (or (gptel-workflow-run-step-count run) 0))
         (continuations (or (gptel-workflow-run-continuation-count run) 0))
         (duration (if (and (gptel-workflow-run-start-time run)
                            (gptel-workflow-run-end-time run))
                       (- (gptel-workflow-run-end-time run)
                          (gptel-workflow-run-start-time run))
                     0))
         (min-steps (or (cdr (assq 'min_steps efficiency-cfg)) 1))
         (max-steps (or (cdr (assq 'max_steps efficiency-cfg)) 50))
         (max-continuations (or (cdr (assq 'max_continuations efficiency-cfg)) 5))
         (max-duration (or (cdr (assq 'max_duration_seconds efficiency-cfg)) 120))
         (steps-score
          (cond
           ((= steps 0) 0.0)
           ((< steps min-steps) 0.5)
           ((> steps max-steps) 0.3)
           (t 1.0)))
         (continuations-score
          (if (> continuations max-continuations) 0.3 1.0))
         (duration-score
          (cond
           ((= duration 0) 0.5)
           ((> duration max-duration) 0.5)
           (t 1.0))))
    (/ (+ steps-score continuations-score duration-score) 3.0)))

(defun gptel-workflow--score-constraints (run phases-cfg)
  "Score constraint satisfaction of RUN against PHASES-CFG."
  (let* ((expected-phases (cdr (assq 'expected phases-cfg)))
         (violations '())
         (total-constraints 0)
         (satisfied 0))
    (when expected-phases
      (dolist (expected-phase expected-phases)
        (cl-incf total-constraints)
        (if (gptel-workflow--phase-active-p run expected-phase)
            (cl-incf satisfied)
          (push (list :type 'missing-phase
                      :phase expected-phase
                      :expected t)
                violations))))
    (if (> total-constraints 0)
        (max 0.0 (/ (float satisfied) total-constraints))
      1.0)))

(defun gptel-workflow--score-tools (run tools-cfg)
  "Score tool usage of RUN against TOOLS-CFG."
  (cond
   ((null run) 1.0)
   ((null tools-cfg) 1.0)
   (t
    (let* ((used-tools (gptel-workflow--tool-names run))
           (required (cdr (assq 'required tools-cfg)))
           (forbidden-before (cdr (assq 'forbidden_before_phase tools-cfg)))
           (p1-forbidden (and forbidden-before (cdr (assq 'P1 forbidden-before))))
           (total-score 0.0)
           (count 0))
      (when required
        (let* ((found (cl-intersection required used-tools :test #'string=))
               (score (/ (float (length found)) (max 1 (length required)))))
          (cl-incf total-score score)
          (cl-incf count)))
      (when p1-forbidden
        (let* ((p1-tools (if (gptel-workflow--phase-active-p run 'P1)
                             used-tools
                           nil))
               (violations (cl-intersection p1-forbidden p1-tools :test #'string=))
               (score (if violations 0.0 1.0)))
          (cl-incf total-score score)
          (cl-incf count)))
      (if (> count 0)
          (/ total-score count)
        1.0)))))

(defun gptel-workflow--score-eight-keys (run eight-keys-cfg)
  "Score Eight Keys of RUN against EIGHT-KEYS-CFG."
  (let ((output (gptel-workflow-run-output run)))
    (if (and output (fboundp 'gptel-benchmark-eight-keys-score))
        (let* ((scores (gptel-benchmark-eight-keys-score output))
               (overall (alist-get 'overall scores))
               (min-overall (cdr (assq 'min_overall eight-keys-cfg))))
          (setf (gptel-workflow-run-eight-keys-scores run) scores)
          (if min-overall
              (if (>= overall min-overall) 1.0 overall)
            overall))
      0.5)))

;;; Results

(defun gptel-workflow-save-results (run scores)
  "Save RUN and SCORES to results file."
  (let* ((results-dir (expand-file-name gptel-workflow-results-dir))
         (workflow (gptel-workflow-run-workflow run))
         (results-file (expand-file-name (format "%s-results.json" workflow) results-dir)))
    (unless (file-exists-p results-dir)
      (make-directory results-dir t))
    (let* ((entry (list :test-id (gptel-workflow-run-test-id run)
                        :run-id (format-time-string "%Y%m%d-%H%M%S")
                        :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
                        :metrics (list :duration_seconds
                                       (if (and (gptel-workflow-run-start-time run)
                                                (gptel-workflow-run-end-time run))
                                           (- (gptel-workflow-run-end-time run)
                                              (gptel-workflow-run-start-time run))
                                         0)
                                       :step_count (gptel-workflow-run-step-count run)
                                       :continuation_count (gptel-workflow-run-continuation-count run)
                                       :completed (gptel-workflow-run-completed-p run)
                                       :phases (vconcat (gptel-workflow-run-phase-trace run))
                                       :tool_calls (vconcat (mapcar (lambda (tc)
                                                                      (list :tool (plist-get tc :tool)
                                                                            :timestamp (plist-get tc :timestamp)))
                                                                    (reverse (gptel-workflow--tool-calls-list run)))))
                        :scores scores))
           (existing (when (file-exists-p results-file)
                       (condition-case nil
                           (gptel-workflow--read-json results-file)
                         (error nil))))
           (history (if (vectorp existing) (append existing nil)
                      (if (listp existing) existing '()))))
      (gptel-workflow--write-json (cons entry history) results-file)
      entry)))

(defun gptel-workflow--write-json (data file)
  "Write DATA as JSON to FILE."
  (with-temp-file file
    (let ((json-encoding-pretty-print t))
      (insert (json-encode data)))))

;;; Interactive Commands

(defun gptel-workflow-benchmark-run (workflow-name test-id)
  "Run a single workflow benchmark test.
WORKFLOW-NAME is the workflow to test (plan_agent or code_agent).
TEST-ID is the test case ID."
  (interactive
   (let* ((workflow (completing-read "Workflow: " '("plan_agent" "code_agent")))
          (tests (gptel-workflow-load-tests workflow))
          (test-ids (mapcar (lambda (tc) (plist-get tc :id)) tests))
          (test-id (if test-ids
                       (completing-read "Test ID: " test-ids)
                     (read-string "Test ID: "))))
     (list workflow test-id)))
  (let* ((tests (gptel-workflow-load-tests workflow-name))
         (test (cl-find test-id tests :key (lambda (tc) (plist-get tc :id)) :test #'equal))
         (agent-type (gptel-workflow--agent-type workflow-name)))
    (if (not test)
        (message "Test %s not found for workflow %s" test-id workflow-name)
      (message "[workflow-bench] Running: %s/%s..." workflow-name test-id)
      (gptel-workflow-run-test
       test
       (lambda (run)
         (let* ((success-criteria (plist-get test :success-criteria))
                (scores (gptel-workflow-score run success-criteria)))
           (gptel-workflow-save-results run scores)
           (push run gptel-workflow--runs)
           (message "[workflow-bench] Complete: %s - Overall: %.0f%%"
                    test-id (* (plist-get scores :overall-score) 100))))
       agent-type))))

(defun gptel-workflow-benchmark-run-all (workflow-name)
  "Run all benchmark tests for WORKFLOW-NAME."
  (interactive
   (list (completing-read "Workflow: " '("plan_agent" "code_agent"))))
  (let* ((tests (gptel-workflow-load-tests workflow-name))
         (agent-type (gptel-workflow--agent-type workflow-name))
         (total (length tests))
         (completed 0)
         (results nil))
    (if (null tests)
        (message "[workflow-bench] No tests found for %s" workflow-name)
      (message "[workflow-bench] Running %d tests for %s..." total workflow-name)
      (dolist (test tests)
        (gptel-workflow-run-test
         test
         (lambda (run)
           (let* ((success-criteria (plist-get test :success-criteria))
                  (scores (gptel-workflow-score run success-criteria)))
             (gptel-workflow-save-results run scores)
             (push (cons run scores) results)
             (cl-incf completed)
             (message "[workflow-bench] Progress: %d/%d tests completed" completed total)
             (when (= completed total)
               (setq gptel-workflow--runs
                     (append (mapcar #'car results) gptel-workflow--runs))
               (let ((avg-overall
                      (/ (apply #'+ (mapcar (lambda (r)
                                              (plist-get (cdr r) :overall-score))
                                            results))
                         (length results))))
                 (gptel-workflow-benchmark-save-historical workflow-name results)
                 (message "[workflow-bench] All tests complete. Avg overall: %.0f%%"
                          (* avg-overall 100))))))
         agent-type)))))

(defun gptel-workflow-benchmark-report ()
  "Show workflow benchmark report."
  (interactive)
  (let ((runs (reverse gptel-workflow--runs)))
    (with-output-to-temp-buffer "*Workflow Benchmark Report*"
      (princ "=== Workflow Benchmark Report ===\n\n")
      (if (null runs)
          (princ "No benchmark runs recorded.\n")
        (dolist (run runs)
          (princ (format "Test: %s\n" (gptel-workflow-run-test-id run)))
          (princ (format "  Workflow: %s\n" (gptel-workflow-run-workflow run)))
          (princ (format "  Completed: %s\n" (if (gptel-workflow-run-completed-p run) "Yes" "No")))
          (princ (format "  Steps: %d\n" (gptel-workflow-run-step-count run)))
          (princ (format "  Continuations: %d\n" (gptel-workflow-run-continuation-count run)))
          (princ (format "  Duration: %.1fs\n"
                         (if (and (gptel-workflow-run-start-time run)
                                  (gptel-workflow-run-end-time run))
                             (- (gptel-workflow-run-end-time run)
                                (gptel-workflow-run-start-time run))
                           0)))
          (princ (format "  Tool calls: %d\n" (length (gptel-workflow-run-tool-calls run))))
          (when (gptel-workflow-run-tool-calls run)
            (princ "  Tools: ")
            (princ (mapconcat #'symbol-name
                              (delete-dups (gptel-workflow--tool-names run))
                              ", "))
            (princ "\n"))
          (when (gptel-workflow-run-phase-trace run)
            (princ "  Phases: ")
            (princ (mapconcat (lambda (p) (symbol-name (plist-get p :phase)))
                              (gptel-workflow-run-phase-trace run)
                              " -> "))
            (princ "\n"))
          (when (gptel-workflow-run-error-message run)
            (princ (format "  Error: %s\n" (gptel-workflow-run-error-message run))))
          (princ "\n"))))))

;;; Cancel Support

(defvar gptel-workflow-benchmark--cancelled nil
  "Flag to cancel running benchmark.")

(defun gptel-workflow-benchmark-cancel ()
  "Cancel running benchmark."
  (interactive)
  (setq gptel-workflow-benchmark--cancelled t)
  (message "[workflow-bench] Cancellation requested..."))

;;; Historical Tracking

(defun gptel-workflow-benchmark-save-historical (workflow-name results)
  "Save RESULTS to historical file for WORKFLOW-NAME."
  (let* ((history-file (expand-file-name (format "%s-history.json" workflow-name)
                                         gptel-workflow-results-dir))
         (existing (when (file-exists-p history-file)
                     (condition-case nil
                         (gptel-workflow--read-json history-file)
                       (error nil))))
         (run-id (format-time-string "%Y%m%d-%H%M%S"))
         (summary (gptel-workflow--summarize-results results))
         (entry (list :run-id run-id
                      :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
                      :summary summary)))
    (unless (file-exists-p gptel-workflow-results-dir)
      (make-directory gptel-workflow-results-dir t))
    (let ((history (if (vectorp existing) (append existing nil) existing)))
      (gptel-workflow--write-json (cons entry history) history-file)
      entry)))

(defun gptel-workflow--summarize-results (results)
  "Create summary of RESULTS."
  (let ((total (length results))
        (avg-overall 0.0)
        (avg-efficiency 0.0)
        (avg-completion 0.0))
    (dolist (r results)
      (let ((scores (cdr r)))
        (when scores
          (cl-incf avg-overall (or (plist-get scores :overall-score) 0))
          (cl-incf avg-efficiency (or (plist-get scores :efficiency-score) 0))
          (cl-incf avg-completion (or (plist-get scores :completion-score) 0)))))
    (list :total-tests total
          :avg-overall (if (> total 0) (/ avg-overall total) 0.0)
          :avg-efficiency (if (> total 0) (/ avg-efficiency total) 0.0)
          :avg-completion (if (> total 0) (/ avg-completion total) 0.0))))

(defun gptel-workflow-benchmark-load-history (workflow-name)
  "Load historical benchmark data for WORKFLOW-NAME."
  (let ((history-file (expand-file-name (format "%s-history.json" workflow-name)
                                        gptel-workflow-results-dir)))
    (when (file-exists-p history-file)
      (let ((data (gptel-workflow--read-json history-file)))
        (if (vectorp data) (append data nil) data)))))

(defun gptel-workflow-benchmark-trend (workflow-name)
  "Show trend of benchmark scores over time for WORKFLOW-NAME."
  (interactive
   (list (completing-read "Workflow: " '("plan_agent" "code_agent"))))
  (let ((history (gptel-workflow-benchmark-load-history workflow-name)))
    (if (not history)
        (message "[workflow-bench] No historical data for %s" workflow-name)
      (with-output-to-temp-buffer (format "*Workflow Trend: %s*" workflow-name)
        (princ (format "=== Benchmark Trend: %s ===\n\n" workflow-name))
        (princ "Timestamp                 Avg Overall  Avg Efficiency  Avg Completion\n")
        (princ "------------------------------------------------------------------------\n")
        (dolist (entry (reverse history))
          (let* ((summary (plist-get entry :summary))
                 (timestamp (or (plist-get entry :timestamp) "unknown"))
                 (avg-overall (* 100 (or (plist-get summary :avg-overall) 0)))
                 (avg-efficiency (* 100 (or (plist-get summary :avg-efficiency) 0)))
                 (avg-completion (* 100 (or (plist-get summary :avg-completion) 0))))
            (princ (format "%-25s %6.1f%%      %6.1f%%        %6.1f%%\n"
                           timestamp avg-overall avg-efficiency avg-completion))))
        (princ "\n")))))

(defun gptel-workflow-benchmark-trend-analysis (workflow-name)
  "Analyze trend for WORKFLOW-NAME and return evolution-relevant data.
Returns plist with :direction, :velocity, :recommendation."
  (let* ((history (gptel-workflow-benchmark-load-history workflow-name))
         (result (list :workflow workflow-name
                       :data-points (length history)
                       :direction 'stable
                       :velocity 0.0
                       :recommendation nil)))
    (when (and history (>= (length history) 2))
      (let* ((recent (seq-take history 5))
             (scores (mapcar (lambda (e)
                               (let ((s (plist-get e :summary)))
                                 (or (plist-get s :avg-overall) 0)))
                             (if (listp recent) recent (append recent nil))))
             (first-half (seq-subseq scores 0 (floor (/ (length scores) 2))))
             (second-half (seq-subseq scores (floor (/ (length scores) 2)))))
        (when (and first-half second-half)
          (let* ((avg-first (/ (apply #'+ first-half) (length first-half)))
                 (avg-second (/ (apply #'+ second-half) (length second-half)))
                 (velocity (- avg-second avg-first)))
            (setq result (plist-put result :velocity velocity))
            (setq result (plist-put result :direction
                                    (cond ((> velocity 0.05) 'improving)
                                          ((< velocity -0.05) 'declining)
                                          (t 'stable))))
            (setq result (plist-put result :recommendation
                                    (cond ((> velocity 0.05) "Continue current approach")
                                          ((< velocity -0.05) "Investigate and apply fixes")
                                          (t "Consider optimization"))))))))
    result))

;;; Eight Keys Breakdown

(defun gptel-workflow-benchmark-show-eight-keys (workflow-name)
  "Show Eight Keys breakdown for WORKFLOW-NAME benchmark results."
  (interactive
   (list (completing-read "Workflow: " '("plan_agent" "code_agent"))))
  (let* ((results-file (expand-file-name (format "%s-results.json" workflow-name)
                                         gptel-workflow-results-dir))
         (results (when (file-exists-p results-file)
                    (gptel-workflow--read-json results-file))))
    (if (not results)
        (message "[workflow-bench] No results found for %s" workflow-name)
      (let* ((results-list (if (vectorp results) (append results nil) results))
             (breakdown (gptel-workflow--eight-keys-breakdown results-list)))
        (with-output-to-temp-buffer (format "*Eight Keys: %s*" workflow-name)
          (princ (format "=== Eight Keys Breakdown: %s ===\n\n" workflow-name))
          (dolist (key-def gptel-benchmark-eight-keys-definitions)
            (let* ((key (car key-def))
                   (symbol (plist-get (alist-get key gptel-benchmark-eight-keys-definitions) :symbol))
                   (name (plist-get (alist-get key gptel-benchmark-eight-keys-definitions) :name))
                   (score (alist-get key breakdown)))
              (princ (format "%s %s: %.1f%%\n" symbol name (* 100 (or score 0))))))
          (princ "\n"))))))

(defun gptel-workflow--eight-keys-breakdown (results)
  "Generate Eight Keys breakdown from RESULTS."
  (let ((key-totals (make-vector 8 0.0))
        (key-counts (make-vector 8 0))
        (key-names [phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                                 pi-synthesis mu-directness exists-truth forall-vigilance]))
    (dolist (r results)
      (let* ((eight-keys (plist-get r :eight-keys-scores)))
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
      (reverse breakdown))))

;;; Auto-Feedback and Self-Improvement

(defvar gptel-workflow-feedback-file
  (expand-file-name "workflow-feedback.json" gptel-workflow-results-dir)
  "File storing workflow benchmark feedback and improvement suggestions.")

(defun gptel-workflow-analyze-results (workflow-name)
  "Analyze benchmark results for WORKFLOW-NAME and generate suggestions.
Returns plist with :patterns, :issues, and :recommendations."
  (interactive
   (list (completing-read "Workflow: " '("plan_agent" "code_agent"))))
  (let* ((results-file (expand-file-name (format "%s-results.json" workflow-name)
                                         gptel-workflow-results-dir))
         (results (when (file-exists-p results-file)
                    (gptel-workflow--read-json results-file)))
         (analysis nil))
    (if (not results)
        (message "[workflow-bench] No results to analyze for %s" workflow-name)
      (setq analysis (gptel-workflow--analyze-patterns
                      (if (vectorp results) (append results nil) results)))
      (gptel-workflow--save-feedback workflow-name analysis)
      (gptel-workflow--display-analysis workflow-name analysis)
      analysis)))

(defun gptel-workflow--analyze-patterns (results)
  "Analyze RESULTS for patterns, issues, and generate recommendations."
  (let ((patterns '())
        (issues '())
        (recommendations '())
        (total (length results))
        (low-completion 0)
        (low-efficiency 0)
        (tool-usage (make-hash-table :test 'equal)))
    (dolist (r results)
      (let* ((scores (plist-get r :scores))
             (metrics (plist-get r :metrics)))
        (when scores
          (when (< (or (plist-get scores :completion-score) 1.0) 0.7)
            (cl-incf low-completion))
          (when (< (or (plist-get scores :efficiency-score) 1.0) 0.7)
            (cl-incf low-efficiency)))
        (when metrics
          (let ((tools (plist-get metrics :tool_calls)))
            (when (vectorp tools)
              (dolist (tc (append tools nil))
                (let ((tool (plist-get tc :tool)))
                  (when tool
                    (puthash tool (1+ (gethash tool tool-usage 0)) tool-usage)))))))))
    (when (> low-completion 0)
      (push (list :type 'low-completion
                  :count low-completion
                  :percentage (/ (float low-completion) total))
            issues)
      (push "Review timeout settings and task complexity" recommendations))
    (when (> low-efficiency 0)
      (push (list :type 'low-efficiency
                  :count low-efficiency
                  :percentage (/ (float low-efficiency) total))
            issues)
      (push "Consider adjusting max_steps or improving tool selection" recommendations))
    (let ((most-used (sort (hash-table-keys tool-usage)
                           (lambda (a b) (> (gethash a tool-usage 0)
                                            (gethash b tool-usage 0))))))
      (push (list :type 'tool-usage-pattern
                  :tools (cl-subseq most-used 0 (min 5 (length most-used))))
            patterns))
    (list :patterns patterns
          :issues issues
          :recommendations (delete-dups recommendations)
          :total-tests total
          :analysis-timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))

(defun gptel-workflow--save-feedback (workflow-name analysis)
  "Save ANALYSIS for WORKFLOW-NAME to feedback file."
  (let* ((feedback-file (expand-file-name "workflow-feedback.json"
                                          gptel-workflow-results-dir))
         (existing (when (file-exists-p feedback-file)
                     (condition-case nil
                         (gptel-workflow--read-json feedback-file)
                       (error nil))))
         (entry (list :workflow workflow-name
                      :analysis analysis))
         (history (if (vectorp existing) (append existing nil)
                    (if (listp existing) existing '()))))
    (unless (file-exists-p gptel-workflow-results-dir)
      (make-directory gptel-workflow-results-dir t))
    (gptel-workflow--write-json (cons entry history) feedback-file)))

(defun gptel-workflow--display-analysis (workflow-name analysis)
  "Display ANALYSIS for WORKFLOW-NAME."
  (when (null analysis)
    (error "[workflow-bench] Cannot display nil analysis for %s" workflow-name))
  (let* ((total-tests (or (plist-get analysis :total-tests) 0))
         (timestamp (or (plist-get analysis :analysis-timestamp) "N/A"))
         (issues (or (plist-get analysis :issues) '()))
         (patterns (or (plist-get analysis :patterns) '()))
         (recommendations (or (plist-get analysis :recommendations) '())))
    (when (zerop total-tests)
      (message "[workflow-bench] Warning: analysis for %s has zero tests" workflow-name))
    (with-output-to-temp-buffer (format "*Workflow Analysis: %s*" workflow-name)
      (princ (format "=== Workflow Analysis: %s ===\n\n" workflow-name))
      (princ (format "Analyzed: %s\n" timestamp))
      (princ (format "Total Tests: %d\n\n" total-tests))
      (princ "--- Issues Detected ---\n")
      (dolist (issue issues)
        (princ (format "  - %s: %d tests (%.0f%%)\n"
                       (or (plist-get issue :type) "unknown")
                       (or (plist-get issue :count) 0)
                       (* 100 (or (plist-get issue :percentage) 0)))))
      (princ "\n--- Patterns ---\n")
      (dolist (pattern patterns)
        (princ (format "  - %s: %S\n"
                       (or (plist-get pattern :type) "unknown")
                       (or (plist-get pattern :tools) '()))))
      (princ "\n--- Recommendations ---\n")
      (dolist (rec recommendations)
        (princ (format "  - %s\n" rec))))))

(defun gptel-workflow-generate-improvements (workflow-name)
  "Generate improvement suggestions for WORKFLOW-NAME using analyzer subagent.
This is the auto-feedback loop that can suggest improvements to the workflow."
  (interactive
   (list (completing-read "Workflow: " '("plan_agent" "code_agent"))))
  (let* ((analysis (gptel-workflow-analyze-results workflow-name))
         (history (gptel-workflow-benchmark-load-history workflow-name)))
    (if (not analysis)
        (message "[workflow-bench] No analysis available")
      (let* ((prompt (format "Analyze the following workflow benchmark data and suggest specific improvements.

WORKFLOW: %s

ANALYSIS:
%s

HISTORICAL TREND:
%s

Generate:
1. Specific improvements to test cases
2. Suggested changes to success criteria thresholds
3. New test cases to add
4. Prompt improvements for the agent

Output as JSON with keys: test_improvements, threshold_changes, new_tests, prompt_suggestions"
                             workflow-name
                             (format "%S" analysis)
                             (format "%S" (cl-subseq (or history '()) 0 (min 5 (length history))))))
             (improvements nil))
        (if (fboundp 'gptel-agent--task)
            (gptel-agent--task
             (lambda (result)
               (setq improvements (condition-case nil
                                      (json-read-from-string result)
                                    (error (list :raw result))))
               (gptel-workflow--display-improvements workflow-name improvements))
             "analyzer"
             (format "Workflow improvements: %s" workflow-name)
             prompt)
          (message "[workflow-bench] gptel-agent--task not available"))))))

(defun gptel-workflow--display-improvements (workflow-name improvements)
  "Display IMPROVEMENTS for WORKFLOW-NAME."
  (with-output-to-temp-buffer (format "*Workflow Improvements: %s*" workflow-name)
    (princ (format "=== Suggested Improvements: %s ===\n\n" workflow-name))
    (when (listp improvements)
      (when-let ((test-imp (alist-get 'test_improvements improvements)))
        (princ "--- Test Improvements ---\n")
        (princ (format "%s\n\n" test-imp)))
      (when-let ((thresholds (alist-get 'threshold_changes improvements)))
        (princ "--- Threshold Changes ---\n")
        (princ (format "%s\n\n" thresholds)))
      (when-let ((new-tests (alist-get 'new_tests improvements)))
        (princ "--- New Tests to Add ---\n")
        (princ (format "%s\n\n" new-tests)))
      (when-let ((prompt-sug (alist-get 'prompt_suggestions improvements)))
        (princ "--- Prompt Suggestions ---\n")
        (princ (format "%s\n" prompt-sug))))))

(defun gptel-workflow-auto-improve (workflow-name)
  "Run full auto-improvement cycle for WORKFLOW-NAME.
1. Run all benchmarks
2. Analyze results
3. Generate improvements
4. Display summary"
  (interactive
   (list (completing-read "Workflow: " '("plan_agent" "code_agent"))))
  (message "[workflow-bench] Starting auto-improvement cycle for %s..." workflow-name)
  (gptel-workflow-benchmark-run-all workflow-name))

;;; Provide

(provide 'gptel-workflow-benchmark)

;;; gptel-workflow-benchmark.el ends here
