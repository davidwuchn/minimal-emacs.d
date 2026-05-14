;;; standalone-research.el --- Completely standalone research runner -*- lexical-binding: t; -*-
;;; Bypasses all strategic.el functions. Works even when load-file corrupts them.

(defun slr--load-skill (skill-name)
  "Load SKILL-NAME SKILL.md content."
  (let* ((root "/Users/davidwu/.emacs.d")
         (file (expand-file-name (format "assistant/skills/%s/SKILL.md" skill-name) root)))
    (if (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (buffer-string))
      "")))

(defun slr--save-findings (findings &optional file-path)
  "Save findings to file."
  (let ((file (or file-path
                  (expand-file-name "var/tmp/research-findings.md"
                                    "/Users/davidwu/.emacs.d"))))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert (format "# Research Findings\n\n> Updated: %s\n\n%s"
                      (format-time-string "%Y-%m-%d %H:%M")
                      findings)))
    (message "[slr] Saved %d chars to %s" (length findings) file)))

(defun slr-run-research ()
  "Run external research using subagent and save results.
  This is a standalone function that does NOT call any strategic.el functions."
  (interactive)
  (let ((prompt (slr--load-skill "researcher-prompt")))
    (message "[slr] Prompt: %d chars, subagents=%s, subagent-fbound=%s"
             (length prompt)
             (and (boundp 'gptel-auto-experiment-use-subagents)
                  gptel-auto-experiment-use-subagents)
             (fboundp 'gptel-benchmark-call-subagent))
    (if (and (boundp 'gptel-auto-experiment-use-subagents)
             gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (let ((timeout 300))
          (message "[slr] Calling subagent with %ds timeout..." timeout)
          (gptel-benchmark-call-subagent
           'researcher "External research" prompt
           (lambda (result)
             (message "[slr] Subagent returned %d chars" (length result))
             (slr--save-findings result))
           timeout))
      (message "[slr] Subagents unavailable, saving empty findings")
      (slr--save-findings ""))))

(provide 'standalone-research)
