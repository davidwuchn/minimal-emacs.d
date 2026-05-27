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

(defmacro gptel-test-context--ensure (ctx)
  "Validate CTX is a non-nil gptel-test-context, signal on invalid."
  `(progn
     (when (null ,ctx)
       (signal 'wrong-type-argument (list 'gptel-test-context ,ctx)))
     (cl-check-type ,ctx gptel-test-context)))

(defun gptel-test-context--clear-errors (ctx)
  "Clear all errors in test context CTX and reset passed flag."
  (gptel-test-context--ensure ctx)
  (setf (gptel-test-context-errors ctx) nil)
  (setf (gptel-test-context-passed ctx) t)
  ctx)

(defun gptel-test-context--add-error (ctx msg)
  "Record an error MSG in test context CTX and mark as failed."
  (gptel-test-context--ensure ctx)
  (setf (gptel-test-context-errors ctx)
        (nconc (gptel-test-context-errors ctx) (list msg)))
  (setf (gptel-test-context-passed ctx) nil))

(defun gptel-test-context--assert-equal (ctx expr expected)
  "Assert in CTX that EXPR equals EXPECTED, record error on mismatch."
  (gptel-test-context--ensure ctx)
  (when (not (equal expr expected))
    (gptel-test-context--add-error
     ctx (format "expected %S, got %S" expected expr))))

(defun gptel-test-context--assert-member (ctx expr item)
  "Assert in CTX that ITEM is a member of EXPR list."
  (gptel-test-context--ensure ctx)
  (when (not (and (proper-list-p expr) (member item expr)))
    (gptel-test-context--add-error
     ctx (format "expected %S in result %S" item expr))))

(defun gptel-test-context--result (ctx)
  "Return final result alist from CTX: (passed . errors)."
  (gptel-test-context--ensure ctx)
  (cons (gptel-test-context-passed ctx)
        (or (nreverse (gptel-test-context-errors ctx)) '())))

;;; Test harness macros

(defmacro gptel-auto-workflow--with-test-context (&rest body)
  "Execute BODY with a fresh test context, collecting errors.
Returns (PASS-P . ERRORS)."
  `(let ((ctx (gptel-test-context--make)))
     ,@body
     (gptel-test-context--result ctx)))

(defmacro gptel-auto-workflow--test-assert (expr expected)
  "Assert in test context that EXPR equals EXPECTED."
  `(gptel-test-context--assert-equal ctx ,expr ,expected))

(defmacro gptel-auto-workflow--test-member (expr item)
  "Assert in test context that ITEM is a member of EXPR."
  `(gptel-test-context--assert-member ctx ,expr ,item))

(defmacro gptel-auto-workflow--test-error (msg)
  "Manually add an error message to the test context."
  `(gptel-test-context--add-error ctx ,msg))

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
  (gptel-auto-workflow--with-test-context
    (gptel-auto-workflow--test-assert
     (gptel-auto-workflow--json-target-file '((file . "lisp/modules/test.el") (priority . 1)))
     "lisp/modules/test.el")
    (gptel-auto-workflow--test-assert
     (gptel-auto-workflow--json-target-file (list '("file" . "lisp/modules/test.el") '("priority" . 1)))
     "lisp/modules/test.el")
    (gptel-auto-workflow--test-assert
     (gptel-auto-workflow--json-target-file '((path . "lisp/modules/test2.el")))
     "lisp/modules/test2.el")
    (when (gptel-auto-workflow--json-target-file nil)
      (gptel-auto-workflow--test-error "nil input should return nil"))
    (when (gptel-auto-workflow--json-target-file '((file . 123)))
      (gptel-auto-workflow--test-error "non-string file value should return nil"))
    (when (gptel-auto-workflow--json-target-file '((other . "lisp/modules/test.el") (name . "test")))
      (gptel-auto-workflow--test-error "unknown keys should return nil"))
    (gptel-auto-workflow--test-assert
     (gptel-auto-workflow--json-target-file '()) nil)
    (gptel-auto-workflow--test-assert
     (gptel-auto-workflow--json-target-file '((file . ""))) nil)
    (gptel-auto-workflow--test-assert
     (gptel-auto-workflow--json-target-file '((file . nil))) nil)))

(defun gptel-auto-workflow--test-validate-and-add-target ()
  "Test that validate-and-add-target handles edge cases correctly."
  (let ((test-root (expand-file-name "lisp/modules/" user-emacs-directory)))
    (gptel-auto-workflow--with-test-context
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target 123 test-root '("existing.el"))
       '("existing.el"))
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target "test.el" "" '("existing.el"))
       '("existing.el"))
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target "test.el" nil '("existing.el"))
       '("existing.el"))
      (gptel-auto-workflow--test-member
       (gptel-auto-workflow--validate-and-add-target '((file . "gptel-auto-workflow-strategic.el")) test-root '())
       "gptel-auto-workflow-strategic.el")
      (gptel-auto-workflow--test-member
       (gptel-auto-workflow--validate-and-add-target (list (cons "file" "gptel-auto-workflow-strategic.el")) test-root '())
       "gptel-auto-workflow-strategic.el")
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target
        (expand-file-name "gptel-auto-workflow-strategic.el" test-root)
        test-root (list "gptel-auto-workflow-strategic.el"))
       (list "gptel-auto-workflow-strategic.el"))
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target '((file . 123)) test-root '())
       '())
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target '((file . "")) test-root '())
       '())
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target '()) '())
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target '((other . "test.el")) test-root '())
       '())
      (gptel-auto-workflow--test-assert
       (gptel-auto-workflow--validate-and-add-target "nonexistent.el" test-root '())
       '()))))

(defun gptel-auto-workflow--run-behavioral-tests (changed-files)
  "Run behavioral tests relevant to CHANGED-FILES.
Returns (PASS-P . OUTPUT-STRING)."
  (unless (listp changed-files)
    (signal 'wrong-type-argument (list 'listp changed-files)))
  (let ((output "")
        (all-passed t))
    (dolist (test-entry gptel-auto-workflow--behavioral-test-suite)
      (let* ((name (car test-entry))
             (test-file (or (plist-get (cdr test-entry) :file) ""))
             (test-fn (or (plist-get (cdr test-entry) :test) #'ignore)))
        (when (and (not (string-empty-p test-file))
                   (not (eq test-fn #'ignore))
                   (cl-some (lambda (f) (string-match-p (regexp-quote test-file) f))
                            changed-files))
          (setq output (concat output (format "\n[behavioral] Running %s...\n" name)))
          (condition-case err
              (let ((result (funcall test-fn)))
                (if (and (consp result) (car result))
                    (setq output (concat output (format "[behavioral] %s: PASSED\n" name)))
                  (setq all-passed nil)
                  (setq output (concat output (format "[behavioral] %s: FAILED\n  %s\n"
                                                       name
                                                       (if (consp result)
                                                           (mapconcat #'identity (cdr result) "\n  ")
                                                         (format "invalid result: %S" result)))))))
            (error
             (setq all-passed nil)
             (setq output (concat output (format "[behavioral] %s: ERROR - %s\n"
                                                 name (error-message-string err)))))))))
    (cons all-passed output)))

(provide 'gptel-auto-workflow-behavioral-tests)
;;; gptel-auto-workflow-behavioral-tests.el ends here
