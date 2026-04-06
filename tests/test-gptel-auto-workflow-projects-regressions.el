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
  (ert-skip "Flaky test - mocking issues with task routing")
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
  (ert-skip "Flaky test - mocking issues with child FSM info")
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

(ert-deftest regression/auto-workflow-projects/task-routing-nil-fsm-info-follows-child-fsm ()
  "Nil `gptel-fsm-info' lookups should follow the active child FSM, not the parent placeholder."
  (let* ((project-root (make-temp-file "aw-project" t))
         (worktree-dir (expand-file-name "var/tmp/experiments/optimize/foo-exp1" project-root))
         (gptel-auto-workflow--current-project project-root)
         (gptel-auto-workflow--current-target "lisp/modules/foo.el")
         (observed-info nil)
         (parent-info (list :buffer :parent-buffer
                            :position :parent-pos))
         (child-info (list :buffer :child-buffer
                           :position :child-pos
                           :tools '(:child-tools)))
         parent-fsm
         child-fsm)
    (unwind-protect
        (progn
          (make-directory worktree-dir t)
          (setq parent-fsm (gptel-make-fsm :info parent-info))
          (setq child-fsm (gptel-make-fsm :info child-info))
          (cl-letf (((symbol-function 'my/gptel--subagent-cache-get) (lambda (&rest _) nil))
                    ((symbol-function 'my/gptel-agent--task-override)
                     (lambda (_main-cb _agent-type _description _prompt)
                       (setq-local gptel--fsm-last child-fsm)
                       (setq observed-info (gptel-fsm-info))))
                    ((symbol-function 'gptel-auto-workflow--get-project-for-context)
                     (lambda ()
                       (cons project-root (get-buffer-create "*aw-project-root*"))))
                    ((symbol-function 'gptel-auto-workflow--get-worktree-dir)
                     (lambda (_target) worktree-dir))
                    ((symbol-function 'gptel-auto-workflow--get-worktree-buffer)
                     (lambda (_dir)
                       (let ((buf (get-buffer-create "*aw-worktree*")))
                         (with-current-buffer buf
                           (setq-local gptel--fsm-last parent-fsm))
                         buf)))
                    ((symbol-function 'gptel-fsm-info)
                     (lambda (&optional fsm)
                       (let ((active-fsm (or fsm
                                             (and (boundp 'gptel--fsm-last)
                                                  gptel--fsm-last))))
                         (cond
                          ((eq active-fsm parent-fsm) parent-info)
                          ((eq active-fsm child-fsm) child-info)
                          (t nil))))))
            (gptel-auto-workflow--advice-task-override
             (lambda (&rest _args)
               (error "orig task runner should not be used when safe override is available"))
             (lambda (_result) nil)
             "analyzer"
             "desc"
             "prompt")
            (should (equal observed-info child-info))
            (should (equal (plist-get observed-info :tools) '(:child-tools)))))
      (delete-directory project-root t)
       (when (get-buffer "*aw-project-root*")
         (kill-buffer "*aw-project-root*"))
       (when (get-buffer "*aw-worktree*")
         (kill-buffer "*aw-worktree*")))))

(ert-deftest regression/auto-workflow-projects/get-worktree-buffer-anchors-relative-dirs-to-project-root ()
  "Relative worktree dirs should resolve from the workflow project root."
  (let* ((project-root (make-temp-file "aw-project" t))
         (exp1-dir (expand-file-name "var/tmp/experiments/optimize/foo-exp1" project-root))
         (relative-dir "var/tmp/experiments/optimize/foo-exp2")
         (expected-dir (expand-file-name relative-dir project-root))
         (gptel-auto-workflow--current-project project-root)
         (gptel-auto-workflow--worktree-buffers (make-hash-table :test 'equal))
         (gptel-auto-workflow--project-buffers (make-hash-table :test 'equal))
         created-buf)
    (unwind-protect
        (progn
          (make-directory exp1-dir t)
          (make-directory expected-dir t)
          (cl-letf (((symbol-function 'gptel-mode) (lambda () nil))
                    ((symbol-function 'gptel--apply-preset) (lambda (&rest _) nil))
                    ((symbol-function 'hack-dir-local-variables-non-file-buffer) (lambda (&rest _) nil))
                    ((symbol-function 'gptel-make-fsm) (lambda (&rest _) :fsm))
                    ((symbol-function 'message) (lambda (&rest _) nil)))
            (with-temp-buffer
              (setq default-directory (file-name-as-directory exp1-dir))
              (setq created-buf (gptel-auto-workflow--get-worktree-buffer relative-dir))))
          (should (buffer-live-p created-buf))
          (should
           (equal (buffer-local-value 'default-directory created-buf)
                  (file-name-as-directory expected-dir)))
          (should (eq (gethash (file-name-as-directory expected-dir)
                               gptel-auto-workflow--worktree-buffers)
                      created-buf)))
      (when (buffer-live-p created-buf)
        (kill-buffer created-buf))
      (delete-directory project-root t))))

(ert-deftest regression/auto-workflow-projects/get-worktree-buffer-keeps-same-leaf-roots-isolated ()
  "Different worktree roots with the same leaf name must not share a buffer."
  (let* ((project-root (make-temp-file "aw-project" t))
         (nested-root (expand-file-name
                       "var/tmp/experiments/optimize/agent-riven-exp1/var/tmp/experiments/optimize/agent-riven-exp2"
                       project-root))
         (top-level-root (expand-file-name
                          "var/tmp/experiments/optimize/agent-riven-exp2"
                          project-root))
         (gptel-auto-workflow--current-project project-root)
         (gptel-auto-workflow--worktree-buffers (make-hash-table :test 'equal))
         (gptel-auto-workflow--project-buffers (make-hash-table :test 'equal))
         nested-buf
         top-level-buf)
    (unwind-protect
        (progn
          (make-directory nested-root t)
          (make-directory top-level-root t)
          (cl-letf (((symbol-function 'gptel-mode) (lambda () nil))
                    ((symbol-function 'gptel--apply-preset) (lambda (&rest _) nil))
                    ((symbol-function 'hack-dir-local-variables-non-file-buffer) (lambda (&rest _) nil))
                    ((symbol-function 'gptel-make-fsm) (lambda (&rest _) :fsm))
                    ((symbol-function 'message) (lambda (&rest _) nil)))
            (setq nested-buf (gptel-auto-workflow--get-worktree-buffer nested-root))
            (setq top-level-buf (gptel-auto-workflow--get-worktree-buffer top-level-root)))
          (should (buffer-live-p nested-buf))
          (should (buffer-live-p top-level-buf))
          (should-not (eq nested-buf top-level-buf))
          (should-not (equal (buffer-name nested-buf) (buffer-name top-level-buf)))
          (should (equal (buffer-local-value 'default-directory nested-buf)
                         (file-name-as-directory nested-root)))
          (should (equal (buffer-local-value 'default-directory top-level-buf)
                         (file-name-as-directory top-level-root)))
          (should (eq (gethash (file-name-as-directory nested-root)
                               gptel-auto-workflow--worktree-buffers)
                      nested-buf))
          (should (eq (gethash (file-name-as-directory top-level-root)
                               gptel-auto-workflow--worktree-buffers)
                      top-level-buf)))
      (when (buffer-live-p nested-buf)
        (kill-buffer nested-buf))
      (when (buffer-live-p top-level-buf)
        (kill-buffer top-level-buf))
      (delete-directory project-root t))))

(ert-deftest regression/auto-workflow-projects/get-worktree-buffer-recovers-nil-buffer-tables ()
  "Worktree buffer lookup should self-heal if shared tables were left nil."
  (let* ((project-root (make-temp-file "aw-project" t))
         (worktree-dir (expand-file-name "var/tmp/experiments/optimize/foo-exp1" project-root))
         (gptel-auto-workflow--current-project project-root)
         (gptel-auto-workflow--worktree-buffers nil)
         (gptel-auto-workflow--project-buffers nil)
         created-buf)
    (unwind-protect
        (progn
          (make-directory worktree-dir t)
          (cl-letf (((symbol-function 'gptel-mode) (lambda () nil))
                    ((symbol-function 'gptel--apply-preset) (lambda (&rest _) nil))
                    ((symbol-function 'hack-dir-local-variables-non-file-buffer) (lambda (&rest _) nil))
                    ((symbol-function 'gptel-make-fsm) (lambda (&rest _) :fsm))
                    ((symbol-function 'message) (lambda (&rest _) nil)))
            (setq created-buf (gptel-auto-workflow--get-worktree-buffer worktree-dir)))
          (should (buffer-live-p created-buf))
          (should (hash-table-p gptel-auto-workflow--worktree-buffers))
          (should (hash-table-p gptel-auto-workflow--project-buffers))
          (should (eq (gethash (file-name-as-directory worktree-dir)
                               gptel-auto-workflow--worktree-buffers)
                      created-buf))
          (should (eq (gethash (file-name-as-directory worktree-dir)
                               gptel-auto-workflow--project-buffers)
                      created-buf)))
      (when (buffer-live-p created-buf)
        (kill-buffer created-buf))
      (delete-directory project-root t))))

(ert-deftest regression/auto-workflow-projects/task-routing-prefers-safe-task-override ()
  "Per-project routing should prefer the safe task override when available."
  (ert-skip "Flaky test - mocking issues with safe task override")
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
               (lambda (_secs _repeat fn &rest _args)
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

(ert-deftest regression/auto-workflow-projects/queue-helper-keeps-running-until-async-finish ()
  "Async queued jobs should stay marked running until their completion callback fires."
  (let ((gptel-auto-workflow--cron-job-running nil)
        (scheduled nil)
        (finish-job nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn &rest _args)
                  (setq scheduled fn)
                  'fake-timer))
              ((symbol-function 'gptel-auto-workflow--persist-status)
                (lambda (&rest _) nil)))
      (should
       (eq (gptel-auto-workflow--queue-cron-job
            "auto-workflow"
            (lambda (callback)
              (setq finish-job callback))
            :async t)
           'queued))
      (should gptel-auto-workflow--cron-job-running)
      (should (functionp scheduled))
      (funcall scheduled)
      (should gptel-auto-workflow--cron-job-running)
      (should (functionp finish-job))
      (funcall finish-job)
      (should-not gptel-auto-workflow--cron-job-running))))

(ert-deftest regression/auto-workflow-projects/queue-helper-resets-stale-stats ()
  "Queued jobs should start from clean stats instead of leaking prior run counts."
  (let ((gptel-auto-workflow--cron-job-running nil)
        (gptel-auto-workflow--stats '(:phase "complete" :total 7 :kept 2))
        (scheduled nil))
    (cl-letf (((symbol-function 'run-at-time)
               (lambda (_secs _repeat fn &rest _args)
                 (setq scheduled fn)
                 'fake-timer))
              ((symbol-function 'gptel-auto-workflow--persist-status)
               (lambda (&rest _) nil)))
      (should
       (eq (gptel-auto-workflow--queue-cron-job
            "auto-workflow"
            (lambda ())
            :async nil)
           'queued))
      (should (equal gptel-auto-workflow--stats
                     '(:phase "auto-workflow-queued" :total 0 :kept 0)))
      (funcall scheduled)
      (should (equal gptel-auto-workflow--stats
                     '(:phase "idle" :total 0 :kept 0)))))) 

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

(ert-deftest regression/auto-workflow-projects/run-all-projects-marks-quota-exhausted ()
  "Project completion should surface quota exhaustion instead of success."
  (let ((gptel-auto-workflow-projects '("/tmp/project-a"))
        (callbacks nil)
        (messages nil)
        (gptel-auto-experiment--quota-exhausted nil)
        (gptel-auto-workflow--stats '(:phase "complete" :total 3 :kept 0)))
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
      (setq gptel-auto-experiment--quota-exhausted t)
      (funcall (car callbacks) '(:quota t))
      (should (seq-some (lambda (msg)
                          (string-match-p "\\[auto-workflow\\] ! Quota exhausted: /tmp/project-a/" msg))
                        messages))
      (should (seq-some (lambda (msg)
                          (string-match-p "\\[auto-workflow\\] All projects processed: /tmp/project-a/:quota-exhausted" msg))
                        messages))
      (should-not (seq-some (lambda (msg)
                              (string-match-p "\\[auto-workflow\\] ✓ Completed: /tmp/project-a/" msg))
                            messages)))))

(provide 'test-gptel-auto-workflow-projects-regressions)

;;; test-gptel-auto-workflow-projects-regressions.el ends here
