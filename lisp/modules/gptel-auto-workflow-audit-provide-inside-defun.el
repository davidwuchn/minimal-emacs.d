;;; gptel-auto-workflow-audit-provide-inside-defun.el --- Detect provide swallowed by defun -*- lexical-binding: t; -*-

;; This audit check detects when (provide '...) is inside a defun body,
;; which happens when the unbalanced-parens fixer inserts close parens
;; before provide, swallowing it into the preceding defun.

;;;###autoload
(defun gptel-auto-workflow--audit-provide-inside-defun (file)
  "Audit FILE for (provide '...) inside a defun body.
Returns 1 if swallowed, 0 if at top-level."
  (let ((issues 0))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      (while (search-forward "(provide" nil t)
        (let* ((provide-pos (- (point) 8))
               (state (save-excursion
                        (syntax-ppss provide-pos))))
          (when (and (> (car state) 0)
                     (not (nth 3 state))
                     (not (nth 4 state)))
            (setq issues (1+ issues))
            (when (fboundp 'gptel-auto-workflow--semantic-audit-record)
              (gptel-auto-workflow--semantic-audit-record
               file (line-number-at-pos provide-pos)
               'provide-inside-defun
               "(provide ...) is inside a defun"))))))
    issues))

;;;###autoload
(defun gptel-auto-workflow--fix-provide-inside-defun (file)
  "Fix FILE where (provide '...) is inside a defun."
  (let ((fixed 0))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      (goto-char (point-min))
      (while (search-forward "(provide" nil t)

        (let* ((provide-pos (- (point) 8))
               (provide-line (line-number-at-pos provide-pos))
               ;; `syntax-ppss` can move point; keep the scan stable.
               (state (save-excursion
                        (syntax-ppss provide-pos)))
               (depth (car state)))
          (when (and (> depth 0)
                     (not (nth 3 state))
                     (not (nth 4 state)))
            (save-excursion
              (goto-char provide-pos)
              (beginning-of-line)
              (insert (make-string depth ?\)))
              (insert "\n"))
            (message "[self-heal] Inserted %d close paren(s) before provide at line %d"
                     depth provide-line)
            (setq fixed 1))))
      (when (> fixed 0)
        (write-region (point-min) (point-max) file)))
    fixed))

(provide 'gptel-auto-workflow-audit-provide-inside-defun)
;;; gptel-auto-workflow-audit-provide-inside-defun.el ends here
