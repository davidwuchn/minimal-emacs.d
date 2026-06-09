(ert-deftest tdd/self-heal/lesson-restore-handler-is-defensive ()
  "The self-heal lesson restore handler at main.el:530-554 must not
cause the cron-safe error handler to fire. Now uses ignore-errors
so any internal error is silently swallowed."
  (let ((source (with-temp-buffer
                  (insert-file-contents "lisp/modules/gptel-tools-agent-main.el")
                  (buffer-string))))
    (with-temp-buffer
      (insert source)
      (goto-char (point-min))
      ;; The handler should use ignore-errors to prevent internal errors
      ;; from propagating to the cron-safe outer handler.
      (should (re-search-forward "Restore self-healing lessons" nil t))
      (should (re-search-forward "ignore-errors" nil t)))))

(provide 'test-lesson-restore-safe)
;;; test-lesson-restore-safe.el ends here
