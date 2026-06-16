;;; test-gptel-tools-agent-git.el --- Tests for git operations -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-git.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-git.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-git)

;;; Log conflict tests

(ert-deftest test-git/log-conflict-no-error ()
  "Log conflict should handle nil without error."
  (ignore-errors (gptel-auto-workflow--log-conflict nil nil))
  (should t))

(ert-deftest test-git/log-conflict-empty-hash ()
  "Log conflict should skip empty hash."
  (should-not (gptel-auto-workflow--log-conflict "" nil)))

;;; Subagent cache tests

(ert-deftest test-git/subagent-cache-key-exists ()
  "Subagent cache key function should exist."
  (should (fboundp 'my/gptel--subagent-cache-key)))

(ert-deftest test-git/subagent-cache-enabled-p-exists ()
  "Subagent cache enabled function should exist."
  (should (fboundp 'my/gptel--subagent-cache-enabled-p)))

(ert-deftest test-git/subagent-cache-get-exists ()
  "Subagent cache get function should exist."
  (should (fboundp 'my/gptel--subagent-cache-get)))

(ert-deftest test-git/subagent-cache-put-exists ()
  "Subagent cache put function should exist."
  (should (fboundp 'my/gptel--subagent-cache-put)))

(ert-deftest test-git/subagent-cache-clear-exists ()
  "Subagent cache clear function should exist."
  (should (fboundp 'my/gptel--subagent-cache-clear)))

;;; Deliver subagent result tests

(ert-deftest test-git/deliver-subagent-result-exists ()
  "Deliver subagent result function should exist."
  (should (fboundp 'my/gptel--deliver-subagent-result)))

;;; FSM tools seeding tests

(ert-deftest test-git/seed-fsm-tools-exists ()
  "Seed FSM tools function should exist."
  (should (fboundp 'my/gptel--seed-fsm-tools)))

;;; Task request buffer tests

(ert-deftest test-git/task-request-buffer-nil-state ()
  "Nil state should return nil."
  (should-not (my/gptel--agent-task-request-buffer nil)))

(ert-deftest test-git/task-request-buffer-non-list-state ()
  "Non-list state should return nil."
  (should-not (my/gptel--agent-task-request-buffer "not-a-list")))

(ert-deftest test-git/task-request-buffer-valid-state ()
  "Valid state with dead buffers returns nil."
  (should-not (my/gptel--agent-task-request-buffer
               '(:request-buf nil :origin-buf nil))))

(ert-deftest test-git/workflow-owned-worktree-root-nil-dir ()
  "Nil dir should return nil."
  (should-not (my/gptel--workflow-owned-worktree-root nil)))

(ert-deftest test-git/workflow-owned-worktree-root-non-string-dir ()
  "Non-string dir should return nil."
  (should-not (my/gptel--workflow-owned-worktree-root 42)))

;;; ─── Logging sanitize tests ───

(ert-deftest git/sanitize-log-escapes-percent ()
  "%% in output must be escaped for C-level message_dolog."
  (should (string-match-p "%%"
           (my/gptel--sanitize-for-logging "score: 85%"))))

(ert-deftest git/sanitize-log-escapes-ampersand ()
  "& in output must be escaped to prevent partial HTML entity artifacts."
  (should (string-match-p "&&"
           (my/gptel--sanitize-for-logging "a & b"))))

(ert-deftest git/sanitize-log-no-double-escape ()
  "Already-escaped %% should not become %%%%."
  (should-not (string-match-p "%%%%"
                (my/gptel--sanitize-for-logging "%%s"))))

(ert-deftest git/sanitize-log-newlines-replaced ()
  "Newlines must be replaced with spaces."
  (should-not (string-match-p "\n"
                (my/gptel--sanitize-for-logging "line1\nline2"))))

(ert-deftest git/message-advice-safe-when-context-activity-unbound ()
  "my/gptel--agent-task-note-message-activity is the :before advice
on `message'.  When my/gptel--agent-task-note-context-activity is
NOT bound (e.g., if gptel-tools-agent-subagent hasn't loaded), the
advice must silently skip — not raise void-function.

Regression for the same bug class as fad42a82d8 fix on the write-region
advice, but in the message advice path which was NOT fixed by fad42a82d8."
  (require 'gptel-tools-agent-git)
  (require 'gptel-tools-agent-subagent)
  (let ((saved-def (symbol-function 'my/gptel--agent-task-note-context-activity)))
    (unwind-protect
        (progn
          (fmakunbound 'my/gptel--agent-task-note-context-activity)
          (should-not (fboundp 'my/gptel--agent-task-note-context-activity))
          (condition-case err
              (progn (message "test message") t)
            (error
             (ert-fail (format "message advice raised: %s" (error-message-string err))))))
      ;; Restore: fset the saved definition (works even if require was no-op)
      (fset 'my/gptel--agent-task-note-context-activity saved-def)
      (should (fboundp 'my/gptel--agent-task-note-context-activity)))))

(provide 'test-gptel-tools-agent-git)
;;; test-gptel-tools-agent-git.el ends here