;;; test-nucleus-source-check.el --- Structural test for nucleus-config error handling

;;; Commentary:
;; TDD regression test: nucleus-config must not silently swallow errors.
;;
;; The previous commit 77f23356c fixed silent ignore-errors for
;; nucleus-presets-setup.  This test prevents regression of the same
;; anti-pattern for nucleus--register-gptel-directives.

;;; Code:

(require 'ert)

(ert-deftest test-nucleus-config-no-ignore-errors-for-directives ()
  "nucleus-config must use condition-case (not ignore-errors) for
nucleus--register-gptel-directives.  This is a structural regression
test: any future commit that reverts to ignore-errors will fail."
  (let* ((source
          (locate-library "nucleus-config"))
         (path (and source (file-chase-links source))))
    (should path)
    (should (string-suffix-p "lisp/nucleus-config.el" path))
    (let ((contents (with-temp-buffer
                     (insert-file-contents path)
                     (buffer-string))))
      ;; The directives function must NOT be wrapped in ignore-errors
      (should-not (string-match-p
                  "ignore-errors[ \t\n]+(.*?nucleus--register-gptel-directives"
                  contents)))))

(provide 'test-nucleus-source-check)
;;; test-nucleus-source-check.el ends here
