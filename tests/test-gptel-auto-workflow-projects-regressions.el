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
         (captured-buffer nil)
         (used-safe-override nil))
    (unwind-protect
        (progn
          (make-directory worktree-dir t)
          (cl-letf (((symbol-function 'my/gptel--subagent-cache-get) (lambda (&rest _) nil))
                    ((symbol-function 'my/gptel-agent--task-override)
                     (lambda (_main-cb _agent-type _description _prompt)
                       (setq used-safe-override t
                             captured-default-directory default-directory
                             captured-buffer (current-buffer))))
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
              (lambda (&rest _args)
                (error "orig task runner should not be used when safe override is available"))
              (lambda (_result) nil)
              "executor"
              "desc"
              "prompt")
             (should used-safe-override)
             (should (equal (file-name-as-directory captured-default-directory)
                            (file-name-as-directory worktree-dir)))
             (should (equal (buffer-name captured-buffer) "*aw-worktree*"))))
       (delete-directory project-root t)
       (when (get-buffer "*aw-project-root*")
        (kill-buffer "*aw-project-root*"))
       (when (get-buffer "*aw-worktree*")
         (kill-buffer "*aw-worktree*")))))

(ert-deftest regression/auto-workflow-projects/task-routing-preserves-child-fsm-info ()
  "Per-project routing should preserve real child FSM info for nested request code."
  (let* ((project-root (make-temp-file "aw-project" t))
         (worktree-dir (expand-file-name "var/tmp/experiments/optimize/foo-exp1" project-root))
         (gptel-auto-workflow--current-project project-root)
         (gptel-auto-workflow--current-target "lisp/modules/foo.el")
         (observed-child-info nil)
         parent-fsm
         child-fsm)
    (unwind-protect
        (progn
          (make-directory worktree-dir t)
          (setq parent-fsm (gptel-make-fsm :info (list :buffer (current-buffer)
                                                       :position (point-marker))))
          (setq child-fsm (gptel-make-fsm :info (list :buffer :child-buffer
                                                      :disable-auto-retry t)))
          (cl-letf (((symbol-function 'my/gptel--subagent-cache-get) (lambda (&rest _) nil))
                    ((symbol-function 'my/gptel-agent--task-override)
                     (lambda (_main-cb _agent-type _description _prompt)
                       (setq observed-child-info (gptel-fsm-info child-fsm))))
                    ((symbol-function 'gptel-auto-workflow--get-project-for-context)
                     (lambda ()
                       (cons project-root (get-buffer-create "*aw-project-root*"))))
                    ((symbol-function 'gptel-auto-workflow--get-worktree-dir)
                     (lambda (_target) worktree-dir))
                    ((symbol-function 'gptel-auto-workflow--get-worktree-buffer)
                     (lambda (_dir) (get-buffer-create "*aw-worktree*")))
                    ((symbol-function 'gptel-fsm-info)
                     (lambda (&optional fsm)
                       (cond
                        ((eq fsm parent-fsm) (list :buffer :parent-buffer))
                        ((eq fsm child-fsm) (list :buffer :child-buffer
                                                  :disable-auto-retry t))
                        (t nil)))))
            (with-current-buffer (get-buffer-create "*aw-worktree*")
              (setq-local gptel--fsm-last parent-fsm))
            (gptel-auto-workflow--advice-task-override
             (lambda (&rest _args)
               (error "orig task runner should not be used when safe override is available"))
             (lambda (_result) nil)
             "executor"
             "desc"
             "prompt")
            (should (equal (plist-get observed-child-info :buffer) :child-buffer))
            (should (plist-get observed-child-info :disable-auto-retry))))
      (delete-directory project-root t)
      (when (get-buffer "*aw-project-root*")
        (kill-buffer "*aw-project-root*"))
      (when (get-buffer "*aw-worktree*")
        (kill-buffer "*aw-worktree*")))))

(ert-deftest regression/auto-workflow-projects/task-routing-prefers-safe-task-override ()
  "Per-project routing should prefer the safe task override when available."
  (let* ((project-root (make-temp-file "aw-project" t))
         (gptel-auto-workflow--current-project project-root)
         (called nil))
    (unwind-protect
        (cl-letf (((symbol-function 'my/gptel--subagent-cache-get) (lambda (&rest _) nil))
                  ((symbol-function 'my/gptel-agent--task-override)
                   (lambda (&rest _args) (setq called 'safe)))
                  ((symbol-function 'gptel-auto-workflow--get-project-for-context)
                   (lambda ()
                     (cons project-root (get-buffer-create "*aw-project-root*"))))
                  ((symbol-function 'gptel-auto-workflow--get-worktree-buffer)
                   (lambda (_dir) (get-buffer-create "*aw-worktree*")))
                  ((symbol-function 'gptel-fsm-info)
                   (lambda (&optional _fsm) nil)))
          (gptel-auto-workflow--advice-task-override
           (lambda (&rest _args) (setq called 'orig))
           (lambda (_result) nil)
           "analyzer"
           "desc"
           "prompt")
          (should (eq called 'safe)))
      (delete-directory project-root t)
      (when (get-buffer "*aw-project-root*")
        (kill-buffer "*aw-project-root*"))
      (when (get-buffer "*aw-worktree*")
        (kill-buffer "*aw-worktree*")))))

(ert-deftest regression/auto-workflow-projects/queue-helper-returns-before-job-runs ()
  "Queued cron work should not run inline in the `emacsclient' request."
  (let ((gptel-auto-workflow--cron-job-running nil)
        (job-ran nil)
        (scheduled nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn)
                  (setq scheduled fn)
                  'fake-timer))
              ((symbol-function 'gptel-auto-workflow--persist-status)
               (lambda (&rest _) nil)))
      (should
       (eq (gptel-auto-workflow--queue-cron-job
            "auto-workflow"
            (lambda () (setq job-ran t)))
           'queued))
      (should gptel-auto-workflow--cron-job-running)
      (should-not job-ran)
      (should (functionp scheduled))
      (funcall scheduled)
      (should job-ran)
      (should-not gptel-auto-workflow--cron-job-running))))

(ert-deftest regression/auto-workflow-projects/queue-helper-rejects-overlap ()
  "A second cron request should return immediately when one is already queued."
  (let ((gptel-auto-workflow--cron-job-running t)
        (scheduled nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (&rest _)
                  (setq scheduled t)
                  'fake-timer))
              ((symbol-function 'gptel-auto-workflow--persist-status)
               (lambda (&rest _) nil)))
      (should
       (eq (gptel-auto-workflow--queue-cron-job
            "auto-workflow"
            (lambda ()))
           'already-running))
       (should-not scheduled)
       (should gptel-auto-workflow--cron-job-running))))

(ert-deftest regression/auto-workflow-projects/run-all-projects-waits-for-async-completion ()
  "Project results should be recorded when async completion fires, not at start."
  (let ((gptel-auto-workflow-projects '("/tmp/project-a" "/tmp/project-a"))
        (callbacks nil)
        (messages nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-project-buffer)
               (lambda (_root) (get-buffer-create "*aw-project*")))
              ((symbol-function 'hack-dir-local-variables-non-file-buffer)
               (lambda (&rest _) nil))
              ((symbol-function 'gptel-auto-workflow-cron-safe)
               (lambda (completion-callback)
                 (push completion-callback callbacks)
                 'started))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages))))
      (gptel-auto-workflow-run-all-projects)
      (should (= (length callbacks) 1))
      (should-not (seq-some (lambda (msg)
                              (string-match-p "\\[auto-workflow\\] ✓ Completed:" msg))
                            messages))
      (funcall (car callbacks) '(:ok t))
      (should (seq-some (lambda (msg)
                          (string-match-p "\\[auto-workflow\\] ✓ Completed: /tmp/project-a/" msg))
                        messages))
      (should (seq-some (lambda (msg)
                          (string-match-p "\\[auto-workflow\\] All projects processed: /tmp/project-a/:success" msg))
                        messages)))))

(ert-deftest regression/auto-workflow-projects/run-all-projects-ignores-duplicate-completion ()
  "Late duplicate project completions should not re-log completion or finish twice."
  (let ((gptel-auto-workflow-projects '("/tmp/project-a"))
        (callbacks nil)
        (messages nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-project-buffer)
               (lambda (_root) (get-buffer-create "*aw-project*")))
              ((symbol-function 'hack-dir-local-variables-non-file-buffer)
               (lambda (&rest _) nil))
              ((symbol-function 'gptel-auto-workflow-cron-safe)
               (lambda (completion-callback)
                 (push completion-callback callbacks)
                 'started))
              ((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages))))
      (gptel-auto-workflow-run-all-projects)
      (should (= (length callbacks) 1))
      (funcall (car callbacks) '(:ok t))
      (funcall (car callbacks) '(:ok t :duplicate t))
      (should (= (cl-count-if
                  (lambda (msg)
                    (string-match-p "\\[auto-workflow\\] ✓ Completed: /tmp/project-a/" msg))
                  messages)
                 1))
      (should (= (cl-count-if
                  (lambda (msg)
                    (string-match-p "\\[auto-workflow\\] All projects processed:" msg))
                  messages)
                 1)))))

(provide 'test-gptel-auto-workflow-projects-regressions)

;;; test-gptel-auto-workflow-projects-regressions.el ends here
