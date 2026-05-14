;;; gptel-auto-workflow-research-cache.el --- Research trace replay cache for AutoTTS -*- lexical-binding: t; -*-
;;; Commentary:
;; Implements a replay store for research traces, enabling cheap evaluation
;; of research strategies without API calls.
;;
;; Structure:
;;   var/tmp/research-traces/
;;   ├── raw/              # Full research turn outputs (JSON)
;;   ├── index.json        # Metadata index for fast lookup
;;   └── replay/           # Replay-ready chunks
;;
;; Usage:
;;   (gptel-auto-workflow--cache-research-turn "topic" turn-data)
;;   (gptel-auto-workflow--replay-research-turn "topic" controller-config)

;;; Code:

(defvar gptel-auto-workflow--research-cache-dir
  (expand-file-name "var/tmp/research-traces/")
  "Directory for research trace cache.")

(defvar gptel-auto-workflow--research-cache-max-size 1000
  "Maximum number of traces to keep in cache.")

(defvar gptel-auto-workflow--research-cache-index nil
  "In-memory index of cached traces.")

(defun gptel-auto-workflow--ensure-research-cache-dir ()
  "Create research cache directory if needed."
  (unless (file-exists-p gptel-auto-workflow--research-cache-dir)
    (make-directory gptel-auto-workflow--research-cache-dir t))
  (let ((raw-dir (expand-file-name "raw" gptel-auto-workflow--research-cache-dir))
        (replay-dir (expand-file-name "replay" gptel-auto-workflow--research-cache-dir)))
    (unless (file-exists-p raw-dir) (make-directory raw-dir t))
    (unless (file-exists-p replay-dir) (make-directory replay-dir t))))

(defun gptel-auto-workflow--research-cache-index-file ()
  "Return path to cache index file."
  (expand-file-name "index.json" gptel-auto-workflow--research-cache-dir))

(defun gptel-auto-workflow--load-research-cache-index ()
  "Load cache index from disk."
  (let ((index-file (gptel-auto-workflow--research-cache-index-file)))
    (setq gptel-auto-workflow--research-cache-index
          (if (file-exists-p index-file)
              (condition-case err
                  (json-read-file index-file)
                (error
                 (message "[research-cache] Failed to load index: %s" err)
                 '()))
            '()))))

(defun gptel-auto-workflow--save-research-cache-index ()
  "Save cache index to disk."
  (gptel-auto-workflow--ensure-research-cache-dir)
  (let ((index-file (gptel-auto-workflow--research-cache-index-file)))
    (with-temp-file index-file
      (insert (json-encode gptel-auto-workflow--research-cache-index)))))

(defun gptel-auto-workflow--cache-research-turn (topic turn-data)
  "Cache a research turn for TOPIC.
TURN-DATA is a plist with :prompt :findings :controller-decision :confidence etc."
  (gptel-auto-workflow--ensure-research-cache-dir)
  (gptel-auto-workflow--load-research-cache-index)
  
  (let* ((timestamp (format-time-string "%Y%m%d-%H%M%S"))
         (trace-id (format "%s-%s-%s" topic timestamp (random 10000)))
         (raw-file (expand-file-name (format "%s.json" trace-id)
                                    (expand-file-name "raw" gptel-auto-workflow--research-cache-dir)))
         (entry (list :id trace-id
                     :topic topic
                     :timestamp timestamp
                     :prompt (plist-get turn-data :prompt)
                     :findings-length (length (or (plist-get turn-data :findings) ""))
                     :controller-decision (symbol-name (plist-get turn-data :controller-decision))
                     :confidence (or (plist-get turn-data :confidence) 0.0)
                     :ema-conf (or (plist-get turn-data :ema-conf) 0.0)
                     :ema-delta (or (plist-get turn-data :ema-delta) 0.0)
                     :tokens-used (or (plist-get turn-data :tokens-used) 0)
                     :file raw-file)))
    
    ;; Save raw data
    (with-temp-file raw-file
      (insert (json-encode turn-data)))
    
    ;; Update index
    (push entry gptel-auto-workflow--research-cache-index)
    
    ;; Trim if too large
    (when (> (length gptel-auto-workflow--research-cache-index)
              gptel-auto-workflow--research-cache-max-size)
      (setq gptel-auto-workflow--research-cache-index
            (butlast gptel-auto-workflow--research-cache-index
                    (- (length gptel-auto-workflow--research-cache-index)
                       gptel-auto-workflow--research-cache-max-size))))
    
    ;; Save index
    (gptel-auto-workflow--save-research-cache-index)
    
    (message "[research-cache] Cached turn %s (%d chars)" trace-id (plist-get turn-data :findings-length))
    trace-id))

(defun gptel-auto-workflow--get-cached-traces (topic &optional n)
  "Get up to N cached traces for TOPIC.
Returns list of trace entries sorted by recency."
  (gptel-auto-workflow--load-research-cache-index)
  (let ((traces (cl-remove-if-not
                (lambda (entry)
                  (string= (plist-get entry :topic) topic))
                gptel-auto-workflow--research-cache-index)))
    (if n
        (cl-subseq traces 0 (min n (length traces)))
      traces)))

(defun gptel-auto-workflow--load-trace-data (trace-id)
  "Load full trace data for TRACE-ID."
  (let ((raw-file (expand-file-name (format "%s.json" trace-id)
                                   (expand-file-name "raw" gptel-auto-workflow--research-cache-dir))))
    (when (file-exists-p raw-file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents raw-file)
            (json-read))
        (error
         (message "[research-cache] Failed to load trace %s: %s" trace-id err)
         nil)))))

(defun gptel-auto-workflow--replay-research-turn (trace-id controller-config)
  "Replay a cached research turn with new CONTROLLER-CONFIG.
Returns simulated controller decision without API calls."
  (let ((trace-data (gptel-auto-workflow--load-trace-data trace-id)))
    (unless trace-data
      (error "Trace %s not found" trace-id))
    
    (let* ((findings (plist-get trace-data :findings))
           (output-length (length findings))
           (turn (or (plist-get trace-data :turn) 0)))
      
      ;; Simulate controller decision on cached data
      (when (fboundp 'gptel-auto-workflow--controller-decide-research-flow)
        (gptel-auto-workflow--controller-decide-research-flow
         controller-config output-length findings)))))

(defun gptel-auto-workflow--evaluate-controller-offline (controller-config topic &optional n)
  "Evaluate CONTROLLER-CONFIG against N cached traces for TOPIC.
Returns statistics: accuracy, token cost, stop rate, etc."
  (let ((traces (gptel-auto-workflow--get-cached-traces topic n))
        (results (list :total 0 :stopped 0 :branched 0 :continued 0
                      :cut 0 :total-tokens 0 :total-confidence 0.0)))
    
    (dolist (trace traces)
      (let* ((trace-id (plist-get trace :id))
             (decision (gptel-auto-workflow--replay-research-turn trace-id controller-config))
             (tokens (or (plist-get trace :tokens-used) 0))
             (confidence (or (plist-get trace :confidence) 0.0)))
        
        (cl-incf (plist-get results :total))
        (cl-incf (plist-get results :total-tokens) tokens)
        (cl-incf (plist-get results :total-confidence) confidence)
        
        (case decision
          (stop (cl-incf (plist-get results :stopped)))
          (branch (cl-incf (plist-get results :branched)))
          (continue (cl-incf (plist-get results :continued)))
          (cut (cl-incf (plist-get results :cut))))))
    
    ;; Calculate averages
    (when (> (plist-get results :total) 0)
      (plist-put results :avg-tokens (/ (plist-get results :total-tokens)
                                       (plist-get results :total)))
      (plist-put results :avg-confidence (/ (plist-get results :total-confidence)
                                           (plist-get results :total))))
    
    (message "[research-cache] Offline eval for '%s': %d traces, stop=%d, branch=%d, continue=%d, cut=%d"
             topic
             (plist-get results :total)
             (plist-get results :stopped)
             (plist-get results :branched)
             (plist-get results :continued)
             (plist-get results :cut))
    
    results))

(defun gptel-auto-workflow--sweep-beta-offline (topic &optional beta-values)
  "Sweep beta values offline for TOPIC.
BETA-VALUES is list of beta values to test (default: 0.0 to 1.0 step 0.25)."
  (let ((betas (or beta-values '(0.0 0.25 0.5 0.75 1.0)))
        (best-result nil)
        (best-beta nil))
    
    (message "[research-cache] Starting beta sweep for '%s'..." topic)
    
    (dolist (beta betas)
      (let* ((params (when (fboundp 'gptel-auto-workflow--research-beta-schedule)
                      (gptel-auto-workflow--research-beta-schedule beta)))
             (result (gptel-auto-workflow--evaluate-controller-offline params topic 50)))
        
        (message "[research-cache] β=%.2f: avg_tokens=%.0f, stop_rate=%.2f, confidence=%.2f"
                 beta
                 (or (plist-get result :avg-tokens) 0)
                 (if (> (plist-get result :total) 0)
                     (/ (float (plist-get result :stopped))
                        (plist-get result :total))
                   0.0)
                 (or (plist-get result :avg-confidence) 0.0))
        
        ;; Track best (highest confidence at reasonable token cost)
        (when (or (null best-result)
                  (> (or (plist-get result :avg-confidence) 0.0)
                     (or (plist-get best-result :avg-confidence) 0.0)))
          (setq best-result result)
          (setq best-beta beta))))
    
    (message "[research-cache] Best beta for '%s': %.2f (confidence: %.2f)"
             topic best-beta (or (plist-get best-result :avg-confidence) 0.0))
    
    (list :best-beta best-beta
          :best-result best-result
          :all-betas betas)))

(defun gptel-auto-workflow--cache-size ()
  "Return number of cached traces."
  (gptel-auto-workflow--load-research-cache-index)
  (length gptel-auto-workflow--research-cache-index))

(defun gptel-auto-workflow--clear-research-cache ()
  "Clear all cached research traces."
  (interactive)
  (when (yes-or-no-p "Clear all research trace cache? ")
    (setq gptel-auto-workflow--research-cache-index nil)
    (gptel-auto-workflow--save-research-cache-index)
    ;; Delete raw files
    (let ((raw-dir (expand-file-name "raw" gptel-auto-workflow--research-cache-dir)))
      (when (file-exists-p raw-dir)
        (dolist (file (directory-files raw-dir t "\\.json$"))
          (delete-file file))))
    (message "[research-cache] Cache cleared")))

(provide 'gptel-auto-workflow-research-cache)
;;; gptel-auto-workflow-research-cache.el ends here
