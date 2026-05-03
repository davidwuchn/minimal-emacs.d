;;; gptel-ext-retry.el --- Automatic retry and payload compaction -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Automatic retry for transient API errors with exponential backoff.
;; Pre-send payload compaction to prevent oversized requests.
;;
;; Three-layer defense against oversized API payloads:
;;   Layer 1 — Pre-send (retries=0): my/gptel--compact-payload
;;   Layer 2 — Retry (retries=1): trim tool results
;;   Layer 3 — Retry (retries=2+): truncate ALL + strip reasoning + reduce tools
;;
;; ASSUMPTION: Transient errors (408, 429, 500-504, network failures) are
;;   safe to retry with exponential backoff. Non-transient errors (auth,
;;   invalid params) should fail immediately.
;;
;; BEHAVIOR: Implements progressive payload reduction on each retry:
;;   - Retry 1: Keep N-1 recent tool results (N = my/gptel-retry-keep-recent-tool-results)
;;   - Retry 2+: Strip reasoning_content, reduce tools to only used ones
;;   - Retry 3+: Truncate ALL tool results, strip images
;;
;; EDGE CASE: Subagent FSMs have custom handlers and should NOT be retried
;;   here — parent timeout handles their failures. Detected by checking
;;   if handlers match main request handlers.
;;
;; EDGE CASE: Thinking-enabled models (Moonshot) require reasoning_content
;;   field to exist on ALL assistant tool-call messages, even if empty.
;;   my/gptel--repair-thinking-tool-call-messages ensures this invariant.
;;
;; EDGE CASE: Payload compaction only runs on first attempt (retries=0).
;;   Subsequent retries use my/gptel-auto-retry's trimming logic.
;;
;; TEST: Verify retry behavior with (ert-deftest test-gptel-retry ...)
;;   in tests/test-gptel-ext-retry.el. Test transient error detection,
;;   exponential backoff timing, and payload reduction effectiveness.
;;
;; WISDOM: my/gptel-trim-min-bytes (default 5000) prevents tiny trims that
;;   break prompt cache consistency without meaningful payload reduction.
;;   Based on Anthropic's guidance: context edits should clear ≥5000 tokens.

;;; Code:

(require 'cl-lib)
(require 'gptel)
(require 'gptel-openai)
(require 'seq)

(defvar gptel-send--handlers)
(defvar gptel-request--handlers)
(defvar gptel-auto-workflow--headless)
(defvar gptel-auto-workflow-persistent-headless)

(declare-function my/gptel--trim-context-images "gptel-ext-context-images")

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

(defcustom my/gptel-reasoning-keep-turns 1
  "Number of recent assistant turns whose reasoning_content to preserve.
Older reasoning blocks are stripped to reduce payload while preserving
recent reasoning context for continuity.
Set to 0 to strip all reasoning, nil to disable reasoning trimming."
  :type '(choice (const :tag "Disabled" nil)
                 (const :tag "Strip all" 0)
                 integer)
  :group 'gptel)

(defcustom my/gptel-trim-min-bytes 5000
  "Minimum bytes to save per trimming operation.
If trimming would not save at least this many bytes, skip trimming.
This prevents tiny trims that provide negligible payload reduction
while potentially breaking prompt cache consistency.

Set to 0 to disable the minimum threshold (always trim).

Default is 5000 bytes (5KB) based on Anthropic's guidance that context
edits should clear at least 5000 tokens to be worthwhile, adjusted
for byte-level operations (~3.5 bytes/token)."
  :type 'integer
  :group 'gptel)

(defconst my/gptel--retry-base-delay 4.0
  "Initial delay in seconds for exponential backoff on transient errors.
Used by `my/gptel-auto-retry' to compute retry delays.")

(defconst my/gptel--retry-backoff-factor 2.0
  "Multiplier for exponential backoff delay on each retry attempt.
Used by `my/gptel-auto-retry' to compute retry delays.")

(defconst my/gptel--retry-max-delay 30.0
  "Maximum delay in seconds for exponential backoff retries.
Prevents excessively long waits when many retries are needed.")

(defun my/gptel--retry-delay (retries)
  "Compute exponential backoff delay in seconds for RETRIES attempt.
Uses `my/gptel--retry-base-delay', `my/gptel--retry-backoff-factor',
and `my/gptel--retry-max-delay' constants.

ASSUMPTION: retries >= 0; negative values treated as 0.
BEHAVIOR: delay = min(max-delay, base-delay * backoff-factor^retries)
EDGE CASE: Negative retries clamped to 0 to prevent sub-second delays.
TEST: (my/gptel--retry-delay 0) => 4.0
TEST: (my/gptel--retry-delay 3) => 30.0 (capped)"
  (let ((r (if (and (numberp retries) (>= retries 0))
               retries
             0)))
    (min my/gptel--retry-max-delay
         (* my/gptel--retry-base-delay
            (expt my/gptel--retry-backoff-factor r)))))

(defconst my/gptel--unbounded-byte-limit 999999999
  "Unbounded byte limit for model-specific context limits.
Used as fallback when a model is not in `my/gptel-model-context-bytes'
or when `my/gptel-payload-byte-limit' is nil.
Setting a high but finite value prevents nil arithmetic issues
while effectively disabling the limit for unknown models.
ASSUMPTION: No model will ever produce a payload exceeding this limit.
TEST: Can be grepped to find all fallback limit usages.")

(defun my/gptel--compute-trim-keep-count (info retry-count)
  "Compute how many tool results to keep based on RETRY-COUNT and settings.
INFO is the FSM info plist.  RETRY-COUNT is the current retry count.

Returns max(0, `my/gptel-retry-keep-recent-tool-results' - RETRY-COUNT).
When `my/gptel-retry-keep-recent-tool-results' is nil, returns 0.

BEHAVIOR: keep count decreases with each retry:
  retry 0: keep default value
  retry 1: keep default-1
  retry 2+: keep 0 (truncate all)"
  (let ((retries (or retry-count (plist-get info :retries) 1)))
    (max 0 (- (or my/gptel-retry-keep-recent-tool-results 0) retries))))

(defun my/gptel--should-trim-p (info force-trim-p)
  "Return non-nil if tool-result trimming should proceed.
INFO is the FSM info plist.  FORCE-TRIM-P bypasses user preference.
Returns nil if trimming is disabled (unless FORCE-TRIM-P is set)."
  (and info (or force-trim-p my/gptel-retry-keep-recent-tool-results)))

(defun my/gptel--trim-tool-results-for-retry (info &optional retry-count force-trim-p)
  "Trim old tool-result content in INFO's :data :messages to reduce payload.

Progressive trimming: on each successive retry, fewer tool results are kept
intact.  The keep count is computed as:

  max(0, `my/gptel-retry-keep-recent-tool-results' - retry-count)

where RETRY-COUNT is the current retry count (defaults to INFO's :retries).

RETRY-COUNT 1 (retry 1): keep max(0, 2-1) = 1 recent result
RETRY-COUNT 2 (retry 2): keep max(0, 2-2) = 0 results (truncate ALL)
RETRY-COUNT 3+:          keep 0 (truncate ALL)

This preserves the tool_call_id pairing required by OpenAI-compatible APIs
while progressively reducing payload size on successive retries.

If `my/gptel-trim-min-bytes' is non-zero, trimming only proceeds when
the byte savings would meet or exceed that threshold.

FORCE-TRIM-P, when non-nil, bypasses the `my/gptel-retry-keep-recent-tool-results'
nil check. Used by compaction passes to ensure trimming occurs even if the user
has disabled retry trimming (nil). This allows pre-send compaction to work
independently of retry settings.

Returns the number of messages truncated, or 0 if nothing was done."
  (if (not (my/gptel--should-trim-p info force-trim-p))
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (keep (my/gptel--compute-trim-keep-count info retry-count))
           (replacement my/gptel-retry-truncated-result-text)
           (truncated 0)
           (bytes-saved 0))
      (when (and messages (plusp (length messages)))
        (let ((tool-indices
               (my/gptel--collect-message-indices
                messages
                (lambda (msg) (my/gptel--message-role-p msg "tool")))))
          (when (> (length tool-indices) keep)
            (let ((to-truncate (seq-take tool-indices (- (length tool-indices) keep))))
              ;; Single pass: collect candidates and calculate bytes-saved
              ;; Then check threshold before modifying messages
              (let ((candidates))
                (dolist (idx to-truncate)
                  (let* ((msg (aref messages idx))
                         (content (plist-get msg :content)))
                    (when (and (stringp content)
                               (> (string-bytes content) (string-bytes replacement)))
                      (push idx candidates)
                      (cl-incf bytes-saved (- (string-bytes content) (string-bytes replacement))))))
                (when (or (= my/gptel-trim-min-bytes 0)
                          (>= bytes-saved my/gptel-trim-min-bytes))
                  (dolist (idx (nreverse candidates))
                    (let* ((msg (aref messages idx))
                           (content (plist-get msg :content)))
                      (plist-put msg :content replacement)
                      (cl-incf truncated)))))))))
       truncated)))

(defun my/gptel--trim-gemini-function-responses-for-retry (info &optional retry-count force-trim-p)
  "Trim old Gemini function-response content in INFO's :data :contents.

Gemini requests are serialized with `:contents' entries containing
`:functionResponse' parts instead of OpenAI-style `:messages' with role
\"tool\".  This mirrors `my/gptel--trim-tool-results-for-retry' for that
payload shape so provider failover to Gemini can still compact oversized
tool-output history.

Returns the number of function-response parts truncated, or 0 if nothing was
done."
  (if (not (my/gptel--should-trim-p info force-trim-p))
      0
    (let* ((data (plist-get info :data))
           (contents (and data (plist-get data :contents)))
           (keep (my/gptel--compute-trim-keep-count info retry-count))
           (replacement my/gptel-retry-truncated-result-text)
           (truncated 0)
           (bytes-saved 0)
           candidates)
      (when (and contents (sequencep contents) (not (stringp contents)))
        (dotimes (content-index (length contents))
          (let* ((content-entry (elt contents content-index))
                 (parts (and (consp content-entry)
                             (plist-get content-entry :parts))))
            (when (and parts (sequencep parts) (not (stringp parts)))
              (dotimes (part-index (length parts))
                (let* ((part (elt parts part-index))
                       (function-response
                        (and (consp part)
                             (plist-get part :functionResponse)))
                       (response
                        (and (consp function-response)
                             (plist-get function-response :response)))
                       (response-content
                        (and (consp response)
                             (plist-get response :content))))
                  (when (and (stringp response-content)
                             (> (string-bytes response-content)
                                (string-bytes replacement)))
                    (push (list content-index part-index)
                          candidates)
                    (cl-incf bytes-saved
                             (- (string-bytes response-content)
                                (string-bytes replacement))))))))))
      (when (> (length candidates) keep)
        (let* ((ordered-candidates (nreverse candidates))
               (to-truncate (seq-take ordered-candidates
                                      (max 0 (- (length ordered-candidates) keep)))))
          (when (or (= my/gptel-trim-min-bytes 0)
                    (>= bytes-saved my/gptel-trim-min-bytes))
            (dolist (candidate to-truncate)
              (pcase-let ((`(,content-index ,part-index) candidate))
                (let* ((content-entry (elt contents content-index))
                       (parts (plist-get content-entry :parts))
                       (part (elt parts part-index))
                       (function-response (plist-get part :functionResponse))
                       (response (plist-get function-response :response)))
                  (plist-put response :content replacement)
                  (cl-incf truncated)))))))
      truncated)))

(defun my/gptel--trim-reasoning-content (info)
  "Strip reasoning_content from older assistant messages in INFO to reduce payload.

Preserves the N most recent assistant turns with reasoning_content, where N is
`my/gptel-reasoning-keep-turns'.  Older non-tool-call reasoning blocks are set
to an empty string so the field remains present in the serialized payload.
Assistant turns that carry `:tool_calls' keep their reasoning intact because
thinking-enabled backends can reject compacted tool-call history when that
reasoning is blanked.

Called on retry 2+ (retries >= 2) to remove chain-of-thought reasoning text
that accumulates across tool-use rounds.

Returns the number of messages whose reasoning_content was stripped."
  (if (null my/gptel-reasoning-keep-turns)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (keep my/gptel-reasoning-keep-turns)
           (stripped 0))
      (when (and messages (> (length messages) 0))
        (let ((reasoning-indices
               (my/gptel--collect-message-indices
                messages
                (lambda (msg)
                  (and (my/gptel--message-role-p msg "assistant")
                       (not (plist-get msg :tool_calls))
                       (plist-get msg :reasoning_content)
                       (not (equal "" (plist-get msg :reasoning_content))))))))
          (when (> (length reasoning-indices) keep)
            (let ((to-strip (seq-take reasoning-indices
                                      (- (length reasoning-indices) keep))))
              (dolist (idx to-strip)
                (let ((msg (aref messages idx)))
                  (plist-put msg :reasoning_content "")
                  (cl-incf stripped)))))))
      stripped)))

(defun my/gptel--repair-thinking-tool-call-messages (info)
  "Ensure thinking-enabled assistant tool-call messages stay API-valid.

When the active model/backend requires a reasoning field (for example Moonshot's
`reasoning_content`), every assistant message with `:tool_calls` must carry that
field, even if it is the empty string.

INFO is the request info plist containing :model, :backend, :data, and :buffer.

Returns the number of messages repaired."
  (let* ((model (plist-get info :model))
         (reasoning-key (and (fboundp 'my/gptel--reasoning-key-for-model)
                             (my/gptel--reasoning-key-for-model model)))
         (messages (let ((data (plist-get info :data)))
                     (and data (plist-get data :messages))))
         (gptel-buf (plist-get info :buffer))
         (reasoning-alist
          (and gptel-buf (buffer-live-p gptel-buf)
               (boundp 'my/gptel--tool-reasoning-alist)
               (buffer-local-value 'my/gptel--tool-reasoning-alist gptel-buf)))
         (repaired 0))
    (when (and reasoning-key messages
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
              (let* ((tc (seq-elt tool-calls j))
                     (func (plist-get tc :function))
                     (name (and func (plist-get func :name))))
                (when name
                  (puthash name t used-names)))))))
      ;; Only filter if we found any used tools (safety: don't send empty tools)
      (when (> (hash-table-count used-names) 0)
        (let* ((original-count (length data-tools))
               ;; Filter serialized tools vector directly (cl-remove-if-not preserves sequence type)
               (filtered (cl-remove-if-not
                          (lambda (tool-plist)
                            (let* ((func (plist-get tool-plist :function))
                                   (name (and func (plist-get func :name))))
                              (gethash name used-names)))
                          data-tools))
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

Removes message content from older messages (beyond
`my/gptel-truncate-old-messages-keep'), replacing with a truncation marker.
Keeps the message structure intact for API compatibility.

Returns the number of messages truncated, or 0 if nothing was done."
  (if (null my/gptel-truncate-old-messages-keep)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (keep my/gptel-truncate-old-messages-keep)
           (truncated 0)
           (truncation-text "[Earlier conversation truncated to reduce payload size]"))
      (when (and (vectorp messages) (> (length messages) keep))
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

(defun my/gptel--message-role-p (msg role)
  "Return non-nil if MSG has ROLE.
ROLE is a string like \"tool\", \"assistant\", \"user\", etc.
Handles nil MSG gracefully (returns nil).
ASSUMPTION: Role values are strings, compared with `equal'."
  (and msg (equal (plist-get msg :role) role)))

(defun my/gptel--collect-message-indices (messages predicate)
  "Collect indices of messages in MESSAGES vector matching PREDICATE.
PREDICATE is a function that takes a message plist and returns non-nil if it matches.
Returns a list of indices in ascending order, or nil if PREDICATE is not a function.
ASSUMPTION: PREDICATE is a valid function; nil or non-function returns nil immediately.
EDGE CASE: Non-function predicate returns nil (no runtime error)."
  (when (and (functionp predicate)
             (vectorp messages)
             (> (length messages) 0))
    (cl-loop for i from 0 below (length messages)
             for msg = (aref messages i)
             when (funcall predicate msg)
             collect i)))

(defun my/gptel--strip-images-from-messages (info)
  "Strip image content from all messages in INFO to reduce payload.
Removes :image_url parts from multimodal message content arrays.
Base64 images can easily exceed 1MB each.

ASSUMPTION: Content can be string (text-only), vector, or list of parts.
  JSON deserialization may produce either vectors or lists for arrays.
BEHAVIOR: Works directly with sequence type (vector or list),
  filters out image_url parts, preserves text parts.
EDGE CASE: Empty content or non-sequence content is skipped safely.
EDGE CASE: Content that becomes empty after filtering is preserved as empty vector.

Returns the number of image parts removed, or 0 if nothing was done."
  (let* ((data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (removed 0)
         (image-p
          (lambda (part)
            (and (sequencep part)
                 (not (stringp part))
                 (let ((type (if (listp part)
                                 (plist-get part :type)
                               (cl-loop for i from 0 below (1- (length part)) by 2
                                        when (eq (aref part i) :type)
                                        return (aref part (1+ i))))))
                   (equal type "image_url"))))))
    (when (and messages (> (length messages) 0))
      (dotimes (i (length messages))
        (let* ((msg (aref messages i))
               (content (plist-get msg :content)))
          (when (and content (sequencep content) (not (stringp content)) (> (length content) 0))
            (let ((original-length (length content))
                  (filtered (cl-remove-if image-p content)))
              (when (< (length filtered) original-length)
                (cl-incf removed (- original-length (length filtered)))
                (plist-put msg :content filtered)))))))
    removed))

;; --- Constants for Transient Error Detection ---
;; Extracted patterns for testability and maintainability.
;; ASSUMPTION: These patterns classify errors as transient (retryable) vs permanent.
;; TEST: Each constant can be tested independently with string-match-p.

(defconst my/gptel--transient-error-string-patterns
  "Malformed JSON\\|Could not parse HTTP\\|json-read-error\\|Empty reply\\|Timeout\\|timeout\\|curl: (28)\\|curl: (6)\\|curl: (7)\\|exit code 28\\|exit code 6\\|exit code 7\\|Bad Gateway\\|Service Unavailable\\|Gateway Timeout\\|Connection refused\\|Could not resolve host\\|Overloaded\\|overloaded\\|Too Many Requests\\|InvalidParameter\\|function\\.arguments\\|1013\\|server is initializing"
  "Regex pattern for transient error messages in string form.
Matches network failures, curl errors, gateway errors, model-side bugs, and API cold starts.")

(defconst my/gptel--transient-http-statuses
  '(408 429 500 502 503 504)
  "HTTP status codes indicating transient errors safe to retry.
408: Request Timeout
429: Too Many Requests (rate limit)
500-504: Server errors (Internal, Bad Gateway, Unavailable, Gateway Timeout)")

(defconst my/gptel--transient-http-400-patterns
  "InvalidParameter\\|function\\.arguments\\|must be in JSON"
  "Regex pattern for HTTP 400 errors that are model-side bugs (retryable).
These indicate malformed tool arguments generated by the model, not user errors.")

(defconst my/gptel--transient-error-message-patterns
  "overloaded\\|too many requests\\|rate limit\\|timeout\\|free usage limit\\|access_terminated_error\\|reached your usage limit\\|quota will be refreshed in the next cycle\\|server is initializing\\|1013"
  "Regex pattern for transient errors in plist :message field.
Matched case-insensitively against error message text.")

(defconst my/gptel--auth-failure-statuses
  '(401 403)
  "HTTP status codes indicating permanent auth failures (not retryable).
401: Unauthorized (invalid API key)
403: Forbidden (access denied)")

(defun my/gptel--extract-error-message (error-data)
  "Extract error message string from ERROR-DATA.
ERROR-DATA can be a string, plist, or alist.
Returns the message string if found, nil otherwise.
ASSUMPTION: Error messages can be in :message (plist) or 'message (alist) keys."
  (cond
    ((stringp error-data) error-data)
    ((listp error-data)
     (or (plist-get error-data :message)
         (cdr (assq 'message error-data))))
    (t nil)))

(defun my/gptel--transient-error-p (error-data http-status)
  "Return non-nil if ERROR-DATA or HTTP-STATUS indicate a transient API error.
Matches network failures, overload responses, rate limits, and common
curl error codes that are safe to retry with backoff.
Also retries model-side bugs like malformed tool arguments.

ASSUMPTION: HTTP status codes 408, 429, 500-504 are transient and safe to retry.
ASSUMPTION: Error messages containing 'Malformed JSON', 'timeout', 'Overloaded',
  'Too Many Requests' indicate temporary failures, not permanent errors.
ASSUMPTION: HTTP 400 with 'InvalidParameter' or 'function.arguments' errors
  are model-side bugs (not user errors) and should be retried.

BEHAVIOR: Checks both string error messages and numeric HTTP status codes.
  Returns t if ANY match is found (OR logic for maximum coverage).

EDGE CASE: error-data can be string, plist, or nil. Handles all three.
EDGE CASE: http-status can be string, number, or t (curl success). Converts
  strings to numbers, ignores t.
EDGE CASE: Misleading success codes can still accompany application-level
  transient errors after the FSM has already entered `ERRS', so plist message
  patterns are checked for any status except known auth failures
  (see `my/gptel--auth-failure-statuses').
EDGE CASE: Pattern variables may be nil during load order issues; guards prevent errors.

TEST: (my/gptel--transient-error-p \"Malformed JSON\" 500) => t
TEST: (my/gptel--transient-error-p \"Invalid API key\" 401) => nil
TEST: (my/gptel--transient-error-p nil 429) => t"
  (let* ((status (cond
                  ((stringp http-status) (string-to-number http-status))
                  ((numberp http-status) http-status)
                  (t nil)))
         (error-msg (my/gptel--extract-error-message error-data))
         (string-pattern (and (boundp 'my/gptel--transient-error-string-patterns)
                              (stringp my/gptel--transient-error-string-patterns)
                              my/gptel--transient-error-string-patterns))
         (http-400-pattern (and (boundp 'my/gptel--transient-http-400-patterns)
                                (stringp my/gptel--transient-http-400-patterns)
                                my/gptel--transient-http-400-patterns))
         (msg-pattern (and (boundp 'my/gptel--transient-error-message-patterns)
                          (stringp my/gptel--transient-error-message-patterns)
                          my/gptel--transient-error-message-patterns)))
    (or (and (stringp error-data)
             string-pattern
             (string-match-p string-pattern (downcase error-data)))
        (and (symbolp error-data)
             string-pattern
             (string-match-p string-pattern (downcase (symbol-name error-data))))
        (and (numberp status) (memq status my/gptel--transient-http-statuses))
        (and (numberp status)
             (= status 400)
             (listp error-data)
             (stringp error-msg)
             http-400-pattern
             (string-match-p http-400-pattern error-msg))
        (and (listp error-data)
             (stringp error-msg)
             (or (null status) (not (memq status my/gptel--auth-failure-statuses)))
             msg-pattern
             (string-match-p msg-pattern (downcase error-msg))))))

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

(defun my/gptel--format-error-message (error-data http-status)
  "Format error message from ERROR-DATA and HTTP-STATUS.
Extracts message from plist/alist when error-data is not a string."
  (or (my/gptel--extract-error-message error-data)
      (if (and http-status (not (eq http-status t)))
          (format "HTTP %s" http-status)
        "Transient API Error")))

(defun my/gptel--headless-auto-workflow-agent-buffer-p (info)
  "Return non-nil when INFO belongs to a headless auto-workflow agent buffer."
  (let ((buf (and (listp info) (plist-get info :buffer))))
    (and (bound-and-true-p gptel-auto-workflow--headless)
         (bound-and-true-p gptel-auto-workflow-persistent-headless)
         (buffer-live-p buf)
         (string-prefix-p "*gptel-agent:" (buffer-name buf)))))

(defun my/gptel--apply-trim-with-logging (info trim-fn fmt)
  "Apply TRIM-FN to INFO and log result using FMT if items were trimmed.
TRIM-FN should take INFO and return the number of items trimmed.
FMT is a format string that receives the count as its single argument.
Returns the number of items trimmed."
  (when (functionp trim-fn)
    (let ((count (or (funcall trim-fn info) 0)))
      (when (> count 0)
        (message fmt count))
      count)))

(defun my/gptel-auto-retry (orig-fn machine &optional new-state)
  "Intercept FSM transitions to ERRS and retry the request if transient.

Implements OpenCode-style exponential backoff for network/overload errors.
Skips retries for subagent FSMs (they have their own timeout handler).

ORIG-FN is the original `gptel--fsm-transition' function.
MACHINE is the gptel FSM instance.
NEW-STATE is the target state (defaults to next state in MACHINE).

ASSUMPTION: FSM in ERRS state with transient error should retry, not fail.
ASSUMPTION: Exponential backoff (4s, 8s, 16s, 30s cap) prevents API overload.
ASSUMPTION: my/gptel-max-retries=3 prevents doom-loops from context overflow.

BEHAVIOR: On transient error:
  1. Clean up partial buffer insertions (prevent corruption)
  2. Reset FSM state to WAIT (triggers fresh request)
  3. Increment retry counter
  4. Apply progressive payload trimming (tool results, reasoning, tools)
  5. Schedule async retry with exponential backoff delay
  6. Return nil to abort ERRS transition (timer takes over)

BEHAVIOR: On non-transient error or max retries exceeded:
  - Call original function to proceed to ERRS state (fail normally)

EDGE CASE: Subagent FSMs detected by handler mismatch — never retry them.
EDGE CASE: my/gptel-max-retries=nil means retry indefinitely (capped at 30s delay).
EDGE CASE: Partial insertion cleanup requires both :position and :tracking-marker
  to be live markers in the same buffer, with start <= tracking.

WISDOM: Progressive trimming adapts to severity:
  - Retry 1: Light trim (keep recent tool results)
  - Retry 2+: Aggressive (strip reasoning, reduce tools, truncate all)
  This balances payload reduction with context preservation.

TEST: Verify with network failure simulation — should retry 3 times with
  increasing delays, then fail. Check message buffer for retry logs."
  (unless new-state (setq new-state (gptel--fsm-next machine)))
  (let* ((info (gptel-fsm-info machine))
         ;; Guard: ensure info is a proper list before accessing with plist-get
         (disable-auto-retry (and (listp info) (plist-get info :disable-auto-retry)))
         (headless-agent-buffer-p
          (and (listp info) (my/gptel--headless-auto-workflow-agent-buffer-p info)))
         (error-data (and (listp info) (plist-get info :error)))
         (http-status (and (listp info) (plist-get info :http-status)))
         (retries (if (listp info) (or (plist-get info :retries) 0) 0))
         ;; Detect subagent FSMs: they use custom handlers and should not be
         ;; retried (the parent's timeout handles failures).
         ;; A request is retryable if its handlers are one of the "main"
         ;; handler sets: gptel-send--handlers (interactive),
         ;; gptel-request--handlers (programmatic), or
         ;; gptel-agent-request--handlers (agent mode).
         (handlers (gptel-fsm-handlers machine))
         (subagent-p (not (or (eq handlers gptel-send--handlers)
                              (eq handlers gptel-request--handlers)
                              (and (boundp 'gptel-agent-request--handlers)
                                   (eq handlers gptel-agent-request--handlers))))))
    (if (and (eq new-state 'ERRS)
             (not disable-auto-retry)
             (not headless-agent-buffer-p)
             (not subagent-p)
             (or (null my/gptel-max-retries) (< retries my/gptel-max-retries))
             (my/gptel--transient-error-p error-data http-status))
        (let* ((delay (my/gptel--retry-delay retries))
               (error-msg (my/gptel--format-error-message error-data http-status)))
          (if my/gptel-max-retries
              (message "gptel: API failed with '%s'. Retrying (%d/%d) in %.1fs..."
                       error-msg (1+ retries) my/gptel-max-retries delay)
            (message "gptel: API failed with '%s'. Retrying (Attempt %d) in %.1fs..."
                     error-msg (1+ retries) delay))
          
          ;; Clean up partial buffer insertions if any.
          (my/gptel--cleanup-partial-insertion info)

          ;; Progressive payload trimming before retry (before incrementing retries).
          ;; Tool results: keep count decreases with each retry
          ;;   retry 0 → keep max(0, default-0), retry 1 → keep max(0, default-1), retry 2+ → keep 0
          ;; Reasoning content: stripped on retry 2+ to reclaim space
          ;; from accumulated chain-of-thought text.
          ;; Tools array: reduced on retry 2+ to only tools actually
          ;; used in the conversation, removing ~60-80% of definitions.
          (let ((trimmed (my/gptel--trim-tool-results-for-retry info retries)))
            (when (> trimmed 0)
              (message "gptel: Trimmed %d old tool result(s) to reduce payload (retry %d, keeping %d recent)"
                       trimmed retries
                       (max 0 (- (or my/gptel-retry-keep-recent-tool-results 0) retries))))
            (when (>= retries 2)
              (my/gptel--apply-trim-with-logging
               info #'my/gptel--trim-reasoning-content
               "gptel: Stripped reasoning_content from %d assistant message(s)")
              (my/gptel--apply-trim-with-logging
               info #'my/gptel--reduce-tools-for-retry
               "gptel: Removed %d unused tool definition(s) from payload")
              (my/gptel--apply-trim-with-logging
               info #'my/gptel--repair-thinking-tool-call-messages
               "gptel: Restored empty reasoning field on %d tool-call message(s)")))

          ;; Reset FSM state to WAIT and increment retry counter
          (plist-put info :error nil)
          (plist-put info :status nil)
          (plist-put info :http-status nil)
          (plist-put info :retries (1+ retries))

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

(defun my/gptel--run-compaction-pass (info pass-num bytes-limit bytes-var trimmed-total-var pass-var trim-fn &optional pass-msg)
  "Execute a single compaction pass in `my/gptel--compact-payload'.

INFO is the FSM info plist with :data containing messages.
PASS-NUM is the pass number (1-7) for logging.
BYTES-LIMIT is the maximum allowed payload size.
BYTES-VAR is a symbol bound to the current byte count (modified in-place).
TRIMMED-TOTAL-VAR is a symbol bound to total items trimmed (modified in-place).
PASS-VAR is a symbol bound to last executed pass number (modified in-place).
TRIM-FN is a function of one argument (INFO) that returns items trimmed.
PASS-MSG is a format string for logging when items were trimmed (gets `n' and `new-bytes' as args).

Returns t if still over limit after pass, nil otherwise.
BEHAVIOR: Only executes if still over BYTES-LIMIT. Updates byte tracking,
  trimmed total, and pass number variables. Logs progress.
EDGE CASE: TRIM-FN may return nil or 0 — handled gracefully."
  (when (> (symbol-value bytes-var) bytes-limit)
    (let* ((trim-fn-resolved
            (cond
             ((symbolp trim-fn) (symbol-function trim-fn))
             ((functionp trim-fn) trim-fn)
             ((and (consp trim-fn) (eq (car trim-fn) 'function))
              (cadr trim-fn))
             (t (error "gptel: compaction pass %d: trim-fn must be a function, got: %S"
                       pass-num trim-fn))))
           (n (or (funcall trim-fn-resolved info) 0)))
      (cl-incf (symbol-value trimmed-total-var) n)
      (set bytes-var (my/gptel--estimate-payload-bytes info))
      (set pass-var pass-num)
      (when (and pass-msg (> n 0))
        (message pass-msg n (/ (symbol-value bytes-var) 1024))))
    (> (symbol-value bytes-var) bytes-limit)))

(defconst my/gptel-model-context-bytes
  '(("kimi-k2.5"          . 400000)   ; 131K tokens ≈ 460KB, leave room for output
    ("kimi-for-coding"    . 400000)
    ("qwen3.5-plus"       . 400000)   ; 131K tokens
    ("qwen3-coder-next"   . 400000)
    ("qwen3-coder-plus"   . 3000000)  ; 1M tokens ≈ 3.5MB, leave room for output
    ("qwen3-max-2026-01-23" . 400000)
    ("glm-5"              . 350000)   ; 128K tokens
    ("glm-4.7"            . 350000)
    ("MiniMax-M2.5"       . 300000)
    ("deepseek-v4-flash"  . 3000000)  ; 1M tokens ≈ 3.5MB, leave room for output
    ("deepseek-v4-pro"    . 3000000)
    ("deepseek-chat"      . 3000000)
    ("deepseek-reasoner"  . 3000000))
  "Approximate max JSON byte size per model.

Computed as context window × ~3.5 bytes/token, minus output reservation.
Used as fallback when `my/gptel-payload-byte-limit' would be too generous
for a smaller-context model.")

(defun my/gptel--estimate-payload-bytes (info)
  "Estimate the JSON byte size of INFO's :data payload.

Uses `json-serialize' for accuracy.  Returns 0 if :data is nil or serialization fails."
  (let ((data (plist-get info :data)))
    (if data
        (condition-case err
            (string-bytes (gptel--json-encode data))
          (error
           (when gptel-log-level
             (message "gptel: payload estimation failed: %s" (error-message-string err)))
           0))
      0)))

(defun my/gptel--effective-byte-limit (info)
  "Return the byte limit to use for INFO's request.
Takes the minimum of `my/gptel-payload-byte-limit' and the model-specific
context limit from `my/gptel-model-context-bytes'.

ASSUMPTION: Model names may include version/date suffixes (e.g., \"kimi-k2.5-20250711\").
  Uses prefix matching to map variant names to their family limits.
EDGE CASE: Unknown models fall back to `my/gptel--unbounded-byte-limit'."
  (let* ((model (plist-get info :model))
         (global-limit (or my/gptel-payload-byte-limit my/gptel--unbounded-byte-limit))
         (model-limit
          (if (stringp model)
              (or (cl-loop for (pattern . limit) in my/gptel-model-context-bytes
                           when (string-prefix-p pattern model)
                           return limit)
                  my/gptel--unbounded-byte-limit)
            my/gptel--unbounded-byte-limit)))
    (min global-limit model-limit)))

(defconst my/gptel--compaction-passes
  `((1 ,(lambda (i) (my/gptel--trim-tool-results-for-retry i 1 t))
        "gptel: Pass 1: trimmed %d tool result(s), now %dKB")
    (2 ,(lambda (i) (my/gptel--trim-gemini-function-responses-for-retry i 1 t))
       "gptel: Pass 2: trimmed %d Gemini function response(s), now %dKB")
    (3 my/gptel--trim-reasoning-content
       "gptel: Pass 3: stripped reasoning from %d message(s), now %dKB")
    (4 my/gptel--reduce-tools-for-retry
       "gptel: Pass 4: removed %d unused tool def(s), now %dKB")
    (5 ,(lambda (_info)
           (and (fboundp 'my/gptel--trim-context-images)
                (my/gptel--trim-context-images)))
       "gptel: Pass 5: trimmed %d context image(s), now %dKB")
    (6 ,(lambda (i) (my/gptel--trim-tool-results-for-retry i 3 t))
       "gptel: Pass 6: truncated %d remaining tool results, now %dKB")
    (7 ,(lambda (i) (my/gptel--trim-gemini-function-responses-for-retry i 3 t))
       "gptel: Pass 7: truncated %d remaining Gemini function response(s), now %dKB")
    (8 my/gptel--truncate-old-messages
       "gptel: Pass 8: truncated %d old message(s), now %dKB")
    (9 my/gptel--strip-images-from-messages
       "gptel: Pass 9: stripped %d image(s) from messages, now %dKB"))
  "Ordered list of compaction passes for `my/gptel--compact-payload'.
Each entry is (PASS-NUM TRIM-FN LOG-FMT).
Passes execute sequentially until payload drops below limit.
ASSUMPTION: Passes are ordered from least to most destructive.")

(defun my/gptel--compact-payload (fsm)
  "Proactively trim FSM's payload if it exceeds byte limits.
Called as :before advice on `gptel-curl-get-response'.

Only runs on the first attempt (retries=0) — retry trimming handles
subsequent attempts via `my/gptel-auto-retry'.

Applies trimming progressively until under limit or nothing left to trim:
  1. Trim old OpenAI-style tool results
  2. Trim old Gemini-style function responses
  3. Strip reasoning_content
  4. Reduce tools array to only used tools
  5. Trim context images (oldest first)
  6. Aggressive OpenAI-style tool result trim
  7. Aggressive Gemini-style function response trim
  8. Truncate old user/assistant messages
  9. Strip images from multimodal messages (last resort)

ASSUMPTION: Payload estimation via json-serialize is accurate enough for
  compaction decisions. Estimation errors are logged but don't block.
ASSUMPTION: Model-specific context limits (my/gptel-model-context-bytes)
  are more precise than global limit for known models.
ASSUMPTION: Progressive passes (1-9) are ordered by least-to-most destructive.

BEHAVIOR: Estimates payload size, compares to effective byte limit
  (min of global and model-specific). If over limit, applies 9 passes
  of increasingly aggressive trimming until under limit or exhausted.

BEHAVIOR: Repairs thinking-enabled model messages BEFORE compaction to
  ensure all tool-call messages have reasoning_content field (required
  by Moonshot API even if empty).

EDGE CASE: my/gptel-payload-byte-limit=nil disables pre-send compaction.
EDGE CASE: Estimation errors (json-serialize fails) return 0 bytes,
  skipping compaction (safe fallback).
EDGE CASE: Pass 5 (context images) requires my/gptel--trim-context-images
  from gptel-ext-context-images — gracefully skips if unavailable.

WISDOM: 9-pass progressive approach minimizes context loss:
  - Pass 1-4: Remove redundant data (old results, unused tools)
  - Pass 5-7: Remove expensive media and remaining tool outputs
  - Pass 8-9: Nuclear option (truncate conversation, strip all images)
  Each pass re-estimates size, stopping early if under limit.

TEST: Create payload >200KB, verify compaction runs and reduces size.
  Check message log for pass-by-pass progress reports."
  (when my/gptel-payload-byte-limit
    (let* ((info (gptel-fsm-info fsm))
           (retries (or (plist-get info :retries) 0)))
      (when (= retries 0)
        (let ((limit (my/gptel--effective-byte-limit info))
              (repaired (my/gptel--repair-thinking-tool-call-messages info)))
          (when (> repaired 0)
            (message "gptel: Repaired reasoning field on %d tool-call message(s) before compaction" repaired))
          (cl-progv
              '(bytes trimmed-total pass)
              (list (my/gptel--estimate-payload-bytes info) 0 0)
            (when (> bytes limit)
              (message "gptel: Payload %dKB exceeds %dKB limit, compacting..."
                       (/ bytes 1024) (/ limit 1024))
              (let ((my/gptel-retry-keep-recent-tool-results
                     (if (null my/gptel-retry-keep-recent-tool-results)
                         2
                       my/gptel-retry-keep-recent-tool-results)))
                (cl-loop for (pass-num trim-fn log-fmt) in my/gptel--compaction-passes
                         while (> bytes limit)
                         do (my/gptel--run-compaction-pass
                             info pass-num limit 'bytes 'trimmed-total 'pass
                             trim-fn log-fmt)))
              (if (> bytes limit)
                  (message "gptel: WARNING: Payload still %dKB after %d passes of compaction (limit %dKB)"
                           (/ bytes 1024) pass (/ limit 1024))
                (message "gptel: Compaction complete: %d items trimmed across %d pass(es), payload now %dKB"
                         trimmed-total pass (/ bytes 1024))))))))))

(advice-add 'gptel-curl-get-response :before #'my/gptel--compact-payload)

(defun my/gptel--process-name-safe (process)
  "Return PROCESS name, tolerating nil or dead processes."
  (if (processp process)
      (process-name process)
    "<unknown>"))

(defun my/gptel--curl-sentinel-protect-quit (orig process status)
  "Run curl sentinel ORIG for PROCESS and STATUS without leaking `quit'.
Process sentinels run asynchronously.  A raw `quit' from the request callback
aborts gptel's sentinel before it can remove the request from
`gptel--request-alist', delete the curl process, and kill its buffer."
  (let* ((request (and (processp process)
                       (boundp 'gptel--request-alist)
                       (alist-get process gptel--request-alist)))
         (fsm (car-safe request))
         (info (and fsm (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
         (callback (and (consp info) (plist-get info :callback)))
         (wrapped nil))
    (unwind-protect
        (condition-case err
            (progn
              (when callback
                (setq wrapped t)
                (plist-put
                 info :callback
                 (lambda (&rest args)
                   (condition-case callback-err
                       (apply callback args)
                     (quit
                      (plist-put info :error
                                 (format "Callback quit: %s"
                                         (error-message-string callback-err)))
                      (plist-put info :status "Callback quit")
                      (message "gptel: suppressed quit in curl callback for %s: %s"
                               (my/gptel--process-name-safe process)
                               (error-message-string callback-err))
                      nil)))))
              (funcall orig process status))
          (quit
           (message "gptel: suppressed quit in curl sentinel for %s: %s"
                    (my/gptel--process-name-safe process)
                    (error-message-string err))))
      (when wrapped
        (plist-put info :callback callback)))))

(with-eval-after-load 'gptel-request
  (advice-add 'gptel-curl--sentinel
              :around #'my/gptel--curl-sentinel-protect-quit)
  (advice-add 'gptel-curl--stream-cleanup
              :around #'my/gptel--curl-sentinel-protect-quit))

(provide 'gptel-ext-retry)
;;; gptel-ext-retry.el ends here
