;;; strategy-adaptive-skills.el --- Dynamically select skills based on file characteristics -*- lexical-binding: t; -*-
;; Hypothesis: Loading domain-relevant skills based on target's actual feature usage improves context relevance.
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-adaptive-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using adaptive skill selection.
Dynamically selects skills based on target's feature usage patterns."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (features (strategy-adaptive-skills--detect-features target))
         (skills (strategy-adaptive-skills--select-matching-skills features)))
    (concat base-prompt
            "\n\n;; Dynamically Selected Context\n"
            (format ";; Detected features: %s\n" (string-join features ", "))
            (format ";; Relevant guidance loaded from skill: %s\n" (mapconcat #'identity skills ", "))
            (when skills
              (concat "\n" (string-join (mapcar #'gptel-auto-workflow--load-skill-content skills) "\n"))))))

(defun strategy-adaptive-skills--detect-features (target)
  "Detect feature patterns in TARGET file.
Returns list of detected feature keywords."
  (let ((features nil))
    (when (file-exists-p target)
      (with-temp-buffer
        (insert-file-contents target)
        (goto-char (point-min))
        (cond
         ((re-search-forward "\\s-(cl-\\+" nil t) (push "cl-compatibility" features))
         ((re-search-forward "\\s-(pcase\\s-" nil t) (push "pattern-matching" features))
         ((re-search-forward "\\s-(require\\s-+'\\s-*cl-lib" nil t) (push "cl-lib" features))
         ((re-search-forward "\\s-(require\\s-+'\\s-*eieio" nil t) (push "eieio" features))
         ((re-search-forward "\\s-(defcustom\\s-" nil t) (push "customization" features))
         ((re-search-forward "\\s-(use-package\\s-" nil t) (push "use-package" features))
         ((re-search-forward "\\s-(add-to-list\\s-+'\\s-*major-mode" nil t) (push "major-mode" features))
         ((re-search-forward "\\s-(define-minor-mode\\s-\\|define-derived-mode\\s-" nil t) (push "minor-mode" features))
         ((re-search-forward "\\s-(font-lock\\s-" nil t) (push "font-lock" features))
         ((re-search-forward "\\s-(define-derived-mode\\s-" nil t) (push "major-mode" features))
         ((re-search-forward "\\s-(defvar\\s-+[a-z-]*hook\\s-" nil t) (push "hooks" features))
         ((re-search-forward "\\s-(run-hooks\\s-\\|add-hook\\s-" nil t) (push "hooks" features))
         ((re-search-forward "\\s-(defadvice\\s-\\|advice-add\\s-" nil t) (push "advice" features))
         ((re-search-forward "\\s-(lambda\\s-+\\[" nil t) (push "closure-patterns" features))
         ((re-search-forward "\\s-(lexical-let\\s-\\|lexical-binding\\s-" nil t) (push "lexical-scope" features))))
        (goto-char (point-min))
        (let ((case-fold-search t))
          (when (re-search-forward ";;;\\s-+ Commentary" nil t)
            (push "commentary" features))
          (when (re-search-forward ";;;\\s-+Code:" nil t)
            (push "commentary-section" features))))
    (delete-dups features)))

(defun strategy-adaptive-skills--select-matching-skills (features)
  "Select skills matching detected FEATURES.
Returns list of skill names to load."
  (let ((skill-map '(("cl-compatibility" . "cl-style")
                     ("cl-lib" . "cl-style")
                     ("eieio" . "oop-patterns")
                     ("customization" . "defcustom-best-practices")
                     ("use-package" . "use-package-patterns")
                     ("major-mode" . "major-mode-development")
                     ("minor-mode" . "minor-mode-development")
                     ("font-lock" . "font-lock-patterns")
                     ("hooks" . "hook-patterns")
                     ("advice" . "advice-anti-patterns")
                     ("closure-patterns" . "closure-best-practices")
                     ("lexical-scope" . "lexical-binding-guide")
                     ("pattern-matching" . "pcase-patterns")))
        (selected nil))
    (dolist (feature features)
      (let ((skill (assoc feature skill-map)))
        (when skill
          (push (cdr skill) selected))))
    (delete-dups selected)))

(defun strategy-adaptive-skills-get-metadata ()
  "Return metadata for this strategy."
  (list :name "adaptive-skills"
        :version "1.0"
        :hypothesis "Dynamically loading domain-relevant skills based on feature detection improves context relevance"
        :axis "E"
        :components ["feature-detection" "dynamic-skill-selection"]))

(provide 'strategy-adaptive-skills)