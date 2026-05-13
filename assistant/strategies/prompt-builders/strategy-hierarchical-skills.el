;;; strategy-hierarchical-skills.el --- Layered skill composition with precedence -*- lexical-binding: t; -*-
;; Hypothesis: Organizing skills in a hierarchical precedence system allows higher-priority skills to override lower-priority guidance.
;; Axis: E
;;
;; This strategy loads skills in layers: core (always), domain (based on patterns), experimental (based on iteration).

(require 'gptel-tools-agent-prompt-build)

(defun strategy-hierarchical-skills-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with hierarchical skill composition for TARGET.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((patterns (plist-get analysis :patterns))
         ;; Layer 1: Core skills (always loaded)
         (core-skills (gptel-auto-workflow--load-skill-content "code-improvement-core"))
         ;; Layer 2: Domain skills (based on detected patterns)
         (domain-skills (strategy-hierarchical-skills--load-domain-skills patterns))
         ;; Layer 3: Experimental skills (based on experiment iteration)
         (experimental-skills (strategy-hierarchical-skills--load-experimental-skills
                               experiment-id max-experiments))
         ;; Compose layered skills with precedence markers
         (layered-skills (strategy-hierarchical-skills--compose-layers
                          core-skills domain-skills experimental-skills)))
    ;; Get baseline and inject layered skills
    (let ((base-prompt (gptel-auto-experiment-build-prompt
                        target experiment-id max-experiments analysis baseline previous-results)))
      (concat base-prompt "\n\n;; LAYERED SKILLS (applied in order)\n" layered-skills))))

(defun strategy-hierarchical-skills--load-domain-skills (patterns)
  "Load domain-specific skills based on PATTERNS."
  (let ((skills '()))
    (dolist (pattern patterns)
      (let ((type (plist-get pattern :type)))
        (cond ((member type '("performance" "memory"))
               (push "performance-optimization" skills))
              ((member type '("error" "crash"))
               (push "robust-error-handling" skills))
              ((member type '("api" "interface"))
               (push "api-design" skills))
              ((member type '("test" "coverage"))
               (push "testing-best-practices" skills)))))
    (delete-dups skills)))

(defun strategy-hierarchical-skills--load-experimental-skills (experiment-id max-experiments)
  "Load experimental skills based on EXPERIMENT-ID and MAX-EXPERIMENTS."
  (cond
   ;; Early experiments: try more experimental approaches
   ((< experiment-id (/ max-experiments 3))
    '("experimental-refactoring" "novel-patterns"))
   ;; Mid experiments: balance experimental and stable
   ((< experiment-id (* 2 (/ max-experiments 3)))
    '("balanced-approach"))
   ;; Late experiments: focus on proven patterns
   (t '("proven-patterns"))))

(defun strategy-hierarchical-skills--compose-layers (core domain experimental)
  "Compose skill layers with precedence markers."
  (format ";; === CORE SKILLS (highest precedence) ===\n%s\n\n;; === DOMAIN SKILLS (override core) ===\n%s\n\n;; === EXPERIMENTAL SKILLS (may override domain) ===\n%s"
          (or core "// No core skills")
          (if domain (string-join (mapcar #'gptel-auto-workflow--load-skill-content domain) "\n")
            "// No domain-specific skills")
          (if experimental (string-join (mapcar #'gptel-auto-workflow--load-skill-content experimental) "\n")
            "// No experimental skills")))

(defun strategy-hierarchical-skills-get-metadata ()
  (list :name "hierarchical-skills"
        :version "1.0"
        :hypothesis "Organizing skills in a hierarchical precedence system allows higher-priority skills to override lower-priority guidance"
        :axis "E"
        :components ["skill-hierarchy" "layered-loading" "precedence-composition"]))

(provide 'strategy-hierarchical-skills)