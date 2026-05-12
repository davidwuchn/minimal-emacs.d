;;; strategy-axis-skills.el --- Load skills matching dominant historical axis -*- lexical-binding: t; -*-
;; Hypothesis: Prepending skills that match the historically most successful axis focuses the model on proven reasoning patterns.
;; Axis: E

(require 'gptel-tools-agent-prompt-build)

(defun strategy-axis-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using axis-matched skill prelude."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (dominant-axis (if previous-results
                            (let ((counts (make-hash-table :test 'equal))
                                  (best-axis "A")
                                  (best-count 0))
                              (dolist (res previous-results)
                                (let ((axis (plist-get res :axis)))
                                  (when axis
                                    (let ((count (1+ (gethash axis counts 0))))
                                      (puthash axis count counts)
                                      (when (> count best-count)
                                        (setq best-count count)
                                        (setq best-axis axis))))))
                              best-axis)
                          "A"))
         (skill-prelude (condition-case nil
                            (gptel-auto-workflow--load-skill-content dominant-axis)
                          (error ";; No axis-specific skill content available.\n"))))
    (concat ";; Axis-matched skill prelude (" dominant-axis ")\n"
            skill-prelude
            "\n\n=== Task Prompt ===\n\n"
            base-prompt)))

(defun strategy-axis-skills-get-metadata ()
  (list :name "axis-skills"
        :version "1.0"
        :hypothesis "Prepending skills that match the historically most successful axis focuses the model on proven reasoning patterns."
        :axis "E"
        :components ["skill-loading" "axis-matching" "historical-weighting"]))

(provide 'strategy-axis-skills)