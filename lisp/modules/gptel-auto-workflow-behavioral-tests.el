;;; gptel-auto-workflow-behavioral-tests.el --- Behavioral smoke tests for auto-workflow -*- lexical-binding: t; -*-

;;; Commentary:
;; Runtime behavioral tests that catch semantic bugs missed by syntax/ERT checks.
;; These tests execute changed functions with edge-case inputs to detect
;; silent behavioral regressions (like removing defensive code).

;;; Code:

(require 'cl-lib)
(require 'json)

(declare-function gptel-auto-workflow--json-target-file
                  "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--json-object-p
                  "gptel-auto-workflow-strategic")

(declare-function gptel-auto-workflow--validate-and-add-target
                  "gptel-auto-workflow-strategic")

(defvar gptel-auto-workflow--behavioral-test-suite
  '(("json-target-extraction"
     :file "lisp/modules/gptel-auto-workflow-strategic.el"
     :test gptel-auto-workflow--test-json-target-extraction)
    ("validate-and-add-target"
     :file "lisp/modules/gptel-auto-workflow-strategic.el"
     :test gptel-auto-workflow--test-validate-and-add-target))
  "Alist of behavioral tests.
Each entry: (NAME :file FILE :test FUNCTION).")

(defun gptel-auto-workflow--test-json-target-extraction ()
  "Test that JSON target extraction handles both symbol and string keys."
  (let ((passed t)
        (errors nil))
    (cl-macrolet ((assert-equal (expr expected &rest args)
                                `(when (not (equal ,expr ,expected))
                                   (push (format "expected %S, got %S" ,expected ,expr) errors)
                                   (setq passed nil))))
      (assert-equal (gptel-auto-workflow--json-target-file '((file . "lisp/modules/test.el") (priority . 1)))
                    "lisp/modules/test.el")
      (assert-equal (gptel-auto-workflow--json-target-file (list '("file" . "lisp/modules/test.el") '("priority" . 1)))
                    "lisp/modules/test.el")
      (assert-equal (gptel-auto-workflow--json-target-file '((path . "lisp/modules/test2.el")))
                    "lisp/modules/test2.el")
      (when (gptel-auto-workflow--json-target-file nil)
        (push "nil input should return nil" errors)
        (setq passed nil))
      (when (gptel-auto-workflow--json-target-file '((file . 123)))
        (push "non-string file value should return nil" errors)
        (setq passed nil))
      (when (gptel-auto-workflow--json-target-file '((other . "lisp/modules/test.el") (name . "test")))
        (push "unknown keys should return nil" errors)
        (setq passed nil)))
    (cons passed (nreverse errors))))

(defun gptel-auto-workflow--test-validate-and-add-target ()
  "Test that validate-and-add-target handles edge cases correctly."
  (let ((passed t)
        (errors nil)
        (test-root (expand-file-name "lisp/modules/" user-emacs-directory)))
    (cl-macrolet ((assert-equal (expr expected &rest args)
                                `(when (not (equal ,expr ,expected))
                                   (push (format "expected %S, got %S" ,expected ,expr) errors)
                                   (setq passed nil)))
                 (assert-member (expr item &rest args)
                                `(when (not (and (listp ,expr) (member ,item ,expr)))
                                   (push (format "expected %S in result %S" ,item ,expr) errors)
                                   (setq passed nil))))
      (assert-equal (gptel-auto-workflow--validate-and-add-target 123 test-root '("existing.el"))
                    '("existing.el"))
      (assert-equal (gptel-auto-workflow--validate-and-add-target "test.el" "" '("existing.el"))
                    '("existing.el"))
      (assert-equal (gptel-auto-workflow--validate-and-add-target "test.el" nil '("existing.el"))
                    '("existing.el"))
      (let ((result (gptel-auto-workflow--validate-and-add-target
                     '((file . "gptel-auto-workflow-strategic.el")) test-root '())))
        (when (or (not (listp result)) (not (member "gptel-auto-workflow-strategic.el" result)))
          (push "JSON object should extract and validate file" errors)
          (setq passed nil)))
      (let ((result (gptel-auto-workflow--validate-and-add-target
                     (list (cons "file" "gptel-auto-workflow-strategic.el")) test-root '())))
        (when (or (not (listp result)) (not (member "gptel-auto-workflow-strategic.el" result)))
          (push "JSON object with string key should extract and validate" errors)
          (setq passed nil)))
      (assert-equal (gptel-auto-workflow--validate-and-add-target
                     (expand-file-name "gptel-auto-workflow-strategic.el" test-root)
                     test-root (list "gptel-auto-workflow-strategic.el"))
                    (list "gptel-auto-workflow-strategic.el"))
      (assert-equal (gptel-auto-workflow--validate-and-add-target '((file . 123)) test-root '())
                    '())
      (assert-equal (gptel-auto-workflow--validate-and-add-target '((file . "")) test-root '())
                    '()))
    (cons passed (nreverse errors))))

(defun gptel-auto-workflow--run-behavioral-tests (changed-files)
  "Run behavioral tests relevant to CHANGED-FILES.
Returns (PASS-P . OUTPUT-STRING)."
  (let ((output "")
        (all-passed t))
    (dolist (test-entry gptel-auto-workflow--behavioral-test-suite)
      (let* ((name (car test-entry))
             (test-file (plist-get (cdr test-entry) :file))
             (test-fn (plist-get (cdr test-entry) :test)))
        (when (and test-file test-fn
                   (cl-some (lambda (f) (string-match-p (regexp-quote test-file) f))
                            changed-files))
          (setq output (concat output (format "\n[behavioral] Running %s...\n" name)))
          (condition-case err
              (let ((result (funcall test-fn)))
                (if (car result)
                    (setq output (concat output (format "[behavioral] %s: PASSED\n" name)))
                  (setq all-passed nil)
                  (setq output (concat output (format "[behavioral] %s: FAILED\n  %s\n"
                                                       name
                                                       (mapconcat #'identity (cdr result) "\n  "))))))
            (error
             (setq all-passed nil)
             (setq output (concat output (format "[behavioral] %s: ERROR - %s\n"
                                                 name (error-message-string err)))))))))
    (cons all-passed output)))

(provide 'gptel-auto-workflow-behavioral-tests)
