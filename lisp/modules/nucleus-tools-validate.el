;;; nucleus-tools-validate.el --- Validate tool prompt signatures -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Validates that tool prompt lambda signatures match registered :args.
;; Run M-x nucleus-validate-tool-signatures to check all tools.

;;; Code:

(defvar ok nil)
(defvar warnings nil)
(require 'cl-lib)

(defvar nucleus--validation-cache nil
  "Cache for validation results: (timestamp . results).")

(defconst nucleus--validation-cache-ttl 60
  "Time-to-live in seconds for validation cache.")

(defun nucleus--get-cached-validation ()
  "Get cached validation results if fresh, else nil.

Returns the cached results alist or nil if cache is stale/invalid."
  (when (consp nucleus--validation-cache)
    (let ((timestamp (car nucleus--validation-cache))
          (results (cdr nucleus--validation-cache)))
      ;; ASSUMPTION: Cache is always stored as (timestamp . results-list)
      ;; by nucleus--validate-all-tools. Only check that timestamp is a
      ;; number and results is a proper list.
      ;; BEHAVIOR: Returns cached results if timestamp is recent and results
      ;; is a proper list.
      ;; EDGE CASE: nil car or non-number car => nil (cache invalid)
      ;; TEST: See test-nucleus-tools-validate.el cache tests
      (when (and (numberp timestamp)
                 (< (- (float-time) timestamp) nucleus--validation-cache-ttl)
                 (proper-list-p results))
        results))))

(defun nucleus--extract-prompt-signature (tool-name prompt-text)
  "Extract lambda signature for TOOL-NAME from PROMPT-TEXT.

Returns alist of param names, or nil if no signature found."
  (when (null prompt-text)
    (error "nucleus--extract-prompt-signature: prompt-text cannot be nil"))
  (let ((regex (format "^λ(\\([^)]*\\))\\. %s" (regexp-quote (symbol-name tool-name)))))
    (when (or (string-match regex prompt-text)
              (string-match "^λ(\\([^)]*\\))" prompt-text))
      (let ((params-str (match-string 1 prompt-text)))
        (cl-loop for param in (split-string params-str "," t)
                 for clean = (car (split-string (string-trim param) ":"))
                 when (and clean (not (string-empty-p clean)))
                 collect (intern (replace-regexp-in-string "\\?$" "" clean)))))))

(defun nucleus--extract-registered-args (tool-name)
  "Extract registered arg names for TOOL-NAME.

Returns list of arg name symbols, or nil if tool not found."
  (when (fboundp 'gptel-get-tool)
    (let* ((name-str (if (symbolp tool-name) (symbol-name tool-name) tool-name))
           (tool (ignore-errors (gptel-get-tool name-str))))
      (when tool
        (let ((args (gptel-tool-args tool)))
          (when (listp args)
            (cl-loop for arg in args
                     when (and (listp arg) (plist-get arg :name))
                     collect (intern (replace-regexp-in-string "-" "_" (plist-get arg :name))))))))))

(defun nucleus--validate-tool (tool-name prompt-text)
  "Validate TOOL-NAME prompt signature matches registered args.

Returns (status . message) where status is:
- \\='ok: Signature matches
- \\='warning: Minor mismatch (e.g. opt marker)
- \\='error: Major mismatch"
  (let ((prompt-sig (nucleus--extract-prompt-signature tool-name prompt-text))
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

(defun nucleus--count-validation-results (results)
  "Count validation RESULTS by status.

Returns list (ok warnings errors) counts."
  (let ((_ok 0) (_warnings 0) (errors 0))
    (when (proper-list-p results)
      (cl-loop for result in results
               when (and (consp result) (consp (cdr result)))
               do (let ((entry (cdr result)))
                    (when (consp entry)
                      (pcase (car entry)
                        ('ok (cl-incf ok))
                        ('warning (cl-incf warnings))
                        ('error (cl-incf errors)))))))
    (list ok warnings errors)))

(defun nucleus--validate-all-tools ()
  "Validate all tool prompts match their registered signatures.

Returns alist of (tool-name status . message). Results are cached
for `nucleus--validation-cache-ttl' seconds."
  (or (nucleus--get-cached-validation)
      (let ((results '()))
        (when (and (boundp 'nucleus-tool-prompts)
                   (proper-list-p nucleus-tool-prompts)
                   nucleus-tool-prompts)
          (cl-loop for (tool-name . prompt-text) in nucleus-tool-prompts
                   do (push (cons tool-name (nucleus--validate-tool tool-name prompt-text))
                            results)))
        (setq nucleus--validation-cache
              (cons (float-time) (nreverse results)))
        (nreverse results))))

;;;###autoload
(defun nucleus-validate-tool-signatures ()
  "Validate all tool prompt signatures match registered :args.

Displays results in a buffer showing:
- ✓ OK: Signature matches
- ⚠ WARNING: Minor issue (no signature, tool not registered)
- ✗ ERROR: Major mismatch between prompt and registration"
  (interactive)
  (let* ((results (nucleus--validate-all-tools))
         (counts (nucleus--count-validation-results results))
         (ok (car counts))
         (warnings (cadr counts))
         (errors (nth 2 counts)))
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

(defun nucleus--report-tool-signatures ()
  "Report signature validation results and warn about errors."
  (let* ((results (nucleus--validate-all-tools))
         (counts (nucleus--count-validation-results results))
         (ok (car counts))
         (warnings (cadr counts))
         (errors (nth 2 counts))
         (error-details '()))
    (cl-loop for (tool-name . (status . msg)) in results
             when (eq status 'error)
             do (push (format "%s (%s)" tool-name msg) error-details))
    (when (> errors 0)
      (message "[nucleus] WARNING: %d tool signature mismatches found: %s"
               errors (string-join (nreverse error-details) ", "))
      (message "[nucleus] Run M-x nucleus-validate-tool-signatures for details."))))

;;; Auto-validate on load
(when (and (boundp 'nucleus-tool-prompts) nucleus-tool-prompts)
  (run-with-idle-timer 3 nil #'nucleus--report-tool-signatures))

(provide 'nucleus-tools-validate)

;;; nucleus-tools-validate.el ends here
