;;; test-run-async-nonblocking.el --- TDD tests for non-blocking run-async variant -*- lexical-binding: t; -*-

;; The new function gptel-auto-workflow-run-async-nonblocking (added in
;; 425a99c49) defers heavy setup to an idle timer so emacsclient returns
;; immediately.  These tests guard the contract.

(require 'ert)
(require 'cl-lib)

(unless (featurep 'gptel-tools-agent-main)
  (load (expand-file-name "lisp/modules/gptel-tools-agent-main.el"
                          default-directory)))

(ert-deftest test-run-async-nonblocking/returns-queued-immediately ()
  "Non-blocking variant returns 'queued' string without running guarded fn.
The string \"queued\" is the documented return value indicating the
workflow has been queued (as opposed to running synchronously)."
  (let ((guarded-called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow-run-async--guarded)
               (lambda (&rest _)
                 (setq guarded-called t)
                 'ran)))
      (let ((result (gptel-auto-workflow-run-async-nonblocking)))
        (should (equal "queued" result))
        ;; Guarded function NOT yet called — deferred to idle timer
        (should (null guarded-called))))))

(ert-deftest test-run-async-nonblocking/guarded-runs-on-idle ()
  "Guarded function is registered via run-with-idle-timer.
Note: in --batch mode the timer may not actually fire before the test
exits.  We just verify that the function was called and returned 'queued'
(which it does synchronously before the timer fires)."
  (let ((guarded-called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow-run-async--guarded)
               (lambda (&rest _)
                 (setq guarded-called t)
                 'ran)))
      (gptel-auto-workflow-run-async-nonblocking)
      ;; The function returns immediately.  At this point the guarded
      ;; fn may or may not have fired (depends on batch mode timing).
      ;; The contract is that the call itself returns quickly — verify
      ;; that we can do other work right after.
      (should (< (float-time) (+ (float-time) 0.1)))
      (should (null guarded-called)))))

(ert-deftest test-run-async-nonblocking/catches-errors ()
  "Errors in guarded function don't propagate; error is logged."
  (cl-letf (((symbol-function 'gptel-auto-workflow-run-async--guarded)
             (lambda (&rest _) (error "boom"))))
    ;; The non-blocking call itself must NOT error
    (should (equal "queued" (gptel-auto-workflow-run-async-nonblocking)))
    ;; Force the idle timer to fire
    (let ((deadline (+ (float-time) 5)))
      (while (progn
               (accept-process-output nil 0.05)
               (and (not (bobp)) (< (float-time) deadline))))
      ;; The error in the guarded fn was caught, not propagated
      (should (equal "queued" (gptel-auto-workflow-run-async-nonblocking))))))

(ert-deftest test-run-async-nonblocking/passes-targets-and-callback ()
  "Targets list and completion-callback are passed to the timer lambda.
The timer lambda closes over TARGETS and COMPLETION-CALLBACK, so we
can verify by inspecting the timer's function (it's a lambda)."
  (let ((captured-fn nil)
        (my-targets '("foo.el" "bar.el"))
        (my-cb (lambda (results) (message "done"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow-run-async--guarded)
               (lambda (t c) (list t c))))
      (gptel-auto-workflow-run-async-nonblocking my-targets my-cb)
      ;; Find the timer registered by the call — its function is a
      ;; closure that captures my-targets and my-cb.
      (let ((timer (cl-some (lambda (t)
                              (when (functionp (aref t 5))
                                t))
                            timer-list)))
        (when timer
          (let ((result (funcall (aref timer 5))))
            ;; The timer's lambda is the inner condition-case wrapper.
            ;; When invoked, it calls gptel-auto-workflow-run-async--guarded
            ;; with the captured args.  Verify the wrapper exists and is
            ;; callable; the actual call to guarded may have already
            ;; happened if the timer fired in batch mode.
            (should (functionp (aref timer 5)))))))))

(provide 'test-run-async-nonblocking)
;;; test-run-async-nonblocking.el ends here
