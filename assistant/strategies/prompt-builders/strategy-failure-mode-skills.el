;;; strategy-failure-mode-skills.el --- Skill loading weighted by failure mode frequency -*- lexical-binding: t; -*-
;; Hypothesis: Skills should be loaded proportionally to how often their domain appears in failure patterns
;; Axis: E, D
;;
;; IMPORTANT: Computes failure-mode frequencies and weights skill selection accordingly.
;; Domains with higher failure rates get more skill content included.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-mode-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with skills weighted by failure mode frequency."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (skill-blocks (strategy-failure-mode-skills--build-weighted-skills analysis))
         (weighted-guidance (if skill-blocks
                                 (concat "\n\n;; Weighted Skill Content (by failure mode relevance)\n" skill-blocks)
                               "")))
    (concat base-prompt weighted-guidance)))

(defun strategy-failure-mode-skills--compute-domain-frequencies (patterns)
  "Compute frequency map of domains across failure patterns."
  (let ((domain-counts (make-hash-table :test 'equal))
        (total 0))
    (dolist (pattern patterns)
      (let* ((domain (or (plist-get pattern :domain)
                         (plist-get pattern :category)
                         "general"))
             (count (or (plist-get pattern :failure-count) 1)))
        (puthash domain (+ count (gethash domain domain-counts 0)) domain-counts)
        (setq total (+ total count))))
    (let (result)
      (maphash (lambda (dom count)
                 (push (cons dom (/ (float count) (float total))) result))
               domain-counts)
      result)))

(defun strategy-failure-mode-skills--build-weighted-skills (analysis)
  "Build skill content weighted by failure mode frequency."
  (let* ((patterns (plist-get analysis :patterns))
         (frequencies (strategy-failure-mode-skills--compute-domain-frequencies patterns))
         (domain-to-skill '(("memory" . "memory-management")
                            ("performance" . "performance-optimization")
                            ("error" . "error-handling")
                            ("type" . "type-safety")
                            ("concurrency" . "concurrency-patterns")
                            ("api" . "api-design")))
         (skill-lines nil))
    (dolist (freq-entry frequencies)
      (let* ((domain (car freq-entry))
             (weight (cdr freq-entry))
             (skill-name (or (cdr (assoc domain domain-to-skill)) "general"))
             (skill-content (gptel-auto-workflow--load-skill-content skill-name)))
        (when (and skill-content (> weight 0.1))
          (push (format ";; [%s] (weight: %.0f%%)\n%s"
                        domain
                        (* weight 100)
                        skill-content)
                skill-lines))))
    (mapconcat 'identity (nreverse skill-lines) "\n\n")))

(defun strategy-failure-mode-skills-get-metadata ()
  (list :name "failure-mode-skills"
        :version "1.0"
        :hypothesis "Loading skills weighted by failure mode frequency improves guidance relevance"
        :axis "E,D"
        :components ["skill-weighting" "failure-frequency" "adaptive-skill-selection"]))

(provide 'strategy-failure-mode-skills)