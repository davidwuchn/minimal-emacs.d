;;; test-audit-provide-inside-defun-loader.el --- TDD: file must load cleanly -*- lexical-binding: t; -*-

;; Regression test for the silent-truncation bug pattern.
;; The previous version of gptel-auto-workflow-audit-provide-inside-defun.el
;; had a missing open-paren in the --audit-provide-inside-defun defun,
;; causing Emacs to silently truncate the file at the unbalanced paren.
;; Result: --audit-provide-inside-defun was NOT bound even though the
;; module loaded successfully (via the --fix-* function below).
;;
;; This test asserts:
;;   1. The file loads without error
;;   2. Both --audit-provide-inside-defun AND --fix-provide-inside-defun
;;      are fboundp after load
;;
;; If either fails, the file has the silent-truncation bug pattern.

;;; Code:

(require 'ert)

;; Load the module under test
(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-auto-workflow-audit-provide-inside-defun)

(ert-deftest test-audit-provide-inside-defun/file-loads-cleanly ()
  "The module file must load without read errors.
Catches the silent-truncation pattern where a missing open-paren
makes Emacs stop reading the file partway through."
  (let ((load-file-name nil))
    (should (featurep 'gptel-auto-workflow-audit-provide-inside-defun))
    (should (fboundp 'gptel-auto-workflow--audit-provide-inside-defun))
    (should (fboundp 'gptel-auto-workflow--fix-provide-inside-defun))))

(ert-deftest test-audit-provide-inside-defun/detects-swallowed-provide ()
  "audit() must return non-zero when provide is inside a defun."
  (let* ((content "(defun foo ()\n  1\n(provide 'bar)\n;;; bar.el ends here\n")
         (file (make-temp-file "ov5-audit-" nil ".el"))
         (gptel-auto-workflow--semantic-audit-issues nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (let ((issues (gptel-auto-workflow--audit-provide-inside-defun file)))
            (should (>= issues 1))))
      (delete-file file))))

(ert-deftest test-audit-provide-inside-defun/clean-provide-returns-zero ()
  "audit() must return 0 when provide is at top level."
  (let* ((content "(defun foo ()\n  1)\n\n(provide 'bar)\n;;; bar.el ends here\n")
         (file (make-temp-file "ov5-audit-clean-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (let ((issues (gptel-auto-workflow--audit-provide-inside-defun file)))
            (should (= issues 0))))
      (delete-file file))))

(provide 'test-audit-provide-inside-defun-loader)
;;; test-audit-provide-inside-defun-loader.el ends here
