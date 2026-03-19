;;; test-gptel-agent-loop.el --- Tests for gptel-agent-loop -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar gptel--preset nil)
(defvar gptel--fsm-last nil)
(defvar gptel-agent-request--handlers nil)
(defvar gptel-agent--agents nil)
(defvar gptel-request--transitions nil)

(cl-defstruct gptel-fsm info)

(defun gptel--preset-syms (_preset) nil)
(defun gptel--apply-preset (preset) (setq gptel--preset preset))
(defun gptel--update-status (&rest _args) nil)
(defun gptel--display-tool-calls (_calls _info) nil)
(defun gptel-make-fsm (&rest args) args)
(defun gptel-agent--task-overlay (&rest _args) nil)
(defun my/gptel--coerce-fsm (obj) obj)
(defun my/gptel--deliver-subagent-result (callback result) (funcall callback result))

(require 'gptel-agent-loop)

(defmacro gptel-agent-loop-test--with-env (&rest body)
  `(let ((gptel-agent--agents '(("executor" :steps 1)
                                ("reviewer" :steps 3)))
         (gptel-agent-loop--state nil)
         (gptel-agent-loop--active-tasks (make-hash-table :test 'eq))
         (gptel--fsm-last nil)
         (gptel--preset nil))
     (with-temp-buffer
       (setq gptel--fsm-last
             (make-gptel-fsm :info (list :buffer (current-buffer)
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
  (should (gptel-agent-loop--transient-error-p "Rate limit exceeded"))
  (should (gptel-agent-loop--transient-error-p "503 Service Unavailable"))
  (should (gptel-agent-loop--transient-error-p "InvalidParameter error"))
  (should-not (gptel-agent-loop--transient-error-p "User error")))

(ert-deftest gptel-agent-loop-test-looks-like-planning ()
  (should (gptel-agent-loop--looks-like-planning-p "Let me create the files now. I will start with..."))
  (should (gptel-agent-loop--looks-like-planning-p "Now I need to check the directory structure."))
  (should (gptel-agent-loop--looks-like-planning-p "First, I will read the configuration."))
  (should (gptel-agent-loop--looks-like-planning-p "Step 1: Create the module. Step 2: Add tests."))
  (should-not (gptel-agent-loop--looks-like-planning-p "Done."))
  (should-not (gptel-agent-loop--looks-like-planning-p "Created file successfully."))
  (should-not (gptel-agent-loop--looks-like-planning-p "short")))

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

(ert-deftest gptel-agent-loop-test-max-steps-disables-tools-on-summary-turn ()
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

(provide 'test-gptel-agent-loop)

;;; test-gptel-agent-loop.el ends here
