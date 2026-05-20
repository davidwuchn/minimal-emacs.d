;;; strategy-characteristic-adaptive-ordering.el --- Reorder prompt sections based on code analysis -*- lexical-binding: t; -*-
;; Hypothesis: Reordering prompt sections based on code characteristics (size, complexity) produces better-targeted guidance.
;; Axis: C (Section ordering)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-characteristic-adaptive-ordering-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with adaptively ordered sections based on target characteristics."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (char-analysis (gptel-auto-workflow--analyze-target-characteristics target))
         (section-order (gptel-auto-workflow--determine-section-order char-analysis))
         (reordered-section (format "\n\n;; Adaptive section order based on code characteristics:\n;; Analysis: %s\n;; Section priority: %s"
                                    (prin1-to-string char-analysis)
                                    (mapconcat #'symbol-name section-order " -> "))))
    (concat base-prompt reordered-section)))

(defun gptel-auto-workflow--analyze-target-characteristics (target)
  "Analyze TARGET file and return characteristics plist."
  (when (file-exists-p target)
    (with-temp-buffer
      (insert-file-contents target)
      (let* ((lines (count-lines (point-min) (point-max)))
             (size (file-attribute-size (file-attributes target)))
             (defuns (how-many "^\\s-(defun\\s-" (point-min) (point-max)))
             (complexity (if (> lines 500) 'large (if (> lines 100) 'medium 'small))))
        (list :line-count lines
              :byte-size size
              :function-count defuns
              :complexity complexity
              :pattern-density (/ (float defuns) (max lines 1)))))))

(defun gptel-auto-workflow--determine-section-order (char-plist)
  "Determine optimal section order based on CHARACTERISTICS."
  (let ((complexity (plist-get char-plist :complexity)))
    (cond ((eq complexity 'large)
           '(complexity-section patterns-section skills-section basic-guidance))
          ((eq complexity 'medium)
           '(patterns-section skills-section complexity-section basic-guidance))
          (t
           '(skills-section patterns-section basic-guidance complexity-section)))))

(defun strategy-characteristic-adaptive-ordering-get-metadata ()
  (list :name "characteristic-adaptive-ordering"
        :version "1.0"
        :hypothesis "Reordering prompt sections based on code characteristics produces better-targeted guidance."
        :axis "C"
        :components ["code-analysis" "dynamic-ordering"]))

(provide 'strategy-characteristic-adaptive-ordering)