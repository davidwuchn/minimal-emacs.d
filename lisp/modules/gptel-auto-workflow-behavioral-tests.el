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
  (let ((passed t)
        (errors nil))
    ;; Test 1: Symbol keys (normal case)
    (let* ((symbol-data '((file . "lisp/modules/test.el") (priority . 1)))
           (result (gptel-auto-workflow--json-target-file symbol-data)))
      (when (not (equal result "lisp/modules/test.el"))
        (push "Symbol key extraction failed" errors)
        (setq passed nil)))

    ;; Test 2: String keys (defensive case - this would have caught the bug)
    (let* ((string-data (list '("file" . "lisp/modules/test.el") '("priority" . 1)))
           (result (gptel-auto-workflow--json-target-file string-data)))
      (when (not (equal result "lisp/modules/test.el"))
        (push "String key extraction failed (BUG: defensive lookup removed)" errors)
        (setq passed nil)))

    ;; Test 3: Mixed keys
    (let* ((mixed-data '((path . "lisp/modules/test2.el")))
           (result (gptel-auto-workflow--json-target-file mixed-data)))
      (when (not (equal result "lisp/modules/test2.el"))
        (push "Mixed key extraction failed" errors)
        (setq passed nil)))

    ;; Test 4: Nil/empty handling
    (let ((result (gptel-auto-workflow--json-target-file nil)))
      (when result
        (push "Nil handling failed" errors)
        (setq passed nil)))

    ;; Test 5: Non-string value for file key should return nil (defensive)
    (let* ((nonstring-data '((file . 123)))
           (result (gptel-auto-workflow--json-target-file nonstring-data)))
      (when result
        (push "Non-string file value should return nil" errors)
        (setq passed nil)))

    ;; Test 6: Missing recognized keys should return nil
    (let* ((unknown-keys '((other . "lisp/modules/test.el") (name . "test")))
           (result (gptel-auto-workflow--json-target-file unknown-keys)))
      (when result
        (push "Unknown keys should return nil" errors)
        (setq passed nil)))

    (cons passed (nreverse errors))))

(defun gptel-auto-workflow--test-validate-and-add-target ()
  "Test that validate-and-add-target handles edge cases correctly."
  (let ((passed t)
        (errors nil)
        (test-root (expand-file-name "lisp/modules/" user-emacs-directory)))
    ;; Test 1: Non-string input should return targets unchanged
    (let* ((targets '("existing.el"))
           (result (gptel-auto-workflow--validate-and-add-target 123 test-root targets)))
      (when (not (equal result targets))
        (push "Non-string input should return targets unchanged" errors)
        (setq passed nil)))

    ;; Test 2: Empty proj-root should return targets unchanged
    (let* ((targets '("existing.el"))
           (result (gptel-auto-workflow--validate-and-add-target "test.el" "" targets)))
      (when (not (equal result targets))
        (push "Empty proj-root should return targets unchanged" errors)
        (setq passed nil)))

    ;; Test 3: Nil proj-root should return targets unchanged
    (let* ((targets '("existing.el"))
           (result (gptel-auto-workflow--validate-and-add-target "test.el" nil targets)))
      (when (not (equal result targets))
        (push "Nil proj-root should return targets unchanged" errors)
        (setq passed nil)))

    ;; Test 4: JSON object input should extract and validate
    (let* ((json-obj '((file . "gptel-auto-workflow-strategic.el")))
           (targets '())
           (result (gptel-auto-workflow--validate-and-add-target json-obj test-root targets)))
      (when (or (not (listp result)) (not (member "gptel-auto-workflow-strategic.el" result)))
        (push "JSON object input should extract and validate file" errors)
        (setq passed nil)))

    ;; Test 4b: JSON object with string keys should also extract and validate
    (let* ((json-obj (list (cons "file" "gptel-auto-workflow-strategic.el")))
           (targets '())
           (result (gptel-auto-workflow--validate-and-add-target json-obj test-root targets)))
      (when (or (not (listp result)) (not (member "gptel-auto-workflow-strategic.el" result)))
        (push "JSON object with string file key should extract and validate file" errors)
        (setq passed nil)))

    ;; Test 5: Duplicate target should not be added
    (let* ((existing "gptel-auto-workflow-strategic.el")
           (targets (list existing))
           (result (gptel-auto-workflow--validate-and-add-target
                    (expand-file-name existing test-root) test-root targets)))
      (when (or (not (equal result targets)) (/= (length result) 1))
        (push "Duplicate target should not be added twice" errors)
        (setq passed nil)))

    ;; Test 6: JSON object with non-string file value should return targets unchanged
    (let* ((targets '())
           (json-obj '((file . 123)))
           (result (gptel-auto-workflow--validate-and-add-target json-obj test-root targets)))
      (when (not (equal result targets))
        (push "JSON object with non-string file value should return targets unchanged" errors)
        (setq passed nil)))

    ;; Test 7: JSON object with empty file value should return targets unchanged
    (let* ((targets '())
           (json-obj '((file . "")))
           (result (gptel-auto-workflow--validate-and-add-target json-obj test-root targets)))
      (when (not (equal result targets))
        (push "JSON object with empty file value should return targets unchanged" errors)
        (setq passed nil)))

    (cons passed (nreverse errors))))

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
