(defun tdd/scan-bare-defvars-in-file (file)
  "Find truly bare (defvar FOO) patterns in FILE.
Truly bare: the form closes with ) on the same or next line,
with ONLY whitespace between (no value, no docstring)."
  (let ((results '()))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward "^(defvar \\([a-z][a-z0-9-]*\\)\\s-*$" nil t)
        (let ((var-name (match-string 1))
              (line-no (line-number-at-pos))
              (is-bare nil))
          (skip-syntax-forward " ")
          (cond
            ((eq (char-after) ?\))
             (setq is-bare t))
            ((eq (char-after) ?\n)
             (forward-line 1)
             (skip-syntax-forward " ")
             (when (eq (char-after) ?\))
               (setq is-bare t))))
          (when is-bare
            (push (list var-name line-no) results))
          (beginning-of-line))))
    (nreverse results)))

(defun tdd/run-defvar-scan-tests ()
  (let ((all-results '())
        (total-bare 0)
        (files-with-bare 0))
    (dolist (file (directory-files "lisp/modules" t "\\.el$"))
      (let ((bare (tdd/scan-bare-defvars-in-file file)))
        (when bare
          (setq files-with-bare (1+ files-with-bare)
                total-bare (+ total-bare (length bare))
                all-results (cons (cons file bare) all-results)))))
    (list :total-bare total-bare :files-with-bare files-with-bare :details all-results)))

(ert-deftest tdd/defvar/scan-results ()
  (let ((result (tdd/run-defvar-scan-tests)))
    (should (eq 0 (plist-get result :total-bare)))))

(provide 'test-defvar-bare-binding)
;;; test-defvar-bare-binding.el ends here
