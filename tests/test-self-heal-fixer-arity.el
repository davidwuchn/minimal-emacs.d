(unless (fboundp 'gptel-auto-workflow--fix-docstring-width)
  (load-file "lisp/modules/gptel-auto-workflow-evolution.el"))

(ert-deftest tdd/self-heal/docstring-width-fixer-takes-file-arg ()
  "The fixer function must accept FILE as its single arg.
Bug: self-heal logs 'Wrong number of arguments: 0' repeatedly
across cycles, even though the fixer is defined with 1 arg.
This test verifies the fixer requires FILE arg and basic invocation."
  ;; Calling with no args must signal wrong-number-of-arguments
  (should-error (gptel-auto-workflow--fix-docstring-width)
                :type 'wrong-number-of-arguments)
  ;; Calling with a valid file should work (and return 0 if no fixes)
  (let ((target-file (make-temp-file "self-heal-fixer-arity" nil ".el")))
    (unwind-protect
        (progn
          (write-region ";; test\n" nil target-file)
          (should (integerp (gptel-auto-workflow--fix-docstring-width target-file))))
      (delete-file target-file))))

(ert-deftest tdd/self-heal/run-fixer-with-rollback-passes-file-arg ()
  "run-fixer-with-rollback must call the fixer with FILE.
Regression test: self-heal was logging 'Wrong number of arguments: 0'
which implies either (a) the fixer was called with 0 args, or
(b) something shadowed the function definition."
  (let* ((target-file (make-temp-file "self-heal-fixer" nil ".el"))
         (captured-arg nil)
         (spy-fixer (lambda (file)
                      (setq captured-arg file)
                      0)))
    (unwind-protect
        (progn
          (write-region ";; test\n" nil target-file)
          (let ((result (gptel-auto-workflow--run-fixer-with-rollback
                         target-file spy-fixer)))
            (should (= 0 result))
            (should (string= target-file captured-arg))))
      (delete-file target-file))))

(ert-deftest tdd/self-heal/fix-file-runs-all-fixers-with-file-arg ()
  "Verify --fix-file invokes each fixer with the file arg (not 0).
Spy on every fixer in the list and verify they all received the file."
  (let* ((target-file (make-temp-file "self-heal-all-fixers" nil ".el"))
         (call-count (make-hash-table :test 'eq))
         (parens-fn (lambda (_) t))
         (warnings-fn (lambda (_) (list (cons 0 "stub")))))
    (unwind-protect
        (progn
          (write-region ";; test\n" nil target-file)
          (cl-letf (((symbol-function 'gptel-auto-workflow--check-parens) parens-fn)
                    ((symbol-function 'gptel-auto-workflow--byte-compile-warnings-for-file) warnings-fn)
                    ((symbol-function 'gptel-auto-workflow--fix-docstring-width)
                     (lambda (file)
                       (cl-incf (gethash 'docstring call-count 0))
                       (should (string= target-file file))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-unescaped-quotes)
                     (lambda (file)
                       (cl-incf (gethash 'unescaped call-count 0))
                       (should (string= target-file file))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-let-needs-let*)
                     (lambda (file)
                       (cl-incf (gethash 'let-needs-let* call-count 0))
                       (should (string= target-file file))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-unused-variables)
                     (lambda (&rest _)
                       (cl-incf (gethash 'unused call-count 0))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-free-variables)
                     (lambda (&rest _)
                       (cl-incf (gethash 'free call-count 0))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-unknown-functions)
                     (lambda (&rest _)
                       (cl-incf (gethash 'unknown call-count 0))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-condition-case-no-handlers)
                     (lambda (&rest _)
                       (cl-incf (gethash 'condition-case call-count 0))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-arg-mismatch)
                     (lambda (&rest _)
                       (cl-incf (gethash 'arg-mismatch call-count 0))
                       0))
                    ((symbol-function 'gptel-auto-workflow--fix-let-empty-body)
                     (lambda (&rest _)
                       (cl-incf (gethash 'let-empty-body call-count 0))
                       0)))
            (gptel-auto-workflow--self-heal-byte-compiler--fix-file target-file)
            ;; Every fixer should have been called exactly once
            (should (= 1 (gethash 'docstring call-count 0)))
            (should (= 1 (gethash 'unescaped call-count 0)))
            (should (= 1 (gethash 'let-needs-let* call-count 0)))
            (should (= 1 (gethash 'unused call-count 0)))
            (should (= 1 (gethash 'free call-count 0)))
            (should (= 1 (gethash 'unknown call-count 0)))
            (should (= 1 (gethash 'condition-case call-count 0)))
            (should (= 1 (gethash 'arg-mismatch call-count 0)))))
      (delete-file target-file))))

(provide 'test-self-heal-fixer-arity)
;;; test-self-heal-fixer-arity.el ends here
