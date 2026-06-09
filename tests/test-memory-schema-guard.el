(defun tdd/scan-unguarded-self-audit-calls ()
  (let ((source (with-temp-buffer
                  (insert-file-contents "lisp/modules/gptel-auto-workflow-memory-schema.el")
                  (buffer-string)))
        (unguarded nil)
        (pos 0))
    (while (string-match "gptel-auto-workflow-self-audit--root" source pos)
      (let ((preceding (substring source (max 0 (- (match-beginning 0) 300))
                                  (match-beginning 0))))
        (unless (string-match-p "fboundp" preceding)
          (push (match-beginning 0) unguarded)))
      (setq pos (1+ (match-beginning 0))))
    unguarded))

(ert-deftest tdd/memory-schema/self-audit-root-calls-are-guarded ()
  (should (null (tdd/scan-unguarded-self-audit-calls))))

(provide 'test-memory-schema-guard)
;;; test-memory-schema-guard.el ends here
