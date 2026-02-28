;;; nucleus-tools-validate.el --- Validate tool prompt signatures -*- lexical-binding: t -*-

;;; Commentary:
;; Validates that tool prompt lambda signatures match registered :args.
;; Run M-x nucleus-validate-tool-signatures to check all tools.

;;; Code:

(require 'cl-lib)

(defun nucleus--extract-prompt-signature (prompt-text)
  "Extract lambda signature from PROMPT-TEXT.

Returns alist of param names, or nil if no signature found."
  (when (string-match "^λ(\\([^)]*\\))" prompt-text)
    (let ((params-str (match-string 1 prompt-text)))
      (cl-loop for param in (split-string params-str "," t)
               for clean = (car (split-string (string-trim param) ":"))
               when (and clean (not (string-empty-p clean)))
               collect (intern clean)))))

(defun nucleus--extract-registered-args (tool-name)
  "Extract registered arg names for TOOL-NAME.

Returns list of arg name symbols, or nil if tool not found."
  (when (fboundp 'my/gptel--safe-get-tool)
    (let ((tool (my/gptel--safe-get-tool tool-name)))
      (when tool
        (let ((args (gptel-tool-args tool)))
          (cl-loop for arg in args
                   for name = (plist-get arg :name)
                   when name
                   collect (intern (replace-regexp-in-string "-" "_" name))))))))

(defun nucleus--validate-tool (tool-name prompt-text)
  "Validate TOOL-NAME prompt signature matches registered args.

Returns (status . message) where status is:
- 'ok: Signature matches
- 'warning: Minor mismatch (e.g. opt marker)
- 'error: Major mismatch"
  (let ((prompt-sig (nucleus--extract-prompt-signature prompt-text))
        (registered-args (nucleus--extract-registered-args tool-name)))
    (cond
     ((and (null prompt-sig) (null registered-args))
      (cons 'ok "No signature to validate"))
     ((null prompt-sig)
      (cons 'warning "No lambda signature in prompt"))
     ((null registered-args)
      (cons 'warning "Tool not registered or has no args"))
     ((equal prompt-sig registered-args)
      (cons 'ok "Signature matches registered args"))
     (t
      (cons 'error
            (format "Mismatch: prompt has %s, registered has %s"
                    prompt-sig registered-args))))))

(defun nucleus--validate-all-tools ()
  "Validate all tool prompts match their registered signatures.

Returns alist of (tool-name status . message)."
  (let ((results '()))
    (when (and (boundp 'nucleus-tool-prompts) nucleus-tool-prompts)
      (cl-loop for (tool-name . prompt-text) in nucleus-tool-prompts
               do (push (cons tool-name (nucleus--validate-tool tool-name prompt-text))
                        results)))
    (nreverse results)))

;;;###autoload
(defun nucleus-validate-tool-signatures ()
  "Validate all tool prompt signatures match registered :args.

Displays results in a buffer showing:
- ✓ OK: Signature matches
- ⚠ WARNING: Minor issue (no signature, tool not registered)
- ✗ ERROR: Major mismatch between prompt and registration"
  (interactive)
  (let ((results (nucleus--validate-all-tools))
        (errors 0)
        (warnings 0)
        (ok 0))
    (cl-loop for (_result . (status . _msg)) in results
             do (pcase status
                  ('ok (cl-incf ok))
                  ('warning (cl-incf warnings))
                  ('error (cl-incf errors))))
    (with-current-buffer (get-buffer-create "*nucleus-tool-validation*")
      (erase-buffer)
      (insert "Nucleus Tool Signature Validation\n")
      (insert "===================================\n\n")
      (insert (format "Summary: %d OK, %d warnings, %d errors\n\n" ok warnings errors))
      (cl-loop for (tool-name . (status . msg)) in results
               do (insert (format "%-25s " tool-name)
                          (pcase status
                            ('ok "✓ OK")
                            ('warning "⚠ WARNING")
                            ('error "✗ ERROR"))
                          (format ": %s\n" msg)))
      (goto-char (point-min))
      (display-buffer (current-buffer))
      (when (> errors 0)
        (message "Validation complete: %d errors found. See *nucleus-tool-validation* buffer." errors)))))

(provide 'nucleus-tools-validate)

;;; nucleus-tools-validate.el ends here
