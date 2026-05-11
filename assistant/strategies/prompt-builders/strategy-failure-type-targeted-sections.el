;;; strategy-failure-type-targeted-sections.el --- Targeted section injection based on failure type -*- lexical-binding: t; -*-
;; Hypothesis: Injecting targeted remediation sections based on dominant failure type improves fix quality over generic guidance
;; Axis: C (Section ordering) and D (Variable computation)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-type-targeted-sections-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using failure-type-targeted section injection."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (failure-types (strategy-failure-type-targeted-sections--classify-failures failure-patterns))
         (targeted-sections (strategy-failure-type-targeted-sections--select-sections failure-types)))
    (concat base-prompt "\n\n" targeted-sections)))

(defun strategy-failure-type-targeted-sections--classify-failures (patterns)
  "Classify failure PATTERNS into types."
  (let ((type-counts (list :logic 0 :style 0 :edge-case 0 :performance 0 :unknown 0)))
    (dolist (pattern patterns)
      (let ((pattern-str (format "%s" pattern)))
        (cond
         ((or (string-match-p "nil\\|empty\\|undefined\\|null" pattern-str)
              (string-match-p "wrong.*value\\|incorrect.*result" pattern-str))
          (setq type-counts (plist-put type-counts :logic (1+ (plist-get type-counts :logic)))))
         ((or (string-match-p "format\\|naming\\|convention" pattern-str)
              (string-match-p "should.*be\\|prefer" pattern-str))
          (setq type-counts (plist-put type-counts :style (1+ (plist-get type-counts :style)))))
         ((or (string-match-p "edge\\|boundary\\|corner\\|limit" pattern-str)
              (string-match-p "crash\\|exception\\|error.*case" pattern-str))
          (setq type-counts (plist-put type-counts :edge-case (1+ (plist-get type-counts :edge-case)))))
         ((or (string-match-p "slow\\|performance\\|efficient\\|memory" pattern-str)
              (string-match-p "O([0-9]" pattern-str))
          (setq type-counts (plist-put type-counts :performance (1+ (plist-get type-counts :performance)))))
         (t
          (setq type-counts (plist-put type-counts :unknown (1+ (plist-get type-counts :unknown))))))))
    type-counts))

(defun strategy-failure-type-targeted-sections--select-sections (type-counts)
  "Select targeted sections based on TYPE-COUNTS."
  (let* ((dominant-type
          (car (seq-sort-by (lambda (type) (plist-get type-counts type))
                            #'>
                            '(:logic :style :edge-case :performance :unknown))))
         (section-alist
          '(("logic" . ";; LOGIC FIX GUIDANCE:\n;; - Trace data flow dependencies\n;; - Check boundary conditions\n;; - Verify state transitions")
            ("style" . ";; STYLE GUIDANCE:\n;; - Follow naming conventions\n;; - Use consistent formatting")
            ("edge-case" . ";; EDGE CASE GUIDANCE:\n;; - Handle nil gracefully\n;; - Check empty collections\n;; - Validate range inputs")
            ("performance" . ";; PERFORMANCE GUIDANCE:\n;; - Avoid repeated computation\n;; - Use efficient data structures")
            ("unknown" . ";; GENERAL REMEDIATION\n;; - Review recent changes\n;; - Check test coverage")))
         (selected (cdr (assoc (symbol-name dominant-type) section-alist))))
    (format ";; TARGETED SECTION (dominant issue: %s)\n%s"
            dominant-type
            (or selected (cdr (assoc "unknown" section-alist))))))

(defun strategy-failure-type-targeted-sections-get-metadata ()
  (list :name "failure-type-targeted-sections"
        :version "1.0"
        :hypothesis "Injecting targeted remediation sections based on dominant failure type improves fix quality"
        :axis "C,D"
        :components ["failure-classification" "targeted-section-injection"]))

(provide 'strategy-failure-type-targeted-sections)