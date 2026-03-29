;;; test-gptel-agent-loop-integration.el --- Integration tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defvar gptel-agent--agents nil)
(defvar gptel--fsm-last nil)
(defvar gptel-agent-request--handlers nil)
(defvar gptel--preset nil)
(defvar gptel-request--transitions nil)

(cl-defstruct gptel-fsm (state 'INIT) table handlers info)

(defun gptel--preset-syms (_preset) nil)
(defun gptel--apply-preset (preset) (setq gptel--preset preset))
(defun gptel--update-status (&rest _args) nil)
(defun gptel--display-tool-calls (&rest _args) nil)
(defun gptel-make-fsm (&rest args) args)
(defun gptel-agent--task-overlay (&rest _args) nil)
(defun my/gptel--coerce-fsm (obj) obj)
(defun my/gptel--deliver-subagent-result (callback result) (funcall callback result))

(require 'gptel-agent-loop)

(ert-deftest gptel-agent-loop-integration-test-enable-disable ()
  (cl-letf (((symbol-function 'gptel-agent--task) #'ignore))
    (gptel-agent-loop-enable)
    (should (advice-member-p #'gptel-agent-loop-task 'gptel-agent--task))
    (gptel-agent-loop-disable)
    (should-not (advice-member-p #'gptel-agent-loop-task 'gptel-agent--task))))

(ert-deftest gptel-agent-loop-integration-test-state-uses-struct-and-active-table ()
  (let ((gptel-agent--agents '(("executor" :steps 2)))
        callback)
    (with-temp-buffer
      (setq gptel--fsm-last
            (make-gptel-fsm :info (list :buffer (current-buffer)
                                        :position (point-marker))))
      (cl-letf (((symbol-function 'gptel-request)
                 (lambda (_prompt &rest args)
                   (setq callback (plist-get args :callback)))))
        (gptel-agent-loop-task #'ignore "executor" "integration task" "prompt")
        (should (gptel-agent-loop--task-p gptel-agent-loop--state))
        (should (= 1 (hash-table-count gptel-agent-loop--active-tasks)))
        (funcall callback "done" '(:tool-use nil))
        (should (null gptel-agent-loop--state))
        (should (= 0 (hash-table-count gptel-agent-loop--active-tasks)))))))

(provide 'test-gptel-agent-loop-integration)

;;; test-gptel-agent-loop-integration.el ends here
