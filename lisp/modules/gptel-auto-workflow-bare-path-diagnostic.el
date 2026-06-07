;;; gptel-auto-workflow-bare-path-diagnostic.el --- Self-heal diagnostic for bare paths -*- lexical-binding: t; -*-

;; This file provides a self-healing diagnostic that scans for bare
;; (non-absolute) string path literals used in I/O calls without workspace
;; boundary expansion. These are portability hazards that resolve relative
;; to `default-directory' at runtime, which varies between batch mode and
;; interactive sessions.

;;; Code:

(defconst gptel-auto-workflow--bare-path-dangerous-functions
  '("directory-files" "with-temp-file" "find-file" "insert-file-contents")
  "List of I/O function names that should not receive bare string path literals.")

(defun gptel-auto-workflow--diagnose-bare-paths (&optional module-dir)
  "Scan .el files in MODULE-DIR for bare string paths in dangerous I/O calls.
Each violation is a plist with :file :line :function :raw-path :suggested-fix.
MODULE-DIR defaults to the workspace lisp/modules/ directory.

Rules for flagging a string literal as a bare path violation:
  - The string is quoted (appears as double-quoted text in the source)
  - The string is NOT absolute (does not start with / or ~)
  - The call is NOT already wrapped in expand-file-name with a root
  - The call is NOT already wrapped in gptel-auto-workflow--expand-workspace-path
  - The line is NOT a comment (does not start with ; in column 0)

Returns a list of violation plists."
  (let* ((scan-dir (or module-dir
                       (gptel-auto-workflow--expand-workspace-path "lisp/modules")))
         (violations nil)
         (dangerous-fn-names gptel-auto-workflow--bare-path-dangerous-functions))
    (dolist (file (directory-files scan-dir t "\\.el\\'"))
      (when (file-regular-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (let ((lines (split-string (buffer-string) "\n" t)))
            (dotimes (i (length lines))
              (let* ((line-num (1+ i))
                     (line (nth i lines)))
                ;; Skip comment lines (leading ;)
                (unless (string-match-p "\\`[;]" line)
                  (dolist (fn-name dangerous-fn-names)
                    ;; Match: (fn-name "bare-string" ...)
                    (let ((pattern (concat "(" fn-name "[ \\t\\n]+\"\\([^\"]+\\)\"")))
                      (when (string-match pattern line)
                        (let ((raw-path (match-string 1 line)))
                          ;; Only flag if: not absolute AND not already wrapped
                          (when (and raw-path
                                     (not (string-match-p "\\`[/~]" raw-path))
                                     ;; Not wrapped in expand-file-name with root
                                     (not (string-match-p
                                           (concat "expand-file-name[ \\t\\n]+\""
                                                   (regexp-quote raw-path) "\"")
                                           line))
                                     ;; Not wrapped in --expand-workspace-path
                                     (not (string-match-p
                                           (concat "gptel-auto-workflow--expand-workspace-path[ \\t\\n]+\""
                                                   (regexp-quote raw-path) "\"")
                                           line)))
                            (push (list :file (file-name-nondirectory file)
                                        :line line-num
                                        :function fn-name
                                        :raw-path raw-path
                                        :suggested-fix
                                        (format "(gptel-auto-workflow--expand-workspace-path \"%s\")"
                                                raw-path))
                                  violations)))))))))))))
    (nreverse violations)))

(defun gptel-auto-workflow--self-heal-bare-paths ()
  "Run bare-path diagnostic and report violations.
Returns plist with :violations-found :fixes-applied :violations.
Fixes-applied is always 0 (diagnostic only -- human must approve fixes).
This function is designed to be called as Phase 0 of self-heal."
  (let* ((violations (gptel-auto-workflow--diagnose-bare-paths))
         (count (length violations)))
    (when (> count 0)
      (message "[self-heal] Phase 0: Bare-path diagnostic found %d violations"
               count)
      (dolist (v violations)
        (message "[self-heal]   %s:%d: (%s \"%s\") -> %s"
                 (plist-get v :file)
                 (plist-get v :line)
                 (plist-get v :function)
                 (plist-get v :raw-path)
                  (plist-get v :suggested-fix))))
    (when (= count 0)
      (message "[self-heal] Phase 0: Bare-path diagnostic - no violations found"))
    (list :violations-found count
          :fixes-applied 0
          :violations violations)))

(provide 'gptel-auto-workflow-bare-path-diagnostic)
;;; gptel-auto-workflow-bare-path-diagnostic.el ends here
