;;; strategy-surprise-based-retrieval.el --- Retrieve context based on code novelty -*- lexical-binding: t; -*-
;; Hypothesis: Novel code patterns require additional reference context more than conventional patterns.
;; Axis: B
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-surprise-based-retrieval-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with novelty-based context retrieval."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Identify novel/unusual patterns in target
         (novelty-report (strategy-surprise--compute-novelty target))
         ;; Retrieve relevant reference patterns based on novelty
         (reference-patterns (strategy-surprise--retrieve-similar previous-results novelty-report)))
    (concat base-prompt "\n\n;; Novelty-Aware Reference Patterns\n" reference-patterns)))

(defun strategy-surprise--compute-novelty (target)
  "Compute novelty score for code patterns in TARGET.
Higher scores indicate unusual patterns needing more context."
  (when (and (fboundp 'treesit-parser-create)
             (fboundp 'treesit-defun-name))
    (let ((patterns (make-hash-table :test 'equal))
          results)
      (save-excursion
        (with-current-buffer (or (get-file-buffer target) (find-file-noselect target))
          (goto-char (point-min))
          (while (re-search-forward (rx (group (+ (or word (syntax punctuation))))) nil t)
            (let ((pattern (match-string 1)))
              (puthash pattern (1+ (gethash pattern patterns 0)) patterns))))
        ;; Score patterns by frequency inverse (rare = novel)
        (maphash (lambda (k v)
                   (push (cons k (/ 1.0 (1+ v))) results))
                 patterns)
        results))))

(defun strategy-surprise--retrieve-similar (previous-results novelty-report)
  "Retrieve similar patterns from PREVIOUS-RESULTS based on NOVELTY-REPORT."
  (let ((novel-patterns (cl-loop for (pattern . score) in novelty-report
                                 when (> score 0.5) collect pattern))
        (similar-fixes nil))
    (dolist (result previous-results)
      (when (and (plist-get result :success)
                 (member (plist-get result :pattern) novel-patterns))
        (push (plist-get result :fix-approach) similar-fixes)))
    (if similar-fixes
        (format "NOVEL-PATTERNS-DETECTED: %s\nSIMILAR-SUCCESSFUL-FIXES:\n- %s"
                (mapconcat 'identity novel-patterns ", ")
                (mapconcat 'identity (cl-remove-duplicates similar-fixes :test 'equal) "\n- "))
      (format "NOVEL-PATTERNS-DETECTED: %s\nCAUTION: No prior successful fixes for these patterns."
              (mapconcat 'identity novel-patterns ", ")))))

(defun strategy-surprise-based-retrieval-get-metadata ()
  (list :name "surprise-based-retrieval"
        :version "1.0"
        :hypothesis "Novel code patterns require additional reference context more than conventional patterns."
        :axis "B"
        :components ["novelty-detection" "pattern-frequency" "similarity-retrieval"]))

(provide 'strategy-surprise-based-retrieval)