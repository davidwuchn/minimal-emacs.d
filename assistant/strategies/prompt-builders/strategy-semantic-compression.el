;;; strategy-semantic-compression.el --- Semantic compression preserving function interfaces -*- lexical-binding: t; -*-
;; Hypothesis: Preserving function/macro signatures while compressing bodies maintains comprehension with reduced token count
;; Axis: F
;;
(require 'gptel-tools-agent-prompt-build)

(defvar strategy-semantic-compression--signature-regexps
  (list (rx bol (zero-or-more (any " \t")) (group "defun" (1+ space)
                                                  (group (1+ (or word ?- ?_ ?< ?>)))
                                                  (0+ space)
                                                  (group (0+ not-newline))
                                                  ")"))
        (rx bol (zero-or-more (any " \t")) (group "defmacro" (1+ space)
                                                   (group (1+ (or word ?- ?_)))
                                                   (0+ space)
                                                   (group (0+ not-newline))
                                                   ")"))
        (rx bol (zero-or-more (any " \t")) (group "cl-defun" (1+ space)
                                                   (group (1+ (or word ?- ?_)))
                                                   (0+ space)
                                                   (group (0+ not-newline))
                                                   ")"))
        (rx bol (zero-or-more (any " \t")) (group "defadvice" (1+ space)
                                                   (group (1+ (or word ?- ?_)))
                                                   (0+ space)
                                                   (group (0+ not-newline))
                                                   ")"))))

(defun strategy-semantic-compression-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using semantic compression that preserves interface definitions."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (compressed-context (strategy-semantic-compression--compress-file target))
         (compression-note "\n\n;; Semantic Compression Applied: Function bodies replaced with '...'"))
    (concat base-prompt compression-note "\n\n;; Compressed Interface View\n" compressed-context)))

(defun strategy-semantic-compression--compress-file (file)
  "Compress FILE content preserving function/macro signatures."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((lines (split-string (buffer-string) "\n" t))
          (result ""))
      (dolist (line lines)
        (let ((compressed-line (strategy-semantic-compression--compress-line line)))
          (setq result (concat result compressed-line "\n"))))
      result)))

(defun strategy-semantic-compression--compress-line (line)
  "Compress LINE if it contains a function definition."
  (catch 'compressed
    (dolist (regex strategy-semantic-compression--signature-regexps)
      (when (string-match regex line)
        (let ((indent (substring line 0 (- (match-end 1) (match-beginning 1))))
              (def-type (match-string 1 line))
              (name (match-string 2 line))
              (args (match-string 3 line)))
          (throw 'compressed
                 (format "%s%s %s (%s) ...)" indent def-type name args)))))
    line))

(provide 'strategy-semantic-compression)