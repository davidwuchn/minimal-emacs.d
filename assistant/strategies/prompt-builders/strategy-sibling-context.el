;;; strategy-sibling-context.el --- Load sibling file headers for context -*- lexical-binding: t; -*-
;; Hypothesis: Exposing headers from sibling files in the same directory improves cross-file consistency of generated improvements.
;; Axis: B
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-sibling-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using sibling file context."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (target-dir (file-name-directory target))
         (all-files (directory-files target-dir t "\\.el\\'" t))
         (siblings nil)
         (context-chunks nil))
    ;; Collect up to 3 readable siblings excluding target
    (dolist (f all-files)
      (unless (string= f target)
        (push f siblings)))
    (setq siblings (reverse siblings))
    (dotimes (i (min 3 (length siblings)))
      (let ((sib (nth i siblings)))
        (when (file-readable-p sib)
          (with-temp-buffer
            (insert-file-contents sib nil 0 500)
            (let ((lines nil)
                  (count 0))
              (goto-char (point-min))
              (while (and (not (eobp)) (< count 5))
                (push (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))
                      lines)
                (forward-line 1)
                (setq count (1+ count)))
              (push (format ";;; From %s:\n%s"
                            (file-name-nondirectory sib)
                            (mapconcat #'identity (reverse lines) "\n"))
                    context-chunks))))))
    (if context-chunks
        (concat base-prompt
                "\n\n;; Module context from sibling files\n"
                (mapconcat #'identity (reverse context-chunks) "\n\n")
                "\n\nWhen improving the target file, ensure consistency with the patterns and naming conventions visible in the sibling files above.")
      base-prompt)))

(defun strategy-sibling-context-get-metadata ()
  (list :name "sibling-context"
        :version "1.0"
        :hypothesis "Exposing headers from sibling files in the same directory improves cross-file consistency of generated improvements."
        :axis "B"
        :components ["context-retrieval" "sibling-files" "module-consistency"]))

(provide 'strategy-sibling-context)