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

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(declare-function gptel-auto-workflow--controller-decide-with-doom-check "strategic-daemon-functions")
(declare-function gptel-auto-workflow--json-encode-plist "gptel-auto-workflow-ontology-router" (plist))

(defvar gptel-auto-workflow--research-cache-dir
  (expand-file-name "var/tmp/research-traces/"
                    (or (ignore-errors
                          (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                               (gptel-auto-workflow--worktree-base-root)))
                        (ignore-errors
                          (and (fboundp 'gptel-auto-workflow--effective-project-root)
                               (gptel-auto-workflow--effective-project-root)))
                        user-emacs-directory
                        default-directory))
  "Directory for research trace cache.")

(defvar gptel-auto-workflow--research-cache-max-size 1000
  "Maximum number of traces to keep in cache.")

(defvar gptel-auto-workflow--research-cache-index nil
  "In-memory index of cached traces.")

(defvar gptel-auto-workflow--replay-ema-conf 0.0
  "Temporary EMA confidence used during offline replay.")

(defvar gptel-auto-workflow--replay-ema-history nil
  "Temporary EMA history used during offline replay.")

(defun gptel-auto-workflow--research-cache-detect-topic (text)
  "Detect replay topic from TEXT without requiring the full strategic module."
  (let ((normalized (downcase (or text ""))))
    (cond
     ((string-match-p "performance\\|benchmark\\|cache\\|speed\\|optimize\\|efficiency\\|context-cache" normalized)
      "performance")
     ((string-match-p "nil-safety\\|nil\\|null\\|guard\\|sandbox\\|validation" normalized)
      "nil-safety")
     ((string-match-p "error-handling\\|exception\\|recover\\|retry" normalized)
      "error-handling")
     ((string-match-p "async\\|concurrent\\|parallel\\|loop" normalized)
      "async")
     (t "general"))))

(defun gptel-auto-workflow--research-cache-trace-topic-text (trace)
  "Return combined text fields from TRACE for topic detection."
  (string-join
   (delq nil
         (list (let ((value (plist-get trace :findings)))
                 (and (stringp value) (not (string-empty-p value)) value))
               (let ((value (plist-get trace :output)))
                 (and (stringp value) (not (string-empty-p value)) value))
               (let ((value (plist-get trace :prompt)))
                 (and (stringp value) (not (string-empty-p value)) value))
               (let ((outcomes (plist-get trace :outcomes)))
                 (and outcomes
                      (mapconcat
                       (lambda (outcome)
                         (or (plist-get outcome :target) ""))
                       outcomes
                       " ")))
               (let ((value (plist-get trace :strategy)))
                 (and (stringp value) (not (string-empty-p value)) value))))
   " "))

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
          (gptel-auto-workflow--merge-research-cache-index
           (if (file-exists-p index-file)
               (condition-case err
                   (let ((json-object-type 'plist)
                         (json-array-type 'list)
                         (json-key-type 'keyword))
                     (json-read-file index-file))
                 (error
                  (message "[research-cache] Failed to load index: %s" err)
                  nil))
             nil)
           (gptel-auto-workflow--build-research-cache-index-from-traces)))))

(defun gptel-auto-workflow--merge-research-cache-index (cached traced)
  "Return CACHED and TRACED replay index entries merged by trace id."
  (let ((seen (make-hash-table :test 'equal))
        (merged nil))
    (dolist (entry (append traced cached))
      (let ((id (plist-get entry :id)))
        (when (and id (not (gethash id seen)))
          (puthash id t seen)
          (push entry merged))))
    (sort merged
          (lambda (a b)
            (string> (or (plist-get a :timestamp) "")
                     (or (plist-get b :timestamp) ""))))))

(defun gptel-auto-workflow--research-cache-index-trace-file (trace-file)
  "Add TRACE-FILE to replay index if the research cache module is loaded."
  (when (and (stringp trace-file) (file-exists-p trace-file))
    (gptel-auto-workflow--load-research-cache-index)
    (when-let ((entry (gptel-auto-workflow--trace-entry-from-file trace-file)))
      (setq gptel-auto-workflow--research-cache-index
            (gptel-auto-workflow--merge-research-cache-index
             (list entry)
             gptel-auto-workflow--research-cache-index))
      (gptel-auto-workflow--save-research-cache-index))))

(defun gptel-auto-workflow--trace-entry-from-file (file)
  "Return replay index entry for trace FILE, or nil on parse failure."
  (condition-case err
      (let ((json-object-type 'plist)
            (json-array-type 'list)
            (json-key-type 'keyword))
        (let* ((trace (json-read-file file))
               (id (file-name-sans-extension (file-name-nondirectory file)))
               (topic-text (gptel-auto-workflow--research-cache-trace-topic-text trace))
               (topic (if (fboundp 'gptel-auto-workflow--detect-research-topic)
                          (gptel-auto-workflow--detect-research-topic topic-text)
                        (or (plist-get trace :topic)
                            (gptel-auto-workflow--research-cache-detect-topic topic-text)))))
          (list :id id
                :topic topic
                :timestamp (or (plist-get trace :timestamp) "unknown")
                :prompt (or (plist-get trace :prompt) "")
                :findings-length (or (plist-get trace :output-length)
                                     (length (or (plist-get trace :findings)
                                                 (plist-get trace :output)
                                                 "")))
                :controller-decision (or (plist-get trace :controller-decision) "continue")
                :confidence (or (plist-get trace :confidence) 0.0)
                :ema-conf (or (plist-get trace :ema-conf) 0.0)
                :ema-delta (or (plist-get trace :ema-delta) 0.0)
                :tokens-used (or (plist-get trace :tokens-used) 0)
                :file file)))
    (error
     (message "[research-cache] Failed to index %s: %s"
              (file-name-nondirectory file) err)
     nil)))

(defun gptel-auto-workflow--build-research-cache-index-from-traces ()
  "Build replay index from production trace JSON files."
  (let* ((trace-dir gptel-auto-workflow--research-cache-dir)
         (raw-dir (expand-file-name "raw" trace-dir))
         (dirs (delete-dups (delq nil (list trace-dir
                                             (and (file-directory-p raw-dir) raw-dir)))))
         (entries nil))
    (dolist (dir dirs)
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.json\\'"))
          (unless (string= (file-name-nondirectory file) "index.json")
            (when-let ((entry (gptel-auto-workflow--trace-entry-from-file file)))
              (push entry entries))))))
    (sort entries
          (lambda (a b)
            (string> (or (plist-get a :timestamp) "")
                     (or (plist-get b :timestamp) ""))))))

(defun gptel-auto-workflow--save-research-cache-index ()
  "Save cache index to disk."
  (gptel-auto-workflow--ensure-research-cache-dir)
  (let ((index-file (gptel-auto-workflow--research-cache-index-file)))
    (with-temp-file index-file
      (insert (gptel-auto-workflow--json-encode-plist gptel-auto-workflow--research-cache-index)))))

(defun gptel-auto-workflow--cache-research-turn (topic turn-data)
  "Cache a research turn for TOPIC.
TURN-DATA is a plist with :prompt :findings :controller-decision
:confidence etc."
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
       (insert (gptel-auto-workflow--json-encode-plist turn-data)))
    
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
  (gptel-auto-workflow--load-research-cache-index)
  (let* ((entry (cl-find-if (lambda (item)
                              (string= (plist-get item :id) trace-id))
                            gptel-auto-workflow--research-cache-index))
         (raw-file (cl-find-if
                    #'file-exists-p
                    (delq nil
                          (list (plist-get entry :file)
                                (expand-file-name (format "%s.json" trace-id)
                                                  (expand-file-name "raw" gptel-auto-workflow--research-cache-dir))
                                (expand-file-name (format "%s.json" trace-id)
                                                  gptel-auto-workflow--research-cache-dir))))))
    (when raw-file
      (condition-case err
          (with-temp-buffer
            (insert-file-contents raw-file)
            (let ((json-object-type 'plist)
                  (json-array-type 'list)
                  (json-key-type 'keyword))
              (json-read)))
        (error
         (message "[research-cache] Failed to load trace %s: %s" trace-id err)
         nil)))))

(defun gptel-auto-workflow--replay-research-turn (trace-id controller-config)
  "Replay a cached research turn with new CONTROLLER-CONFIG.
Returns simulated controller decision without API calls."
  (let ((trace-data (gptel-auto-workflow--load-trace-data trace-id)))
    (unless trace-data
      (error "Trace %s not found" trace-id))
    
    (let* ((findings (or (plist-get trace-data :findings)
                         (plist-get trace-data :output)
                         ""))
           (output-length (or (plist-get trace-data :output-length)
                              (length findings)))
           (turn (or (plist-get trace-data :turn)
                     (1- (or (plist-get trace-data :turn-count) 1))
                     0))
           (replay-config (copy-sequence controller-config))
           (old-ema-conf (and (boundp 'gptel-auto-workflow--research-ema-conf)
                              gptel-auto-workflow--research-ema-conf))
           (old-ema-history (and (boundp 'gptel-auto-workflow--research-ema-history)
                                 gptel-auto-workflow--research-ema-history)))
      (plist-put replay-config :turn-count turn)
       
      ;; Simulate controller decision on cached data
      (when (fboundp 'gptel-auto-workflow--controller-decide-research-flow)
        (unwind-protect
            (progn
              (when (boundp 'gptel-auto-workflow--research-ema-conf)
                (setq gptel-auto-workflow--research-ema-conf
                      (or (plist-get trace-data :ema-conf) 0.0)))
              (when (boundp 'gptel-auto-workflow--research-ema-history)
                (setq gptel-auto-workflow--research-ema-history
                      (or (delq nil
                                (mapcar (lambda (turn-trace)
                                          (plist-get turn-trace :ema-conf))
                                        (plist-get trace-data :trace-log)))
                          (list (or (plist-get trace-data :ema-conf) 0.0)))))
(gptel-auto-workflow--controller-decide-with-doom-check
                replay-config output-length findings))
          (when (boundp 'gptel-auto-workflow--research-ema-conf)
            (setq gptel-auto-workflow--research-ema-conf old-ema-conf))
          (when (boundp 'gptel-auto-workflow--research-ema-history)
            (setq gptel-auto-workflow--research-ema-history old-ema-history)))))))

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
        
        (pcase decision
          ('stop (cl-incf (plist-get results :stopped)))
          ('branch (cl-incf (plist-get results :branched)))
          ('continue (cl-incf (plist-get results :continued)))
          ('cut (cl-incf (plist-get results :cut))))))
    
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

;; Initialize replay index from existing traces on module load
(ignore-errors
  (gptel-auto-workflow--load-research-cache-index)
  (message "[research-cache] Index initialized with %d entries"
           (length gptel-auto-workflow--research-cache-index)))

(provide 'gptel-auto-workflow-research-cache)
;;; gptel-auto-workflow-research-cache.el ends here
