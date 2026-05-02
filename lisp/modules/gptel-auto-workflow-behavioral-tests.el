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

(defun gptel-auto-workflow--test-assert (condition message)
  "Return nil if CONDITION is true, otherwise return MESSAGE."
  (and (not condition) message))

(defun gptel-auto-workflow--test-json-target-extraction ()
  "Test that JSON target extraction handles both symbol and string keys."
  (let ((errors
         (delq nil
               (list
                ;; Test 1: Symbol keys (normal case)
                (let* ((symbol-data '((file . "lisp/modules/test.el") (priority . 1)))
                       (result (gptel-auto-workflow--json-target-file symbol-data)))
                  (gptel-auto-workflow--test-assert
                   (equal result "lisp/modules/test.el")
                   "Symbol key extraction failed"))
                ;; Test 2: String keys (defensive case - this would have caught the bug)
                (let* ((string-data (list '("file" . "lisp/modules/test.el") '("priority" . 1)))
                       (result (gptel-auto-workflow--json-target-file string-data)))
                  (gptel-auto-workflow--test-assert
                   (equal result "lisp/modules/test.el")
                   "String key extraction failed (BUG: defensive lookup removed)"))
                ;; Test 3: Mixed keys
                (let* ((mixed-data '((path . "lisp/modules/test2.el")))
                       (result (gptel-auto-workflow--json-target-file mixed-data)))
                  (gptel-auto-workflow--test-assert
                   (equal result "lisp/modules/test2.el")
                   "Mixed key extraction failed"))
                ;; Test 4: Nil/empty handling
                (let ((result (gptel-auto-workflow--json-target-file nil)))
                  (gptel-auto-workflow--test-assert
                   (not result)
                   "Nil handling failed"))))))
    (cons (null errors) (nreverse errors))))

(defun gptel-auto-workflow--test-validate-and-add-target ()
  "Test that validate-and-add-target handles edge cases correctly."
  (let* ((test-root (expand-file-name "lisp/modules/" user-emacs-directory))
         (errors
          (delq nil
                (list
                ;; Test 1: Non-string input should return targets unchanged
                (let* ((targets '("existing.el"))
                       (result (gptel-auto-workflow--validate-and-add-target 123 test-root targets)))
                  (gptel-auto-workflow--test-assert
                   (equal result targets)
                   "Non-string input should return targets unchanged"))
                ;; Test 2: Empty proj-root should return targets unchanged
                (let* ((targets '("existing.el"))
                       (result (gptel-auto-workflow--validate-and-add-target "test.el" "" targets)))
                  (gptel-auto-workflow--test-assert
                   (equal result targets)
                   "Empty proj-root should return targets unchanged"))
                ;; Test 3: Nil proj-root should return targets unchanged
                (let* ((targets '("existing.el"))
                       (result (gptel-auto-workflow--validate-and-add-target "test.el" nil targets)))
                  (gptel-auto-workflow--test-assert
                   (equal result targets)
                   "Nil proj-root should return targets unchanged"))
                ;; Test 4: JSON object input should extract and validate
                (let* ((json-obj '((file . "gptel-auto-workflow-strategic.el")))
                       (targets '())
                       (result (gptel-auto-workflow--validate-and-add-target json-obj test-root targets)))
                  (gptel-auto-workflow--test-assert
                   (and (listp result) (member "gptel-auto-workflow-strategic.el" result))
                   "JSON object input should extract and validate file"))
                ;; Test 5: Duplicate target should not be added
                (let* ((existing "gptel-auto-workflow-strategic.el")
                       (targets (list existing))
                       (result (gptel-auto-workflow--validate-and-add-target
                                (expand-file-name existing test-root) test-root targets)))
                  (gptel-auto-workflow--test-assert
                   (and (equal result targets) (= (length result) 1))
                   "Duplicate target should not be added twice"))))))
    (cons (null errors) (nreverse errors))))

(defun gptel-auto-workflow--run-behavioral-tests (changed-files)
  "Run behavioral tests relevant to CHANGED-FILES.
Returns (PASS-P . OUTPUT-STRING)."
  (let ((output "")
        (all-passed t))
    (dolist (test-entry gptel-auto-workflow--behavioral-test-suite)
      (let* ((name (car test-entry))
             (test-file (plist-get (cdr test-entry) :file))
             (test-fn (plist-get (cdr test-entry) :test)))
        (when (and test-file (functionp test-fn)
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
