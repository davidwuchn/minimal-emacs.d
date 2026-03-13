;;; gptel-ext-retry.el --- Automatic retry and payload compaction -*- lexical-binding: t; -*-

;;; Commentary:
;; Automatic retry for transient API errors with exponential backoff.
;; Pre-send payload compaction to prevent oversized requests.
;;
;; Three-layer defense against oversized API payloads:
;;   Layer 1 — Pre-send (retries=0): my/gptel--compact-payload
;;   Layer 2 — Retry (retries=1): trim tool results
;;   Layer 3 — Retry (retries=2+): truncate ALL + strip reasoning + reduce tools

;;; Code:

(require 'cl-lib)
(require 'gptel)
(require 'gptel-openai)

(defvar gptel-send--handlers)    ; defined in gptel
(defvar gptel-request--handlers) ; defined in gptel

;; --- Automatic Retry for Transient API Errors ---
;; Gemini often returns "Malformed JSON" due to API load or payload limits.
;; This automatically retries the request up to 3 times before failing.

(defcustom my/gptel-max-retries 3
  "Number of times to retry failed gptel requests.
If nil, retry indefinitely using exponential backoff (capped at 30s).
Default is 3 to prevent doom-loops caused by context overflow errors."
  :type '(choice (const :tag "Infinite" nil) integer)
  :group 'gptel)

(defcustom my/gptel-retry-keep-recent-tool-results 2
  "Number of recent tool-result messages to keep intact during retry.
Older tool results are truncated to reduce payload size.
Set to nil to disable tool-result trimming on retry."
  :type '(choice (const :tag "Disabled" nil) integer)
  :group 'gptel)

(defcustom my/gptel-retry-truncated-result-text "[Content truncated to reduce context size for retry]"
  "Replacement text for truncated tool results during retry."
  :type 'string
  :group 'gptel)

(defun my/gptel--trim-tool-results-for-retry (info)
  "Trim old tool-result content in INFO's :data :messages to reduce payload.

Progressive trimming: on each successive retry, fewer tool results are kept
intact.  The keep count is computed as:

  max(0, `my/gptel-retry-keep-recent-tool-results' - retries)

where retries is the CURRENT retry count from INFO's :retries (already
incremented before this function is called).

Retry 1 (retries=1): keep max(0, 2-1) = 1 recent result
Retry 2 (retries=2): keep max(0, 2-2) = 0 results (truncate ALL)
Retry 3+:            keep 0 (truncate ALL)

This preserves the tool_call_id pairing required by OpenAI-compatible APIs
while progressively reducing payload size on successive retries.

Returns the number of messages truncated, or 0 if nothing was done."
  (if (null my/gptel-retry-keep-recent-tool-results)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (retries (or (plist-get info :retries) 1))
           (keep (max 0 (- my/gptel-retry-keep-recent-tool-results retries)))
           (replacement my/gptel-retry-truncated-result-text)
           (truncated 0))
      (when (and messages (> (length messages) 0))
        ;; Collect indices of tool-result messages (role = "tool")
        (let ((tool-indices '()))
          (dotimes (i (length messages))
            (let ((msg (aref messages i)))
              (when (equal (plist-get msg :role) "tool")
                (push i tool-indices))))
          ;; tool-indices is now newest-first (pushed in forward order, so reversed)
          ;; Actually dotimes pushes 0,1,2... so tool-indices is reversed (last first)
          ;; We want to keep the LAST `keep' entries, so drop from the front of tool-indices
          (setq tool-indices (nreverse tool-indices)) ; now oldest-first
          (when (> (length tool-indices) keep)
            (let ((to-truncate (seq-take tool-indices (- (length tool-indices) keep))))
              (dolist (idx to-truncate)
                (let* ((msg (aref messages idx))
                       (content (plist-get msg :content)))
                  (when (and (stringp content)
                             (> (length content) (length replacement)))
                    (plist-put msg :content replacement)
                    (cl-incf truncated))))))))
      truncated)))

(defun my/gptel--trim-reasoning-content (info)
  "Strip reasoning_content from assistant messages in INFO to reduce payload.

Called on retry 2+ (retries >= 2) to remove chain-of-thought reasoning text
that accumulates across tool-use rounds.  The :reasoning_content field is
set to an empty string so it remains present in the serialized payload
\(some APIs like Moonshot require the field to exist when thinking is enabled).

Returns the number of messages whose reasoning_content was stripped."
  (let* ((data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (stripped 0))
    (when (and messages (> (length messages) 0))
      (dotimes (i (length messages))
        (let ((msg (aref messages i)))
          (when (and (equal (plist-get msg :role) "assistant")
                     (plist-get msg :reasoning_content)
                     (not (equal "" (plist-get msg :reasoning_content))))
             (plist-put msg :reasoning_content "")
             (cl-incf stripped)))))
    stripped))

(defun my/gptel--repair-thinking-tool-call-messages (info)
  "Ensure thinking-enabled assistant tool-call messages stay API-valid.

When the active model/backend requires a reasoning field (for example Moonshot's
`reasoning_content`), every assistant message with `:tool_calls` must carry that
field, even if it is the empty string.  Returns the number of messages repaired."
  (let* ((model (plist-get info :model))
         (backend (plist-get info :backend))
         (reasoning-key (and (fboundp 'my/gptel--reasoning-key-for-model)
                             (my/gptel--reasoning-key-for-model model backend)))
         (data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (gptel-buf (plist-get info :buffer))
         (reasoning-alist
          (and gptel-buf (buffer-live-p gptel-buf)
               (boundp 'my/gptel--tool-reasoning-alist)
               (buffer-local-value 'my/gptel--tool-reasoning-alist gptel-buf)))
         (repaired 0))
    (when (and reasoning-key messages (> (length messages) 0)
               (fboundp 'my/gptel--ensure-reasoning-on-messages))
      (setq repaired
            (my/gptel--ensure-reasoning-on-messages
             messages reasoning-key reasoning-alist)))
    repaired))

(defun my/gptel--reduce-tools-for-retry (info)
  "Reduce the tools array in INFO to only tools referenced in conversation.

Scans :data :messages for all assistant messages containing :tool_calls,
collects the set of tool names actually invoked, then filters both
:data :tools (the serialized vector sent to the API) and :tools (the
gptel-tool struct list used for dispatch) to only those names.

This typically removes 60-80% of the tools payload (~5-8KB) on
conversations that only use 3-5 of 18+ registered tools.

Returns the number of tool definitions removed, or 0 if nothing changed."
  (let* ((data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (data-tools (and data (plist-get data :tools)))  ; vector of plists
         (struct-tools (plist-get info :tools))            ; list of gptel-tool structs
         (used-names (make-hash-table :test #'equal))
         (removed 0))
    (when (and messages data-tools (> (length data-tools) 0))
      ;; Pass 1: collect all tool names referenced in tool_calls
      (dotimes (i (length messages))
        (let* ((msg (aref messages i))
               (tool-calls (plist-get msg :tool_calls)))
          (when tool-calls
            (dotimes (j (length tool-calls))
              (let* ((tc (aref tool-calls j))
                     (func (plist-get tc :function))
                     (name (and func (plist-get func :name))))
                (when name
                  (puthash name t used-names)))))))
      ;; Only filter if we found any used tools (safety: don't send empty tools)
      (when (> (hash-table-count used-names) 0)
        (let* ((original-count (length data-tools))
               ;; Filter serialized tools vector
               (filtered (vconcat
                          (cl-remove-if-not
                           (lambda (tool-plist)
                             (let* ((func (plist-get tool-plist :function))
                                    (name (and func (plist-get func :name))))
                               (gethash name used-names)))
                           (append data-tools nil)))) ; vector -> list for cl-remove-if-not
               (new-count (length filtered)))
          (when (< new-count original-count)
            (plist-put data :tools filtered)
            ;; Also filter struct list to match
            (when struct-tools
              (plist-put info :tools
                         (cl-remove-if-not
                          (lambda (ts)
                            (gethash (gptel-tool-name ts) used-names))
                          struct-tools)))
            (setq removed (- original-count new-count))))))
    removed))

(defcustom my/gptel-truncate-old-messages-keep 6
  "Number of recent messages to keep when truncating old messages.
Pass 5 of compaction removes older user/assistant messages beyond this count.
Set to nil to disable old message truncation."
  :type '(choice (const :tag "Disabled" nil) integer)
  :group 'gptel)

(defun my/gptel--truncate-old-messages (info)
  "Truncate old user/assistant messages in INFO to reduce payload.

Removes message content from older messages (beyond `my/gptel-truncate-old-messages-keep'),
replacing with a truncation marker. Keeps the message structure intact for API compatibility.

Returns the number of messages truncated, or 0 if nothing was done."
  (if (null my/gptel-truncate-old-messages-keep)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (keep my/gptel-truncate-old-messages-keep)
           (truncated 0)
           (truncation-text "[Earlier conversation truncated to reduce payload size]"))
      (when (and messages (> (length messages) keep))
        (let ((cutoff (- (length messages) keep)))
          (dotimes (i cutoff)
            (let* ((msg (aref messages i))
                   (role (plist-get msg :role))
                   (content (plist-get msg :content)))
              ;; Only truncate user and assistant messages, not system/tool
              (when (and (member role '("user" "assistant"))
                         (stringp content)
                         (> (length content) (length truncation-text)))
                (plist-put msg :content truncation-text)
                (cl-incf truncated))))))
      truncated)))

(defun my/gptel--transient-error-p (error-data http-status)
  "Return non-nil if ERROR-DATA or HTTP-STATUS indicate a transient API error.
Matches network failures, overload responses, rate limits, and common
curl error codes that are safe to retry with backoff."
  (or (and (stringp error-data)
           (string-match-p "Malformed JSON\\|Could not parse HTTP\\|json-read-error\\|Empty reply\\|Timeout\\|timeout\\|curl: (28)\\|curl: (6)\\|curl: (7)\\|Bad Gateway\\|Service Unavailable\\|Gateway Timeout\\|Connection refused\\|Could not resolve host\\|Overloaded\\|overloaded\\|Too Many Requests" error-data))
      (and (numberp http-status) (memq http-status '(408 429 500 502 503 504)))
      ;; Catch dictionary format errors from OpenCode style backend responses
      (and (listp error-data)
           (string-match-p "overloaded\\|too many requests\\|rate limit\\|timeout\\|free usage limit"
                           (downcase (or (plist-get error-data :message) ""))))))

(defun my/gptel--cleanup-partial-insertion (info)
  "Remove partial buffer text inserted before a failed request.
Uses INFO's :position and :tracking-marker to identify the region.
Guard: both markers must be live, in the same buffer, and
start <= tracking to avoid corrupting the buffer."
  (when-let* ((start-marker (plist-get info :position))
              (tracking-marker (plist-get info :tracking-marker))
              (start-pos (and (markerp start-marker) (marker-position start-marker)))
              (track-pos (and (markerp tracking-marker) (marker-position tracking-marker)))
              (buf (marker-buffer tracking-marker)))
    (when (and (buffer-live-p buf)
               (eq (marker-buffer start-marker) buf)
               (< start-pos track-pos))
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (delete-region start-marker tracking-marker)
          (set-marker tracking-marker start-marker))))))

(defun my/gptel-auto-retry (orig-fn machine &optional new-state)
  "Intercept FSM transitions to ERRS and retry the request if transient.
Implements OpenCode-style exponential backoff for network/overload errors.
Skips retries for subagent FSMs (they have their own timeout handler)."
  (unless new-state (setq new-state (gptel--fsm-next machine)))
  (let* ((info (gptel-fsm-info machine))
         (error-data (plist-get info :error))
         (http-status (plist-get info :http-status))
         (retries (or (plist-get info :retries) 0))
         ;; Detect subagent FSMs: they use gptel-agent-request--handlers
         ;; and should not be retried (the parent's timeout handles failures).
         ;; A request is retryable if its handlers are one of the two known
         ;; "main" handler sets: gptel-send--handlers (interactive) or
         ;; gptel-request--handlers (programmatic).  Anything else is a
         ;; subagent whose parent timeout manages failure.
         (handlers (gptel-fsm-handlers machine))
         (subagent-p (not (or (eq handlers gptel-send--handlers)
                              (eq handlers gptel-request--handlers)))))
    (if (and (eq new-state 'ERRS)
             (not subagent-p)
             (or (null my/gptel-max-retries) (< retries my/gptel-max-retries))
             (my/gptel--transient-error-p error-data http-status))
        (let* ((base-delay 2.0)
               (factor 2.0)
               (delay (min 30.0 (* base-delay (expt factor retries)))))
          (if my/gptel-max-retries
              (message "gptel: API failed with '%s'. Retrying (%d/%d) in %.1fs..." 
                       (if (stringp error-data) (string-trim error-data)
                         (if http-status (format "HTTP %s" http-status) "Transient API Error"))
                       (1+ retries) my/gptel-max-retries delay)
            (message "gptel: API failed with '%s'. Retrying (Attempt %d) in %.1fs..." 
                     (if (stringp error-data) (string-trim error-data)
                       (if http-status (format "HTTP %s" http-status) "Transient API Error"))
                     (1+ retries) delay))
          
          ;; Clean up partial buffer insertions if any.
           (my/gptel--cleanup-partial-insertion info)
          
           ;; Reset FSM state to WAIT to trigger a fresh request
           (plist-put info :error nil)
           (plist-put info :status nil)
           (plist-put info :http-status nil)
           (plist-put info :retries (1+ retries))
           
           ;; Progressive payload trimming before retry.
             ;; Tool results: keep count decreases with each retry
             ;;   retry 1 → keep max(0, default-1), retry 2+ → keep 0
             ;; Reasoning content: stripped on retry 2+ to reclaim space
             ;; from accumulated chain-of-thought text.
             ;; Tools array: reduced on retry 2+ to only tools actually
             ;; used in the conversation, removing ~60-80% of definitions.
             (let ((trimmed (my/gptel--trim-tool-results-for-retry info))
                   (new-retries (plist-get info :retries)))
                (when (> trimmed 0)
                  (message "gptel: Trimmed %d old tool result(s) to reduce payload (retry %d, keeping %d recent)"
                           trimmed new-retries
                           (max 0 (- my/gptel-retry-keep-recent-tool-results new-retries))))
                (when (>= new-retries 2)
                 (let ((reasoning-stripped (my/gptel--trim-reasoning-content info)))
                   (when (> reasoning-stripped 0)
                     (message "gptel: Stripped reasoning_content from %d assistant message(s)" reasoning-stripped)))
                  (let ((tools-removed (my/gptel--reduce-tools-for-retry info)))
                    (when (> tools-removed 0)
                      (message "gptel: Removed %d unused tool definition(s) from payload" tools-removed)))
                  (let ((repaired (my/gptel--repair-thinking-tool-call-messages info)))
                    (when (> repaired 0)
                      (message "gptel: Restored empty reasoning field on %d tool-call message(s)" repaired)))))
            
            ;; Schedule the FSM transition asynchronously (non-blocking exponential backoff)
            (run-at-time delay nil
                        (lambda (m f-orig)
                         (funcall f-orig m 'WAIT))
                       machine orig-fn)
          ;; Return nil to abort the current transition to ERRS and let the timer take over
          nil)
      (funcall orig-fn machine new-state))))

(advice-add 'gptel--fsm-transition :around #'my/gptel-auto-retry)

;; --- Pre-Send Payload Compaction ---
;; Proactively trim oversized payloads BEFORE the first send attempt,
;; preventing wasted retries when the payload is already too large.

(defcustom my/gptel-payload-byte-limit 200000
  "Maximum JSON payload size in bytes before proactive compaction.
When the serialized payload exceeds this limit, the pre-send hook
applies progressive trimming (tool results, reasoning, tools array)
before the request is sent.

Set to nil to disable pre-send compaction (rely on retry trimming only).
Default is 200KB — conservative for DashScope/Moonshot endpoints that
tend to reset connections around 250-300KB."
  :type '(choice (const :tag "Disabled" nil) integer)
  :group 'gptel)

(defconst my/gptel-model-context-bytes
  '((kimi-k2\.5        . 400000)   ; 131K tokens ≈ 460KB, leave room for output
    (kimi-for-coding    . 400000)
    (qwen3\.5-plus      . 400000)   ; 131K tokens
    (qwen3-coder-next   . 400000)
    (qwen3-coder-plus   . 400000)
    (qwen3-max-2026-01-23 . 400000)
    (glm-5              . 350000)   ; 128K tokens
    (glm-4\.7            . 350000)
    (MiniMax-M2\.5       . 300000)
    (deepseek-chat      . 200000)   ; 64K tokens
    (deepseek-reasoner  . 200000))
  "Approximate max JSON byte size per model (context window × ~3.5 bytes/token,
minus output reservation).  Used as fallback when `my/gptel-payload-byte-limit'
would be too generous for a smaller-context model.")

(defun my/gptel--estimate-payload-bytes (info)
  "Estimate the JSON byte size of INFO's :data payload.
Uses `json-serialize' for accuracy.  Returns 0 if :data is nil."
  (let ((data (plist-get info :data)))
    (if data
        (condition-case nil
            (string-bytes (gptel--json-encode data))
          (error 0))
      0)))

(defun my/gptel--effective-byte-limit (info)
  "Return the byte limit to use for INFO's request.
Takes the minimum of `my/gptel-payload-byte-limit' and the model-specific
context limit from `my/gptel-model-context-bytes'."
  (let* ((model (plist-get info :model))
         (global-limit (or my/gptel-payload-byte-limit 999999999))
         (model-limit (or (alist-get model my/gptel-model-context-bytes) 999999999)))
    (min global-limit model-limit)))

(defun my/gptel--compact-payload (fsm)
  "Proactively trim FSM's payload if it exceeds byte limits.
Called as :before advice on `gptel-curl-get-response'.

Only runs on the first attempt (retries=0) — retry trimming handles
subsequent attempts via `my/gptel-auto-retry'.

Applies trimming progressively until under limit or nothing left to trim:
  1. Trim old tool results (keep 2 recent)
  2. Strip reasoning_content
  3. Reduce tools array to only used tools"
  (when my/gptel-payload-byte-limit
    (let* ((info (gptel-fsm-info fsm))
           (retries (or (plist-get info :retries) 0)))
      ;; Only compact on first send — retries have their own trimming
       (when (= retries 0)
         (let ((limit (my/gptel--effective-byte-limit info))
               (repaired (my/gptel--repair-thinking-tool-call-messages info))
               (bytes (my/gptel--estimate-payload-bytes info))
               (trimmed-total 0)
               (pass 0))
           (when (> repaired 0)
             (message "gptel: Repaired reasoning field on %d tool-call message(s) before compaction" repaired))
           (when (> bytes limit)
             (message "gptel: Payload %dKB exceeds %dKB limit, compacting..."
                      (/ bytes 1024) (/ limit 1024))
            ;; Pass 1: trim tool results (keep 2 recent)
            (let ((my/gptel-retry-keep-recent-tool-results 2))
              (plist-put info :retries 1)  ; simulate retry 1 for keep count
              (let ((n (my/gptel--trim-tool-results-for-retry info)))
                (cl-incf trimmed-total n)
                (setq bytes (my/gptel--estimate-payload-bytes info))
                (setq pass 1)
                (when (> n 0)
                  (message "gptel: Pass 1: trimmed %d tool result(s), now %dKB"
                           n (/ bytes 1024)))))
            ;; Pass 2: strip reasoning (if still over)
             (when (> bytes limit)
               (let ((n (my/gptel--trim-reasoning-content info)))
                 (cl-incf trimmed-total n)
                 (setq repaired (my/gptel--repair-thinking-tool-call-messages info))
                 (cl-incf trimmed-total repaired)
                 (setq bytes (my/gptel--estimate-payload-bytes info))
                 (setq pass 2)
                 (when (or (> n 0) (> repaired 0))
                   (message "gptel: Pass 2: stripped reasoning from %d message(s), repaired %d tool-call message(s), now %dKB"
                            n repaired (/ bytes 1024)))))
            ;; Pass 3: reduce tools array (if still over)
            (when (> bytes limit)
              (let ((n (my/gptel--reduce-tools-for-retry info)))
                (cl-incf trimmed-total n)
                (setq bytes (my/gptel--estimate-payload-bytes info))
                (setq pass 3)
                (when (> n 0)
                  (message "gptel: Pass 3: removed %d unused tool def(s), now %dKB"
                           n (/ bytes 1024)))))
            ;; Pass 4: aggressive tool result trim (keep 0)
            (when (> bytes limit)
              (let ((my/gptel-retry-keep-recent-tool-results 2))
                (plist-put info :retries 3)  ; simulate retry 3 for keep=0
                (let ((n (my/gptel--trim-tool-results-for-retry info)))
                  (cl-incf trimmed-total n)
                  (setq bytes (my/gptel--estimate-payload-bytes info))
                  (setq pass 4)
                  (when (> n 0)
                    (message "gptel: Pass 4: truncated %d remaining tool results, now %dKB"
                             n (/ bytes 1024))))))
            ;; Pass 5: truncate old user/assistant messages
            (when (> bytes limit)
              (let ((n (my/gptel--truncate-old-messages info)))
                (cl-incf trimmed-total n)
                (setq bytes (my/gptel--estimate-payload-bytes info))
                (setq pass 5)
                (when (> n 0)
                  (message "gptel: Pass 5: truncated %d old message(s), now %dKB"
                           n (/ bytes 1024)))))
            ;; Reset retries to 0 (we simulated retries for trim functions)
            (plist-put info :retries 0)
            (if (> bytes limit)
                (message "gptel: WARNING: Payload still %dKB after %d passes of compaction (limit %dKB)"
                         (/ bytes 1024) pass (/ limit 1024))
              (message "gptel: Compaction complete: %d items trimmed across %d pass(es), payload now %dKB"
                       trimmed-total pass (/ bytes 1024)))))))))

(advice-add 'gptel-curl-get-response :before #'my/gptel--compact-payload)

(provide 'gptel-ext-retry)
;;; gptel-ext-retry.el ends here
