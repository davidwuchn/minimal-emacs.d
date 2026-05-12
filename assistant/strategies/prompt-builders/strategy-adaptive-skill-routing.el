;;; strategy-adaptive-skill-routing.el --- Load skills based on detected code patterns -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically routing skills based on detected code patterns improves relevance over static file-type matching
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-adaptive-skill-routing-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using pattern-triggered skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Extract detected patterns from analysis
         (detected-patterns (plist-get analysis :patterns))
         ;; Map patterns to relevant skills
         (skill-routes (strategy-adaptive-skill-routing--map-patterns-to-skills detected-patterns))
         ;; Load dynamically routed skills
         (dynamic-skills (mapconcat (lambda (skill-id)
                                       (or (gptel-auto-workflow--load-skill-content skill-id) ""))
                                     skill-routes
                                     "\n\n")))
    (concat base-prompt "\n\n;; Dynamically Routed Skills\n" dynamic-skills)))

(defun strategy-adaptive-skill-routing--map-patterns-to-skills (patterns)
  "Map detected PATTERNS to skill IDs."
  (let ((routes nil))
    (dolist (pattern patterns)
      (pcase (car-safe pattern)
        ('naming-convention (push "naming-best-practices" routes))
        ('memory-leak (push "memory-management" routes))
        ('concurrency (push "threading-patterns" routes))
        ('error-handling (push "error-recovery" routes))
        ('performance (push "optimization-hints" routes))
        ('security (push "secure-coding" routes))
        (_ (push "general-refactoring" routes))))
    (delete-dups routes)))

(defun strategy-adaptive-skill-routing-get-metadata ()
  (list :name "adaptive-skill-routing"
        :version "1.0"
        :hypothesis "Dynamically routing skills based on detected code patterns improves relevance"
        :axis "E"
        :components ["pattern-detection" "skill-routing" "dynamic-loading"]))

(provide 'strategy-adaptive-skill-routing)