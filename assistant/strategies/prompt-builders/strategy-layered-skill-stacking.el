;;; strategy-layered-skill-stacking.el --- Layer skills by relevance and file scope -*- lexical-binding: t; -*-
;; Hypothesis: Layering skills from general→project→pattern-specific yields better context alignment than flat loading
;; Axis: E

(require 'gptel-tools-agent-prompt-build)
(require 'seq)

(defun strategy-layered-skill-stacking--determine-layers (target analysis)
  "Determine skill layers based on target and analysis."
  (let* ((ext (file-name-extension target))
         (layers (list (cons "general" (gptel-auto-workflow--load-skill-content "general-best-practices"))))
         (type-skill (pcase ext
                       ("el" "emacs-lisp-idioms")
                       ("py" "python-idioms")
                       ("js" "javascript-patterns")
                       ("ts" "typescript-patterns")
                       (_ "generic-code-quality")))
         (type-content (gptel-auto-workflow--load-skill-content type-skill)))
    (when type-content
      (push (cons "language" type-content) layers))
    (when-let* ((patterns (plist-get analysis :patterns))
                (top-pattern (car (seq-sort-by (lambda (p) (or (plist-get p :severity-score) 0)) '> patterns)))
                (pattern-type (plist-get top-pattern :type))
                (pattern-skill (gptel-auto-workflow--load-skill-content (format "pattern-%s" pattern-type))))
      (push (cons "pattern" pattern-skill) layers))
    (nreverse layers)))

(defun strategy-layered-skill-stacking--format-layers (layers)
  "Format layers for prompt inclusion with relevance markers."
  (string-join (mapcar (lambda (layer)
                          (format "=== %s SKILLS (%d chars) ===\n%s"
                                  (car layer)
                                  (length (cdr layer))
                                  (cdr layer)))
                        layers)
               "\n\n"))

(defun strategy-layered-skill-stacking-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with layered skill stacking from general to specific."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (layers (strategy-layered-skill-stacking--determine-layers target analysis))
         (layered-skills (when layers
                           (concat "\n\n;; LAYERED SKILL REFERENCE\n"
                                   "Skills loaded in order of specificity:\n"
                                   (strategy-layered-skill-stacking--format-layers layers)))))
    (concat base-prompt (or layered-skills ""))))

(defun strategy-layered-skill-stacking-get-metadata ()
  (list :name "layered-skill-stacking"
        :version "1.0"
        :hypothesis "Layering skills from general to specific contexts improves AI alignment with code improvement goals"
        :axis "E"
        :components ["skill-layering" "relevance-ordering" "context-stacking"]))

(provide 'strategy-layered-skill-stacking)