;;; strategy-failure-pattern-skill-injection.el --- Inject skills based on failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically injecting domain skills based on detected failure patterns improves fix quality.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-pattern-skill-injection-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with skills injected based on failure ANALYSIS."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (detected-patterns (plist-get analysis :patterns))
         (relevant-skills (select-skills-for-patterns detected-patterns))
         (injected-skills (mapconcat 'identity relevant-skills "\n\n")))
    (concat base-prompt "\n\n;; Relevant skill context:\n" injected-skills)))

(defun select-skills-for-patterns (patterns)
  "Select skills that address detected PATTERNS."
  (let ((skill-domains '(("memory" . "resource-management")
                         ("error" . "error-handling")
                         ("performance" . "optimization")
                         ("concurrency" . "concurrency")
                         ("api" . "api-design")
                         ("style" . "code-style"))))
    (delq nil
          (mapcar (lambda (pattern)
                    (when (string-match (car pattern) (format "%s" patterns))
                      (gptel-auto-workflow--load-skill-content (cdr pattern))))
                  skill-domains))))

(defun strategy-failure-pattern-skill-injection-get-metadata ()
  (list :name "failure-pattern-skill-injection"
        :version "1.0"
        :hypothesis "Pattern-triggered skill injection targets domain knowledge where it matters most"
        :axis "E"
        :components ["pattern-detection" "skill-selection" "context-injection"]))

(provide 'strategy-failure-pattern-skill-injection)