(ert-deftest tdd/self-heal/lesson-restore-handler-is-defensive ()
  "The self-heal lesson restore handler at main.el:526-547 must not
cause the cron-safe error handler to fire. Fix: wrap the body in
safe-call so any internal error is captured and doesn't propagate."
  (let ((source (with-temp-buffer
                  (insert-file-contents "lisp/modules/gptel-tools-agent-main.el")
                  (buffer-string))))
    (with-temp-buffer
      (insert source)
      (goto-char (point-min))
      (should (re-search-forward "Self-heal lesson restore skipped:" nil t))
      ;; The handler should use safe-call or ignore-errors, not just
      ;; condition-case err — so internal errors don't propagate to
      ;; the cron-safe outer handler
      (should (re-search-backward "safe-call\\|ignore-errors" nil t)))))

(provide 'test-lesson-restore-safe)
;;; test-lesson-restore-safe.el ends here
