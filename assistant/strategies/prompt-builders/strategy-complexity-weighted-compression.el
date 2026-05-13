;;; strategy-complexity-weighted-compression.el --- Adaptive compression via cyclomatic complexity proxies -*- lexical-binding: t; -*-
;; Hypothesis: Compression strategy should adapt to code complexity, not just file size.
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-complexity-weighted-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using complexity-weighted compression strategy."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (file-size (nth 7 (file-attributes target)))
         (content (with-temp-buffer
                    (insert-file-contents target)
                    (buffer-string)))
         (lines (split-string content "\n"))
         (line-count (length lines))
         (paren-depth (cl-loop for i from 0 below (length content)
                                when (eq (aref content i) ?\()
                                count i))
         (bracket-density (cl-loop for i from 0 below (length content)
                                   when (eq (aref content i) ?\{)
                                   count i))
         (defun-count (cl-loop for line in lines
                               when (string-match "^\\s *(defun\\s +" line)
                               count line))
         (cond-density (cl-loop for line in lines
                                when (string-match "if\\|cond\\|when\\|unless" line)
                                count line))
         (complexity-index (+ (* 0.3 (/ defun-count (max 1 (sqrt line-count))))
                              (* 0.4 (/ paren-depth (max 1 (/ (length content) 100))))
                              (* 0.3 (/ cond-density (max 1 (/ line-count 10))))))
         (compression-level (cond
                             ((> complexity-index 5.0) "aggressive")
                             ((> complexity-index 2.0) "moderate")
                             (t "minimal")))
         (complexity-section (format "\n\n;; Complexity analysis:\n;; Functions: %d | Lines: %d | Control density: %.1f\n;; Nesting proxy (parens): %d | Bracket density: %d\n;; Complexity index: %.2f | Compression: %s"
                                     defun-count line-count cond-density
                                     paren-depth bracket-density
                                     complexity-index compression-level)))
    (concat base-prompt complexity-section)))

(defun strategy-complexity-weighted-compression-get-metadata ()
  (list :name "complexity-weighted-compression"
        :version "1.0"
        :hypothesis "Compression strategy adapts to cyclomatic complexity proxies, not just file size"
        :axis "D"
        :components ["complexity-metrics" "compression" "adaptive"]))

(provide 'strategy-complexity-weighted-compression)