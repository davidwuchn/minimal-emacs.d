;;; strategy-dependency-context.el --- Inject dependency interface context -*- lexical-binding: t; -*-
;; Hypothesis: Surfacing dependency interfaces improves cross-module reasoning and reduces incorrect assumptions.
;; Axis: B

(require 'gptel-tools-agent-prompt-build)

(defun strategy-dependency-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using strategy dependency-context.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (dep-context (when (and (stringp target) (file-readable-p target))
                        (with-temp-buffer
                          (insert-file-contents target)
                          (let ((deps nil))
                            (goto-char (point-min))
                            (while (re-search-forward "(require\\s-+'\\([^) \t\n]+\\))" nil t)
                              (push (match-string 1) deps))
                            (setq deps (delete-dups deps))
                            (if deps
                                (concat "\n\n=== Dependency Interface Context ===\n"
                                        (mapconcat
                                         (lambda (dep)
                                           (let ((path (locate-library dep)))
                                             (if (and path (file-readable-p path))
                                                 (with-temp-buffer
                                                   (insert-file-contents path)
                                                   (concat ";; " dep " (first 30 lines):\n"
                                                           (buffer-substring-no-properties
                                                            (point-min)
                                                            (save-excursion
                                                              (goto-char (point-min))
                                                              (forward-line 30)
                                                              (point)))))
                                               (format ";; %s: library not found" dep))))
                                         deps
                                         "\n---\n"))
                              ""))))))
    (concat base-prompt (or dep-context ""))))

(defun strategy-dependency-context-get-metadata ()
  (list :name "dependency-context"
        :version "1.0"
        :hypothesis "Surfacing dependency interfaces improves cross-module reasoning and reduces incorrect assumptions."
        :axis "B"
        :components ["context-retrieval" "dependencies" "cross-module"]))

(provide 'strategy-dependency-context)