;;; gptel-auto-workflow-research-benchmark.el --- Benchmark research strategies -*- lexical-binding: t; -*-

;; Reuse benchmark infrastructure for AutoTTS-style research evolution.
;; Treats research sessions as benchmark experiments with strategy comparison.

;;; Commentary:
;; Instead of building separate AutoTTS system, reuse existing benchmark:
;; - gptel-benchmark-call-subagent for researcher calls
;; - Eight Keys scoring for research quality
;; - TSV results for replay store
;; - Strategy harness for strategy evolution

;;; Code:

(require 'cl-lib)

(defvar gptel-auto-workflow--research-strategies
  '("own-repos-first" "deep-external" "quick-own-only" "topic-specific")
  "Available research strategies to benchmark.")

(defvar gptel-auto-workflow--research-benchmark-results nil
  "Accumulator for research benchmark results.")

(defun gptel-auto-workflow--benchmark-research-strategy (strategy topic callback)
  "Benchmark single research STRATEGY on TOPIC.
Calls CALLBACK with result plist."
  (let* ((strategy-prompt (gptel-auto-workflow--format-research-strategy-prompt strategy topic))
         (start-time (float-time)))
    (message "[research-benchmark] Testing strategy '%s' on topic '%s'" strategy topic)
    (gptel-benchmark-call-subagent
     'researcher
     (format "Research benchmark: %s" strategy)
     strategy-prompt
     (lambda (result)
       (let* ((duration (- (float-time) start-time))
              (output (if (stringp result) result (format "%s" result)))
              (output-len (length output))
              (tokens (* output-len 0.25))
              (quality (gptel-auto-workflow--score-research-output output))
              (efficiency (/ quality (max tokens 1))))
         (message "[research-benchmark] %s: quality=%.2f tokens=%.0f efficiency=%.4f"
                  strategy quality tokens efficiency)
         (funcall callback
                  (list :strategy strategy
                        :topic topic
                        :quality quality
                        :tokens tokens
                        :efficiency efficiency
                        :duration duration
                        :output-len output-len
                        :output output)))))))

(defun gptel-auto-workflow--score-research-output (output)
  "Score research output quality (0-1).
Uses heuristics based on AutoTTS paper:
- URLs present = higher score
- Structured format = higher score
- Specific techniques = higher score
- No generic advice = higher score"
  (let ((score 0.0))
    (when (string-match-p "https?://" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "## .*\\n" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "```" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "\\*\\*" output)
      (setq score (+ score 0.15)))
    (let ((len (length output)))
      (cond ((> len 3000) (setq score (+ score 0.15)))
            ((> len 1000) (setq score (+ score 0.1)))
            (t (setq score (+ score 0.05)))))
    (unless (string-match-p "use AI\\|improve code\\|better" output)
      (setq score (+ score 0.1)))
    score))

(defun gptel-auto-workflow--format-research-strategy-prompt (strategy topic)
  "Format research prompt with specific STRATEGY for TOPIC."
  (let ((strategy-guidance (gptel-auto-workflow--load-strategy-as-text strategy)))
    (format "## Research Task\n\nTopic: %s\nStrategy: %s\n\n%s\n\n## Instructions\n\n1. Follow the strategy phases EXACTLY\n2. Track your confidence after each phase (0-1)\n3. Stop early if confidence > 0.7 and you have 2+ insights\n4. Return structured output with URLs and code examples\n5. END your response with JSON metadata:\n```json\n{\n  \"strategy_used\": \"%s\",\n  \"phases_completed\": [\"search\", \"fetch\"],\n  \"confidence_final\": 0.8,\n  \"insights_count\": 3,\n  \"tokens_estimate\": 3500\n}\n```"
            topic strategy strategy-guidance strategy)))

(defun gptel-auto-workflow--load-strategy-as-text (strategy)
  "Load strategy definition as text guidance."
  (let ((strategy-file (expand-file-name
                        (format "assistant/skills/researcher-prompt/strategies/%s.json"
                                strategy)
                        (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p strategy-file)
        (with-temp-buffer
          (insert-file-contents strategy-file)
          (let ((data (json-read)))
            (format "**Strategy**: %s\n**Description**: %s\n**Phases**: %s"
                    (cdr (assoc 'name data))
                    (cdr (assoc 'description data))
                    (mapconcat (lambda (p) (cdr (assoc 'name p)))
                               (cdr (assoc 'phases data)) " → "))))
      (format "Strategy '%s' not found. Use default approach." strategy))))

(defun gptel-auto-workflow--benchmark-all-research-strategies (topic callback)
  "Benchmark all research strategies on TOPIC.
Calls CALLBACK with best strategy name."
  (setq gptel-auto-workflow--research-benchmark-results nil)
  (let ((strategies gptel-auto-workflow--research-strategies)
        (results nil)
        (remaining 0))
    (setq remaining (length strategies))
    (dolist (strategy strategies)
      (gptel-auto-workflow--benchmark-research-strategy
       strategy topic
       (lambda (result)
         (push result results)
         (setq remaining (1- remaining))
         (when (<= remaining 0)
           (let* ((best (car (sort results
                                   (lambda (a b)
                                     (> (plist-get a :efficiency)
                                        (plist-get b :efficiency))))))
                  (best-strategy (plist-get best :strategy)))
             (message "[research-benchmark] Best strategy: %s (efficiency=%.4f)"
                      best-strategy (plist-get best :efficiency))
             (setq gptel-auto-workflow--research-benchmark-results results)
             (funcall callback best-strategy))))))))

(defun gptel-auto-workflow--evolve-research-strategy ()
  "Evolve research strategy using benchmark results.
Runs after pipeline completes to pick best strategy for next run."
  (when gptel-auto-workflow--research-benchmark-results
    (let* ((results gptel-auto-workflow--research-benchmark-results)
           (strategies (make-hash-table :test 'equal)))
      (dolist (r results)
        (let* ((name (plist-get r :strategy))
               (existing (gethash name strategies '(0 0 0))))
          (puthash name
                   (list (+ (nth 0 existing) (plist-get r :quality))
                         (+ (nth 1 existing) (plist-get r :tokens))
                         (1+ (nth 2 existing)))
                   strategies)))
      (let ((best nil)
            (best-score 0))
        (maphash (lambda (name stats)
                   (let ((avg-quality (/ (nth 0 stats) (nth 2 stats)))
                         (avg-tokens (/ (nth 1 stats) (nth 2 stats)))
                         (score (/ (nth 0 stats) (max (nth 1 stats) 1))))
                     (when (> score best-score)
                       (setq best name
                             best-score score))
                     (message "[research-evolve] %s: avg-quality=%.2f avg-tokens=%.0f score=%.4f"
                              name avg-quality avg-tokens score)))
                 strategies)
        (when best
          (message "[research-evolve] Evolved to strategy: %s" best)
          (setq gptel-auto-workflow--active-strategy best))))))

(provide 'gptel-auto-workflow-research-benchmark)

;;; gptel-auto-workflow-research-benchmark.el ends here
