;;; strategy-domain-section-reorder.el --- Reorder sections based on file domain -*- lexical-binding: t; -*-
;; Hypothesis: Different file domains need different section priorities for optimal results
;; Axis: C (Section ordering)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-domain-section-reorder-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using domain-aware section ordering.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  ;; Detect the domain of the target file
  (let* ((domain (strategy-domain-section-reorder--detect-domain target))
         ;; Get baseline prompt sections
         (base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Build domain-specific section ordering guidance
         (section-guidance (strategy-domain-section-reorder--build-section-guidance domain analysis)))
    (concat base-prompt "\n\n;; Domain-aware section ordering\n"
            section-guidance)))

(defun strategy-domain-section-reorder--detect-domain (target)
  "Detect the domain of TARGET file."
  (let ((filename (file-name-nondirectory target)))
    (cond
     ;; Test files
     ((or (string-match-p "\\`test-" filename)
          (string-match-p "-test\\.el\\'" filename)
          (string-match-p "_test\\.el\\'" filename)
          (string-match-p "/tests?/" target))
      'testing)
     ;; Configuration files
     ((or (string-match-p "\\`init-" filename)
          (string-match-p "\\`config-" filename)
          (string-match-p "\\`setup-" filename)
          (string-match-p "\\`\\." filename))
      'configuration)
     ;; Library/utility files
     ((or (string-match-p "\\`[^:]+\\.el\\'" filename)
          (string-match-p "/lib/" target)
          (string-match-p "/utils/" target))
      'library)
     ;; Main entry point
     ((or (string-match-p "\\`main\\.el\\'" filename)
          (string-match-p "\\`[^:]+-main\\.el\\'" filename))
      'entry-point)
     ;; Default to library
     (t 'library))))

(defun strategy-domain-section-reorder--build-section-guidance (domain analysis)
  "Build section ordering guidance for DOMAIN based on ANALYSIS."
  (let ((patterns (plist-get analysis :patterns)))
    (pcase domain
      ('testing
       "Section Priority for TESTING:\n1. Test pattern failures (prioritize fixing broken tests)\n2. Test structure patterns (assertions, fixtures)\n3. Code under test context (minimize, focus on test-interface)\n4. Error handling patterns (for test utilities)")
      ('configuration
       "Section Priority for CONFIGURATION:\n1. Structure patterns (customizable options)\n2. Error handling patterns (early failure detection)\n3. Loading order dependencies\n4. Default values and fallbacks")
      ('library
       "Section Priority for LIBRARY:\n1. API/interface patterns (public functions)\n2. Internal dependency patterns\n3. Error handling conventions\n4. Documentation patterns")
      ('entry-point
       "Section Priority for ENTRY-POINT:\n1. Initialization and setup patterns\n2. Error handling and recovery\n3. Main flow control patterns\n4. Cleanup and exit patterns")
      (_
       "Use default section ordering."))))

(defun strategy-domain-section-reorder-get-metadata ()
  "Return metadata for this strategy."
  (list :name "domain-section-reorder"
        :version "1.0"
        :hypothesis "Different file domains need different section priorities for optimal results"
        :axis "C"
        :components ["domain-detection" "section-prioritization" "domain-guidance"]))

(provide 'strategy-domain-section-reorder)