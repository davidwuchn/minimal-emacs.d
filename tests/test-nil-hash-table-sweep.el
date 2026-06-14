;;; test-nil-hash-table-sweep.el --- TDD sweep for remaining nil hash tables -*- lexical-binding: t; -*-

;; Run the existing nil-hash-table audit (Pi5's d0bcaf3de) across
;; all lisp/modules/*.el files.  Any non-zero issue count (minus
;; known false positives) is a regression.

(require 'ert)
(require 'cl-lib)

(unless (featurep 'gptel-auto-workflow-self-heal-semantic)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                          default-directory)))

(defvar tdd-sweep--known-false-positives
  '("gptel-prefix-cache--run-id"
    "gptel-auto-workflow--memory-schema-code-links")
  "List of defvar names that the audit flags but are NOT hash tables.
`gptel-prefix-cache--run-id' is a string run-id, not a hash table.
The audit matches it because the word \"cache\" appears in nearby
hash-table operations in the same file.
`gptel-auto-workflow--memory-schema-code-links' is intentionally nil
for lazy init.")

(defun tdd-sweep--file-issues (file)
  "Return list of (LINE-NO . VAR-NAME) for real nil-hash-table issues in FILE."
  (let ((real-issues nil)
        (file-content (with-temp-buffer
                        (insert-file-contents file)
                        (buffer-string))))
    (with-temp-buffer
      (insert file-content)
      (goto-char (point-min))
      (while (re-search-forward
              "^(defvar[ \t]+\\([a-z][a-z0-9-]*\\)[ \t]+nil\\b" nil t)
        (let ((var-name (match-string 1))
              (line-no (line-number-at-pos))
              (used-p nil))
          (dolist (fn '("gethash" "puthash" "maphash" "clrhash"))
            (when (string-match-p
                   (format "(%s\\b[^)]*\\b%s\\b" fn (regexp-quote var-name))
                   file-content)
              (setq used-p t)))
          (when (and used-p
                     (not (member var-name tdd-sweep--known-false-positives)))
            (push (cons line-no var-name) real-issues)))))
    (nreverse real-issues)))

(ert-deftest test-nil-hash-table-sweep/no-nil-hash-tables-in-lisp-modules ()
  "Every lisp/modules/*.el should have 0 nil-initialized hash tables.
Runs Pi5's gptel-auto-workflow--audit-nil-hash-tables on every file."
  (let* ((modules-dir (expand-file-name "lisp/modules" default-directory))
         (files (directory-files modules-dir t "\\.el$"))
         (issues-by-file nil)
         (total 0))
    (dolist (file files)
      (let ((fi (tdd-sweep--file-issues file)))
        (when fi
          (push (cons file fi) issues-by-file)
          (cl-incf total (length fi)))))
    (when issues-by-file
      (ert-fail
       (concat "Unguarded nil hash tables:\n"
               (mapconcat
                (lambda (entry)
                  (concat (format "  %s:\n" (car entry))
                          (mapconcat
                           (lambda (issue)
                             (format "    L%d: (defvar %s nil)\n"
                                     (car issue) (cdr issue)))
                           (cdr entry)
                           "")))
                issues-by-file
                ""))))
    (should (= total 0))))

(provide 'test-nil-hash-table-sweep)
;;; test-nil-hash-table-sweep.el ends here
