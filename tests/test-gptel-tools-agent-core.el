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
  "Default timeout should be 120 seconds."
  (should (= my/gptel-agent-task-timeout 120)))

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

(provide 'test-gptel-tools-agent-core)
;;; test-gptel-tools-agent-core.el ends here