;;; test-platform-sandbox.el --- Tests for platform sandbox -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;; Load the module under test
(unless (featurep 'gptel-platform-sandbox)
  (load (expand-file-name "lisp/modules/gptel-platform-sandbox.el"
                          default-directory)))

;; ── Platform Detection Tests ──

(ert-deftest tdd/platform-sandbox/available-p-returns-boolean ()
  "Should return t or nil, never error."
  (let ((result (gptel-platform-sandbox--available-p)))
    (should (or (eq result t) (null result)))))

(ert-deftest tdd/platform-sandbox/platform-name-returns-keyword ()
  "Should return a keyword."
  (let ((name (gptel-platform-sandbox--platform-name)))
    (should (keywordp name))
    (should (memq name '(:seatbelt :bubblewrap :none)))))

;; ── Command Wrapping Tests ──

(ert-deftest tdd/platform-sandbox/wrap-command-returns-cons ()
  "wrap-command should return a cons (wrapped-cmd . profile-or-nil)."
  (cl-letf (((symbol-function 'gptel-platform-sandbox--platform-name) (lambda () :none)))
    (let ((result (gptel-platform-sandbox--wrap-command "echo hello")))
      (should (consp result))
      (should (stringp (car result)))
      (should (null (cdr result))))))

(ert-deftest tdd/platform-sandbox/wrap-command-seatbelt-returns-profile ()
  "seatbelt mode should return a profile file path."
  (cl-letf (((symbol-function 'gptel-platform-sandbox--platform-name) (lambda () :seatbelt))
            ((symbol-function 'gptel-platform-sandbox--current-mode) (lambda () :agent))
            ((symbol-function 'gptel-platform-sandbox--seatbelt-profile) (lambda (&optional _m) "/tmp/test.sb")))
    (let ((result (gptel-platform-sandbox--wrap-command "echo hello")))
      (should (string-prefix-p "sandbox-exec" (car result)))
      (should (equal "/tmp/test.sb" (cdr result))))))

(ert-deftest tdd/platform-sandbox/wrap-command-bwrap-returns-nil-profile ()
  "bubblewrap mode should return nil profile (no temp file to clean)."
  (cl-letf (((symbol-function 'gptel-platform-sandbox--platform-name) (lambda () :bubblewrap))
            ((symbol-function 'gptel-platform-sandbox--current-mode) (lambda () :agent))
            ((symbol-function 'gptel-platform-sandbox--bwrap-args) (lambda (&optional _m) "--bind / /")))
    (let ((result (gptel-platform-sandbox--wrap-command "echo hello")))
      (should (string-prefix-p "bwrap " (car result)))
      (should (null (cdr result))))))

(ert-deftest tdd/platform-sandbox/plan-mode-restricts-network ()
  "Plan mode seatbelt profile should deny network."
  (cl-letf (((symbol-function 'gptel-platform-sandbox--current-mode) (lambda () :plan))
            ((symbol-function 'gptel-auto-workflow--worktree-base-root) (lambda () "/tmp/test-ws")))
    (let ((profile (gptel-platform-sandbox--seatbelt-profile :plan)))
      (unwind-protect
          (with-temp-buffer
            (insert-file-contents profile)
            (should (string-match "(deny network\\*)" (buffer-string)))
            (should-not (string-match "network-outbound" (buffer-string))))
        (ignore-errors (delete-file profile))))))

(ert-deftest tdd/platform-sandbox/agent-mode-allows-network ()
  "Agent mode seatbelt profile should allow network outbound."
  (cl-letf (((symbol-function 'gptel-platform-sandbox--current-mode) (lambda () :agent))
            ((symbol-function 'gptel-auto-workflow--worktree-base-root) (lambda () "/tmp/test-ws")))
    (let ((profile (gptel-platform-sandbox--seatbelt-profile :agent)))
      (unwind-protect
          (with-temp-buffer
            (insert-file-contents profile)
            (should (string-match "network-outbound" (buffer-string)))
            (should-not (string-match "(deny network\\*)" (buffer-string))))
        (ignore-errors (delete-file profile))))))

;; ── Profile Generation Tests ──

(ert-deftest tdd/platform-sandbox/seatbelt-profile-has-deny-default ()
  "Seatbelt profile should start with deny default."
  (cl-letf (((symbol-function 'gptel-platform-sandbox--workspace-root) nil)
            ((symbol-function 'gptel-auto-workflow--worktree-base-root) (lambda () "/tmp/test-ws")))
    (let ((profile (gptel-platform-sandbox--seatbelt-profile)))
      (unwind-protect
          (progn
            (should (file-exists-p profile))
            (with-temp-buffer
              (insert-file-contents profile)
              (should (string-match "(deny default)" (buffer-string)))
              (should (string-match "subpath" (buffer-string)))))
        (ignore-errors (delete-file profile))))))

(ert-deftest tdd/platform-sandbox/bwrap-args-has-unshare-all ()
  "Bwrap args should include --unshare-all and --share-net in agent mode."
  (let ((gptel-platform-sandbox--workspace-root "/tmp/test-ws")
        (args (gptel-platform-sandbox--bwrap-args :agent)))
    (should (string-match-p "unshare-all" args))
    (should (string-match-p "share-net" args))
    (should (string-match-p "ro-bind" args))))

(ert-deftest tdd/platform-sandbox/bwrap-plan-mode-no-share-net ()
  "Bwrap args in plan mode should NOT include --share-net."
  (let ((gptel-platform-sandbox--workspace-root "/tmp/test-ws")
        (args (gptel-platform-sandbox--bwrap-args :plan)))
    (should (string-match-p "unshare-all" args))
    (should-not (string-match-p "share-net" args))))

(ert-deftest tdd/platform-sandbox/wrap-and-send-integrates-with-bash-tool ()
  "wrap-and-send requires gptel-platform-sandbox and bash tool.
Verifies the function is fboundp after requiring the module."
  (should (fboundp 'gptel-platform-sandbox--wrap-and-send))
  (should (fboundp 'gptel-platform-sandbox--available-p)))

(provide 'test-platform-sandbox)
;;; test-platform-sandbox.el ends here
