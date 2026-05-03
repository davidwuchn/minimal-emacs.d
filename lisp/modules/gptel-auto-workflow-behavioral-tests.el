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

(defmacro gptel-auto-workflow--with-test-context (&rest body)
  "Execute BODY with test context bound to PASSED and ERRORS.
Sets up local variables for tracking test results.
Returns (PASSED-P . ERROR-LIST)."
  (declare (indent 0))
  `(let ((passed t)
         (errors nil))
     (condition-case err
         (progn ,@body)
       (error
        (push (format "Unhandled error: %s" (error-message-string err)) errors)
        (setq passed nil)))
     (cons passed (nreverse errors))))

(defmacro gptel-auto-workflow--test-assert (condition message)
  "Assert CONDITION is true, recording MESSAGE if it fails.
Must be used inside `gptel-auto-workflow--with-test-context'."
  (declare (indent 1))
  `(when (not ,condition)
     (push ,message errors)
     (setq passed nil)))

(defun gptel-auto-workflow--make-json-alist (key-type &optional file priority)
  "Build test alist with KEY-TYPE ('symbol or 'string) for FILE and PRIORITY."
  (unless (memq key-type '(symbol string))
    (signal 'wrong-type-argument (list '(symbol string) key-type)))
  (let ((file-pair (cons (if (eq key-type 'symbol) 'file "file")
                         (or file "lisp/modules/test.el")))
        (priority-pair (when priority
                         (cons (if (eq key-type 'symbol) 'priority "priority")
                               priority))))
    (if priority-pair
        (list file-pair priority-pair)
      (list file-pair))))

(defun gptel-auto-workflow--make-malformed-data (type)
  "Build malformed test data of TYPE: 'improper, 'vector, or 'empty."
  (unless (memq type '(improper vector empty))
    (signal 'wrong-type-argument (list '(improper vector empty) type)))
  (pcase type
    ('improper '("file" "value"))
    ('vector (vector "file" "test.el"))
    ('empty '())))

(defvar gptel-auto-workflow--behavioral-test-suite
  '(("json-target-extraction"
     :file "lisp/modules/gptel-auto-workflow-strategic.el"
     :test gptel-auto-workflow--test-json-target-extraction)
    ("malformed-data-handling"
     :file "lisp/modules/gptel-auto-workflow-strategic.el"
     :test gptel-auto-workflow--test-malformed-data-handling)
    ("validate-and-add-target"
     :file "lisp/modules/gptel-auto-workflow-strategic.el"
     :test gptel-auto-workflow--test-validate-and-add-target))
  "Alist of behavioral tests.
Each entry: (NAME :file FILE :test FUNCTION).")

(defun gptel-auto-workflow--test-json-target-extraction ()
  "Test that JSON target extraction handles both symbol and string keys."
  (gptel-auto-workflow--with-test-context
   ;; Test 1: Symbol keys (normal case)
   (let* ((symbol-data (gptel-auto-workflow--make-json-alist 'symbol "lisp/modules/test.el" 1))
          (result (gptel-auto-workflow--json-target-file symbol-data)))
     (gptel-auto-workflow--test-assert
      (equal result "lisp/modules/test.el")
      "Symbol key extraction failed"))
   
   ;; Test 2: String keys (defensive case - this would have caught the bug)
   (let* ((string-data (gptel-auto-workflow--make-json-alist 'string "lisp/modules/test.el" 1))
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
      "Nil handling failed"))))

(defun gptel-auto-workflow--test-malformed-data-handling ()
  "Test that functions gracefully handle malformed input data."
  (gptel-auto-workflow--with-test-context
   ;; Test 1: Improper list (not a proper alist - car is not a cons)
   (let* ((improper-list (gptel-auto-workflow--make-malformed-data 'improper))
          (result (gptel-auto-workflow--json-object-p improper-list)))
     (gptel-auto-workflow--test-assert
      (not result)
      "Improper list should not be recognized as JSON object"))
   
   ;; Test 2: Vector should not be confused with alist
   (let* ((vector-data (gptel-auto-workflow--make-malformed-data 'vector))
          (result (gptel-auto-workflow--json-object-p vector-data)))
     (gptel-auto-workflow--test-assert
      (not result)
      "Vector should not be recognized as JSON object"))
   
   ;; Test 3: Empty list should not be a JSON object
   (let ((result (gptel-auto-workflow--json-object-p (gptel-auto-workflow--make-malformed-data 'empty))))
     (gptel-auto-workflow--test-assert
      (not result)
      "Empty list should not be recognized as JSON object"))
   
   ;; Test 4: json-target-file should handle improper list gracefully
   (let ((result (gptel-auto-workflow--json-target-file (gptel-auto-workflow--make-malformed-data 'improper))))
     (gptel-auto-workflow--test-assert
      (or (null result) (stringp result))
      "json-target-file should return nil or string for improper list"))
   
   ;; Test 5: json-target-file should handle vector gracefully
   (let ((result (gptel-auto-workflow--json-target-file (gptel-auto-workflow--make-malformed-data 'vector))))
     (gptel-auto-workflow--test-assert
      (or (null result) (stringp result))
      "json-target-file should return nil or string for vector"))
   
   ;; Test 6: validate-and-add-target should handle vector input
   (let* ((targets '("existing.el"))
          (vector-data (gptel-auto-workflow--make-malformed-data 'vector))
          (result (gptel-auto-workflow--validate-and-add-target
                   vector-data (expand-file-name "lisp/modules/" user-emacs-directory) targets)))
     (gptel-auto-workflow--test-assert
      (equal result targets)
      "Vector input should return targets unchanged"))))

(defun gptel-auto-workflow--test-validate-and-add-target ()
  "Test that validate-and-add-target handles edge cases correctly."
  (let ((test-root (expand-file-name "lisp/modules/" user-emacs-directory)))
    (gptel-auto-workflow--with-test-context
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
        "Duplicate target should not be added twice")))))

(defun gptel-auto-workflow--run-behavioral-tests (changed-files)
  "Run behavioral tests relevant to CHANGED-FILES.
Returns (PASS-P . OUTPUT-STRING)."
  ;; ASSUMPTION: changed-files must be a proper list of strings
  ;; EDGE CASE: nil or non-list input returns safe default (no tests to run)
  (if (listp changed-files)
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
        (cons all-passed output))
    (cons t "")))

(provide 'gptel-auto-workflow-behavioral-tests)
