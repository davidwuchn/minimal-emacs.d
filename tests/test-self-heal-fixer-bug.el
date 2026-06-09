;;; test-self-heal-fixer-bug.el --- TDD test for unguarded call fixer bug -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(unless (featurep 'gptel-auto-workflow-self-heal-semantic)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                          default-directory)))

(defun test-fixer--tmp-file (content)
  (let ((file (make-temp-file "ov5-fixer-test-" nil ".el")))
    (with-temp-file file (insert content))
    file))

(defun test-fixer--cleanup (file)
  (when (and file (file-exists-p file))
    (delete-file file)))

(ert-deftest test-self-heal-fixer/wraps-call-with-arguments-correctly ()
  "Auto-fixer must wrap (fn arg1 arg2) as (and (fboundp 'fn) (fn arg1 arg2)).
Bug: was producing (and (fboundp 'fn) (fn) arg1 arg2) - arguments outside the call."
  (let* ((content "(defun test-fn ()
  (let ((parsed (gptel-agent-read-file \"/tmp/test.md\")))
    parsed))")
         (file (test-fixer--tmp-file content)))
    (unwind-protect
        (progn
          ;; Run the fixer
          (let ((fixed (gptel-auto-workflow--fix-unguarded-external-calls file)))
            (should (= fixed 1)))
          ;; Verify the fix is correct
          (let ((fixed-content (with-temp-buffer
                                 (insert-file-contents file)
                                 (buffer-string))))
            ;; The entire call including arguments must be inside the (and ...)
            (should (string-match-p "(and (fboundp 'gptel-agent-read-file) (gptel-agent-read-file \"/tmp/test.md\"))" 
                                   fixed-content))
            ;; Must NOT have the buggy pattern where arguments are outside
            (should-not (string-match-p "(gptel-agent-read-file) \"/tmp/test.md\"" fixed-content))))
      (test-fixer--cleanup file))))

(ert-deftest test-self-heal-fixer/wraps-call-with-multiple-arguments ()
  "Auto-fixer must handle calls with multiple arguments correctly."
  (let* ((content "(defun test-fn ()
  (gptel-agent-read-file \"/tmp/test.md\" nil t))")
         (file (test-fixer--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-unguarded-external-calls file)))
            (should (= fixed 1)))
          (let ((fixed-content (with-temp-buffer
                                 (insert-file-contents file)
                                 (buffer-string))))
            (should (string-match-p "(and (fboundp 'gptel-agent-read-file) (gptel-agent-read-file \"/tmp/test.md\" nil t))"
                                   fixed-content))))
      (test-fixer--cleanup file))))

(provide 'test-self-heal-fixer-bug)
;;; test-self-heal-fixer-bug.el ends here
