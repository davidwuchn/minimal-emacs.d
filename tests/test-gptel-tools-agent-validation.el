;;; test-gptel-tools-agent-validation.el --- Tests for code validation -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-validation.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-validation.el -f ert-run-tests-batch

;;; Code:

(setq load-prefer-newer t)

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-validation)

;;; cl-return-from validation tests

(ert-deftest test-validation/invalid-cl-return-nil-form ()
  "Nil form should return nil (no invalid target)."
  (should-not (gptel-auto-experiment--invalid-cl-return-target nil)))

(ert-deftest test-validation/invalid-cl-return-atom ()
  "Atom should return nil (no invalid target)."
  (should-not (gptel-auto-experiment--invalid-cl-return-target 'x)))

(ert-deftest test-validation/invalid-cl-return-valid-block ()
  "Valid cl-return-from should return nil."
  (should-not
   (gptel-auto-experiment--invalid-cl-return-target
    '(cl-block foo (cl-return-from foo 123)))))

(ert-deftest test-validation/invalid-cl-return-missing-target ()
  "Missing target should return :missing-target."
  (should
   (eq (gptel-auto-experiment--invalid-cl-return-target
        '(cl-return-from nil 123))
       :missing-target)))

(ert-deftest test-validation/invalid-cl-return-unknown-block ()
  "Unknown block should return the block name."
  (should
   (eq (gptel-auto-experiment--invalid-cl-return-target
        '(cl-return-from unknown-block 123))
       'unknown-block)))

(ert-deftest test-validation/invalid-cl-return-nested-valid ()
  "Nested valid blocks should return nil."
  (should-not
   (gptel-auto-experiment--invalid-cl-return-target
    '(cl-block outer
       (cl-block inner
         (cl-return-from inner 1)
         (cl-return-from outer 2))))))

;;; cl-block scope tests

(ert-deftest test-validation/cl-block-adds-scope ()
  "cl-block should add block name to scope."
  (should-not
   (gptel-auto-experiment--invalid-cl-return-target-in-forms
    '((cl-block my-block (cl-return-from my-block t)))
    nil)))

(ert-deftest test-validation/cl-defun-adds-scope ()
  "cl-defun should add function name to scope."
  (should-not
   (gptel-auto-experiment--invalid-cl-return-target-in-forms
    '((cl-defun my-fun () (cl-return-from my-fun t)))
    nil)))

;;; Quote handling tests

(ert-deftest test-validation/quote-skipped ()
  "Quote forms should be skipped."
  (should-not
   (gptel-auto-experiment--invalid-cl-return-target
    '(quote (cl-return-from unknown 123)))))

(ert-deftest test-validation/call-symbols-skip-declaration-arglists ()
  "Declaration and local-function arg names are not executable calls."
  (let* ((forms '((declare-function validate-code--external "external" (name))
                  (defun validate-code-target (table)
                    (cl-flet ((score-strategy (name stats)
                                (ignore name stats)))
                      (maphash #'score-strategy table)))))
         (calls (gptel-auto-experiment--call-symbols-in-forms forms)))
    (should-not (memq 'name calls))))

(ert-deftest test-validation/call-symbols-skip-dolist-bindings ()
  "Dolist variable specs are bindings, not executable calls."
  (let* ((forms '((defun validate-code-target (traces)
                    (dolist (trace (seq-take traces 50))
                      (message "%S" trace)))))
         (calls (gptel-auto-experiment--call-symbols-in-forms forms)))
    (should-not (memq 'trace calls))))

(ert-deftest test-validation/call-symbols-skip-backquoted-data ()
  "Backquoted alists are data, not executable calls."
  (let* ((forms (list (read "(defun validate-code-target (source) `((source . ,source)))")))
         (calls (gptel-auto-experiment--call-symbols-in-forms forms)))
    (should-not (memq 'source calls))))

(ert-deftest test-validation/introduced-call-honors-safe-requires ()
  "Safe top-level requires should be loaded before runtime call checks."
  (let ((forms '((require 'json)
                 (defun validate-code-target (topic-file)
                   (json-read-file topic-file))))
        (diff "+                         (json-read-file topic-file)\n"))
    (should-not (gptel-auto-experiment--introduced-undefined-call diff forms))))

(ert-deftest test-validation/introduced-call-ignores-format-only-readded-calls ()
  "A call present in removed and added lines is formatting churn, not introduced."
  (let ((forms '((defun validate-code-target ()
                  (when (fboundp 'missing-format-only-call)
                    (missing-format-only-call)))))
        (diff "-    (missing-format-only-call))\n+      (missing-format-only-call))\n"))
    (should-not (gptel-auto-experiment--introduced-undefined-call diff forms))))

(provide 'test-gptel-tools-agent-validation)
;;; test-gptel-tools-agent-validation.el ends here
