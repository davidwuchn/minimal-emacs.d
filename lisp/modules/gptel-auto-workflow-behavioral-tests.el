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

(defvar gptel-auto-workflow--behavioral-test-suite
  '(("json-target-extraction"
     :file "lisp/modules/gptel-auto-workflow-strategic.el"
     :test gptel-auto-workflow--test-json-target-extraction))
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
