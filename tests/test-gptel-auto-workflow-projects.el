;;; test-gptel-auto-workflow-projects.el --- Tests for multi-project support -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-projects.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-projects.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-projects)

;;; Variable tests

(ert-deftest test-projects/projects-list ()
  "Projects should be a list."
  (should (listp gptel-auto-workflow-projects)))

(ert-deftest test-projects/project-buffers-hash ()
  "Project buffers should be a hash table."
  (should (hash-table-p gptel-auto-workflow--project-buffers)))

(ert-deftest test-projects/worktree-buffers-hash ()
  "Worktree buffers should be a hash table."
  (should (hash-table-p gptel-auto-workflow--worktree-buffers)))

(ert-deftest test-projects/research-findings-cache-hash ()
  "Research findings cache should be a hash table."
  (should (hash-table-p gptel-auto-workflow--research-findings-cache)))

;;; Ensure buffer tables tests

(ert-deftest test-projects/ensure-buffer-tables ()
  "Ensure buffer tables function should exist."
  (should (fboundp 'gptel-auto-workflow--ensure-buffer-tables)))

;;; Normalized projects tests

(ert-deftest test-projects/normalized-projects-function ()
  "Normalized projects function should exist."
  (should (fboundp 'gptel-auto-workflow--normalized-projects)))

;;; Normalize worktree tests

(ert-deftest test-projects/normalize-worktree-dir-function ()
  "Normalize worktree dir function should exist."
  (should (fboundp 'gptel-auto-workflow--normalize-worktree-dir)))

(provide 'test-gptel-auto-workflow-projects)
;;; test-gptel-auto-workflow-projects.el ends here