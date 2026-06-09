(unless (fboundp 'gptel-auto-workflow--self-heal-byte-compiler-llm)
  (load-file "lisp/modules/gptel-auto-workflow-evolution.el"))

(ert-deftest tdd/self-heal/llm-fn-source-uses-cl-defun ()
  (let ((defun-start nil)
        (cl-defun-start nil))
    (with-temp-buffer
      (insert-file-contents "lisp/modules/gptel-auto-workflow-evolution.el")
      (goto-char (point-min))
      (setq cl-defun-start (re-search-forward "cl-defun gptel-auto-workflow--self-heal-byte-compiler-llm" nil t))
      (goto-char (point-min))
      (setq defun-start (re-search-forward "defun gptel-auto-workflow--self-heal-byte-compiler-llm" nil t)))
    (should defun-start)
    (should cl-defun-start)))

(provide 'test-self-heal-llm-guard)
;;; test-self-heal-llm-guard.el ends here
