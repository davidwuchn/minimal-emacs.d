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

(cl-defstruct (gptel-test-context
               (:constructor gptel-test-context--create (passed errors))
               (:copier nil))
  "Test context for accumulating assertion results."
  (passed t)
  (errors nil))

(defun gptel-test-context--make ()
  "Create a fresh test context with empty error list."
  (gptel-test-context--create t nil))

(defun gptel-test-context--add-error (ctx msg)
  "Record an error MSG in test context CTX and mark as failed."
  (cl-check-type ctx gptel-test-context)
  (setf (gptel-test-context-errors ctx)
        (nconc (gptel-test-context-errors ctx) (list msg)))
  (setf (gptel-test-context-passed ctx) nil))

(defun gptel-test-context--assert-equal (ctx expr expected)
  "Assert in CTX that EXPR equals EXPECTED, record error on mismatch."
  (cl-check-type ctx gptel-test-context)
  (when (not (equal expr expected))
    (gptel-test-context--add-error
     ctx (format "expected %S, got %S" expected expr))))

(defun gptel-test-context--assert-member (ctx expr item)
  "Assert in CTX that ITEM is a member of EXPR list."
  (cl-check-type ctx gptel-test-context)
  (when (not (and (listp expr) (member item expr)))
    (gptel-test-context--add-error
     ctx (format "expected %S in result %S" item expr))))

(defun gptel-test-context--result (ctx)
  "Return final result alist from CTX: (passed . errors)."
  (cl-check-type ctx gptel-test-context)
  (cons (gptel-test-context-passed ctx)
        (or (nreverse (gptel-test-context-errors ctx)) '())))

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
  (let ((ctx (gptel-test-context--make)))
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--json-target-file '((file . "lisp/modules/test.el") (priority . 1)))
     "lisp/modules/test.el")
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--json-target-file (list '("file" . "lisp/modules/test.el") '("priority" . 1)))
     "lisp/modules/test.el")
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--json-target-file '((path . "lisp/modules/test2.el")))
     "lisp/modules/test2.el")
    (when (gptel-auto-workflow--json-target-file nil)
      (gptel-test-context--add-error ctx "nil input should return nil"))
    (when (gptel-auto-workflow--json-target-file '((file . 123)))
      (gptel-test-context--add-error ctx "non-string file value should return nil"))
    (when (gptel-auto-workflow--json-target-file '((other . "lisp/modules/test.el") (name . "test")))
      (gptel-test-context--add-error ctx "unknown keys should return nil"))
    (gptel-test-context--result ctx)))

(defun gptel-auto-workflow--test-validate-and-add-target ()
  "Test that validate-and-add-target handles edge cases correctly."
  (let ((ctx (gptel-test-context--make))
        (test-root (expand-file-name "lisp/modules/" user-emacs-directory)))
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--validate-and-add-target 123 test-root '("existing.el"))
     '("existing.el"))
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--validate-and-add-target "test.el" "" '("existing.el"))
     '("existing.el"))
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--validate-and-add-target "test.el" nil '("existing.el"))
     '("existing.el"))
    (let ((result (gptel-auto-workflow--validate-and-add-target
                   '((file . "gptel-auto-workflow-strategic.el")) test-root '())))
      (gptel-test-context--assert-member ctx result "gptel-auto-workflow-strategic.el"))
    (let ((result (gptel-auto-workflow--validate-and-add-target
                   (list (cons "file" "gptel-auto-workflow-strategic.el")) test-root '())))
      (gptel-test-context--assert-member ctx result "gptel-auto-workflow-strategic.el"))
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--validate-and-add-target
          (expand-file-name "gptel-auto-workflow-strategic.el" test-root)
          test-root (list "gptel-auto-workflow-strategic.el"))
     (list "gptel-auto-workflow-strategic.el"))
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--validate-and-add-target '((file . 123)) test-root '())
     '())
    (gptel-test-context--assert-equal
     ctx (gptel-auto-workflow--validate-and-add-target '((file . "")) test-root '())
     '())
    (gptel-test-context--result ctx)))

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
