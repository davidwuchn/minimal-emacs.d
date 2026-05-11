;;; strategy-critical-section-preservation.el --- Preserve structural sections during compression -*- lexical-binding: t; -*-
;; Hypothesis: Protecting function definitions, docstrings, and require statements during compression maintains code understanding.
;; Axis: F (Adaptive compression)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-critical-section-preservation-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with critical section protection during compression."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Identify critical sections (function defs, docstrings, requires)
         (buffer-content (ignore-errors
                          (with-temp-buffer
                            (insert-file-contents target)
                            (buffer-string))))
         (critical-sections (when buffer-content
                              (append
                               ;; Preserve require statements
                               (when (string-match "(require '[a-zA-Z0-9_-]+)" buffer-content)
                                 (list (match-string 0 buffer-content)))
                               ;; Preserve defun/declare-function patterns
                               (when (string-match-p "(defun\\|declare-function" buffer-content)
                                 (list ";; Contains function definitions - preserved")))))
         (preservation-guidance (when critical-sections
                                  (concat "\n\n;; Critical Section Preservation\n"
                                          ";; The following structural elements must remain intact:\n"
                                          "- Function definitions (defun, defmacro)\n"
                                          "- Required dependencies (require, use-package)\n"
                                          "- Docstrings and type declarations\n"
                                          (mapconcat (lambda (s) (format ";; %s" s)) critical-sections "\n"))))
         (compression-note "\n\n;; Compression Strategy\n;; Prioritize preserving: function signatures, dependencies, and docstrings"))
    (concat base-prompt preservation-guidance compression-note)))

(defun strategy-critical-section-preservation-get-metadata ()
  (list :name "critical-section-preservation"
        :version "1.0"
        :hypothesis "Protecting function definitions, docstrings, and requires during compression maintains code understanding"
        :axis "F"
        :components ["structural-preservation" "dependency-tracking" "docstring-protection"]))

(provide 'strategy-critical-section-preservation)