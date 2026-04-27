;;; test-gptel-trim.el --- ERT tests for progressive payload trimming -*- lexical-binding: t; no-byte-compile: t; -*-

;; Tests for test-trim--trim-tool-results-for-retry and
;; test-trim--trim-reasoning-content in gptel-ext-core.el.

(require 'ert)
(require 'cl-lib)
(require 'seq)

;;; ---- Stubs for the defcustom variables ----

(defvar test-trim--retry-keep-recent-tool-results 2
  "Test stub for the defcustom.")

(defvar test-trim--retry-truncated-result-text
  "[Content truncated to reduce context size for retry]"
  "Test stub for the defcustom.")

(defvar test-trim--reasoning-keep-turns 1
  "Test stub for the defcustom. Number of recent reasoning turns to preserve.")

(defvar test-trim--trim-min-bytes 0
  "Test stub for the defcustom. Set to 0 in tests to always trim.")

;;; ---- Load the functions under test ----
;; We eval the function definitions directly to avoid requiring the full
;; gptel-ext-core.el which has heavy dependencies.

(defun test-trim--trim-tool-results-for-retry (info)
  "Trim old tool-result content in INFO's :data :messages to reduce payload.
Progressive trimming based on :retries in INFO."
  (if (null test-trim--retry-keep-recent-tool-results)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (retries (or (plist-get info :retries) 1))
           (keep (max 0 (- test-trim--retry-keep-recent-tool-results retries)))
           (replacement test-trim--retry-truncated-result-text)
           (truncated 0)
           (bytes-saved 0))
      (when (and messages (> (length messages) 0))
        (let ((tool-indices '()))
          (dotimes (i (length messages))
            (let ((msg (aref messages i)))
              (when (equal (plist-get msg :role) "tool")
                (push i tool-indices))))
          (setq tool-indices (nreverse tool-indices))
          (when (> (length tool-indices) keep)
            (let ((to-truncate (seq-take tool-indices (- (length tool-indices) keep))))
              (dolist (idx to-truncate)
                (let* ((msg (aref messages idx))
                       (content (plist-get msg :content)))
                  (when (and (stringp content)
                             (> (length content) (length replacement)))
                    (cl-incf bytes-saved (- (length content) (length replacement))))))
              (when (or (= test-trim--trim-min-bytes 0)
                         (>= bytes-saved test-trim--trim-min-bytes))
                (dolist (idx to-truncate)
                  (let* ((msg (aref messages idx))
                         (content (plist-get msg :content)))
(when (and (stringp content)
                               (> (length content) (length replacement)))
                      (plist-put msg :content replacement)
                      (cl-incf truncated)))))))))
      truncated)))

(defun test-trim--trim-reasoning-content (info)
  "Strip reasoning_content from older assistant messages in INFO.
Preserves N most recent reasoning blocks where N is `test-trim--reasoning-keep-turns'."
  (if (null test-trim--reasoning-keep-turns)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (keep test-trim--reasoning-keep-turns)
           (stripped 0))
      (when (and messages (> (length messages) 0))
        (let ((reasoning-indices '()))
          (dotimes (i (length messages))
            (let ((msg (aref messages i)))
              (when (and (equal (plist-get msg :role) "assistant")
                         (not (plist-get msg :tool_calls))
                         (plist-get msg :reasoning_content)
                         (not (equal "" (plist-get msg :reasoning_content))))
                (push i reasoning-indices))))
          (setq reasoning-indices (nreverse reasoning-indices))
          (when (> (length reasoning-indices) keep)
            (let ((to-strip (seq-take reasoning-indices
                                      (- (length reasoning-indices) keep))))
              (dolist (idx to-strip)
                (let ((msg (aref messages idx)))
                  (plist-put msg :reasoning_content "")
                  (cl-incf stripped)))))))
      stripped)))

(defun test-trim--reasoning-key-for-model (model &optional _backend)
  "Test stub: return the reasoning key for MODEL."
  (when (stringp model)
    (setq model (intern model)))
  (pcase model
    ('kimi-k2\.5 :reasoning_content)
    ('moonshot :reasoning_content)
    ('deepseek-v4-pro :reasoning_content)
    (_ nil)))

(defvar-local test-trim--tool-reasoning-alist nil
  "Test stub buffer-local reasoning store.")

(defun test-trim--valid-reasoning-value-p (value)
  "Test stub: return non-nil when VALUE is a valid serialized reasoning field."
  (stringp value))

(defun test-trim--fallback-reasoning-value (tool-calls reasoning-alist)
  "Test stub: return stored reasoning for TOOL-CALLS, or empty string."
  (let* ((tc (and (vectorp tool-calls)
                  (> (length tool-calls) 0)
                  (aref tool-calls 0)))
         (id (and tc (plist-get tc :id)))
         (stored (if (and reasoning-alist id)
                     (alist-get id reasoning-alist :absent nil #'equal)
                   :absent)))
    (if (stringp stored) stored "")))

(defun test-trim--ensure-reasoning-on-messages (messages reasoning-key &optional reasoning-alist)
  "Test stub: ensure assistant tool-call messages carry a valid reasoning field."
  (let ((repaired 0))
    (seq-doseq (msg messages)
      (when (and (listp msg)
                 (equal (plist-get msg :role) "assistant")
                 (plist-get msg :tool_calls)
                 (let ((value (plist-get msg reasoning-key)))
                   (or (not (plist-member msg reasoning-key))
                       (not (test-trim--valid-reasoning-value-p value)))))
        (plist-put msg reasoning-key
                   (test-trim--fallback-reasoning-value
                    (plist-get msg :tool_calls) reasoning-alist))
        (cl-incf repaired)))
    repaired))

(defun test-trim--repair-thinking-tool-call-messages (info)
  "Ensure thinking-enabled assistant tool-call messages carry a reasoning field."
  (let* ((model (plist-get info :model))
         (backend (plist-get info :backend))
         (reasoning-key (test-trim--reasoning-key-for-model model backend))
         (data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
          (gptel-buf (plist-get info :buffer))
          (reasoning-alist
           (and gptel-buf (buffer-live-p gptel-buf)
               (buffer-local-value 'test-trim--tool-reasoning-alist gptel-buf)))
         (repaired 0))
    (when (and reasoning-key messages (> (length messages) 0))
      (setq repaired
            (test-trim--ensure-reasoning-on-messages
             messages reasoning-key reasoning-alist)))
    repaired))

;;; ---- Test helpers ----

(defun test--make-tool-msg (content)
  "Create a tool-result message plist with CONTENT."
  (list :role "tool" :tool_call_id (format "call_%d" (random 100000)) :content content))

(defun test--make-assistant-msg (&optional reasoning tool-calls)
  "Create an assistant message plist, optionally with REASONING and TOOL-CALLS."
  (let ((msg (list :role "assistant" :content "Some response text")))
    (when reasoning
      (plist-put msg :reasoning_content reasoning))
    (when tool-calls
      (plist-put msg :tool_calls tool-calls))
    msg))

(defun test--make-user-msg (content)
  "Create a user message plist."
  (list :role "user" :content content))

(defun test--make-info (messages &optional retries)
  "Create an INFO plist with MESSAGES vector and optional RETRIES count."
  (let ((info (list :data (list :messages (apply #'vector messages)))))
    (when retries
      (plist-put info :retries retries))
    info))

(defun test-trim--transient-error-p (error-data http-status)
  "Return non-nil if ERROR-DATA or HTTP-STATUS indicate a transient API error."
  (or (and (stringp error-data)
           (string-match-p "Malformed JSON\\|Could not parse HTTP\\|json-read-error\\|Empty reply\\|Timeout\\|timeout\\|curl: (28)\\|curl: (6)\\|curl: (7)\\|Bad Gateway\\|Service Unavailable\\|Gateway Timeout\\|Connection refused\\|Could not resolve host\\|Overloaded\\|overloaded\\|Too Many Requests" error-data))
      (and (numberp http-status) (memq http-status '(408 429 500 502 503 504)))
      (and (listp error-data)
           (string-match-p "overloaded\\|too many requests\\|rate limit\\|timeout\\|free usage limit"
                           (downcase (or (plist-get error-data :message) ""))))))

(defconst test--truncation-text
  "[Content truncated to reduce context size for retry]"
  "Expected truncation replacement text.")

;;; ===========================================================================
;;; Tool result trimming tests
;;; ===========================================================================

;;; ---- Basic behavior ----

(ert-deftest trim-tool-results/no-tool-messages ()
  "No tool messages → 0 truncated."
  (let ((info (test--make-info
               (list (test--make-user-msg "hello")
                     (test--make-assistant-msg))
               1)))
    (should (= 0 (test-trim--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/disabled-when-nil ()
  "Setting keep-recent to nil disables trimming entirely."
  (let ((test-trim--retry-keep-recent-tool-results nil)
        (info (test--make-info
               (list (test--make-tool-msg "big content here that is definitely long enough")
                     (test--make-tool-msg "another big result that should be long enough"))
               1)))
    (should (= 0 (test-trim--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/empty-messages ()
  "Empty messages vector → 0 truncated."
  (let ((info (test--make-info '() 1)))
    (should (= 0 (test-trim--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/nil-data ()
  "Nil :data → 0 truncated."
  (let ((info (list :data nil :retries 1)))
    (should (= 0 (test-trim--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/short-content-not-truncated ()
  "Content shorter than replacement text is not truncated."
  (let ((info (test--make-info
               (list (test--make-tool-msg "ok")
                     (test--make-tool-msg "ok")
                     (test--make-tool-msg "ok"))
               1)))
    ;; "ok" is shorter than the truncation text, so nothing should be truncated
    (should (= 0 (test-trim--trim-tool-results-for-retry info)))))

;;; ---- Progressive trimming: retry 1 (retries=1) ----

(ert-deftest trim-tool-results/retry-1-keeps-1-of-3 ()
  "Retry 1 with default=2: keep max(0, 2-1)=1 recent, truncate 2 of 3."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "first tool result with enough length to be truncated by the replacement"))
         (msg2 (test--make-tool-msg "second tool result with enough length to be truncated by replacement"))
         (msg3 (test--make-tool-msg "third tool result that is recent and should be kept intact because it is newest"))
         (info (test--make-info (list msg1 msg2 msg3) 1))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 2 result))
    ;; First two truncated
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    ;; Third (most recent) kept intact
    (should (string-match-p "third tool result" (plist-get (aref messages 2) :content)))))

(ert-deftest trim-tool-results/retry-1-keeps-1-of-2 ()
  "Retry 1 with default=2: keep 1 of 2 tool messages."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "old result with enough content length to be truncated properly"))
         (msg2 (test--make-tool-msg "recent result that should be kept intact because it is the newest one"))
         (info (test--make-info (list msg1 msg2) 1))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 1 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (string-match-p "recent result" (plist-get (aref messages 1) :content)))))

(ert-deftest trim-tool-results/retry-1-single-tool-kept ()
  "Retry 1 with default=2 and only 1 tool: nothing to truncate (1 <= keep=1)."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "only tool result, should be kept because count <= keep"))
         (info (test--make-info (list msg1) 1))
         (result (test-trim--trim-tool-results-for-retry info)))
    (should (= 0 result))))

;;; ---- Progressive trimming: retry 2 (retries=2) ----

(ert-deftest trim-tool-results/retry-2-keeps-0 ()
  "Retry 2 with default=2: keep max(0, 2-2)=0, truncate ALL."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "first tool result with enough length to definitely be truncated"))
         (msg2 (test--make-tool-msg "second tool result with enough length to definitely be truncated"))
         (msg3 (test--make-tool-msg "third most recent tool result also truncated because keep is zero"))
         (info (test--make-info (list msg1 msg2 msg3) 2))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 3 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 2) :content)))))

;;; ---- Progressive trimming: retry 3+ (retries=3) ----

(ert-deftest trim-tool-results/retry-3-keeps-0 ()
  "Retry 3 with default=2: keep max(0, 2-3)=0, truncate ALL."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "first tool result content that is long enough to be truncated"))
         (msg2 (test--make-tool-msg "second tool result content that is long enough to be truncated"))
         (info (test--make-info (list msg1 msg2) 3))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 2 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))))

;;; ---- Default retries value ----

(ert-deftest trim-tool-results/no-retries-defaults-to-1 ()
  "When :retries is missing from INFO, defaults to 1."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "old result content that is definitely long enough for truncation"))
         (msg2 (test--make-tool-msg "recent result content that should be kept intact as the newest"))
         ;; No :retries in info
         (info (test--make-info (list msg1 msg2)))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; retries defaults to 1, keep = max(0, 2-1) = 1
    (should (= 1 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (string-match-p "recent result" (plist-get (aref messages 1) :content)))))

;;; ---- Custom keep-recent values ----

(ert-deftest trim-tool-results/keep-3-retry-1 ()
  "With default=3 and retry 1: keep 2, truncate rest."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 3)
         (msgs (list
                (test--make-tool-msg "tool result 1 old enough to be truncated on retry one with keep three")
                (test--make-tool-msg "tool result 2 old enough to be truncated on retry one with keep three")
                (test--make-tool-msg "tool result 3 kept because it is within the recent two window")
                (test--make-tool-msg "tool result 4 kept because it is within the recent two window")))
         (info (test--make-info msgs 1))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; keep = max(0, 3-1) = 2, so truncate 2, keep 2
    (should (= 2 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (string-match-p "tool result 3" (plist-get (aref messages 2) :content)))
    (should (string-match-p "tool result 4" (plist-get (aref messages 3) :content)))))

;;; ---- Mixed message types ----

(ert-deftest trim-tool-results/mixed-messages-only-tools-affected ()
  "User and assistant messages are not touched, only tool messages."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (user-msg (test--make-user-msg "user input text"))
         (asst-msg (test--make-assistant-msg "thinking hard about this"))
         (tool1 (test--make-tool-msg "old tool result content that is long enough for truncation replacement"))
         (tool2 (test--make-tool-msg "recent tool content that should be kept intact as it is newest tool"))
         (info (test--make-info (list user-msg asst-msg tool1 user-msg tool2) 1))
         (result (test-trim--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; keep=1, 2 tool msgs, truncate 1
    (should (= 1 result))
    ;; User and assistant messages untouched
    (should (equal "user input text" (plist-get (aref messages 0) :content)))
    (should (equal "Some response text" (plist-get (aref messages 1) :content)))
    ;; tool1 (index 2) truncated, tool2 (index 4) kept
    (should (equal test--truncation-text (plist-get (aref messages 2) :content)))
    (should (string-match-p "recent tool" (plist-get (aref messages 4) :content)))))

;;; ---- Idempotence ----

(ert-deftest trim-tool-results/idempotent-on-already-truncated ()
  "Running trim again on already-truncated messages returns 0."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "old content that is long enough to be truncated by replacement text"))
         (msg2 (test--make-tool-msg "recent content that should be kept intact as it is newest tool msg"))
         (info (test--make-info (list msg1 msg2) 1)))
    ;; First trim
    (should (= 1 (test-trim--trim-tool-results-for-retry info)))
    ;; Second trim with same retries — already truncated, replacement not longer than itself
    (should (= 0 (test-trim--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/progressive-across-retries ()
  "Simulates escalating retries: retry 1 trims some, retry 2 trims rest."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msgs (list
                (test--make-tool-msg "tool result A with enough content to be truncated by the replacement text")
                (test--make-tool-msg "tool result B with enough content to be truncated by the replacement text")
                (test--make-tool-msg "tool result C the most recent one should be kept on first retry attempt")))
         (info (test--make-info msgs 1))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; Retry 1: keep=1, truncate 2
    (should (= 2 (test-trim--trim-tool-results-for-retry info)))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (string-match-p "tool result C" (plist-get (aref messages 2) :content)))
    ;; Retry 2: keep=0, truncate remaining 1
    (plist-put info :retries 2)
    (should (= 1 (test-trim--trim-tool-results-for-retry info)))
    (should (equal test--truncation-text (plist-get (aref messages 2) :content)))))

;;; ===========================================================================
;;; Reasoning content trimming tests
;;; ===========================================================================

(ert-deftest trim-reasoning/strips-reasoning-from-assistant-msgs ()
  "Strips reasoning_content from older assistant messages, keeping recent ones."
  (let* ((msg1 (test--make-assistant-msg "I'm thinking about the code structure"))
         (msg2 (test--make-assistant-msg "Analyzing the file contents carefully"))
         (msg3 (test--make-user-msg "user text"))
         (info (test--make-info (list msg1 msg2 msg3)))
         (result (test-trim--trim-reasoning-content info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 1 result))
    (should (equal "" (plist-get (aref messages 0) :reasoning_content)))
    (should (equal "Analyzing the file contents carefully"
                   (plist-get (aref messages 1) :reasoning_content)))
    (should (equal "Some response text" (plist-get (aref messages 0) :content)))
    (should (equal "Some response text" (plist-get (aref messages 1) :content)))))

(ert-deftest trim-reasoning/keeps-all-when-under-limit ()
  "When reasoning blocks <= keep count, none are stripped."
  (let* ((msg1 (test--make-assistant-msg "single reasoning block"))
         (info (test--make-info (list msg1)))
         (result (test-trim--trim-reasoning-content info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 0 result))
    (should (equal "single reasoning block"
                   (plist-get (aref messages 0) :reasoning_content)))))

(ert-deftest trim-reasoning/strip-all-when-keep-is-zero ()
  "When `test-trim--reasoning-keep-turns' is 0, strip all reasoning."
  (let* ((test-trim--reasoning-keep-turns 0)
         (msg1 (test--make-assistant-msg "thinking 1"))
         (msg2 (test--make-assistant-msg "thinking 2"))
         (info (test--make-info (list msg1 msg2)))
         (result (test-trim--trim-reasoning-content info)))
    (should (= 2 result))))

(ert-deftest trim-reasoning/disabled-when-nil ()
  "When `test-trim--reasoning-keep-turns' is nil, no trimming occurs."
  (let* ((test-trim--reasoning-keep-turns nil)
         (msg1 (test--make-assistant-msg "thinking"))
         (info (test--make-info (list msg1)))
         (result (test-trim--trim-reasoning-content info)))
    (should (= 0 result))))

(ert-deftest trim-reasoning/keep-2-turns ()
  "When `test-trim--reasoning-keep-turns' is 2, keep 2 most recent."
  (let* ((test-trim--reasoning-keep-turns 2)
         (msg1 (test--make-assistant-msg "thinking 1"))
         (msg2 (test--make-assistant-msg "thinking 2"))
         (msg3 (test--make-assistant-msg "thinking 3"))
         (msg4 (test--make-assistant-msg "thinking 4"))
         (info (test--make-info (list msg1 msg2 msg3 msg4)))
         (result (test-trim--trim-reasoning-content info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 2 result))
    (should (equal "" (plist-get (aref messages 0) :reasoning_content)))
    (should (equal "" (plist-get (aref messages 1) :reasoning_content)))
    (should (equal "thinking 3" (plist-get (aref messages 2) :reasoning_content)))
    (should (equal "thinking 4" (plist-get (aref messages 3) :reasoning_content)))))

(ert-deftest trim-reasoning/ignores-messages-without-reasoning ()
  "Assistant messages without reasoning_content are not counted toward keep limit.
With 1 reasoning block and keep=1, nothing is stripped."
  (let* ((msg1 (test--make-assistant-msg nil))
         (msg2 (test--make-assistant-msg "has reasoning content"))
         (info (test--make-info (list msg1 msg2)))
         (result (test-trim--trim-reasoning-content info)))
    (should (= 0 result))))

(ert-deftest trim-reasoning/ignores-non-assistant-messages ()
  "User and tool messages are not touched."
  (let* ((user-msg (test--make-user-msg "user text"))
         (tool-msg (test--make-tool-msg "tool result"))
         (info (test--make-info (list user-msg tool-msg)))
         (result (test-trim--trim-reasoning-content info)))
    (should (= 0 result))))

(ert-deftest trim-reasoning/empty-messages ()
  "Empty messages → 0 stripped."
  (let ((info (test--make-info '())))
    (should (= 0 (test-trim--trim-reasoning-content info)))))

(ert-deftest trim-reasoning/nil-data ()
  "Nil :data → 0 stripped."
  (let ((info (list :data nil)))
    (should (= 0 (test-trim--trim-reasoning-content info)))))

(ert-deftest trim-reasoning/idempotent ()
  "Running reasoning trim twice returns 0 on second run (already stripped)."
  (let* ((msg1 (test--make-assistant-msg "deep thoughts 1"))
         (msg2 (test--make-assistant-msg "deep thoughts 2"))
         (info (test--make-info (list msg1 msg2))))
    (should (= 1 (test-trim--trim-reasoning-content info)))
    (should (= 0 (test-trim--trim-reasoning-content info)))))

(ert-deftest trim-reasoning/repair-thinking-tool-call-message-with-empty-string ()
  "Thinking-enabled assistant tool-call messages keep an empty reasoning field."
  (let* ((tool-id "call_123")
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id tool-id :type "function"
                                                    :function (list :name "Read" :arguments "{}")))))
         (info (test--make-info (list assistant))))
    (plist-put info :model 'moonshot)
    (should (= 1 (test-trim--repair-thinking-tool-call-messages info)))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (plist-member (aref messages 0) :reasoning_content))
      (should (equal "" (plist-get (aref messages 0) :reasoning_content))))))

(ert-deftest trim-reasoning/repair-thinking-tool-call-message-from-buffer-store ()
  "Repair uses stored reasoning when available for tool-call history."
  (let* ((tool-id "call_456")
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id tool-id :type "function"
                                                    :function (list :name "Read" :arguments "{}")))))
         (info (test--make-info (list assistant))))
    (plist-put info :model 'moonshot)
    (with-temp-buffer
      (setq-local test-trim--tool-reasoning-alist `((,tool-id . "stored reasoning")))
      (plist-put info :buffer (current-buffer))
      (should (= 1 (test-trim--repair-thinking-tool-call-messages info))))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (equal "stored reasoning"
                     (plist-get (aref messages 0) :reasoning_content))))))

(ert-deftest trim-reasoning/repair-noop-for-non-thinking-models ()
  "Non-thinking models are left unchanged by repair pass."
  (let* ((assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id "call_789" :type "function"
                                                    :function (list :name "Read" :arguments "{}")))))
         (info (test--make-info (list assistant))))
    (plist-put info :model 'plain-model)
    (should (= 0 (test-trim--repair-thinking-tool-call-messages info)))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should-not (plist-member (aref messages 0) :reasoning_content)))))

(ert-deftest trim-reasoning/repair-thinking-tool-call-message-with-string-model ()
  "Thinking-model detection still works when INFO carries a string model name."
  (let* ((tool-id "call_string_model")
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id tool-id :type "function"
                                                    :function (list :name "Read" :arguments "{}")))))
         (info (test--make-info (list assistant))))
    (plist-put info :model "moonshot")
    (should (= 1 (test-trim--repair-thinking-tool-call-messages info)))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (plist-member (aref messages 0) :reasoning_content))
      (should (equal "" (plist-get (aref messages 0) :reasoning_content))))))

(ert-deftest trim-reasoning/repair-thinking-tool-call-message-with-null-sentinel ()
  "Null reasoning sentinel is normalized to an empty string."
  (let* ((tool-id "call_null")
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id tool-id :type "function"
                                                    :function (list :name "Read" :arguments "{}")))
                          :reasoning_content :null))
         (info (test--make-info (list assistant))))
    (plist-put info :model 'moonshot)
    (should (= 1 (test-trim--repair-thinking-tool-call-messages info)))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (equal "" (plist-get (aref messages 0) :reasoning_content))))))

(ert-deftest trim-reasoning/repair-thinking-tool-call-message-with-nil-value ()
  "Nil reasoning values are normalized to an empty string."
  (let* ((tool-id "call_nil")
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id tool-id :type "function"
                                                    :function (list :name "Read" :arguments "{}")))
                          :reasoning_content nil))
         (info (test--make-info (list assistant))))
    (plist-put info :model 'moonshot)
    (should (= 1 (test-trim--repair-thinking-tool-call-messages info)))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (equal "" (plist-get (aref messages 0) :reasoning_content))))))

;;; ===========================================================================
;;; Integration: progressive trimming + reasoning trim together
;;; ===========================================================================

(ert-deftest integration/retry-1-trims-tools-not-reasoning ()
  "Retry 1: tool results trimmed progressively, reasoning kept."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (msgs (list
                (test--make-assistant-msg "reasoning round 1")
                (test--make-tool-msg "tool 1 old result long enough for truncation by the replacement text string")
                (test--make-assistant-msg "reasoning round 2")
                (test--make-tool-msg "tool 2 recent result that should be kept intact on first retry attempt")))
         (info (test--make-info msgs 1))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; Retry 1: keep=1, truncate tool 1 only
    (let ((trimmed (test-trim--trim-tool-results-for-retry info)))
      (should (= 1 trimmed)))
    ;; Reasoning NOT stripped on retry 1
    (should (equal "reasoning round 1" (plist-get (aref messages 0) :reasoning_content)))
    (should (equal "reasoning round 2" (plist-get (aref messages 2) :reasoning_content)))))

(ert-deftest integration/retry-2-trims-all-tools-and-reasoning ()
  "Retry 2: all tool results truncated AND reasoning stripped."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (test-trim--reasoning-keep-turns 0)
         (msgs (list
                (test--make-assistant-msg "reasoning round 1")
                (test--make-tool-msg "tool 1 result content that is long enough for truncation by replacement")
                (test--make-assistant-msg "reasoning round 2")
                (test--make-tool-msg "tool 2 result content that is long enough for truncation by replacement")))
         (info (test--make-info msgs 2))
         (messages (plist-get (plist-get info :data) :messages)))
    (let ((trimmed (test-trim--trim-tool-results-for-retry info)))
      (should (= 2 trimmed)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 3) :content)))
    (let ((reasoning-stripped (test-trim--trim-reasoning-content info)))
      (should (= 2 reasoning-stripped)))
    (should (equal "" (plist-get (aref messages 0) :reasoning_content)))
    (should (equal "" (plist-get (aref messages 2) :reasoning_content)))))

(ert-deftest integration/full-progressive-sequence ()
  "Simulates a full retry sequence: 3 retries with escalating trimming."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (test-trim--reasoning-keep-turns 0)
         (make-fresh-msgs
          (lambda ()
            (list
             (test--make-assistant-msg "thinking 1")
             (test--make-tool-msg "tool A very long result content that needs to be truncated on retry attempt")
             (test--make-assistant-msg "thinking 2")
             (test--make-tool-msg "tool B another long result that also needs truncation on retry attempts")
             (test--make-assistant-msg "thinking 3")
             (test--make-tool-msg "tool C the most recent result that may or may not survive trimming")))))
    (let* ((info (test--make-info (funcall make-fresh-msgs) 1))
           (messages (plist-get (plist-get info :data) :messages)))
      (should (= 2 (test-trim--trim-tool-results-for-retry info)))
      (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
      (should (equal test--truncation-text (plist-get (aref messages 3) :content)))
      (should (string-match-p "tool C" (plist-get (aref messages 5) :content)))
      (should (equal "thinking 1" (plist-get (aref messages 0) :reasoning_content))))
    (let* ((info (test--make-info (funcall make-fresh-msgs) 2))
           (messages (plist-get (plist-get info :data) :messages)))
      (should (= 3 (test-trim--trim-tool-results-for-retry info)))
      (should (= 3 (test-trim--trim-reasoning-content info)))
      (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
      (should (equal test--truncation-text (plist-get (aref messages 3) :content)))
      (should (equal test--truncation-text (plist-get (aref messages 5) :content)))
      (should (equal "" (plist-get (aref messages 0) :reasoning_content)))
      (should (equal "" (plist-get (aref messages 2) :reasoning_content)))
      (should (equal "" (plist-get (aref messages 4) :reasoning_content))))
    (let* ((info (test--make-info (funcall make-fresh-msgs) 3))
           (messages (plist-get (plist-get info :data) :messages)))
      (should (= 3 (test-trim--trim-tool-results-for-retry info)))
      (should (= 3 (test-trim--trim-reasoning-content info))))))

(provide 'test-gptel-trim)

;;; ===========================================================================
;;; Tools array reduction tests
;;; ===========================================================================

;;; ---- Stubs for gptel-tool structs ----

;; Minimal gptel-tool struct stub for testing.  The real struct has many fields;
;; we only need `name' for our function.
(cl-defstruct (gptel-tool-stub (:constructor gptel-tool-stub-create))
  "Minimal stub for gptel-tool."
  name)

;; Local test implementation with unique name to avoid conflicts
(defun test-trim--reduce-tools-for-retry (info)
  "Reduce the tools array in INFO to only tools referenced in conversation."
  (let* ((data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (data-tools (and data (plist-get data :tools)))
         (struct-tools (plist-get info :tools))
         (used-names (make-hash-table :test #'equal))
         (removed 0))
    (when (and messages data-tools (> (length data-tools) 0))
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
      (when (> (hash-table-count used-names) 0)
        (let* ((original-count (length data-tools))
               (filtered (vconcat
                          (cl-remove-if-not
                           (lambda (tool-plist)
                             (let* ((func (plist-get tool-plist :function))
                                    (name (and func (plist-get func :name))))
                               (gethash name used-names)))
                           (append data-tools nil))))
               (new-count (length filtered)))
          (when (< new-count original-count)
            (plist-put data :tools filtered)
            (when struct-tools
              (plist-put info :tools
                         (cl-remove-if-not
                          (lambda (ts)
                            (gethash (gptel-tool-stub-name ts) used-names))
                          struct-tools)))
            (setq removed (- original-count new-count))))))
    removed))

;;; ---- Test helpers for tools reduction ----

(defun test--make-tool-def (name)
  "Create a serialized tool definition plist for tool NAME."
  (list :type "function"
        :function (list :name name
                        :description (format "Tool %s" name)
                        :parameters (list :type "object" :properties nil))))

(defun test--make-tool-struct (name)
  "Create a gptel-tool struct stub with NAME."
  (gptel-tool-stub-create :name name))

(defun test--make-tool-call (name &optional id)
  "Create a tool_call vector entry for tool NAME with optional ID."
  (list :id (or id (format "call_%d" (random 100000)))
        :type "function"
        :function (list :name name :arguments "{}")))

(defun test--make-assistant-with-tool-calls (tool-names)
  "Create an assistant message with tool_calls for each name in TOOL-NAMES."
  (let ((calls (vconcat (mapcar #'test--make-tool-call tool-names))))
    (list :role "assistant" :content nil :tool_calls calls)))

(defun test--make-tools-info (messages tool-def-names &optional struct-names)
  "Create an INFO plist with MESSAGES, tool definitions for TOOL-DEF-NAMES,
and optionally tool structs for STRUCT-NAMES (defaults to TOOL-DEF-NAMES)."
  (let* ((defs (vconcat (mapcar #'test--make-tool-def tool-def-names)))
         (structs (mapcar #'test--make-tool-struct (or struct-names tool-def-names)))
         (info (list :data (list :messages (apply #'vector messages)
                                 :tools defs)
                     :tools structs)))
    info))

;;; ---- Basic behavior ----

(ert-deftest reduce-tools/no-tool-calls-in-messages ()
  "No tool_calls in any message → 0 removed (don't remove everything)."
  (let* ((info (test--make-tools-info
                (list (test--make-user-msg "hello")
                      (test--make-assistant-msg))
                '("read_file" "write_file" "search"))))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))
    ;; Tools unchanged
    (should (= 3 (length (plist-get (plist-get info :data) :tools))))))

(ert-deftest reduce-tools/nil-data ()
  "Nil :data → 0 removed."
  (let ((info (list :data nil)))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))))

(ert-deftest reduce-tools/nil-tools ()
  "No :tools in :data → 0 removed."
  (let ((info (list :data (list :messages (vector (test--make-user-msg "hi"))
                                :tools nil))))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))))

(ert-deftest reduce-tools/empty-tools-vector ()
  "Empty tools vector → 0 removed."
  (let ((info (list :data (list :messages (vector (test--make-user-msg "hi"))
                                :tools []))))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))))

(ert-deftest reduce-tools/empty-messages ()
  "Empty messages → 0 removed."
  (let ((info (list :data (list :messages (vector)
                                :tools (vector (test--make-tool-def "foo"))))))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))))

;;; ---- Core filtering behavior ----

(ert-deftest reduce-tools/removes-unused-tools ()
  "Only tools referenced in tool_calls survive filtering."
  (let* ((asst (test--make-assistant-with-tool-calls '("read_file")))
         (tool-result (test--make-tool-msg "file contents"))
         (info (test--make-tools-info
                (list (test--make-user-msg "read foo.el")
                      asst
                      tool-result)
                '("read_file" "write_file" "search" "list_dir" "run_command"))))
    (should (= 4 (test-trim--reduce-tools-for-retry info)))
    (let ((remaining (plist-get (plist-get info :data) :tools)))
      (should (= 1 (length remaining)))
      (should (equal "read_file"
                     (plist-get (plist-get (aref remaining 0) :function) :name))))))

(ert-deftest reduce-tools/keeps-multiple-used-tools ()
  "Multiple tools called across rounds are all kept."
  (let* ((asst1 (test--make-assistant-with-tool-calls '("read_file" "search")))
         (tool1 (test--make-tool-msg "search results"))
         (tool2 (test--make-tool-msg "file contents"))
         (asst2 (test--make-assistant-with-tool-calls '("write_file")))
         (tool3 (test--make-tool-msg "wrote file"))
         (info (test--make-tools-info
                (list (test--make-user-msg "refactor")
                      asst1 tool1 tool2
                      asst2 tool3)
                '("read_file" "write_file" "search" "list_dir" "run_command" "git_status"))))
    (should (= 3 (test-trim--reduce-tools-for-retry info)))
    (let* ((remaining (plist-get (plist-get info :data) :tools))
           (names (mapcar (lambda (td) (plist-get (plist-get td :function) :name))
                          (append remaining nil))))
      (should (= 3 (length remaining)))
      (should (member "read_file" names))
      (should (member "write_file" names))
      (should (member "search" names)))))

(ert-deftest reduce-tools/all-tools-used-no-change ()
  "When all defined tools are referenced, nothing is removed."
  (let* ((asst (test--make-assistant-with-tool-calls '("read_file" "write_file")))
         (info (test--make-tools-info
                (list (test--make-user-msg "hi") asst)
                '("read_file" "write_file"))))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))))

(ert-deftest reduce-tools/single-tool-used-of-many ()
  "1 of 18 tools used → removes 17."
  (let* ((all-tools (cl-loop for i from 1 to 18
                             collect (format "tool_%d" i)))
         (asst (test--make-assistant-with-tool-calls '("tool_5")))
         (info (test--make-tools-info
                (list (test--make-user-msg "go") asst)
                all-tools)))
    (should (= 17 (test-trim--reduce-tools-for-retry info)))
    (let ((remaining (plist-get (plist-get info :data) :tools)))
      (should (= 1 (length remaining)))
      (should (equal "tool_5"
                     (plist-get (plist-get (aref remaining 0) :function) :name))))))

;;; ---- Struct list filtering ----

(ert-deftest reduce-tools/filters-struct-list-too ()
  "The :tools struct list is filtered to match :data :tools."
  (let* ((asst (test--make-assistant-with-tool-calls '("read_file")))
         (info (test--make-tools-info
                (list (test--make-user-msg "hi") asst)
                '("read_file" "write_file" "search"))))
    (test-trim--reduce-tools-for-retry info)
    (let ((structs (plist-get info :tools)))
      (should (= 1 (length structs)))
      (should (equal "read_file" (gptel-tool-stub-name (car structs)))))))

(ert-deftest reduce-tools/no-struct-list-still-works ()
  "If :tools struct list is nil, data :tools is still filtered."
  (let* ((asst (test--make-assistant-with-tool-calls '("read_file")))
         (info (list :data (list :messages (vector (test--make-user-msg "hi") asst)
                                 :tools (vconcat (mapcar #'test--make-tool-def
                                                         '("read_file" "write_file"))))
                     :tools nil)))
    (should (= 1 (test-trim--reduce-tools-for-retry info)))
    (should (= 1 (length (plist-get (plist-get info :data) :tools))))))

;;; ---- Idempotence ----

(ert-deftest reduce-tools/idempotent ()
  "Running reduce twice returns 0 on second run."
  (let* ((asst (test--make-assistant-with-tool-calls '("read_file")))
         (info (test--make-tools-info
                (list (test--make-user-msg "hi") asst)
                '("read_file" "write_file" "search"))))
    (should (= 2 (test-trim--reduce-tools-for-retry info)))
    (should (= 0 (test-trim--reduce-tools-for-retry info)))))

;;; ---- Duplicate tool calls ----

(ert-deftest reduce-tools/duplicate-tool-calls-handled ()
  "Same tool called multiple times doesn't cause issues."
  (let* ((asst1 (test--make-assistant-with-tool-calls '("read_file")))
         (asst2 (test--make-assistant-with-tool-calls '("read_file" "read_file")))
         (info (test--make-tools-info
                (list (test--make-user-msg "hi") asst1
                      (test--make-tool-msg "result1")
                      asst2
                      (test--make-tool-msg "result2")
                      (test--make-tool-msg "result3"))
                '("read_file" "write_file" "search"))))
    (should (= 2 (test-trim--reduce-tools-for-retry info)))
    (should (= 1 (length (plist-get (plist-get info :data) :tools))))))

;;; ===========================================================================
;;; Integration: full progressive trimming + tools reduction
;;; ===========================================================================

(ert-deftest integration/retry-2-trims-results-reasoning-and-tools ()
  "Retry 2: tool results truncated, reasoning stripped, AND tools reduced."
  (let* ((test-trim--trim-min-bytes 0)
         (test-trim--retry-keep-recent-tool-results 2)
         (test-trim--reasoning-keep-turns 0)
         (asst1 (test--make-assistant-with-tool-calls '("read_file")))
         (asst2 (test--make-assistant-with-tool-calls '("search")))
         (msgs (list
                (test--make-assistant-msg "reasoning 1")
                asst1
                (test--make-tool-msg "file contents long enough for truncation by the replacement text string")
                (test--make-assistant-msg "reasoning 2")
                asst2
                (test--make-tool-msg "search results long enough for truncation by the replacement text string")))
         (info (test--make-tools-info msgs '("read_file" "write_file" "search" "list_dir" "run_command")))
         (messages (plist-get (plist-get info :data) :messages)))
    (plist-put info :retries 2)
    (should (= 2 (test-trim--trim-tool-results-for-retry info)))
    (should (= 2 (test-trim--trim-reasoning-content info)))
    (should (= 3 (test-trim--reduce-tools-for-retry info)))
    (let* ((remaining (plist-get (plist-get info :data) :tools))
           (names (mapcar (lambda (td) (plist-get (plist-get td :function) :name))
                          (append remaining nil))))
      (should (= 2 (length remaining)))
      (should (member "read_file" names))
      (should (member "search" names)))))

(provide 'test-gptel-trim)

;;; ===========================================================================
;;; Pre-send payload compaction tests
;;; ===========================================================================

;;; ---- Stubs for compaction ----

(defvar test-trim--payload-byte-limit 200000
  "Test stub for payload byte limit.")

(defconst test-trim--model-context-bytes
  '((kimi-k2\.5        . 400000)
    (deepseek-v4-flash  . 3000000)
    (tiny-model         . 50000))
  "Test stub for model context byte limits.")

(defun test-trim--json-encode (obj)
  "Test-local JSON encoder for payload size estimation."
  (json-serialize obj :null-object :null :false-object :json-false))

;; Copy of helper functions under test
(defun test-trim--estimate-payload-bytes (info)
  "Estimate the JSON byte size of INFO's :data payload."
  (let ((data (plist-get info :data)))
    (if data
        (condition-case nil
            (string-bytes (test-trim--json-encode data))
          (error 0))
      0)))

(defun test-trim--effective-byte-limit (info)
  "Return the byte limit for INFO's request."
  (let* ((model (plist-get info :model))
         (global-limit (or test-trim--payload-byte-limit 999999999))
         (model-limit (or (alist-get model test-trim--model-context-bytes) 999999999)))
    (min global-limit model-limit)))

;; Simplified compact function that takes info directly (no FSM dependency)
(defun test--compact-payload-on-info (info)
  "Test helper: run compaction logic directly on INFO plist.
Returns the number of items trimmed, or 0 if no compaction needed."
  (when test-trim--payload-byte-limit
    (let* ((retries (or (plist-get info :retries) 0))
           (limit (test-trim--effective-byte-limit info))
           (bytes (test-trim--estimate-payload-bytes info))
           (trimmed-total 0))
      (when (and (= retries 0) (> bytes limit))
        ;; Pass 1: trim tool results (keep 2 recent)
        (let ((test-trim--retry-keep-recent-tool-results 2))
          (plist-put info :retries 1)
          (let ((n (test-trim--trim-tool-results-for-retry info)))
            (cl-incf trimmed-total n)
            (setq bytes (test-trim--estimate-payload-bytes info))))
        ;; Pass 2: strip reasoning (if still over)
        (when (> bytes limit)
          (let ((n (test-trim--trim-reasoning-content info)))
            (cl-incf trimmed-total n)
            (cl-incf trimmed-total (test-trim--repair-thinking-tool-call-messages info))
            (setq bytes (test-trim--estimate-payload-bytes info))))
        ;; Pass 3: reduce tools array (if still over)
        (when (> bytes limit)
          (let ((n (test-trim--reduce-tools-for-retry info)))
            (cl-incf trimmed-total n)
            (setq bytes (test-trim--estimate-payload-bytes info))))
        ;; Pass 4: aggressive tool result trim (keep 0)
        (when (> bytes limit)
          (let ((test-trim--retry-keep-recent-tool-results 2))
            (plist-put info :retries 3)
            (let ((n (test-trim--trim-tool-results-for-retry info)))
              (cl-incf trimmed-total n)
              (setq bytes (test-trim--estimate-payload-bytes info)))))
        ;; Reset retries
        (plist-put info :retries 0))
      trimmed-total)))

;;; ---- Test helpers for large payloads ----

(defun test--make-large-tool-result (size-bytes)
  "Create a tool-result message with content of approximately SIZE-BYTES."
  (list :role "tool" :tool_call_id "call_12345"
        :content (make-string size-bytes ?x)))

(defun test--make-large-assistant-msg (reasoning-size)
  "Create an assistant message with reasoning_content of REASONING-SIZE bytes."
  (let ((msg (list :role "assistant" :content "response")))
    (when (and reasoning-size (> reasoning-size 0))
      (plist-put msg :reasoning_content (make-string reasoning-size ?r)))
    msg))

;;; ---- Byte estimation tests ----

(ert-deftest estimate-bytes/nil-data ()
  "Nil :data returns 0."
  (should (= 0 (test-trim--estimate-payload-bytes (list :data nil)))))

(ert-deftest estimate-bytes/empty-data ()
  "Empty messages produces small payload."
  (let* ((info (list :data (list :messages [] :model "test")))
         (bytes (test-trim--estimate-payload-bytes info)))
    (should (> bytes 0))
    (should (< bytes 100))))

(ert-deftest estimate-bytes/grows-with-content ()
  "Larger content produces larger byte estimate."
  (let* ((small (list :data (list :messages
                                   (vector (list :role "user" :content "hi")))))
         (large (list :data (list :messages
                                   (vector (list :role "user"
                                                 :content (make-string 10000 ?x)))))))
    (should (> (test-trim--estimate-payload-bytes large)
               (test-trim--estimate-payload-bytes small)))))

;;; ---- Effective byte limit tests ----

(ert-deftest effective-limit/global-only ()
  "When model has no specific limit, use global limit."
  (let ((test-trim--payload-byte-limit 150000)
        (info (list :model 'unknown-model)))
    (should (= 150000 (test-trim--effective-byte-limit info)))))

(ert-deftest effective-limit/model-smaller-than-global ()
  "Model-specific limit wins when smaller than global."
  (let ((test-trim--payload-byte-limit 200000)
        (info (list :model 'tiny-model)))
    (should (= 50000 (test-trim--effective-byte-limit info)))))

(ert-deftest effective-limit/global-smaller-than-model ()
  "Global limit wins when smaller than model limit."
  (let ((test-trim--payload-byte-limit 100000)
        (info (list :model 'kimi-k2\.5)))
    (should (= 100000 (test-trim--effective-byte-limit info)))))

(ert-deftest effective-limit/nil-global-means-no-limit ()
  "nil global limit effectively disables size checking."
  (let ((test-trim--payload-byte-limit nil)
        (info (list :model 'unknown-model)))
    (should (= 999999999 (test-trim--effective-byte-limit info)))))

;;; ---- Compaction logic tests ----

(ert-deftest compact/no-compaction-when-under-limit ()
  "Payload under limit → no trimming."
  (let* ((test-trim--payload-byte-limit 200000)
         (info (test--make-info
                (list (test--make-user-msg "hello")
                      (test--make-assistant-msg))
                0)))
    (plist-put info :model 'kimi-k2\.5)
    (should (= 0 (test--compact-payload-on-info info)))))

(ert-deftest compact/no-compaction-when-disabled ()
  "nil limit → no compaction."
  (let* ((test-trim--payload-byte-limit nil)
         (info (test--make-info
                (list (test--make-large-tool-result 300000)) 0)))
    (plist-put info :model 'kimi-k2\.5)
    ;; Returns nil when disabled
    (should-not (test--compact-payload-on-info info))))

(ert-deftest compact/skips-on-retry ()
  "Compaction only runs on first attempt (retries=0)."
  (let* ((test-trim--payload-byte-limit 1000)
         (info (test--make-info
                (list (test--make-large-tool-result 5000)) 2)))
    (plist-put info :model 'kimi-k2\.5)
    ;; retries=2, should skip
    (should (= 0 (test--compact-payload-on-info info)))))

(ert-deftest compact/trims-large-tool-results ()
  "Large tool results get trimmed when over limit."
  (let* ((test-trim--payload-byte-limit 1000)
         (msgs (list
                (test--make-user-msg "code review please")
                (test--make-assistant-msg)
                (test--make-large-tool-result 5000)
                (test--make-assistant-msg)
                (test--make-large-tool-result 5000)))
         (info (test--make-info msgs 0)))
    (plist-put info :model 'kimi-k2\.5)
    (let ((trimmed (test--compact-payload-on-info info)))
      (should (> trimmed 0))
      ;; Retries should be reset to 0
      (should (= 0 (plist-get info :retries))))))

(ert-deftest compact/strips-reasoning-when-tool-trim-not-enough ()
  "Reasoning gets stripped if tool-result trimming is insufficient.
With `test-trim--reasoning-keep-turns'=1, only older reasoning blocks are stripped."
  (let* ((test-trim--payload-byte-limit 500)
         (test-trim--reasoning-keep-turns 1)
         (msgs (list
                (test--make-large-assistant-msg 2000)
                (test--make-large-tool-result 2000)
                (test--make-large-assistant-msg 2000)
                (test--make-large-tool-result 2000)))
         (info (test--make-info msgs 0)))
    (plist-put info :model 'kimi-k2\.5)
    (let ((trimmed (test--compact-payload-on-info info)))
      (should (> trimmed 0))
      (let ((messages (plist-get (plist-get info :data) :messages)))
        (should (equal "" (plist-get (aref messages 0) :reasoning_content)))
        (should (not (equal "" (plist-get (aref messages 2) :reasoning_content)))))
      (should (= 0 (plist-get info :retries))))))

(ert-deftest compact/preserves-tool-call-reasoning-during-strip ()
  "Compaction keeps tool-call reasoning content intact for thinking models.
Moonshot/Kimi can reject compacted tool-call history when older assistant
tool-call turns lose their reasoning payload entirely."
  (let* ((test-trim--payload-byte-limit 400)
         (test-trim--trim-min-bytes 0)
         (test-trim--reasoning-keep-turns 0)
         (reasoning (make-string 2000 ?r))
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id "call_repair" :type "function"
                                                    :function (list :name "Read" :arguments "{}")))
                          :reasoning_content reasoning))
         (tool-msg-1 (test--make-large-tool-result 2000))
         (tool-msg-2 (test--make-large-tool-result 2000))
         (tool-msg-3 (test--make-large-tool-result 2000))
         (info (test--make-info (list assistant tool-msg-1 tool-msg-2 tool-msg-3) 0)))
    (plist-put info :model 'moonshot)
    (should (> (test--compact-payload-on-info info) 0))
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (plist-member (aref messages 0) :reasoning_content))
      (should (equal reasoning
                     (plist-get (aref messages 0) :reasoning_content))))))

(ert-deftest compact/pass-3-and-4-keep-tool-call-reasoning-valid ()
  "Even when compaction reaches later passes, tool-call reasoning stays intact.
This covers the real failure shape where later compaction passes still run after
tool-call history has already been compacted."
  (let* ((test-trim--payload-byte-limit 120)
         (test-trim--trim-min-bytes 0)
         (test-trim--reasoning-keep-turns 0)
         (reasoning (make-string 2000 ?r))
         (assistant (list :role "assistant"
                          :content ""
                          :tool_calls (vector (list :id "call_late" :type "function"
                                                    :function (list :name "Read" :arguments "{}")))
                          :reasoning_content reasoning))
         (tool-msg-1 (test--make-large-tool-result 4000))
         (tool-msg-2 (test--make-large-tool-result 4000))
         (tools (vconcat (mapcar #'test--make-tool-def
                                 '("Read" "Edit" "Write" "Glob" "Grep" "Diagnostics"
                                   "Code_Map" "Code_Inspect" "Code_Usages" "RunAgent"))))
         (info (list :data (list :messages (vector assistant tool-msg-1 tool-msg-2)
                                 :tools tools)
                     :retries 0
                     :model 'moonshot)))
    (should (> (test--compact-payload-on-info info) 0))
    (let* ((data (plist-get info :data))
           (messages (plist-get data :messages))
           (assistant-msg (aref messages 0)))
      (should (plist-member assistant-msg :reasoning_content))
      (should (equal reasoning
                     (plist-get assistant-msg :reasoning_content))))))

(ert-deftest compact/respects-model-specific-limit ()
  "Uses model-specific limit when smaller than global."
  (let* ((test-trim--payload-byte-limit 999999)
         ;; tiny-model has 50000 byte limit
         (msgs (list (test--make-large-tool-result 60000)))
         (info (test--make-info msgs 0)))
    (plist-put info :model 'tiny-model)
    (let ((trimmed (test--compact-payload-on-info info)))
      ;; Should compact because model limit is 50000 < payload
      (should (> trimmed 0)))))

;;; Tests for transient-error-p

(ert-deftest transient-error/timeout-string ()
  "Should detect timeout in error string."
  (should (test-trim--transient-error-p "Timeout connecting to server" nil)))

(ert-deftest transient-error/overloaded-string ()
  "Should detect overloaded in error string."
  (should (test-trim--transient-error-p "Server is overloaded" nil)))

(ert-deftest transient-error/rate-limit-string ()
  "Should detect rate limit in error string."
  (should (test-trim--transient-error-p "Too Many Requests" nil)))

(ert-deftest transient-error/bad-gateway-string ()
  "Should detect Bad Gateway in error string."
  (should (test-trim--transient-error-p "Bad Gateway" nil)))

(ert-deftest transient-error/service-unavailable-string ()
  "Should detect Service Unavailable in error string."
  (should (test-trim--transient-error-p "Service Unavailable" nil)))

(ert-deftest transient-error/gateway-timeout-string ()
  "Should detect Gateway Timeout in error string."
  (should (test-trim--transient-error-p "Gateway Timeout" nil)))

(ert-deftest transient-error/curl-error-28 ()
  "Should detect curl timeout error."
  (should (test-trim--transient-error-p "curl: (28) Operation timed out" nil)))

(ert-deftest transient-error/curl-error-6 ()
  "Should detect curl DNS error."
  (should (test-trim--transient-error-p "curl: (6) Could not resolve host" nil)))

(ert-deftest transient-error/curl-error-7 ()
  "Should detect curl connection error."
  (should (test-trim--transient-error-p "curl: (7) Failed to connect" nil)))

(ert-deftest transient-error/http-408 ()
  "Should detect HTTP 408 as transient."
  (should (test-trim--transient-error-p nil 408)))

(ert-deftest transient-error/http-429 ()
  "Should detect HTTP 429 as transient."
  (should (test-trim--transient-error-p nil 429)))

(ert-deftest transient-error/http-500 ()
  "Should detect HTTP 500 as transient."
  (should (test-trim--transient-error-p nil 500)))

(ert-deftest transient-error/http-502 ()
  "Should detect HTTP 502 as transient."
  (should (test-trim--transient-error-p nil 502)))

(ert-deftest transient-error/http-503 ()
  "Should detect HTTP 503 as transient."
  (should (test-trim--transient-error-p nil 503)))

(ert-deftest transient-error/http-504 ()
  "Should detect HTTP 504 as transient."
  (should (test-trim--transient-error-p nil 504)))

(ert-deftest transient-error/http-400-not-transient ()
  "Should NOT detect HTTP 400 as transient."
  (should-not (test-trim--transient-error-p nil 400)))

(ert-deftest transient-error/http-401-not-transient ()
  "Should NOT detect HTTP 401 as transient."
  (should-not (test-trim--transient-error-p nil 401)))

(ert-deftest transient-error/http-403-not-transient ()
  "Should NOT detect HTTP 403 as transient."
  (should-not (test-trim--transient-error-p nil 403)))

(ert-deftest transient-error/http-404-not-transient ()
  "Should NOT detect HTTP 404 as transient."
  (should-not (test-trim--transient-error-p nil 404)))

(ert-deftest transient-error/plist-overloaded ()
  "Should detect overloaded from plist error."
  (should (test-trim--transient-error-p '(:message "Server overloaded") nil)))

(ert-deftest transient-error/plist-rate-limit ()
  "Should detect rate limit from plist error."
  (should (test-trim--transient-error-p '(:message "Rate limit exceeded") nil)))

(ert-deftest transient-error/plist-timeout ()
  "Should detect timeout from plist error."
  (should (test-trim--transient-error-p '(:message "Request timeout") nil)))

(ert-deftest transient-error/non-transient-string ()
  "Should NOT detect non-transient errors."
  (should-not (test-trim--transient-error-p "Invalid API key" nil)))

(ert-deftest transient-error/non-transient-plist ()
  "Should NOT detect non-transient plist errors."
  (should-not (test-trim--transient-error-p '(:message "Invalid authentication") nil)))

(provide 'test-gptel-trim)
;;; test-gptel-trim.el ends here
