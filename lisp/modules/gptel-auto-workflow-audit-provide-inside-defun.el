;;; gptel-auto-workflow-audit-provide-inside-defun.el --- Detect provide swallowed by defun -*- lexical-binding: t; -*-

;; This audit check detects when (provide '...) is inside a defun body,
;; which happens when the unbalanced-parens fixer inserts close parens
;; before provide, swallowing it into the preceding defun.

(declare-function gptel-auto-workflow--fix-validate-and-write
                  "gptel-auto-workflow-self-heal-semantic"
                  (buffer file &optional original-content))

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
  "Fix FILE where (provide '...) is inside a defun.
Guards: refuses to modify files with unresolved merge conflicts,
and skips the fix when check-parens confirms the file is already balanced
(syntax-ppss was wrong about the paren depth)."
  (let ((fixed 0)
        (skip nil)
        (original-content nil))
    (with-temp-buffer
      (insert-file-contents file)
      (setq original-content (buffer-string))
      (emacs-lisp-mode)
      ;; Guard: never modify files with unresolved git conflicts.
      ;; Match only at start-of-line (git convention) to avoid
      ;; false positives from string literals in the guard code.
      (goto-char (point-min))
      (when (re-search-forward "^[ \t]*<<<<<<<" nil t)
        (message "[self-heal] Skipping %s: unresolved merge conflict"
                 (file-name-nondirectory file))
        (setq skip t))
      ;; Guard: if parens are already balanced, syntax-ppss was wrong.
      ;; Only proceed if check-parens signals a genuine imbalance.
      (unless skip
        (condition-case nil
            (progn
              (check-parens)
              (setq skip t))
          (error nil)))
      (unless skip
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
          (gptel-auto-workflow--fix-validate-and-write
           (current-buffer) file original-content))))
    fixed))

(provide 'gptel-auto-workflow-audit-provide-inside-defun)
;;; gptel-auto-workflow-audit-provide-inside-defun.el ends here
