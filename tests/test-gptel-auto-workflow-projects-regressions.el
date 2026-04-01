;;; test-gptel-auto-workflow-projects-regressions.el --- Regressions for project routing -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'gptel-auto-workflow-projects)

(defvar gptel-auto-workflow--current-project nil)
(defvar gptel-auto-workflow--current-target nil)
(defvar gptel-auto-workflow-worktree-base nil)

(ert-deftest regression/auto-workflow-projects/task-routing-uses-target-worktree-by-default ()
  "Executor routing should use the recorded target worktree even when base is defaulted."
  (let* ((project-root (make-temp-file "aw-project" t))
         (worktree-dir (expand-file-name "var/tmp/experiments/optimize/foo-exp1" project-root))
         (gptel-auto-workflow--current-project project-root)
         (gptel-auto-workflow--current-target "packages/gptel/gptel-request.el")
         (gptel-auto-workflow-worktree-base nil)
         (captured-default-directory nil)
         (captured-buffer nil))
    (unwind-protect
        (progn
          (make-directory worktree-dir t)
          (cl-letf (((symbol-function 'my/gptel--subagent-cache-get) (lambda (&rest _) nil))
                    ((symbol-function 'gptel-auto-workflow--get-project-for-context)
                     (lambda ()
                       (cons project-root (get-buffer-create "*aw-project-root*"))))
                    ((symbol-function 'gptel-auto-workflow--get-worktree-dir)
                     (lambda (_target) worktree-dir))
                    ((symbol-function 'gptel-auto-workflow--get-worktree-buffer)
                     (lambda (dir)
                       (let ((buf (get-buffer-create "*aw-worktree*")))
                         (with-current-buffer buf
                           (setq-local default-directory (file-name-as-directory dir)))
                         buf)))
                    ((symbol-function 'gptel-fsm-info)
                     (lambda (&optional _fsm) nil)))
            (gptel-auto-workflow--advice-task-override
             (lambda (_main-cb _agent-type _description _prompt)
               (setq captured-default-directory default-directory
                     captured-buffer (current-buffer)))
             (lambda (_result) nil)
             "executor"
             "desc"
             "prompt")
            (should (equal (file-name-as-directory captured-default-directory)
                           (file-name-as-directory worktree-dir)))
            (should (equal (buffer-name captured-buffer) "*aw-worktree*"))))
      (delete-directory project-root t)
      (when (get-buffer "*aw-project-root*")
        (kill-buffer "*aw-project-root*"))
      (when (get-buffer "*aw-worktree*")
        (kill-buffer "*aw-worktree*")))))

(provide 'test-gptel-auto-workflow-projects-regressions)

;;; test-gptel-auto-workflow-projects-regressions.el ends here
