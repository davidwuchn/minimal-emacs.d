;;; strategy-failure-entropy-compression.el --- Information-entropy-based compression -*- lexical-binding: t; -*-
;; Hypothesis: Sections with higher information entropy should be preserved while low-entropy sections compress more aggressively.
;; Axis: F/D (Adaptive compression + Variable computation)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-entropy-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using entropy-weighted compression strategy.
Compresses sections non-uniformly based on measured information entropy."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (section-entropies (strategy-failure-entropy-compression--compute-entropies analysis))
         (compression-plan (strategy-failure-entropy-compression--build-compression-plan section-entropies))
         (entropy-guidance (strategy-failure-entropy-compression--format-entropy-guidance compression-plan)))
    (concat base-prompt "\n\n" entropy-guidance)))

(defun strategy-failure-entropy-compression--compute-entropies (analysis)
  "Compute Shannon entropy for each section in ANALYSIS.
Returns alist of (section-name . entropy-value)."
  (let* ((patterns (plist-get analysis :patterns))
         (recommendations (plist-get analysis :recommendations))
         (pattern-text (when patterns (format "%s" patterns)))
         (rec-text (when recommendations (format "%s" recommendations)))
         (sections (list (cons "patterns" pattern-text)
                         (cons "recommendations" rec-text))))
    (mapcar (lambda (section)
              (let* ((text (cdr section))
                     (entropy (if (or (null text) (string-empty-p text))
                                  0.0
                                (strategy-failure-entropy-compression--shannon-entropy text))))
                (cons (car section) entropy)))
            sections)))

(defun strategy-failure-entropy-compression--shannon-entropy (text)
  "Compute Shannon entropy of TEXT."
  (let* ((chars (remove-duplicates (string-to-list text) :test 'equal))
         (len (float (length text)))
         (freqs (mapcar (lambda (c)
                          (/ (float (cl-count c text :test 'equal)) len))
                        chars)))
    (- (apply '+ (mapcar (lambda (p) (* p (log p 2))) freqs)))))

(defun strategy-failure-entropy-compression--build-compression-plan (section-entropies)
  "Build compression plan from SECTION-ENTROPIES.
Higher entropy = less compression, lower entropy = more compression."
  (let* ((total (apply '+ (mapcar 'cdr section-entropies)))
         (avg (/ total (float (length section-entropies))))
         (plan (mapcar (lambda (pair)
                         (let* ((section (car pair))
                                (entropy (cdr pair))
                                (ratio (/ entropy (max 0.001 avg)))
                                (compression-level (cond
                                                    ((> ratio 1.5) "minimal")
                                                    ((> ratio 1.0) "light")
                                                    ((> ratio 0.5) "moderate")
                                                    (t "aggressive"))))
                           (cons section compression-level)))
                       section-entropies)))
    plan))

(defun strategy-failure-entropy-compression--format-entropy-guidance (compression-plan)
  "Format entropy-based compression guidance from COMPRESSION-PLAN."
  (format ";; Compression Strategy: Information-Entropy Weighted\n;; %s"
          (string-join (mapcar (lambda (pair)
                                 (format "%s: %s compression" (car pair) (cdr pair)))
                               compression-plan)
                       ", ")))

(defun strategy-failure-entropy-compression-get-metadata ()
  "Return metadata for failure-entropy-compression strategy."
  (list :name "failure-entropy-compression"
        :version "1.0"
        :hypothesis "Sections with higher information entropy should be preserved while low-entropy sections compress more aggressively."
        :axis "F/D"
        :components ["entropy-computation" "adaptive-compression" "non-uniform-compression"]))

(provide 'strategy-failure-entropy-compression)