;;; test-gptel-tools-agent-worktree.el --- Tests for worktree management -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-worktree.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-worktree.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-worktree)

;;; Staging branch tests

(ert-deftest test-worktree/staging-branch-configured ()
  "Staging branch should have a configured value."
  (should (stringp gptel-auto-workflow-staging-branch)))

;;; Remote tests

(ert-deftest test-worktree/shared-remote-function-exists ()
  "Shared remote function should exist."
  (should (fboundp 'gptel-auto-workflow--shared-remote)))

;;; Worktree state tests

(ert-deftest test-worktree/worktree-state-defined ()
  "Worktree state variable should be defined."
  (should (boundp 'gptel-auto-workflow--worktree-state)))

;;; Buffer cleanup tests

(ert-deftest test-worktree/discard-buffers-no-error ()
  "Discarding worktree buffers should not error on nil."
  (should-not (gptel-auto-workflow--discard-worktree-buffers nil)))

(provide 'test-gptel-tools-agent-worktree)
;;; test-gptel-tools-agent-worktree.el ends here