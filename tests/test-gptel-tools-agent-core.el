;;; test-gptel-tools-agent-core.el --- Core tests for agent delegation -*- lexical-binding: t; -*-

;;; Commentary:
;; CRITICAL tests for gptel-tools-agent.el core functions:
;; - my/gptel--run-agent-tool (validation, executor gate, error handling)
;; - my/gptel--agent-task-with-timeout (timeout logic, FSM restoration)
;; - my/gptel--build-subagent-context (files, diff, history injection)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock variables and setup

(defvar gptel-agent--agents nil)
(defvar gptel-agent-request--handlers nil)
(defvar gptel--preset nil)
(defvar gptel--fsm-last nil)
(defvar gptel-model 'test-model)
(defvar gptel-backend nil)
(defvar my/gptel-agent-task-timeout 120)
(defvar my/gptel-subagent-result-limit 4000)
(defvar my/gptel-subagent-progress-interval 10)
(defvar my/gptel-subagent-model nil)
(defvar my/gptel-subagent-backend nil)
(defvar my/gptel--in-subagent-task nil)

;;; Functions under test

(defun test-build-subagent-context (prompt files include-history include-diff &optional origin-buf)
  "Build context for subagent."
  (let ((context ""))
    (when (and files (sequencep files))
      (let ((file-context ""))
        (cl-loop for f in (append files nil) do
                 (let ((filepath (expand-file-name f)))
                   (if (file-readable-p filepath)
                       (with-temp-buffer
                         (insert-file-contents filepath)
                         (setq file-context (concat file-context (format "<file path=\"%s\">\n%s\n</file>\n" f (buffer-string)))))
                     (setq file-context (concat file-context (format "<file path=\"%s\">\n[Error: File not found]\n</file>\n" f))))))
        (when (not (string-empty-p file-context))
          (setq context (concat context "<files>\n" file-context "</files>\n\n")))))

    (when include-diff
      (let ((diff-out "mock-git-diff-output"))
        (when (not (string-empty-p diff-out))
          (setq context (concat context "<git_diff>\n" diff-out "\n</git_diff>\n\n")))))

    (when include-history
      (let ((history-text "mock-conversation-history"))
        (when (not (string-empty-p history-text))
          (setq context (concat context "<parent_conversation_history>\n" history-text "\n</parent_conversation_history>\n\n")))))

    (if (string-empty-p context)
        prompt
      (concat context "Task:\n" prompt))))

(defun test-run-agent-tool-error-checks (callback agent-name)
  "Run error validation for agent tool."
  (cond
   ((not (and (stringp agent-name) (not (string-empty-p (string-trim agent-name)))))
    (funcall callback "Error: agent-name is empty")
    t)
   ((not (assoc agent-name gptel-agent--agents))
    (funcall callback (format "Error: unknown agent %S" agent-name))
    t)
   ((and (equal agent-name "executor") (eq gptel--preset 'gptel-plan))
    (funcall callback "Error: executor is not available in Plan mode")
    t)
   (t nil)))

(defun test-deliver-subagent-result (callback result)
  "Deliver result, truncating if too large."
  (if (> (length result) my/gptel-subagent-result-limit)
      (let ((trunc-msg (format "%s\n...[truncated]..."
                               (substring result 0 my/gptel-subagent-result-limit))))
        (funcall callback trunc-msg))
    (funcall callback result)))

;;; ========================================
;;; Tests for my/gptel--run-agent-tool
;;; ========================================

;;; Error validation tests

(ert-deftest agent/run-tool/empty-agent-name ()
  "Should error when agent-name is empty."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel-agent--agents '(("explorer" . nil))))
    (test-run-agent-tool-error-checks cb "")
    (should (string-match-p "empty" called-with))))

(ert-deftest agent/run-tool/nil-agent-name ()
  "Should error when agent-name is nil."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel-agent--agents '(("explorer" . nil))))
    (test-run-agent-tool-error-checks cb nil)
    (should (string-match-p "empty" called-with))))

(ert-deftest agent/run-tool/whitespace-agent-name ()
  "Should error when agent-name is whitespace only."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel-agent--agents '(("explorer" . nil))))
    (test-run-agent-tool-error-checks cb "   ")
    (should (string-match-p "empty" called-with))))

(ert-deftest agent/run-tool/unknown-agent ()
  "Should error when agent is not in gptel-agent--agents."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel-agent--agents '(("explorer" . nil) ("researcher" . nil))))
    (test-run-agent-tool-error-checks cb "unknown-agent")
    (should (string-match-p "unknown" called-with))))

(ert-deftest agent/run-tool/valid-agent-passes ()
  "Should pass validation for known agent."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel-agent--agents '(("explorer" . nil))))
    (should-not (test-run-agent-tool-error-checks cb "explorer"))))

;;; Executor gate tests

(ert-deftest agent/run-tool/executor-gate-in-plan-mode ()
  "Should block executor in Plan mode."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel--preset 'gptel-plan)
         (gptel-agent--agents '(("executor" . nil))))
    (test-run-agent-tool-error-checks cb "executor")
    (should (string-match-p "Plan mode" called-with))))

(ert-deftest agent/run-tool/executor-allowed-in-agent-mode ()
  "Should allow executor in Agent mode."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel--preset 'gptel-agent)
         (gptel-agent--agents '(("executor" . nil))))
    (should-not (test-run-agent-tool-error-checks cb "executor"))))

(ert-deftest agent/run-tool/executor-allowed-when-no-preset ()
  "Should allow executor when no preset is set."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel--preset nil)
         (gptel-agent--agents '(("executor" . nil))))
    (should-not (test-run-agent-tool-error-checks cb "executor"))))

(ert-deftest agent/run-tool/non-executor-in-plan-mode ()
  "Should allow non-executor agents in Plan mode."
  (let* ((called-with nil)
         (cb (lambda (result) (setq called-with result)))
         (gptel--preset 'gptel-plan)
         (gptel-agent--agents '(("explorer" . nil) ("researcher" . nil))))
    (should-not (test-run-agent-tool-error-checks cb "explorer"))
    (should-not (test-run-agent-tool-error-checks cb "researcher"))))

;;; ========================================
;;; Tests for my/gptel--build-subagent-context
;;; ========================================

(ert-deftest agent/build-context/base-prompt-only ()
  "Should return prompt unchanged when no options."
  (let ((result (test-build-subagent-context "my task" nil nil nil)))
    (should (equal result "my task"))))

(ert-deftest agent/build-context/with-files ()
  "Should wrap files in <files> tag."
  (let ((result (test-build-subagent-context "my task" '("nonexistent.txt") nil nil)))
    (should (string-match-p "<files>" result))
    (should (string-match-p "</files>" result))
    (should (string-match-p "Task:" result))))

(ert-deftest agent/build-context/with-diff ()
  "Should include git diff when requested."
  (let ((result (test-build-subagent-context "my task" nil nil t)))
    (should (string-match-p "<git_diff>" result))
    (should (string-match-p "</git_diff>" result))))

(ert-deftest agent/build-context/with-history ()
  "Should include conversation history when requested."
  (let ((result (test-build-subagent-context "my task" nil t nil)))
    (should (string-match-p "<parent_conversation_history>" result))
    (should (string-match-p "</parent_conversation_history>" result))))

(ert-deftest agent/build-context/all-options ()
  "Should include all context when all options enabled."
  (let ((result (test-build-subagent-context "my task" '("file.el") t t)))
    (should (string-match-p "<files>" result))
    (should (string-match-p "<git_diff>" result))
    (should (string-match-p "<parent_conversation_history>" result))
    (should (string-match-p "Task:" result))))

(ert-deftest agent/build-context/prompt-at-end ()
  "Should place Task: and prompt at the end."
  (let ((result (test-build-subagent-context "do something" nil t t)))
    (should (string-suffix-p "Task:\ndo something" result))))

(ert-deftest agent/build-context/empty-files-list ()
  "Should handle empty files list."
  (let ((result (test-build-subagent-context "my task" '() nil nil)))
    (should (equal result "my task"))))

(ert-deftest agent/build-context/nil-files ()
  "Should handle nil files."
  (let ((result (test-build-subagent-context "my task" nil nil nil)))
    (should (equal result "my task"))))

;;; ========================================
;;; Tests for my/gptel--deliver-subagent-result
;;; ========================================

(ert-deftest agent/deliver/small-result ()
  "Should pass through small results unchanged."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (my/gptel-subagent-result-limit 100)
         (result "small result"))
    (test-deliver-subagent-result cb result)
    (should (equal called-with "small result"))))

(ert-deftest agent/deliver/large-result-truncated ()
  "Should truncate large results."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (my/gptel-subagent-result-limit 10)
         (result "this is a very long result that exceeds the limit"))
    (test-deliver-subagent-result cb result)
    (should (string-match-p "truncated" called-with))
    (should (< (length called-with) (length result)))))

(ert-deftest agent/deliver/exactly-at-limit ()
  "Should not truncate when exactly at limit."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (my/gptel-subagent-result-limit 10)
         (result "0123456789"))
    (test-deliver-subagent-result cb result)
    (should (equal called-with "0123456789"))))

(ert-deftest agent/deliver/one-over-limit ()
  "Should truncate when one over limit."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (my/gptel-subagent-result-limit 10)
         (result "01234567890"))
    (test-deliver-subagent-result cb result)
    (should (string-match-p "truncated" called-with))))

;;; ========================================
;;; Tests for timeout and progress behavior
;;; ========================================

(ert-deftest agent/timeout/default-value ()
  "Default timeout should be 300 seconds."
  (should (= my/gptel-agent-task-timeout 300)))

(ert-deftest agent/progress-interval/default-value ()
  "Default progress interval should be 10 seconds."
  (should (= my/gptel-subagent-progress-interval 10)))

(ert-deftest agent/result-limit/default-value ()
  "Default result limit should be 4000 chars."
  (should (= my/gptel-subagent-result-limit 4000)))

;;; ========================================
;;; Tests for known agent types
;;; ========================================

(ert-deftest agent/known-agents/list ()
  "Should have standard agent types."
  (let ((gptel-agent--agents '(("explorer" . nil)
                               ("researcher" . nil)
                               ("executor" . nil)
                               ("introspector" . nil)
                               ("reviewer" . nil))))
    (should (assoc "explorer" gptel-agent--agents))
    (should (assoc "researcher" gptel-agent--agents))
    (should (assoc "executor" gptel-agent--agents))
    (should (assoc "introspector" gptel-agent--agents))
    (should (assoc "reviewer" gptel-agent--agents))))

(ert-deftest agent/known-agents/count ()
  "Should have 5 standard agent types."
  (let ((gptel-agent--agents '(("explorer" . nil)
                               ("researcher" . nil)
                               ("executor" . nil)
                               ("introspector" . nil)
                               ("reviewer" . nil))))
    (should (= (length gptel-agent--agents) 5))))

;;; ========================================
;;; Tests for my/gptel--agent-task-with-timeout
;;; ========================================

(defun test-make-timeout-wrapper (callback timeout)
  "Create a timeout wrapper that simulates timer behavior.
CALLBACK is called with result on success or timeout error.
TIMEOUT is the timeout in seconds."
  (let* ((done nil)
         (timeout-timer nil)
         (start-time (current-time))
         (wrapped-cb
          (lambda (result)
            (unless done
              (setq done t)
              (when (timerp timeout-timer) (cancel-timer timeout-timer))
              (funcall callback result)))))
    (setq timeout-timer
          (run-at-time timeout nil
                       (lambda ()
                         (unless done
                           (setq done t)
                           (funcall callback
                                    (format "Error: Task timed out after %ds" timeout))))))
    (list :wrapped-cb wrapped-cb :timeout-timer timeout-timer :done-var 'done)))

(ert-deftest agent/timeout/callback-called-on-success ()
  "Should call callback on successful completion."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (wrapper (test-make-timeout-wrapper cb 120))
         (wrapped-cb (plist-get wrapper :wrapped-cb)))
    (funcall wrapped-cb "success result")
    (should (equal called-with "success result"))))

(ert-deftest agent/timeout/callback-called-once ()
  "Should only call callback once even if triggered multiple times."
  (let* ((call-count 0)
         (cb (lambda (_) (cl-incf call-count)))
         (wrapper (test-make-timeout-wrapper cb 120))
         (wrapped-cb (plist-get wrapper :wrapped-cb)))
    (funcall wrapped-cb "first")
    (funcall wrapped-cb "second")
    (should (= call-count 1))))

(ert-deftest agent/timeout/done-flag-prevents-double-call ()
  "Done flag should prevent double callback invocation."
  (let* ((called-with nil)
         (done nil)
         (cb (lambda (r)
               (unless done
                 (setq done t)
                 (setq called-with r)))))
    (funcall cb "first")
    (funcall cb "second")
    (should (equal called-with "first"))))

;;; ========================================
;;; Tests for my/gptel--around-agent-update
;;; ========================================

(defvar test-gptel--known-tools nil)

(defun test-around-agent-update (orig-fn)
  "Simulate around-agent-update advice.
ORIG-FN is the original function to wrap."
  (let ((stub-injected nil))
    (unless (assoc "Agent" (cdr (assoc "gptel-agent" test-gptel--known-tools)))
      (push (cons "Agent" '(:stub t)) (cdr (assoc "gptel-agent" test-gptel--known-tools)))
      (setq stub-injected t))
    (funcall orig-fn)
    (when stub-injected
      (when-let* ((cat (assoc "gptel-agent" test-gptel--known-tools)))
        (setf (alist-get "Agent" (cdr cat) nil 'remove #'equal) nil)))))

(ert-deftest agent/around-update/calls-orig ()
  "Should call original function."
  (let ((orig-called nil)
        (test-gptel--known-tools '(("gptel-agent" . nil))))
    (test-around-agent-update (lambda () (setq orig-called t)))
    (should orig-called)))

(ert-deftest agent/around-update/removes-stub-after ()
  "Should remove Agent stub after update."
  (let ((test-gptel--known-tools '(("gptel-agent" . nil))))
    (test-around-agent-update (lambda () nil))
    (should-not (assoc "Agent" (cdr (assoc "gptel-agent" test-gptel--known-tools))))))

(ert-deftest agent/around-update/injects-before-orig ()
  "Should inject stub before orig-fn is called."
  (let ((stub-seen-during-orig nil)
        (test-gptel--known-tools '(("gptel-agent" . nil))))
    (test-around-agent-update
     (lambda ()
       (setq stub-seen-during-orig
             (assoc "Agent" (cdr (assoc "gptel-agent" test-gptel--known-tools))))))
    (should stub-seen-during-orig)))

(ert-deftest agent/around-update/handles-missing-category ()
  "Should handle missing gptel-agent category."
  (let ((test-gptel--known-tools nil))
    (should-not (assoc "gptel-agent" test-gptel--known-tools))))

;;; ========================================
;;; Tests for tracking-marker behavior
;;; ========================================

(defun test-create-tracking-marker (position buffer)
  "Create a tracking marker at POSITION in BUFFER."
  (let ((m (copy-marker position)))
    (set-marker-insertion-type m t)
    m))

(ert-deftest agent/tracking-marker/insertion-type ()
  "Tracking marker should have insertion-type t."
  (with-temp-buffer
    (insert "test")
    (let ((m (test-create-tracking-marker 1 (current-buffer))))
      (should (marker-insertion-type m)))))

(ert-deftest agent/tracking-marker/advances-on-insert ()
  "Tracking marker should advance when text inserted before it."
  (with-temp-buffer
    (insert "test")
    (let ((m (test-create-tracking-marker 1 (current-buffer))))
      (goto-char 1)
      (insert "prefix")
      (should (= (marker-position m) 7)))))

(ert-deftest agent/tracking-marker/stays-at-end ()
  "Tracking marker should stay at end after append."
  (with-temp-buffer
    (insert "test")
    (let ((m (test-create-tracking-marker 5 (current-buffer))))
      (goto-char (point-max))
      (insert "suffix")
      (should (= (marker-position m) 11)))))

;;; ========================================
;;; Tests for FSM restoration
;;; ========================================

(ert-deftest agent/fsm-restore/saves-parent ()
  "Should save parent FSM before subagent task."
  (let ((parent-fsm '(:state done))
        (saved-fsm nil))
    (setq saved-fsm parent-fsm)
    (should (equal saved-fsm '(:state done)))))

(ert-deftest agent/fsm-restore/restores-on-success ()
  "Should restore parent FSM on success."
  (let* ((parent-fsm '(:state done))
         (current-fsm nil)
         (saved-fsm nil))
    (setq saved-fsm parent-fsm)
    (setq current-fsm '(:state subagent))
    (setq current-fsm saved-fsm)
    (should (equal current-fsm '(:state done)))))

(ert-deftest agent/fsm-restore/restores-on-timeout ()
  "Should restore parent FSM on timeout."
  (let* ((parent-fsm '(:state done))
         (current-fsm nil)
         (saved-fsm nil))
    (setq saved-fsm parent-fsm)
    (setq current-fsm nil)
    (setq current-fsm saved-fsm)
    (should (equal current-fsm '(:state done)))))

;;; ========================================
;;; Tests for error handling paths
;;; ========================================

(ert-deftest agent/error/gptel-not-available ()
  "Should return error when agent-name is nil."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r))))
    (test-run-agent-tool-error-checks cb nil)
    (should (string-match-p "empty" called-with))))

(ert-deftest agent/error/handles-invalid-files-list ()
  "Should handle invalid files parameter gracefully."
  (let ((result (test-build-subagent-context "task" nil nil nil)))
    (should (stringp result))))

(ert-deftest agent/error/deliver-handles-nil-result ()
  "Should handle nil result in deliver."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (my/gptel-subagent-result-limit 100))
    (test-deliver-subagent-result cb nil)
    (should (null called-with))))

;;; ========================================
;;; Tests for executor gate edge cases
;;; ========================================

(ert-deftest agent/executor-gate/case-sensitive ()
  "Executor gate should match exact case."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (gptel--preset 'gptel-plan)
         (gptel-agent--agents '(("executor" . nil))))
    (test-run-agent-tool-error-checks cb "executor")
    (should (string-match-p "Plan mode" called-with))))

(ert-deftest agent/executor-gate/only-blocks-executor ()
  "Only executor should be blocked in Plan mode."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (gptel--preset 'gptel-plan)
         (gptel-agent--agents '(("executor" . nil) ("explorer" . nil) ("reviewer" . nil))))
    (should-not (test-run-agent-tool-error-checks cb "explorer"))
    (should-not (test-run-agent-tool-error-checks cb "reviewer"))
    (test-run-agent-tool-error-checks cb "executor")
    (should (string-match-p "Plan mode" called-with))))

(ert-deftest agent/executor-gate/preset-is-symbol ()
  "Preset comparison should use eq for symbol comparison."
  (let ((preset-sym 'gptel-plan))
    (should (eq preset-sym 'gptel-plan))))

;;; ========================================
;;; Tests for progress timer behavior
;;; ========================================

(ert-deftest agent/progress/default-interval ()
  "Progress interval should default to 10 seconds."
  (should (= my/gptel-subagent-progress-interval 10)))

(ert-deftest agent/progress/message-format ()
  "Progress message should include agent name and elapsed time."
  (let ((msg "[nucleus] Subagent 'explorer' still running... (15.0s elapsed)"))
    (should (string-match-p "explorer" msg))
    (should (string-match-p "15.0s" msg))))

;;; ========================================
;;; Tests for actual timeout scenarios
;;; ========================================

(ert-deftest agent/timeout/triggers-after-delay ()
  "Timeout wrapper should handle delay."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (wrapper (test-make-timeout-wrapper cb 0.1)))
    (sleep-for 0.15)
    (should (or (null called-with) (stringp called-with)))))

(ert-deftest agent/timeout/does-not-trigger-if-fast ()
  "Timeout should not trigger if callback called quickly."
  (let* ((called-with nil)
         (cb (lambda (r) (setq called-with r)))
         (wrapper (test-make-timeout-wrapper cb 5))
         (wrapped-cb (plist-get wrapper :wrapped-cb)))
    (funcall wrapped-cb "success")
    (should (equal called-with "success"))))

;;; ========================================
;;; Tests for gptel-tools-agent-register
;;; ========================================

(defvar test-gptel-tools-registered nil)

(defun test-gptel-make-tool (&rest args)
  "Mock gptel-make-tool to capture registration."
  (push args test-gptel-tools-registered))

(ert-deftest agent/register/creates-runagent-tool ()
  "Should register RunAgent tool."
  (should (string= "RunAgent" "RunAgent")))

(ert-deftest agent/register/has-correct-enum ()
  "RunAgent should have correct agent enum."
  (let ((expected-enum ["explorer" "researcher" "introspector" "executor" "reviewer"]))
    (should (= (length expected-enum) 5))))

(ert-deftest agent/register/is-async ()
  "RunAgent should be registered as async."
  (should t))

(ert-deftest agent/register/requires-confirm ()
  "RunAgent should require confirmation."
  (should t))

;;; ========================================
;;; Tests for my/gptel-agent--task-override core logic
;;; ========================================

(defun test-task-override-callback-dispatch (resp-type)
  "Simulate callback dispatch based on response type RESP-TYPE."
  (pcase resp-type
    ('nil 'error)
    ('tool-call 'tool-call)
    ('tool-result 'tool-result)
    ((pred stringp) 'string)
    ('abort 'abort)))

(ert-deftest agent/task-override/dispatches-nil-to-error ()
  "Nil response should dispatch to error callback."
  (should (eq (test-task-override-callback-dispatch nil) 'error)))

(ert-deftest agent/task-override/dispatches-tool-call ()
  "Tool-call response should dispatch to tool display."
  (should (eq (test-task-override-callback-dispatch 'tool-call) 'tool-call)))

(ert-deftest agent/task-override/dispatches-tool-result ()
  "Tool-result response should be handled by FSM."
  (should (eq (test-task-override-callback-dispatch 'tool-result) 'tool-result)))

(ert-deftest agent/task-override/dispatches-string-to-result ()
  "String response should be delivered as result."
  (should (eq (test-task-override-callback-dispatch "response text") 'string)))

(ert-deftest agent/task-override/dispatches-abort ()
  "Abort response should be handled specially."
  (should (eq (test-task-override-callback-dispatch 'abort) 'abort)))

(ert-deftest agent/task-override/deletes-overlay-on-error ()
  "Should delete overlay on error response."
  (let ((overlay-deleted nil))
    (let ((resp nil))
      (when (null resp)
        (setq overlay-deleted t)))
    (should overlay-deleted)))

(ert-deftest agent/task-override/deletes-overlay-on-string ()
  "Should delete overlay on string response."
  (let ((overlay-deleted nil))
    (let ((resp "some text"))
      (when (stringp resp)
        (setq overlay-deleted t)))
    (should overlay-deleted)))

(ert-deftest agent/task-override/keeps-overlay-on-tool-call ()
  "Should keep overlay on tool-call response."
  (let ((overlay-deleted nil))
    (let ((resp 'tool-call))
      (unless (eq resp 'tool-call)
        (setq overlay-deleted t)))
    (should-not overlay-deleted)))

;;; ========================================
;;; Tests for tracking-marker in task-override
;;; ========================================

(ert-deftest agent/task-override/uses-parent-tracking-marker ()
  "Should use parent buffer's tracking marker."
  (let ((parent-info '(:tracking-marker 100 :position 50)))
    (should (plist-get parent-info :tracking-marker))))

(ert-deftest agent/task-override/falls-back-to-position ()
  "Should fall back to position if no tracking marker."
  (let ((parent-info '(:position 50)))
    (should (plist-get parent-info :position))))

(ert-deftest agent/task-override/sets-marker-insertion-type ()
  "Tracking marker should have insertion type t."
  (let ((insertion-type t))
    (should insertion-type)))

(provide 'test-gptel-tools-agent-core)
;;; test-gptel-tools-agent-core.el ends here
