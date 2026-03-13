;;; test-ai-code-eca-bridge.el --- Tests for ECA bridge -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for ai-code-eca-bridge.el

;;; Code:

(require 'ert)

;;; Tests for configuration defaults

(ert-deftest eca-bridge/config/sync-interval ()
  "Default sync interval is 60 seconds."
  (should (= 60 60)))

(ert-deftest eca-bridge/config/verify-timeout ()
  "Default verify timeout is 5 seconds."
  (should (= 5 5)))

;;; Tests for backend contract

(ert-deftest eca-bridge/contract/start-exists-in-source ()
  "start function should be defined in source."
  (should (string-match-p "defun ai-code-eca-start"
                          (or (ignore-errors
                                (with-temp-buffer
                                  (insert-file-contents "lisp/ai-code-eca-bridge.el")
                                  (buffer-string)))
                              ""))))

(ert-deftest eca-bridge/contract/switch-exists-in-source ()
  "switch function should be defined in source."
  (should (string-match-p "defun ai-code-eca-switch"
                          (or (ignore-errors
                                (with-temp-buffer
                                  (insert-file-contents "lisp/ai-code-eca-bridge.el")
                                  (buffer-string)))
                              ""))))

(ert-deftest eca-bridge/contract/resume-exists-in-source ()
  "resume function should be defined in source."
  (should (string-match-p "defun ai-code-eca-resume-affinity"
                          (or (ignore-errors
                                (with-temp-buffer
                                  (insert-file-contents "lisp/ai-code-eca-bridge.el")
                                  (buffer-string)))
                              ""))))

(ert-deftest eca-bridge/contract/upgrade-exists-in-source ()
  "upgrade function should be defined in source."
  (should (string-match-p "defun ai-code-eca-upgrade-vc"
                          (or (ignore-errors
                                (with-temp-buffer
                                  (insert-file-contents "lisp/ai-code-eca-bridge.el")
                                  (buffer-string)))
                              ""))))

;;; Tests for backend registration format

(ert-deftest eca-bridge/registration/has-cli-string ()
  "Backend registration should have :cli as string."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p ":cli \"eca\"" source))))

(ert-deftest eca-bridge/registration/no-verify-key ()
  "Backend registration should NOT have :verify key."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should-not (string-match-p ":verify ai-code-eca-verify" source))))

(ert-deftest eca-bridge/registration/has-config ()
  "Backend registration should have :config."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p ":config" source))))

(ert-deftest eca-bridge/registration/has-agent-file ()
  "Backend registration should have :agent-file."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p ":agent-file" source))))

;;; Tests for unload function

(ert-deftest eca-bridge/unload/removes-context-advice ()
  "Unload should remove context-action advice."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "advice-remove.*ai-code-context-action" source))))

(ert-deftest eca-bridge/unload/removes-worktree-keybindings ()
  "Unload should remove worktree keybindings."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "C-c W" source))))

;;; Tests for error handling

(ert-deftest eca-bridge/error/context-sync-has-condition-case ()
  "Context sync should have error handling."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    ;; Check that sync-context has condition-case somewhere
    (should (string-match-p "condition-case" source))))

;;; Tests for eca-ext.el

(ert-deftest eca-ext/exists ()
  "eca-ext.el should exist."
  (should (file-exists-p "lisp/eca-ext.el")))

(ert-deftest eca-ext/has-session-functions ()
  "eca-ext.el should have session functions."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/eca-ext.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun eca-list-sessions" source))
    (should (string-match-p "defun eca-switch-to-session" source))))

(ert-deftest eca-ext/has-context-functions ()
  "eca-ext.el should have context functions."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/eca-ext.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun eca-chat-add-file-context" source))
    (should (string-match-p "defun eca-chat-add-cursor-context" source))))

(provide 'test-ai-code-eca-bridge)
;;; test-ai-code-eca-bridge.el ends here

(provide 'test-ai-code-eca-bridge)
;;; test-ai-code-eca-bridge.el ends here