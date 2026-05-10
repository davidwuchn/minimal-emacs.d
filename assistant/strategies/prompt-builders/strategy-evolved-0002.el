;;; strategy-evolved-0002.el --- Calibrate compression guidance by file size tier -*- lexical-binding: t; -*-
;; Hypothesis: Calibrating compression guidance based on file size tiers ensures large files retain critical structural context while small files are processed with full fidelity.
;; Axis: F
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-evolved-0002-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with size-calibrated compression guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (filepath (cond ((bufferp target) (buffer-file-name target))
                         ((stringp target) target)
                         (t nil)))
         (size (if filepath
                   (or (ignore-errors (nth 7 (file-attributes filepath))) 0)
                 0))
         (tier (cond ((> size 15000) 'massive)
                     ((> size 8000) 'large)
                     ((> size 3000) 'medium)
                     (t 'small)))
         (directive (pcase tier
                      ('massive "\n\n[COMPRESSION TIER: MASSIVE] File exceeds 15KB. Preserve only public API signatures, docstrings, error paths, and failure locations. Aggressively elide private helpers and boilerplate unless directly implicated in failures.\n")
                      ('large "\n\n[COMPRESSION TIER: LARGE] File 8-15KB. Compress internal implementations while preserving control flow, data structures, and all conditional branches.\n")
                      ('medium "\n\n[COMPRESSION TIER: MEDIUM] File 3-8KB. Compress redundant patterns and repetitive constructs. Preserve all logic branches and failure sites.\n")
                      ('small "\n\n[COMPRESSION TIER: SMALL] File under 3KB. No compression advised. Process full source context for maximum accuracy.\n"))))
    (concat base-prompt directive)))

(defun strategy-evolved-0002-get-metadata ()
  (list :name "evolved-0002"
        :version "1.0"
        :hypothesis "Calibrating compression guidance based on file size tiers ensures large files retain critical structural context while small files are processed with full fidelity."
        :axis "F"
        :components ["compression" "calibration" "tiers"]))

(provide 'strategy-evolved-0002)