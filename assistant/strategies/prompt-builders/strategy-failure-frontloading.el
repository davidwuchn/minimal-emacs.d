;;; strategy-failure-frontloading.el --- Reorder sections based on failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Moving failure-based guidance to the front of the prompt improves error avoidance.
;; Axis: C

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-frontloading--extract-failure-patterns (analysis)
  "Extract meaningful failure patterns from ANALYSIS."
  (let ((patterns (plist-get analysis :patterns))
        (recs (plist-get analysis :recommendations)))
    (when (or patterns recs)
      (concat "\n\n;; CRITICAL GUIDANCE FROM PAST FAILURES\n"
              (when patterns
                (concat "Failure patterns to avoid:\n"
                        (mapconcat #'identity (if (listp patterns) patterns (list patterns)) "\n")))
              (when recs
                (concat "\nRecommended approaches:\n"
                        (mapconcat #'identity (if (listp recs) recs (list recs)) "\n")))))))

(defun strategy-failure-frontloading--extract-normal-sections (prompt)
  "Remove failure-related sections from PROMPT to front-load them."
  (with-temp-buffer
    (insert prompt)
    (goto-char (point-min))
    (when (re-search-forward "\\n;; CRITICAL GUIDANCE FROM PAST FAILURES.*?^;; END" nil t)
      (delete-region (match-beginning 0) (match-end 0)))
    (when (re-search-forward "\\n;; PREVIOUS EXPERIMENT RESULTS.*?^;; END" nil t)
      (delete-region (match-beginning 0) (match-end 0)))
    (buffer-string)))

(defun strategy-failure-frontloading--reorder-prompt (prompt analysis)
  "Reorder PROMPT to front-load failure patterns from ANALYSIS."
  (let* ((failure-content (strategy-failure-frontloading--extract-failure-patterns analysis))
         (clean-prompt (strategy-failure-frontloading--extract-normal-sections prompt)))
    (if (string-empty-p failure-content)
        clean-prompt
      (concat failure-content "\n\n" clean-prompt))))

(defun strategy-failure-frontloading-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure patterns front-loaded."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (target-size (if (and (stringp target) (file-exists-p target))
                          (file-attribute-size (file-attributes target)) 0)))
    (if (and analysis (> experiment-id 1))
        (strategy-failure-frontloading--reorder-prompt base-prompt analysis)
      base-prompt)))

(defun strategy-failure-frontloading-get-metadata ()
  (list :name "failure-frontloading"
        :version "1.0"
        :hypothesis "Moving failure-based guidance to the front of the prompt improves error avoidance"
        :axis "C"
        :components ["section-reordering" "failure-patterns"]))

(provide 'strategy-failure-frontloading)