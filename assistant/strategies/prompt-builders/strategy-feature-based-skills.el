;;; strategy-feature-based-skills.el --- Select skills based on code features -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically selecting skills based on detected code features improves prompt relevance.
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-feature-based-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with feature-based skill selection."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; NEW MECHANISM: Detect code features and select relevant skills
         (features (strategy-feature-based-skills--detect-features target))
         (selected-skills (strategy-feature-based-skills--select-skills features)))
    (if selected-skills
        (concat base-prompt
                "\n\n;; Feature-detected skill guidance\n"
                ";; Detected features: " (mapconcat 'identity features ", ") "\n"
                ";; Selected skills:\n"
                (mapconcat (lambda (skill)
                             (gptel-auto-workflow--load-skill-content skill))
                           selected-skills
                           "\n"))
        base-prompt)))

(defun strategy-feature-based-skills--detect-features (target)
  "Detect language features present in TARGET file."
  (let ((features nil)
        (content (condition-case nil
                     (with-temp-buffer
                       (insert-file-contents target)
                       (buffer-string))
                   (error ""))))
    (when (string-match-p "cl-lib\\|use-package\\|leaf" content)
      (push "defmacro" features))
    (when (string-match-p "lambda\\|closure" content)
      (push "functional" features))
    (when (string-match-p "thread-first\\|thread-last\\|->\\|->>" content)
      (push "threading" features))
    (when (string-match-p "condition-case\\|signal\\|error" content)
      (push "error-handling" features))
    (when (string-match-p "defcustom\\|defgroup" content)
      (push "customization" features))
    (when (string-match-p "run-at-time\\|timer" content)
      (push "async-timers" features))
    (when (string-match-p "define-minor-mode\\|define-globalized-minor-mode" content)
      (push "minor-modes" features))
    (when (string-match-p "mapcar\\|mapconcat\\|dolist\\|dotimes" content)
      (push "iteration" features))
    (if features features '("general"))))

(defun strategy-feature-based-skills--select-skills (features)
  "Select skill names based on detected FEATURES."
  (let ((feature-to-skill '(("defmacro" . "macros")
                            ("functional" . "functional-patterns")
                            ("threading" . "threading")
                            ("error-handling" . "error-handling")
                            ("customization" . "customization-definitions")
                            ("async-timers" . "timers-async")
                            ("minor-modes" . "minor-modes")
                            ("iteration" . "iteration-patterns"))))
    (delq nil (mapcar (lambda (f)
                        (cdr (assoc f feature-to-skill)))
                      features))))

(defun strategy-feature-based-skills-get-metadata ()
  (list :name "feature-based-skills"
        :version "1.0"
        :hypothesis "Detecting code features and dynamically loading relevant skills improves prompt specificity"
        :axis "E"
        :components ["feature-detection" "dynamic-skill-selection"]))

(provide 'strategy-feature-based-skills)