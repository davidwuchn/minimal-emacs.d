;;; strategy-entropy-compression.el --- Content-aware compression by entropy -*- lexical-binding: t; -*-
;; Hypothesis: Compressing low-entropy (redundant) sections more aggressively than high-entropy sections preserves key information better.
;; Axis: F
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-entropy-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with entropy-based adaptive compression.
Low-entropy content (high repetition) is compressed more aggressively."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (sections (split-string base-prompt "\n\\s-*\\[\\(?:SECTION\\|GUIDANCE\\)" t))
         (compressed-sections
          (mapcar (lambda (section)
                    (let ((entropy (compute-section-entropy section)))
                      (cond
                       ((< entropy 2.0) (aggressive-compress section 0.5))
                       ((< entropy 3.0) (moderate-compress section 0.75))
                       (t section))))
                  sections)))
    (string-join compressed-sections "")))

(defun compute-section-entropy (text)
  "Compute Shannon entropy of TEXT (bits per character).
Lower values indicate more repetitive/redundant content."
  (when (> (length text) 0)
    (let* ((freqs (make-hash-table :test 'equal))
           (total 0))
      (dolist (char (string-to-list text))
        (cl-incf total)
        (puthash char (1+ (gethash char freqs 0)) freqs))
      (let ((entropy 0.0))
        (maphash (lambda (_ count)
                   (let ((p (/ (float count) total)))
                     (setq entropy (- entropy (* p (log p 2))))))
                 freqs)
        entropy))))

(defun aggressive-compress (text ratio)
  "Compress TEXT to RATIO of original size by removing redundancy."
  (let* ((lines (split-string text "\n" t))
         (unique-lines (remove-duplicates lines :test 'string= :from-end t)))
    (string-join (take (* (length unique-lines) ratio) unique-lines) "\n")))

(defun moderate-compress (text ratio)
  "Compress TEXT to RATIO by condensing whitespace and removing minor variations."
  (let* ((lines (split-string text "\n" t))
         (kept (cond
                ((> (length lines) 20) (append (take 10 lines) (nthcdr (- (length lines) 10) lines)))
                (t lines))))
    (string-join kept "\n")))

(defun strategy-entropy-compression-get-metadata ()
  (list :name "entropy-compression"
        :version "1.0"
        :hypothesis "Entropy-based compression preserves high-information content while aggressively reducing redundancy"
        :axis "F"
        :components ["shannon-entropy" "adaptive-compression"]))

(provide 'strategy-entropy-compression)