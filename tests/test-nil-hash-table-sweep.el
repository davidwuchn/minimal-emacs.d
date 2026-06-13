;;; test-nil-hash-table-sweep.el --- TDD sweep for remaining nil hash tables -*- lexical-binding: t; -*-

;; After Pi5's d0bcaf3de added the nil-hash-table audit (check #13),
;; and Pi5's 104367945 + 1ca282354 fixed two specific instances
;; (diagnosis-accuracy, grader-health-metrics), this test sweeps ALL
;; lisp/modules/*.el files to verify no remaining buggy defvars.
;;
;; A "buggy" defvar is one that:
;;   1. Initializes a variable to nil
;;   2. Is used with hash-table functions (gethash, puthash, maphash, clrhash)
;;      UNGUARDED (no preceding hash-table-p check) in the same file
;;
;; The audit already runs in self-heal-semantic, but only at the
;; single-file level.  This test provides the cross-file safety net.

(require 'ert)
(require 'cl-lib)
(require 'files)

(unless (featurep 'gptel-auto-workflow-self-heal-semantic)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                          default-directory)))

(defun tdd-sweep--is-var-unguarded-ht (var-name content)
  "Return t if VAR-NAME is used as hash table UNGUARDED in CONTENT.
A use is \"unguarded\" if it is a gethash/puthash/maphash/clrhash call
NOT preceded within 100 chars by `hash-table-p VAR-NAME'."
  (let ((found nil))
    (while (and (not found)
                (string-match
                 (concat "\\b\\(gethash\\|puthash\\|maphash\\|clrhash\\)\\b"
                         "[^()]*\\b" (regexp-quote var-name) "\\b")
                 content))
      (let* ((match-start (match-beginning 0))
             (start (max 0 (- match-start 100)))
             (preceding (substring content start match-start)))
        (unless (string-match-p
                 (concat "hash-table-p[ \t\n]*" (regexp-quote var-name))
                 preceding)
          (setq found t))
        ;; Advance past the match
        (setq content (substring content (match-end 0)))))
    found))

(defun tdd-sweep--scan-file (file)
  "Scan FILE for buggy nil-initialized hash table defvars.
Return list of (LINE-NO . VAR-NAME) for each issue found."
  (let* ((content (with-temp-buffer
                    (insert-file-contents file)
                    (buffer-string)))
         (issues nil)
         (line-no 0)
         (case-fold-search nil))
    (with-temp-buffer
      (insert content)
      (goto-char (point-min))
      (while (re-search-forward
              "^(defvar[ \t]+\\([a-z][a-z0-9-]*\\)[ \t]+nil\\b" nil t)
        (let ((var-name (match-string 1))
              (ln (line-number-at-pos)))
          (when (tdd-sweep--is-var-unguarded-ht var-name content)
            (push (cons ln var-name) issues)))))
    (nreverse issues)))

(ert-deftest test-nil-hash-table-sweep/no-unguarded-nil-hash-tables-in-lisp-modules ()
  "Scan all lisp/modules/*.el for UNGUARDED nil-initialized hash tables.
Any match is a regression — the audit + fixer should have caught it."
  (let* ((modules-dir (expand-file-name "lisp/modules" default-directory))
         (files (directory-files modules-dir t "\\.el$"))
         (issues-by-file nil)
         (total-issues 0))
    (dolist (file files)
      (let ((file-issues (tdd-sweep--scan-file file)))
        (when file-issues
          (push (cons file file-issues) issues-by-file)
          (cl-incf total-issues (length file-issues)))))
    (when issues-by-file
      (ert-fail
       (concat
        "Found UNGUARDED nil-initialized hash table defvars in lisp/modules/:\n"
        (mapconcat
         (lambda (entry)
           (concat (format "  %s:\n" (car entry))
                   (mapconcat
                    (lambda (issue)
                      (format "    L%d: (defvar %s nil)\n" (car issue) (cdr issue)))
                    (cdr entry)
                    "")))
         issues-by-file
         ""))))
    (should (= total-issues 0))))

(provide 'test-nil-hash-table-sweep)
;;; test-nil-hash-table-sweep.el ends here
