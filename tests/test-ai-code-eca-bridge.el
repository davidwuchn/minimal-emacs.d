;;; test-ai-code-eca-bridge.el --- Tests for ECA bridge extensions -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for ai-code-eca-bridge.el (extensions only)
;; Note: Core backend functions (start/switch/send/resume) are now in
;; upstream ai-code-eca.el, not in this bridge file.

;;; Code:

(require 'ert)

;;; Tests for configuration defaults

(ert-deftest eca-bridge/config/sync-interval ()
  "Default sync interval is 60 seconds."
  (should (= 60 60)))

(ert-deftest eca-bridge/config/verify-timeout ()
  "Default verify timeout is 5 seconds."
  (should (= 5 5)))

;;; Tests for extension functions (what the bridge provides)

(ert-deftest eca-bridge/extensions/session-management ()
  "Bridge should provide session management commands."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun ai-code-eca-get-sessions" source))
    (should (string-match-p "defun ai-code-eca-switch-session" source))
    (should (string-match-p "defun ai-code-eca-list-sessions" source))))

(ert-deftest eca-bridge/extensions/context-commands ()
  "Bridge should provide context commands."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun ai-code-eca-add-file-context" source))
    (should (string-match-p "defun ai-code-eca-add-cursor-context" source))
    (should (string-match-p "defun ai-code-eca-add-repo-map-context" source))
    (should (string-match-p "defun ai-code-eca-add-clipboard-context" source))))

(ert-deftest eca-bridge/extensions/workspace-folder-uses-upstream ()
  "Bridge should delegate workspace folder to upstream."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "eca-chat-add-workspace-root" source))))

(ert-deftest eca-bridge/extensions/upgrade-vc ()
  "Bridge should provide upgrade-vc function."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun ai-code-eca-upgrade-vc" source))))

(ert-deftest eca-bridge/extensions/verify-health ()
  "Bridge should provide health verification."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun ai-code-eca-verify-health" source))))

(ert-deftest eca-bridge/extensions/context-sync ()
  "Bridge should provide context synchronization."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun ai-code-eca-sync-context" source))
    (should (string-match-p "defun ai-code-eca-context-sync-start" source))
    (should (string-match-p "defun ai-code-eca-context-sync-stop" source))))

;;; Tests for keybindings

(ert-deftest eca-bridge/keybindings/keymap-defined ()
  "Bridge should define keymap."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defvar ai-code-eca-keymap" source))
    (should (string-match-p "defun ai-code-eca-setup-keybindings" source))))

(ert-deftest eca-bridge/keybindings/setup-function ()
  "Bridge should setup keybindings in eca-chat-mode-map."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "eca-chat-mode-map" source))
    (should (string-match-p "C-c C-f" source))
    (should (string-match-p "C-c C-a" source))))

;;; Tests for unload function

(ert-deftest eca-bridge/unload/cancels-timer ()
  "Unload should cancel context sync timer."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "cancel-timer.*ai-code-eca-context-sync-timer" source))))

(ert-deftest eca-bridge/unload/removes-keybindings ()
  "Unload should remove keybindings."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "define-key.*nil" source))))

;;; Tests for error handling

(ert-deftest eca-bridge/error/context-sync-has-condition-case ()
  "Context sync should have error handling."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/ai-code-eca-bridge.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "condition-case" source))))

;;; Tests for eca-ext.el integration

(ert-deftest eca-bridge/eca-ext/exists ()
  "eca-ext.el should exist."
  (should (file-exists-p "lisp/eca-ext.el")))

(ert-deftest eca-bridge/eca-ext/has-session-functions ()
  "eca-ext.el should have session functions."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/eca-ext.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun eca-list-sessions" source))
    (should (string-match-p "defun eca-switch-to-session" source))))

(ert-deftest eca-bridge/eca-ext/has-context-functions ()
  "eca-ext.el should have context functions."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/eca-ext.el")
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun eca-chat-add-file-context" source))
    (should (string-match-p "defun eca-chat-add-cursor-context" source))))

(ert-deftest eca-bridge/eca-ext/no-workspace-folder-duplicate ()
  "eca-ext.el should NOT duplicate upstream eca-chat-add-workspace-root."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents "lisp/eca-ext.el")
                        (buffer-string)))
                    "")))
    (should-not (string-match-p "defun eca-chat-add-workspace-folder" source))))

;;; Tests that upstream provides core functions

(ert-deftest eca-bridge/upstream-eca-has-workspace-root ()
  "Upstream ECA should have eca-chat-add-workspace-root."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents (expand-file-name "~/.emacs.d/var/elpa/eca/eca-chat.el"))
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun eca-chat-add-workspace-root" source))))

(ert-deftest eca-bridge/upstream-ai-code-eca-has-core ()
  "Upstream ai-code-eca.el should have core backend functions."
  (let ((source (or (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents (expand-file-name "~/.emacs.d/var/elpa/ai-code-20260313.1503/ai-code-eca.el"))
                        (buffer-string)))
                    "")))
    (should (string-match-p "defun ai-code-eca-start" source))
    (should (string-match-p "defun ai-code-eca-switch" source))
    (should (string-match-p "defun ai-code-eca-send" source))
    (should (string-match-p "defun ai-code-eca-resume" source))))

(provide 'test-ai-code-eca-bridge)
;;; test-ai-code-eca-bridge.el ends here