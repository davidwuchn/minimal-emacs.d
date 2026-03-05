;;; nucleus-tools-verify.el --- Runtime verification for nucleus tools -*- lexical-binding: t -*-

;;; Commentary:
;; Verifies that all tools declared in nucleus-toolsets are actually registered.
;; Warns if any tools are missing due to module load failures.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'nucleus-tools)

(defun nucleus--verify-tools ()
  "Verify all tools in nucleus-toolsets are actually registered.

Returns alist of (tool-name . status) where status is:
- 'registered: Tool is available
- 'missing: Tool not found (module may have failed to load)
- 'duplicate: Tool appears multiple times"
  (let ((all-declared (cl-loop for (_ . tools) in nucleus-toolsets
                               append tools))
        (registered-tools (when (fboundp 'gptel-get-tool)
                            (cl-loop for tool in (cl-remove-duplicates
                                                  (cl-loop for (_ . tools) in nucleus-toolsets append tools)
                                                  :test 'equal)
                                   when (ignore-errors (gptel-get-tool tool))
                                   collect tool)))
        (seen (make-hash-table :test 'equal))
        (result '()))
    (dolist (tool all-declared)
      (let* ((already-seen (gethash tool seen))
             (status (cond
                      (already-seen 'duplicate)
                      ((member tool registered-tools) 'registered)
                      (t 'missing))))
        (puthash tool t seen)
        ;; We only want to report 'missing or 'registered once per unique tool, 
        ;; but 'duplicate each time it reappears is technically correct if we want to flag duplicates.
        ;; However, since nucleus-toolsets defines multiple agents that share tools, 
        ;; duplicates across different toolsets are EXPECTED and not an error.
        ;; We should only care if the unique set of tools are registered.
        (unless already-seen
          (push (cons tool status) result))))
    (nreverse result)))

(defun nucleus--report-tool-verification ()
  "Report verification results and warn about missing tools."
  (let ((verification (nucleus--verify-tools))
        (missing '())
        (duplicates '()))
    (dolist (item verification)
      (pcase (cdr item)
        ('missing (push (car item) missing))
        ('duplicate (push (car item) duplicates))))
    (when missing
      (message "[nucleus] WARNING: %d tools declared but not registered: %s"
               (length missing) (string-join missing ", "))
      (message "[nucleus] These tools may have failed to load. Check module load errors."))
    (when duplicates
      (message "[nucleus] WARNING: %d tools declared multiple times: %s"
               (length duplicates) (string-join duplicates ", ")))
    (if (and (null missing) (null duplicates))
        (message "[nucleus] All %d declared tools verified and registered." (length verification))
      (message "[nucleus] Verification complete: %d registered, %d missing, %d duplicates"
               (- (length verification) (length missing) (length duplicates))
               (length missing)
               (length duplicates)))))

;;;###autoload
(defun nucleus-verify-tools-interactively ()
  "Interactively verify and display tool registration status."
  (interactive)
  (let ((verification (nucleus--verify-tools)))
    (with-current-buffer (get-buffer-create "*nucleus-tool-verification*")
      (erase-buffer)
      (insert "Nucleus Tool Verification Report\n")
      (insert "==================================\n\n")
      (dolist (item (sort verification (lambda (a b) (string< (car a) (car b)))))
        (let ((tool (car item))
              (status (cdr item)))
          (insert (format "%-25s %s\n" tool
                          (pcase status
                            ('registered "✓ registered")
                            ('missing "✗ MISSING")
                            ('duplicate "⚠ duplicate"))))))
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

;;; Auto-verify on load
(when (and (boundp 'nucleus-toolsets) nucleus-toolsets)
  (run-with-idle-timer 2 nil #'nucleus--report-tool-verification))

(provide 'nucleus-tools-verify)

;;; nucleus-tools-verify.el ends here
