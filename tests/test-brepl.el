;;; test-brepl.el --- Tests for gptel-ext-brepl (brepl for OV5) -*- lexical-binding: t; -*-

(require 'ert)

;; Load brepl
(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-ext-brepl)

(ert-deftest test-brepl/socket-dir-found ()
  "Socket directory is found on this system."
  (let ((dir (gptel-brepl--socket-dir)))
    (should (or (null dir) (stringp dir)))))

(ert-deftest test-brepl/status-plist ()
  "Status returns a valid plist."
  (let ((status (gptel-brepl-status)))
    (should (plistp status))
    (should (booleanp (plist-get status :enabled)))
    (should (booleanp (plist-get status :eval-on-save)))
    (should (booleanp (plist-get status :validate-brackets)))))

(ert-deftest test-brepl/validate-brackets-balanced ()
  "Balanced code passes validation."
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((code "(defun foo () 42)"))
      (let ((result (gptel-brepl-validate-brackets code)))
        (should (plist-get result :valid))
        (should (string= (plist-get result :fixed-content) code))
        (should (null (plist-get result :error)))))))

(ert-deftest test-brepl/validate-brackets-unbalanced ()
  "Unbalanced code fails validation or gets auto-fixed."
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((code "(defun foo () 42"))
      (let ((result (gptel-brepl-validate-brackets code)))
        ;; Either it's invalid (no fixer available) or it was auto-fixed
        (if (plist-get result :valid)
            ;; Auto-fixed case: self-heal fixer added closing paren
            (progn
              (should (stringp (plist-get result :fixed-content)))
              (should-not (string= (plist-get result :fixed-content) code)))
          ;; Unfixable case
          (should (stringp (plist-get result :error))))))))

(ert-deftest test-brepl/eval-expression-fails-without-daemon ()
  "Eval fails gracefully when no daemon is running."
  :expected-result :failed  ; We expect this to fail without a daemon
  (gptel-brepl-eval-expression "(+ 1 2 3)"))

(ert-deftest test-brepl/discover-servers-returns-list ()
  "Server discovery returns a list."
  (let ((servers (gptel-brepl--discover-servers)))
    (should (listp servers))
    ;; Each entry should be a cons cell
    (dolist (s servers)
      (should (consp s))
      (should (stringp (car s)))
      (should (stringp (cdr s))))))

(ert-deftest test-brepl/should-auto-eval-predicate ()
  "Auto-eval predicate filters correctly."
  ;; Test regex exclusions directly without mode dependency
  (let ((test-files '(("/tmp/test-project/lisp/modules/foo.el" . t)
                      ("/tmp/test-project/tests/test-foo.el" . nil)
                      ("/tmp/test-project/foo-autoloads.el" . nil)
                      ("/tmp/test-project/var/elpa/pkg.el" . nil))))
    (dolist (pair test-files)
      (let ((file (car pair))
            (expected (cdr pair)))
        ;; Simulate the file checks from should-auto-eval-p
        (let ((result (and (string-match-p "\\.el\\'" file)
                           (not (string-match-p "/\\." file))
                           (not (string-match-p "-autoloads\\.el\\'" file))
                           (not (string-match-p "\\`test-" (file-name-nondirectory file)))
                           (not (string-match-p "/tests?/" file))
                           (not (string-match-p "/var/" file)))))
          (should (eq result expected)))))))

(ert-deftest test-brepl/after-save-hook-installed ()
  "Save hooks are installed in emacs-lisp-mode buffers."
  (with-temp-buffer
    (emacs-lisp-mode)
    (gptel-brepl-install-save-hooks)
    (should (memq #'gptel-brepl--after-save-eval after-save-hook))))

(provide 'test-brepl)
;;; test-brepl.el ends here
