;;; test-evolution-self-audit-guard.el --- TDD: all self-audit--root calls in evolution.el are guarded -*- lexical-binding: t; -*-

(defun tdd/evolution-scan-unguarded-self-audit-calls ()
  "Scan evolution.el for unguarded calls to self-audit--root.
Return list of (line-number . context) for each unguarded call."
  (let ((file "lisp/modules/gptel-auto-workflow-evolution.el")
        (unguarded nil))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((line-num 0))
          (while (re-search-forward "gptel-auto-workflow-self-audit--root" nil t)
            (setq line-num (line-number-at-pos (match-beginning 0)))
            (let* ((line (buffer-substring-no-properties
                          (line-beginning-position) (line-end-position)))
                   ;; Get 300 chars before the match for context
                   (ctx-start (max (point-min) (- (match-beginning 0) 300)))
                   (preceding (buffer-substring-no-properties
                               ctx-start (match-beginning 0))))
              ;; Skip declare-function lines
              (unless (string-match-p "declare-function" line)
                ;; Skip comment lines
                (unless (string-match-p "^[[:space:]]*;;" line)
                  ;; Check if guarded by fboundp in preceding context
                  (unless (string-match-p "fboundp" preceding)
                    (push (cons line-num
                                (string-trim (substring line 0 (min 80 (length line)))))
                          unguarded)))))))))
    (nreverse unguarded)))

(ert-deftest tdd/evolution/self-audit-root-calls-are-guarded ()
  "All calls to gptel-auto-workflow-self-audit--root in evolution.el must be
guarded with (fboundp 'gptel-auto-workflow-self-audit--root)."
  (let ((unguarded (tdd/evolution-scan-unguarded-self-audit-calls)))
    (should (null unguarded))))

(provide 'test-evolution-self-audit-guard)
;;; test-evolution-self-audit-guard.el ends here
