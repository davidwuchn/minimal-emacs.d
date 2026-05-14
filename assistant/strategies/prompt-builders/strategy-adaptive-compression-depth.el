;;; strategy-adaptive-compression-depth.el --- Hierarchical compression preserving importance layers -*- lexical-binding: t; -*-
;; Hypothesis: Multi-layer compression preserving critical content produces better prompts at all compression levels.
;; Axis: F (Adaptive compression)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-adaptive-compression-depth-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with hierarchical depth-based compression."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (compression-level (strategy-adaptive-compression-depth--compute-level
                             target analysis previous-results))
         (depth-guidance (strategy-adaptive-compression-depth--generate-depth-guidance
                          compression-level analysis)))
    (concat base-prompt
            "\n\n;; Hierarchical compression guidance:\n"
            depth-guidance
            "\n;; Compression level: "
            (number-to-string compression-level)
            "/5\n")))

(defun strategy-adaptive-compression-depth--compute-level (target analysis previous-results)
  "Compute compression depth level (1-5) based on target and history.
Higher levels = more aggressive compression but preserve critical layers."
  (let* ((file-size (or (nth 7 (file-attributes target)) 0))
         (failure-count (length (plist-get analysis :patterns)))
         (prev-iterations (length previous-results))
         (base-level (cond
                      ((< file-size 5000) 1)
                      ((< file-size 20000) 2)
                      ((< file-size 50000) 3)
                      ((< file-size 100000) 4)
                      (t 5)))
         (adjustment (cond
                      ((> failure-count 10) 1)
                      ((> prev-iterations 5) -1)
                      (t 0))))
    (max 1 (min 5 (+ base-level adjustment)))))

(defun strategy-adaptive-compression-depth--generate-depth-guidance (level analysis)
  "Generate compression guidance based on LEVEL (1-5) preserving hierarchy."
  (let ((patterns (plist-get analysis :patterns)))
    (pcase level
      (1 (format "Minimal compression: preserve all details including comments and formatting.\nAnalysis focus: %s"
                 (string-join (mapcar #'car patterns) ", ")))
      (2 (format "Light compression: preserve function signatures and key logic, simplify comments.\nKey concerns: %s"
                 (string-join (mapcar #'car (cl-subseq patterns 0 (min 3 (length patterns)))) ", ")))
      (3 (format "Balanced compression: preserve critical logic paths and public interfaces.\nCritical areas: %s"
                 (string-join (mapcar #'car (cl-subseq patterns 0 (min 2 (length patterns)))) ", ")))
      (4 (format "Aggressive compression: preserve core logic only, drop peripheral concerns.\nMust fix: %s"
                 (car patterns)))
      (5 (format "Maximum compression: preserve only the essential transformation logic.\nPrimary focus: %s"
                 (car patterns)))
      (_ "Standard compression applied."))))

(defun strategy-adaptive-compression-depth-get-metadata ()
  (list :name "adaptive-compression-depth"
        :version "1.0"
        :hypothesis "Hierarchical depth-based compression preserves critical content layers at each level."
        :axis "F"
        :components ["depth-compression" "file-complexity" "adaptive-leveling"]))

(provide 'strategy-adaptive-compression-depth)