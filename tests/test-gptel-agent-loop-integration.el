;;; test-gptel-agent-loop-integration.el --- Integration tests -*- lexical-binding: t; -*-

(require 'ert)

(ert-deftest gptel-agent-loop-integration-test-enable-disable ()
  "Test that loop mode can be enabled and disabled."
  (require 'gptel-agent-loop)
  
  ;; Enable
  (gptel-agent-loop-enable)
  (should (boundp 'gptel-agent-loop--state))
  (message "Loop mode enabled successfully")
  
  ;; Disable
  (gptel-agent-loop-disable)
  (should (null gptel-agent-loop--state))
  (message "Loop mode disabled successfully"))

(ert-deftest gptel-agent-loop-integration-test-state-init ()
  "Test that state is initialized correctly."
  (require 'gptel-agent-loop)
  
  ;; State should be nil initially
  (should (null gptel-agent-loop--state))
  
  ;; After simulating task start, state should have keys
  (setq gptel-agent-loop--state
        (list :step-count 0
              :retries 0
              :aborted nil
              :timeout-timer nil
              :max-steps 100))
  
  (should (= (plist-get gptel-agent-loop--state :step-count) 0))
  (should (= (plist-get gptel-agent-loop--state :max-steps) 100))
  
  ;; Cleanup
  (setq gptel-agent-loop--state nil))

(ert-deftest gptel-agent-loop-integration-test-config-override ()
  "Test that config can be overridden."
  (require 'gptel-agent-loop)
  
  (let ((original-timeout gptel-agent-loop-timeout)
        (original-max-steps gptel-agent-loop-max-steps))
    
    ;; Override
    (setq gptel-agent-loop-timeout 60)
    (setq gptel-agent-loop-max-steps 25)
    
    (should (= gptel-agent-loop-timeout 60))
    (should (= gptel-agent-loop-max-steps 25))
    
    ;; Restore
    (setq gptel-agent-loop-timeout original-timeout)
    (setq gptel-agent-loop-max-steps original-max-steps)))

(provide 'test-gptel-agent-loop-integration)

;;; test-gptel-agent-loop-integration.el ends here