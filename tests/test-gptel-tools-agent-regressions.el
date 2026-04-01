;;; test-gptel-tools-agent-regressions.el --- Regression tests for gptel-tools-agent -*- lexical-binding: t; -*-

;;; Commentary:
;; Focused regressions for bugs found during live auto-workflow runs.

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-fsm)
(require 'gptel-ext-fsm-utils)
(require 'gptel-tools-agent)

(ert-deftest regression/auto-experiment/api-errors-do-not-touch-loop-state ()
  "API failures should not try to mutate outer loop state from a callback."
  (let ((gptel-auto-experiment--api-error-count 2)
        (result nil)
        (temp-dir (make-temp-file "exp-worktree" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow-create-worktree)
                   (lambda (_target _experiment-id) temp-dir))
                  ((symbol-function 'gptel-auto-experiment-analyze)
                   (lambda (_previous-results cb)
                     (funcall cb '(:patterns nil))))
                  ((symbol-function 'gptel-auto-experiment-build-prompt)
                   (lambda (&rest _args) "prompt"))
                  ((symbol-function 'run-with-timer)
                   (lambda (&rest _args) :fake-timer))
                  ((symbol-function 'cancel-timer)
                   (lambda (&rest _args) nil))
                  ((symbol-function 'my/gptel--run-agent-tool)
                   (lambda (cb &rest _args)
                     (funcall cb "Error: executor task failed with throttling")))
                  ((symbol-function 'gptel-auto-experiment-grade)
                   (lambda (_output cb)
                     (funcall cb '(:score 0 :total 9 :passed nil :details "rate-limited"))))
                  ((symbol-function 'gptel-auto-experiment--categorize-error)
                   (lambda (_output)
                     '(:api-rate-limit . "hour allocated quota exceeded")))
                  ((symbol-function 'gptel-auto-experiment-log-tsv)
                   (lambda (&rest _args) nil)))
          (gptel-auto-experiment-run
           "lisp/modules/gptel-tools-agent.el" 1 5 0.4 0.5 nil
           (lambda (exp-result)
             (setq result exp-result)))
          (should result)
          (should (= gptel-auto-experiment--api-error-count 3))
          (should (equal (plist-get result :comparator-reason) ":api-rate-limit"))
          (should-not (plist-get result :kept))))
      (delete-directory temp-dir t)))

(ert-deftest regression/auto-workflow/run-with-targets-is-sequential ()
  "Target execution should stay sequential so worktree routing is stable."
  (let ((gptel-auto-workflow--stats nil)
        (gptel-auto-workflow--running t)
        (gptel-auto-workflow--current-target nil)
        (started '())
        (callbacks '())
        (completed nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--default-dir)
               (lambda () "/tmp/project"))
              ((symbol-function 'gptel-auto-experiment-loop)
               (lambda (target cb)
                 (push target started)
                 (push (cons target cb) callbacks))))
      (gptel-auto-workflow--run-with-targets
       '("one" "two")
       (lambda (results)
         (setq completed results)))
      (should (equal (nreverse started) '("one")))
      (should (equal (plist-get gptel-auto-workflow--stats :phase) "running"))
      (should (= (plist-get gptel-auto-workflow--stats :total) 2))
      (funcall (cdr (assoc "one" callbacks)) '((:target "one" :kept t)))
      (should (equal (nreverse started) '("one" "two")))
      (should (= (plist-get gptel-auto-workflow--stats :kept) 1))
      (should (equal gptel-auto-workflow--current-target "two"))
      (funcall (cdr (assoc "two" callbacks)) '((:target "two" :kept nil)))
      (should (equal completed '((:target "one" :kept t)
                                 (:target "two" :kept nil))))
      (should (equal (plist-get gptel-auto-workflow--stats :phase) "complete"))
      (should-not gptel-auto-workflow--running)
      (should-not gptel-auto-workflow--current-target))))

(ert-deftest regression/auto-workflow/force-stop-updates-phase ()
  "Force stop should persist the idle phase in workflow stats."
  (let ((gptel-auto-workflow--stats nil)
        (gptel-auto-workflow--running t)
        (gptel-auto-workflow--watchdog-timer (run-at-time 3600 nil #'ignore)))
    (unwind-protect
        (progn
          (gptel-auto-workflow-force-stop)
          (should-not gptel-auto-workflow--running)
          (should (equal (plist-get gptel-auto-workflow--stats :phase) "idle")))
      (when (timerp gptel-auto-workflow--watchdog-timer)
        (cancel-timer gptel-auto-workflow--watchdog-timer)))))



(ert-deftest regression/auto-workflow/sanitize-unicode-regex-classes ()
  "Unicode sanitizer should normalize individual dash and zero-width characters."
  (should (equal (gptel-auto-workflow--sanitize-unicode "a–b—c") "a-b-c"))
  (should (equal (gptel-auto-workflow--sanitize-unicode "x​y‌z‍w") "xyzw")))

(ert-deftest regression/auto-workflow/cron-safe-skips-main-promotion ()
  "Cron-safe should sync staging and run the workflow without touching main."
  (let ((ops nil)
        (disabled nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--default-dir)
               (lambda () "/tmp/project"))
              ((symbol-function 'require)
               (lambda (&rest _) t))
              ((symbol-function 'featurep)
               (lambda (_) t))
              ((symbol-function 'load-file)
               (lambda (&rest _) t))
              ((symbol-function 'gptel-auto-workflow--enable-headless-suppression)
               (lambda () t))
              ((symbol-function 'gptel-auto-workflow--disable-headless-suppression)
               (lambda () (setq disabled t)))
              ((symbol-function 'gptel-auto-workflow--cleanup-stale-state)
               (lambda () (push "cleanup" ops)))
              ((symbol-function 'gptel-auto-workflow--sync-staging-with-main)
               (lambda () (push "sync" ops) t))
              ((symbol-function 'gptel-auto-workflow--recover-orphans)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow-run-async--guarded)
               (lambda (_ callback)
                 (push "run" ops)
                 (funcall callback nil)))
              ((symbol-function 'message)
               (lambda (&rest _) nil)))
      (gptel-auto-workflow-cron-safe)
      (should (equal (reverse ops) '("cleanup" "sync" "run")))
      (should disabled))))
(provide 'test-gptel-tools-agent-regressions)

;;; test-gptel-tools-agent-regressions.el ends here
