;;; gptel-benchmark-editor.el --- File editing for auto-improvement -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, editor, improvement

;;; Commentary:

;; File editing functions for applying improvements to skills, tests, and workflows.
;; Provides safe, structured editing with checkpoints for rollback.

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-core)

;;; Customization

(defgroup gptel-benchmark-editor nil
  "File editing for auto-improvement."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-editor-backup t
  "Whether to create backups before editing."
  :type 'boolean
  :group 'gptel-benchmark-editor)

(defcustom gptel-benchmark-editor-skills-dir "./assistant/skills/"
  "Directory containing skill definitions."
  :type 'directory
  :group 'gptel-benchmark-editor)

(defcustom gptel-benchmark-editor-tests-dir "./benchmarks/skill-tests/"
  "Directory containing test definitions."
  :type 'directory
  :group 'gptel-benchmark-editor)

;;; Checkpoint Management

(defvar gptel-benchmark-editor-checkpoints (make-hash-table :test 'equal)
  "Hash table of checkpoints for rollback.")

(defun gptel-benchmark-editor-create-checkpoint (file)
  "Create a checkpoint for FILE before editing."
  (when (and gptel-benchmark-editor-backup (file-exists-p file))
    (let* ((checkpoint-id (format-time-string "%Y%m%d-%H%M%S"))
           (content (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
           (checkpoint (list :id checkpoint-id
                             :file file
                             :content content
                             :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
      (puthash (concat file ":" checkpoint-id) checkpoint gptel-benchmark-editor-checkpoints)
      checkpoint-id)))

(defun gptel-benchmark-editor-rollback (file checkpoint-id)
  "Restore FILE to state at CHECKPOINT-ID."
  (let ((checkpoint (gethash (concat file ":" checkpoint-id) gptel-benchmark-editor-checkpoints)))
    (if checkpoint
        (progn
          (with-temp-file file
            (insert (plist-get checkpoint :content)))
          (message "[editor] Rolled back %s to %s" file checkpoint-id)
          t)
      (message "[editor] Checkpoint %s not found for %s" checkpoint-id file)
      nil)))

;;; Skill Editing

(defun gptel-benchmark-edit-skill-prompt (skill-name modifications &optional callback)
  "Edit SKILL-NAME's prompt with MODIFICATIONS.
MODIFICATIONS is a list of (operation . content) pairs.
Operations: :prepend, :append, :replace-section, :add-constraint."
  (let* ((skill-file (expand-file-name (format "%s/SKILL.md" skill-name)
                                       gptel-benchmark-editor-skills-dir)))
    (if (not (file-exists-p skill-file))
        (message "[editor] Skill file not found: %s" skill-file)
      (let ((checkpoint-id (gptel-benchmark-editor-create-checkpoint skill-file)))
        (with-temp-buffer
          (insert-file-contents skill-file)
          (dolist (mod modifications)
            (pcase (car mod)
              (:prepend
               (goto-char (point-min))
               (when (re-search-forward "^---" nil t 2)
                 (forward-line 1)
                 (insert (cdr mod) "\n\n")))
              (:append
               (goto-char (point-max))
               (insert "\n" (cdr mod)))
              (:add-constraint
               (goto-char (point-min))
               (when (re-search-forward "## Constraints" nil t)
                 (forward-line 1)
                 (insert "- " (cdr mod) "\n")))
              (:replace-section
               (let ((section (plist-get (cdr mod) :section))
                     (new-content (plist-get (cdr mod) :content)))
                 (goto-char (point-min))
                 (when (re-search-forward (format "^## %s" section) nil t)
                   (let ((start (line-beginning-position)))
                     (if (re-search-forward "^## " nil t)
                         (forward-line -1)
                       (goto-char (point-max)))
                     (delete-region start (point))
                     (insert "## " section "\n" new-content)))))))
          (write-region (point-min) (point-max) skill-file))
        (message "[editor] Modified %s (checkpoint: %s)" skill-file checkpoint-id)
        (when callback (funcall callback checkpoint-id))
        checkpoint-id))))

(defun gptel-benchmark-edit-skill-add-behavior (skill-name behavior type)
  "Add BEHAVIOR to SKILL-NAME. TYPE is 'expected or 'forbidden."
  (let* ((test-file (expand-file-name (format "%s.json" skill-name)
                                      gptel-benchmark-editor-tests-dir)))
    (if (not (file-exists-p test-file))
        (message "[editor] Test file not found: %s" test-file)
      (let ((checkpoint-id (gptel-benchmark-editor-create-checkpoint test-file)))
        (let* ((data (gptel-benchmark-read-json test-file))
               (test-cases (cdr (assq 'test_cases data))))
          (when (and test-cases (> (length test-cases) 0))
            (let ((first-test (aref test-cases 0))
                  (key (if (eq type 'expected) 'expected_behaviors 'forbidden_behaviors)))
              (let ((behaviors (cdr (assq key first-test))))
                (when (vectorp behaviors)
                  (let ((new-behaviors (vconcat behaviors (vector behavior))))
                    (aset test-cases 0
                          (cons (cons key new-behaviors)
                                (assq-delete-all key first-test))))
                  (gptel-benchmark-write-json data test-file)))))
          (message "[editor] Added %s behavior to %s (checkpoint: %s)" 
                   type skill-name checkpoint-id)
          checkpoint-id)))))

;;; Test Editing

(defun gptel-benchmark-edit-test-definition (skill-name test-id modifications)
  "Edit TEST-ID in SKILL-NAME's test definition.
MODIFICATIONS is a plist of changes."
  (let* ((test-file (expand-file-name (format "%s.json" skill-name)
                                      gptel-benchmark-editor-tests-dir)))
    (if (not (file-exists-p test-file))
        (message "[editor] Test file not found: %s" test-file)
      (let ((checkpoint-id (gptel-benchmark-editor-create-checkpoint test-file)))
        (let* ((data (gptel-benchmark-read-json test-file))
               (test-cases (cdr (assq 'test_cases data)))
               (found nil))
          (when (vectorp test-cases)
            (dotimes (i (length test-cases))
              (let ((test (aref test-cases i)))
                (when (equal (cdr (assq 'id test)) test-id)
                  (setq found t)
                  (let ((modified test))
                    (when (plist-get modifications :prompt)
                      (setq modified (cons (cons 'prompt (plist-get modifications :prompt))
                                          (assq-delete-all 'prompt modified))))
                    (when (plist-get modifications :expected)
                      (let ((expected (cdr (assq 'expected_behaviors modified))))
                        (setq modified (cons (cons 'expected_behaviors
                                                  (vconcat expected (plist-get modifications :expected)))
                                            (assq-delete-all 'expected_behaviors modified)))))
                    (when (plist-get modifications :forbidden)
                      (let ((forbidden (cdr (assq 'forbidden_behaviors modified))))
                        (setq modified (cons (cons 'forbidden_behaviors
                                                  (vconcat forbidden (plist-get modifications :forbidden)))
                                            (assq-delete-all 'forbidden_behaviors modified)))))
                    (aset test-cases i modified)))))
            (when found
              (gptel-benchmark-write-json data test-file)
              (message "[editor] Modified test %s in %s (checkpoint: %s)"
                       test-id skill-name checkpoint-id))))
          checkpoint-id)))

(defun gptel-benchmark-add-test-case (skill-name test-case)
  "Add TEST-CASE to SKILL-NAME's test definition."
  (let* ((test-file (expand-file-name (format "%s.json" skill-name)
                                      gptel-benchmark-editor-tests-dir)))
    (if (not (file-exists-p test-file))
        (message "[editor] Test file not found: %s" test-file)
      (let ((checkpoint-id (gptel-benchmark-editor-create-checkpoint test-file)))
        (let* ((data (gptel-benchmark-read-json test-file))
               (test-cases (cdr (assq 'test_cases data))))
          (when (vectorp test-cases)
            (let ((new-cases (vconcat test-cases (vector test-case))))
              (setq data (cons (cons 'test_cases new-cases)
                              (assq-delete-all 'test_cases data)))
              (gptel-benchmark-write-json data test-file)
              (message "[editor] Added test case to %s (checkpoint: %s)"
                       skill-name checkpoint-id))))
        checkpoint-id))))

;;; Workflow Editing

(defun gptel-benchmark-edit-workflow-config (workflow-name modifications)
  "Edit WORKFLOW-NAME configuration with MODIFICATIONS."
  (let ((workflow-file (expand-file-name (format "%s.el" workflow-name) "lisp/workflows/")))
    (if (not (file-exists-p workflow-file))
        (message "[editor] Workflow file not found: %s" workflow-file)
      (let ((checkpoint-id (gptel-benchmark-editor-create-checkpoint workflow-file)))
        (with-temp-buffer
          (insert-file-contents workflow-file)
          (dolist (mod modifications)
            (pcase (car mod)
              (:add-step
               (goto-char (point-max))
               (forward-line -3)
               (insert (cdr mod) "\n"))
              (:modify-threshold
               (goto-char (point-min))
               (when (re-search-forward (format "defcustom.*%s" (plist-get (cdr mod) :name)) nil t)
                 (when (re-search-forward ":type 'number" nil t)
                   (forward-line 1)
                   (when (re-search-forward "[0-9]+" nil t)
                     (replace-match (number-to-string (plist-get (cdr mod) :value))))))))))
          (write-region (point-min) (point-max) workflow-file))
        (message "[editor] Modified workflow %s (checkpoint: %s)" workflow-name checkpoint-id)
        checkpoint-id))))

;;; Patch Application

(defun gptel-benchmark-apply-patch (file patch)
  "Apply PATCH to FILE.
PATCH is a unified diff format string."
  (let ((checkpoint-id (gptel-benchmark-editor-create-checkpoint file)))
    (let ((temp-patch (gptel-benchmark-make-temp-file "benchmark-patch")))
      (with-temp-file temp-patch
        (insert patch))
      (let ((result (call-process "patch" nil nil nil "-p1" "-i" temp-patch file)))
        (delete-file temp-patch)
        (if (= result 0)
            (progn
              (message "[editor] Applied patch to %s (checkpoint: %s)" file checkpoint-id)
              checkpoint-id)
          (message "[editor] Failed to apply patch to %s" file)
          nil)))))

;;; Utility Functions

(defun gptel-benchmark-editor-list-checkpoints ()
  "List all stored checkpoints."
  (let (result)
    (maphash (lambda (key checkpoint)
               (push (list :key key
                           :file (plist-get checkpoint :file)
                           :timestamp (plist-get checkpoint :timestamp))
                     result))
             gptel-benchmark-editor-checkpoints)
    result))

(defun gptel-benchmark-editor-clear-checkpoints ()
  "Clear all stored checkpoints."
  (clrhash gptel-benchmark-editor-checkpoints)
  (message "[editor] Cleared all checkpoints"))

;;; Provide

(provide 'gptel-benchmark-editor)

;;; gptel-benchmark-editor.el ends here