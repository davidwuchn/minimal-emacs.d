;;; test-gptel-programmatic-benchmark.el --- Tests for programmatic benchmark -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-programmatic-benchmark.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-programmatic-benchmark.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Module file tests

(ert-deftest test-prog/module-file-in-modules-dir ()
  "Programmatic benchmark module file should be in modules dir."
  (let ((path (expand-file-name "lisp/modules/gptel-programmatic-benchmark.el"
                                (or (and (boundp 'user-emacs-directory) user-emacs-directory)
                                    "~/.emacs.d"))))
    (should (or (file-exists-p path)
                (file-exists-p (expand-file-name "gptel-programmatic-benchmark.el" "lisp/modules"))))))

;;; Function signatures in file tests

(ert-deftest test-prog/tool-name-in-source ()
  "Tool name function should be in source."
  (let ((source-file (expand-file-name "lisp/modules/gptel-programmatic-benchmark.el"
                                        (or (and (boundp 'user-emacs-directory) user-emacs-directory)
                                            default-directory))))
    (when (file-exists-p source-file)
      (with-temp-buffer
        (insert-file-contents source-file)
        (should (search-forward "defun gptel-programmatic-benchmark--tool-name" nil t))))))

(ert-deftest test-prog/make-tools-in-source ()
  "Make tools function should be in source."
  (let ((source-file (expand-file-name "lisp/modules/gptel-programmatic-benchmark.el"
                                        (or (and (boundp 'user-emacs-directory) user-emacs-directory)
                                            default-directory))))
    (when (file-exists-p source-file)
      (with-temp-buffer
        (insert-file-contents source-file)
        (should (search-forward "defun gptel-programmatic-benchmark--make-tools" nil t))))))

(ert-deftest test-prog/make-patch-in-source ()
  "Make patch function should be in source."
  (let ((source-file (expand-file-name "lisp/modules/gptel-programmatic-benchmark.el"
                                        (or (and (boundp 'user-emacs-directory) user-emacs-directory)
                                            default-directory))))
    (when (file-exists-p source-file)
      (with-temp-buffer
        (insert-file-contents source-file)
        (should (search-forward "defun gptel-programmatic-benchmark--make-patch" nil t))))))

(provide 'test-gptel-programmatic-benchmark)
;;; test-gptel-programmatic-benchmark.el ends here