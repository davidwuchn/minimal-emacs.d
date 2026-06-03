;;; strategy-entropy-adaptive-context.el --- Adapt context by code entropy -*- lexical-binding: t; -*-
;; Hypothesis: High entropy (complex, varied symbol usage) sections indicate areas needing more AI context
;; Axis: F

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-entropy-adaptive-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with entropy-based adaptive context."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (content (condition-case nil
                    (with-temp-buffer
                      (insert-file-contents target)
                      (buffer-string))
                  (error "")))
         (chunks (strategy-chunk-by-symmetry content))
         (entropies (mapcar #'strategy-calc-entropy chunks))
         (high-entropy-sections (cl-loop for e in entropies
                                         for i from 0
                                         for chunk in chunks
                                         when (> e 3.5)
                                         collect (format "SECTION-%d:\n%s" i chunk))))
    (concat base-prompt
            (if high-entropy-sections
                (concat "\n\n;; === HIGH ENTROPY SECTIONS ==="
                        "\n;; These sections show high symbol diversity - consider extra attention:"
                        "\n" (mapconcat #'identity high-entropy-sections "\n\n"))
              ""))))

(defun strategy-chunk-by-symmetry (content)
  "Split CONTENT into balanced chunks by blank-line-delimited sections."
  (let ((sections (split-string content "\n\n+" t)))
    (if sections sections (list content))))

(defun strategy-calc-entropy (text)
  "Calculate Shannon entropy of TEXT."
  (let* ((chars (string-to-list text))
         (freqs ()))
    (dolist (c chars)
      (push (cons c (1+ (or (cdr (assoc c freqs)) 0))) freqs))
    (let ((total (float (length chars)))
          (entropy 0.0))
      (dolist (pair freqs)
        (let ((p (/ (float (cdr pair)) total)))
          (setq entropy (- entropy (* p (log p 2.0))))))
      entropy)))

(defun strategy-entropy-adaptive-context-get-metadata ()
  (list :name "entropy-adaptive-context"
        :version "1.0"
        :hypothesis "High Shannon entropy in code sections indicates complexity requiring additional AI context"
        :axis "F"
        :components ["entropy-analysis" "complexity-detection"]))

(provide 'strategy-entropy-adaptive-context)