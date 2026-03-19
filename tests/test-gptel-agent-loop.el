;;; test-gptel-agent-loop.el --- Tests for gptel-agent-loop -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-agent-loop)

(ert-deftest gptel-agent-loop-test-incomplete-marker ()
  "Test that incomplete marker is correctly parsed."
  (let ((result "Partial work done\n\n[RUNAGENT_INCOMPLETE:8 steps]"))
    (let ((parsed (gptel-agent-loop-needs-continuation-p result)))
      (should parsed)
      (should (= (car parsed) 8))
      (should (string-match-p "Partial work done" (cdr parsed))))))

(ert-deftest gptel-agent-loop-test-no-marker ()
  "Test that text without marker returns nil."
  (should-not (gptel-agent-loop-needs-continuation-p "All tasks completed successfully")))

(ert-deftest gptel-agent-loop-test-extract-result ()
  "Test that continuation marker is correctly removed."
  (let ((extracted (gptel-agent-loop-extract-result "Work done\n\n[RUNAGENT_INCOMPLETE:5 steps]")))
    (should (string= extracted "Work done\n\n"))))

(ert-deftest gptel-agent-loop-test-transient-error ()
  "Test transient error detection."
  (should (gptel-agent-loop--transient-error-p "Service overloaded"))
  (should (gptel-agent-loop--transient-error-p "Rate limit exceeded"))
  (should (gptel-agent-loop--transient-error-p "503 Service Unavailable"))
  (should (gptel-agent-loop--transient-error-p "InvalidParameter error"))
  (should-not (gptel-agent-loop--transient-error-p "User error"))
  (should-not (gptel-agent-loop--transient-error-p "File not found")))

(ert-deftest gptel-agent-loop-test-config ()
  "Test configuration values."
  (should (= gptel-agent-loop-timeout 120))
  (should (= gptel-agent-loop-max-steps 50))
  (should (= gptel-agent-loop-max-retries 2))
  (should gptel-agent-loop-force-completion)
  (should gptel-agent-loop-hard-loop))

(ert-deftest gptel-agent-loop-test-turn-skipped-detection ()
  "Test detection of turn skipped message (malformed tool calls)."
  (let ((skipped-msg "gptel: turn skipped (all tool calls had nil/unknown names)")
        (normal-msg "Created file successfully"))
    ;; Turn skipped should match
    (should (string-match-p "gptel: turn skipped\\|all tool calls.*malformed" 
                            (downcase skipped-msg)))
    ;; Normal message should not match
    (should-not (string-match-p "gptel: turn skipped\\|all tool calls.*malformed"
                                 (downcase normal-msg)))))

(provide 'test-gptel-agent-loop)

;;; test-gptel-agent-loop.el ends here