;;; strategy-semantic-skill-loading.el --- Load skills based on code semantics -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically loading skills based on detected code constructs (regex, threading, macros) provides more targeted guidance than pattern-based loading alone.
;; Axis: E (Skill loading)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-semantic-skill-loading-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using semantic skill loading strategy.
Loads additional skills based on detected code constructs in the target."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (constructs (strategy-semantic-skill-loading--detect-constructs target))
         (semantic-skills (strategy-semantic-skill-loading--constructs-to-skills constructs))
         (skill-content (mapconcat (lambda (skill)
                                     (gptel-auto-workflow--load-skill-content skill))
                                   semantic-skills "\n\n")))
    (concat base-prompt "\n\n;; Context-Specific Guidance Based on Detected Constructs\n"
            (format "Detected constructs: %s\n\n%s"
                    (mapconcat 'identity constructs ", ")
                    skill-content))))

(defun strategy-semantic-skill-loading--detect-constructs (target)
  "Detect language constructs in TARGET file by scanning buffer content."
  (let ((constructs '())
        (content (with-temp-buffer
                   (insert-file-contents target)
                   (buffer-string))))
    (when (or (string-match-p "regexp\\|rx\\|string-match" content)
              (string-match-p "defsubst\\|defmacro" content))
      (push "pattern-matching" constructs))
    (when (or (string-match-p "make-thread\\|thread-yield\\|jit-lock" content)
              (string-match-p "run-with-timer\\|cancel-timer" content))
      (push "concurrency" constructs))
    (when (or (string-match-p "cl-loop\\|dolist\\|dotimes" content)
              (string-match-p "seq-map\\|seq-reduce\\|seq-filter" content))
      (push "iteration-patterns" constructs))
    (when (string-match-p "defclass\\|cl-defmethod\\|eieio" content)
      (push "oo-patterns" constructs))
    (when (or (string-match-p "condition-case\\|signal\\|throw" content)
              (string-match-p "unwind-protect\\|assert" content))
      (push "error-handling" constructs))
    constructs))

(defun strategy-semantic-skill-loading--constructs-to-skills (constructs)
  "Map detected CONSTRUCTS to skill names."
  constructs)

(defun strategy-semantic-skill-loading-get-metadata ()
  (list :name "semantic-skill-loading"
        :version "1.0"
        :hypothesis "Detecting code constructs and loading corresponding skills provides more targeted guidance than static pattern matching."
        :axis "E"
        :components ["construct-detection" "dynamic-skill-mapping"]))

(provide 'strategy-semantic-skill-loading)