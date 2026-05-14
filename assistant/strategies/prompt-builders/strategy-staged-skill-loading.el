;;; strategy-staged-skill-loading.el --- Load skills progressively based on code complexity -*- lexical-binding: t; -*-
;; Hypothesis: Staging skill loading by detected complexity tier improves focus and reduces noise.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-staged-skill-loading-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using staged skill loading based on detected code complexity."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity-tier (compute-complexity-tier target))
         (tier-skills (get-skills-for-tier complexity-tier))
         (skill-content (seq-reduce
                         (lambda (acc skill)
                           (concat acc "\n\n;; === SKILL: " skill " ===\n"
                                   (gptel-auto-workflow--load-skill-content skill)))
                         tier-skills "")))
    (concat base-prompt
            "\n\n;; COMPLEXITY ANALYSIS"
            "\nTier: " (symbol-name complexity-tier)
            "\nRelevant Skills:"
            skill-content)))

(defun compute-complexity-tier (target)
  "Determine complexity tier for TARGET file.
Returns symbol: simple, moderate, complex, or intricate."
  (let* ((file-size (nth 7 (file-attributes target)))
         (buffer (find-file-noselect target))
         (lines (when buffer
                  (with-current-buffer buffer
                    (count-lines (point-min) (point-max)))))
         (defuns (when buffer
                   (with-current-buffer buffer
                     (count-matches "^(def" (point-min) (point-max)))))
         (nested-depth (when buffer
                         (with-current-buffer buffer
                           (compute-max-nesting)))))
    (cond
     ((and (< lines 100) (< defuns 10)) 'simple)
     ((and (< lines 300) (< defuns 25) (<= nested-depth 3)) 'moderate)
     ((and (< lines 800) (< defuns 60) (<= nested-depth 5)) 'complex)
     (t 'intricate))))

(defun compute-max-nesting ()
  "Compute maximum parenthetical nesting depth in current buffer."
  (save-excursion
    (goto-char (point-min))
    (let ((max-depth 0)
          (current-depth 0))
      (while (not (eobp))
        (cond
         ((eq (char-after) ?\()
          (setq current-depth (1+ current-depth))
          (when (> current-depth max-depth)
            (setq max-depth current-depth)))
         ((eq (char-after) ?\))
          (setq current-depth (1- current-depth))))
        (forward-char 1))
      max-depth)))

(defun get-skills-for-tier (tier)
  "Return list of skills appropriate for COMPLEXITY-TIER."
  (pcase tier
    ('simple '("refactor" "style"))
    ('moderate '("refactor" "style" "testing"))
    ('complex '("refactor" "style" "testing" "performance"))
    ('intricate '("refactor" "style" "testing" "performance" "architecture"))))

(defun strategy-staged-skill-loading-get-metadata ()
  (list :name "staged-skill-loading"
        :version "1.0"
        :hypothesis "Staging skill loading by detected complexity tier improves focus and reduces noise."
        :axis "E"
        :components ["skill-staging" "complexity-detection"]))

(provide 'strategy-staged-skill-loading)