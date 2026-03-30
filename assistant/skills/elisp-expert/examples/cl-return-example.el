;;; cl-return-example.el --- Example of cl-return-from with cl-block -*- lexical-binding: t; -*-

;; ASSUMPTION: cl-return-from requires cl-block wrapper in same function
;; BEHAVIOR: Demonstrates correct early return pattern
;; EDGE CASE: nil input handled via cl-return-from
;; TEST: Byte-compile should pass with no errors

(require 'cl-lib)

;;;###autoload
(defun find-first-matching (predicate list)
  "Find first element in LIST matching PREDICATE.

Uses cl-return-from for early return when match found.
Returns nil if no match or if list is empty."
  (cl-block find-first-matching
    (when (null list)
      (cl-return-from find-first-matching nil))
    (dolist (item list)
      (when (funcall predicate item)
        (cl-return-from find-first-matching item)))
    nil))

;;;###autoload
(defun validate-user-input (input)
  "Validate INPUT and return processed result or nil.

Demonstrates multiple early returns using cl-return-from.
Returns nil if input fails any validation step."
  (cl-block validate-user-input
    ;; Guard: input must not be nil
    (when (null input)
      (cl-return-from validate-user-input nil))
    
    ;; Guard: input must be string
    (unless (stringp input)
      (cl-return-from validate-user-input nil))
    
    ;; Guard: input must not be empty
    (when (string-empty-p input)
      (cl-return-from validate-user-input nil))
    
    ;; Guard: input must be trimmed
    (let ((trimmed (string-trim input)))
      (when (< (length trimmed) 3)
        (cl-return-from validate-user-input nil))
      ;; All validations passed
      (cl-return-from validate-user-input trimmed))))

;;;###autoload
(defun process-buffer-lines (buffer predicate)
  "Process lines in BUFFER matching PREDICATE.

Returns list of matching lines, or nil if buffer doesn't exist.
Uses cl-return-from for early exit on invalid buffer."
  (cl-block process-buffer-lines
    ;; Guard: buffer must exist
    (unless (buffer-live-p buffer)
      (cl-return-from process-buffer-lines nil))
    
    (let ((results '()))
      (with-current-buffer buffer
        (save-excursion
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position))))
              (when (funcall predicate line)
                (push line results)))
            (forward-line 1))))
      (nreverse results))))

(provide 'cl-return-example)
;;; cl-return-example.el ends here
