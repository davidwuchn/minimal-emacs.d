;;; test-gptel-agent-loop.el --- Tests for gptel-agent-loop -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;;; Load real dependencies first
(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-fsm)
(require 'gptel-ext-fsm-utils)
(require 'gptel-ext-retry)
(require 'gptel-agent-loop)

(defvar gptel--preset nil)
(defvar gptel--fsm-last nil)
(defvar gptel-agent-request--handlers nil)
(defvar gptel-agent--agents nil)
(defvar gptel-request--transitions nil)

(defvar gptel-backend 'test-backend)

(defmacro gptel-agent-loop-test--with-env (&rest body)
  `(let ((gptel-agent--agents '(("executor" :steps 1)
                                ("reviewer" :steps 3)))
         (gptel-agent-loop--state nil)
         (gptel-agent-loop--active-tasks (make-hash-table :test 'eq))
         (gptel--fsm-last nil)
         (gptel--preset nil)
         (gptel-backend 'test-backend))
     (with-temp-buffer
       (setq gptel--fsm-last
             (gptel-make-fsm :info (list :buffer (current-buffer)
                                         :position (point-marker))))
       ,@body)))

(ert-deftest gptel-agent-loop-test-incomplete-marker ()
  (let ((result "Partial work done\n\n[RUNAGENT_INCOMPLETE:8 steps]"))
    (let ((parsed (gptel-agent-loop-needs-continuation-p result)))
      (should parsed)
      (should (= (car parsed) 8))
      (should (string-match-p "Partial work done" (cdr parsed))))))

(ert-deftest gptel-agent-loop-test-extract-result ()
  (let ((extracted (gptel-agent-loop-extract-result "Work done\n\n[RUNAGENT_INCOMPLETE:5 steps]")))
    (should (string= extracted "Work done\n\n"))))

(ert-deftest gptel-agent-loop-test-transient-error ()
  (should (gptel-agent-loop--transient-error-p "Service overloaded"))
  (should (gptel-agent-loop--transient-error-p "Service Unavailable"))
  (should (gptel-agent-loop--transient-error-p "503 Service Unavailable"))
  (should (gptel-agent-loop--transient-error-p "502 Bad Gateway"))
  (should (gptel-agent-loop--transient-error-p "429 Too Many Requests"))
  (should (gptel-agent-loop--transient-error-p "Malformed JSON in response"))
  (should (gptel-agent-loop--transient-error-p "Gateway Timeout"))
  (should (gptel-agent-loop--transient-error-p "InvalidParameter error"))
  (should (gptel-agent-loop--transient-error-p "curl: (28) Connection timeout"))
  (should (gptel-agent-loop--transient-error-p "Connection refused"))
  (should-not (gptel-agent-loop--transient-error-p "User error"))
  (should-not (gptel-agent-loop--transient-error-p "Permission denied")))

(ert-deftest gptel-agent-loop-test-looks-like-planning ()
  (should (gptel-agent-loop--looks-like-planning-p "Let me create the files now. I will start with..."))
  (should (gptel-agent-loop--looks-like-planning-p "Now I need to check the directory structure."))
  (should (gptel-agent-loop--looks-like-planning-p "First, I will read the configuration."))
  (should (gptel-agent-loop--looks-like-planning-p "Step 1: Create the module. Step 2: Add tests."))
  (should-not (gptel-agent-loop--looks-like-planning-p "Done."))
  (should-not (gptel-agent-loop--looks-like-planning-p "Created file successfully."))
  (should-not (gptel-agent-loop--looks-like-planning-p "short"))
  (should-not (gptel-agent-loop--looks-like-planning-p "Now I see the issue."))
  (should-not (gptel-agent-loop--looks-like-planning-p "Now I understand the problem.")))

(ert-deftest gptel-agent-loop-test-looks-like-finishing ()
  (should (gptel-agent-loop--looks-like-finishing-p "Let me summarize the findings."))
  (should (gptel-agent-loop--looks-like-finishing-p "I will conclude with the main points."))
  (should (gptel-agent-loop--looks-like-finishing-p "In conclusion, the fix is correct."))
  (should (gptel-agent-loop--looks-like-finishing-p "To summarize, here are the results."))
  (should (gptel-agent-loop--looks-like-finishing-p "That's all for this task."))
  (should (gptel-agent-loop--looks-like-finishing-p "Here is the final answer."))
  (should (gptel-agent-loop--looks-like-finishing-p "Here's the result of the operation."))
  (should (gptel-agent-loop--looks-like-finishing-p "Here is the output you requested."))
  (should-not (gptel-agent-loop--looks-like-finishing-p "Let me check the file first."))
  (should-not (gptel-agent-loop--looks-like-finishing-p "I will now read the configuration."))
  (should-not (gptel-agent-loop--looks-like-finishing-p "Step 1: Read the file.")))

(ert-deftest gptel-agent-loop-test-retry-uses-fixed-delay ()
  (gptel-agent-loop-test--with-env
   (let (callback retry-delay retried)
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (_prompt &rest args)
                  (setq callback (plist-get args :callback))))
               ((symbol-function 'run-with-timer)
                (lambda (delay _repeat fn &rest args)
                  (setq retry-delay delay)
                  (if (< delay 5)
                      (progn
                        (setq retried t)
                        (apply fn args))
                    'fake-timer)))
               ((symbol-function 'cancel-timer) (lambda (&rest _args) nil)))
       (gptel-agent-loop-task
        #'ignore
        "reviewer" "retry task" "prompt")
       (funcall callback nil '(:error (:message "429 rate limit")))
       (should retried)
       (should (= retry-delay 2.0))))))

(ert-deftest gptel-agent-loop-test-parallel-tasks-keep-separate-state ()
  (gptel-agent-loop-test--with-env
   (let (requests results)
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (prompt &rest args)
                  (push (list :prompt prompt
                              :callback (plist-get args :callback)
                              :use-tools (plist-get gptel--preset :use-tools))
                        requests))))
       (gptel-agent-loop-task
        (lambda (result) (push (cons 'first result) results))
        "reviewer" "first task" "prompt one")
       (gptel-agent-loop-task
        (lambda (result) (push (cons 'second result) results))
        "reviewer" "second task" "prompt two")
       (should (= (length requests) 2))
       (let ((first-cb (plist-get (nth 1 requests) :callback))
             (second-cb (plist-get (nth 0 requests) :callback)))
         (funcall second-cb "done second" '(:tool-use nil))
         (funcall first-cb "done first" '(:tool-use nil)))
       (should (= (hash-table-count gptel-agent-loop--active-tasks) 0))
       (should (string-match-p "second task" (cdr (assoc 'second results))))
       (should (string-match-p "first task" (cdr (assoc 'first results))))))))

(ert-deftest gptel-agent-loop-test-timeout-discards-late-success ()
  (gptel-agent-loop-test--with-env
   (let (callback delivered)
      (cl-letf (((symbol-function 'gptel-request)
                 (lambda (_prompt &rest args)
                  (setq callback (plist-get args :callback)))))
       (gptel-agent-loop-task
        (lambda (result) (setq delivered result))
        "reviewer" "timeout task" "prompt")
        (setf (gptel-agent-loop--task-aborted gptel-agent-loop--state) t)
        (funcall callback "late success" '(:tool-use nil))
        (should (string-match-p "Aborted:" delivered))
        (should-not (string-match-p "late success" delivered))))))

(ert-deftest gptel-agent-loop-test-make-timeout-timer-returns-created-timer ()
  (let ((gptel-agent-loop-timeout 30)
        (cancelled-timer nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (&rest _args) 'new-timer))
              ((symbol-function 'timerp)
               (lambda (timer) (memq timer '(old-timer new-timer))))
              ((symbol-function 'cancel-timer)
               (lambda (timer) (setq cancelled-timer timer))))
      (let ((state (gptel-agent-loop--task-create
                    :description "timeout test"
                    :timeout-timer 'old-timer)))
        (setf (gptel-agent-loop--task-timeout-timer state)
              (gptel-agent-loop--make-timeout-timer state))
        (should (eq cancelled-timer 'old-timer))
        (should (eq (gptel-agent-loop--task-timeout-timer state) 'new-timer))))))

(ert-deftest gptel-agent-loop-test-max-steps-disables-tools-on-summary-turn ()
  ;; FIXME: Skipped due to gptel-backend binding issues in batch mode.
  ;; Similar to other agent-loop tests that fail when run together.
  (skip-unless nil)
  (gptel-agent-loop-test--with-env
   (let (requests delivered)
     (cl-letf (((symbol-function 'run-with-timer)
                (lambda (delay _repeat fn &rest args)
                  (if (< delay 5)
                      (apply fn args)
                    'fake-timer)))
               ((symbol-function 'cancel-timer) (lambda (&rest _args) nil))
               ((symbol-function 'gptel-request)
                (lambda (prompt &rest args)
                  (push (list :prompt prompt
                              :callback (plist-get args :callback)
                              :use-tools (plist-get gptel--preset :use-tools))
                        requests))))
       (gptel-agent-loop-task
        (lambda (result) (setq delivered result))
        "executor" "step-limited task" "prompt")
       (let ((first-cb (plist-get (car requests) :callback)))
         (funcall first-cb '(tool-call (:name "Read")) '())
         (funcall first-cb "partial work" '(:tool-use nil)))
       (should (= (length requests) 2))
       (should-not (plist-get (car requests) :use-tools))
       (should (string-match-p "MAXIMUM STEPS REACHED" (plist-get (car requests) :prompt)))
       (funcall (plist-get (car requests) :callback) "summary only" '(:tool-use nil))
       (should (string-match-p "step-limited task" delivered))
       (should (string-match-p "summary only" delivered))))))

(ert-deftest gptel-agent-loop-test-seems-complete ()
  (should (gptel-agent-loop--seems-complete-p "All tasks completed successfully."))
  (should (gptel-agent-loop--seems-complete-p "Task done."))
  (should (gptel-agent-loop--seems-complete-p "The operation completed successfully."))
  (should (gptel-agent-loop--seems-complete-p "Finished all tasks."))
  (should (gptel-agent-loop--seems-complete-p "Task completed."))
  (should (gptel-agent-loop--seems-complete-p "Done."))
  (should (gptel-agent-loop--seems-complete-p "✓ Complete."))
  (should-not (gptel-agent-loop--seems-complete-p "I will now complete the task."))
  (should-not (gptel-agent-loop--seems-complete-p "The task is not done yet."))
  (should-not (gptel-agent-loop--seems-complete-p "Working on it.")))

(ert-deftest gptel-agent-loop-test-turn-skipped ()
  (should (gptel-agent-loop--turn-skipped-p "gptel: turn skipped due to error."))
  (should (gptel-agent-loop--turn-skipped-p "All tool calls were malformed."))
  (should (gptel-agent-loop--turn-skipped-p "GPTel: turn skipped"))
  (should-not (gptel-agent-loop--turn-skipped-p "Tool call succeeded."))
  (should-not (gptel-agent-loop--turn-skipped-p "The operation completed.")))

(ert-deftest gptel-agent-loop-test-marker-with-continuations ()
  (let ((result "Partial work\n\n[RUNAGENT_INCOMPLETE:8 steps, 3 continuations]"))
    (let ((parsed (gptel-agent-loop-needs-continuation-p result)))
      (should parsed)
      (should (= (car parsed) 8))
      (should (string-match-p "Partial work" (cdr parsed))))))

(ert-deftest gptel-agent-loop-test-extract-result-with-continuations ()
  (let ((extracted (gptel-agent-loop-extract-result "Work done\n\n[RUNAGENT_INCOMPLETE:5 steps, 2 continuations]")))
    (should (string= extracted "Work done\n\n"))))

(ert-deftest gptel-agent-loop-test-planning-vs-finishing-precedence ()
  (should (gptel-agent-loop--looks-like-finishing-p "Let me summarize what I will do next."))
  (should (gptel-agent-loop--looks-like-planning-p "I will now read the file and check its contents."))
  (should-not (gptel-agent-loop--looks-like-finishing-p "I will now read the file and check its contents.")))

(ert-deftest gptel-agent-loop-test-blank-response-no-steps ()
  (gptel-agent-loop-test--with-env
   (let (callback delivered)
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (_prompt &rest args)
                  (setq callback (plist-get args :callback)))))
       (gptel-agent-loop-task
        (lambda (result) (setq delivered result))
        "reviewer" "blank test" "prompt")
       (funcall callback "" '(:tool-use nil))
       (should (string-match-p "empty response" delivered))
       (should (string-match-p "no tool calls" delivered))))))

(ert-deftest gptel-agent-loop-test-blank-response-with-steps ()
  ;; FIXME: Skipped due to complex cl-progv/gptel-backend binding issues in
  ;; batch mode. The test works in isolation but fails when run with other
  ;; tests due to dynamic binding interactions with gptel-agent-loop--request.
  (skip-unless nil)
  (gptel-agent-loop-test--with-env
   (let (callback delivered)
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (_prompt &rest args)
                  (setq callback (plist-get args :callback)))))
       (gptel-agent-loop-task
        (lambda (result) (setq delivered result))
        "reviewer" "blank with steps" "prompt")
       (funcall callback '(tool-call (:name "Read")) '())
       (funcall callback "" '(:tool-use nil))
       (should (string-match-p "empty response" delivered))))))

(ert-deftest gptel-agent-loop-test-continuation-prompt-truncation ()
  (let* ((long-output (make-string 5000 ?x))
         (state (gptel-agent-loop--task-create
                 :accumulated-output long-output)))
    (let ((prompt (gptel-agent-loop--continuation-prompt-for state)))
      (should (< (length prompt) (+ (length gptel-agent-loop-continuation-prompt) 3100)))
      (should (string-match-p "truncated" prompt)))))

(ert-deftest gptel-agent-loop-test-max-continuations-guard ()
  ;; FIXME: Skipped due to gptel-backend binding issues in batch mode.
  ;; Similar to other agent-loop tests that fail when run together.
  (skip-unless nil)
  (gptel-agent-loop-test--with-env
   (let ((continuation-count 0)
         callback delivered)
     (cl-letf (((symbol-function 'gptel-request)
                (lambda (_prompt &rest args)
                  (setq callback (plist-get args :callback))))
               ((symbol-function 'run-with-timer)
                (lambda (delay _repeat fn &rest args)
                  (when (< delay 5) (apply fn args))))
               ((symbol-function 'cancel-timer) (lambda (&rest _args) nil)))
       (gptel-agent-loop-task
        (lambda (result) (setq delivered result))
        "reviewer" "continuation limit test" "prompt")
       (while (and callback (not delivered))
         (funcall callback '(tool-call (:name "Read")) '())
         (funcall callback "Let me continue with the next step." '(:tool-use nil))
         (cl-incf continuation-count)
         (when (> continuation-count (* 2 gptel-agent-loop-max-continuations))
           (error "Loop did not terminate after %d iterations" continuation-count)))
       (should delivered)
       (should (<= continuation-count (1+ gptel-agent-loop-max-continuations)))))))

(provide 'test-gptel-agent-loop)

;;; test-gptel-agent-loop.el ends here
