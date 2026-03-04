;;; test-gptel-trim.el --- ERT tests for progressive payload trimming -*- lexical-binding: t; no-byte-compile: t; -*-

;; Tests for my/gptel--trim-tool-results-for-retry and
;; my/gptel--trim-reasoning-content in gptel-ext-core.el.

(require 'ert)
(require 'cl-lib)
(require 'seq)

;;; ---- Stubs for the defcustom variables ----

(defvar my/gptel-retry-keep-recent-tool-results 2
  "Test stub for the defcustom.")

(defvar my/gptel-retry-truncated-result-text
  "[Content truncated to reduce context size for retry]"
  "Test stub for the defcustom.")

;;; ---- Load the functions under test ----
;; We eval the function definitions directly to avoid requiring the full
;; gptel-ext-core.el which has heavy dependencies.

(defun my/gptel--trim-tool-results-for-retry (info)
  "Trim old tool-result content in INFO's :data :messages to reduce payload.
Progressive trimming based on :retries in INFO."
  (if (null my/gptel-retry-keep-recent-tool-results)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (retries (or (plist-get info :retries) 1))
           (keep (max 0 (- my/gptel-retry-keep-recent-tool-results retries)))
           (replacement my/gptel-retry-truncated-result-text)
           (truncated 0))
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
                    (plist-put msg :content replacement)
                    (cl-incf truncated))))))))
      truncated)))

(defun my/gptel--trim-reasoning-content (info)
  "Strip reasoning_content from assistant messages in INFO."
  (let* ((data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (stripped 0))
    (when (and messages (> (length messages) 0))
      (dotimes (i (length messages))
        (let ((msg (aref messages i)))
          (when (and (equal (plist-get msg :role) "assistant")
                     (plist-get msg :reasoning_content))
            (plist-put msg :reasoning_content nil)
            (cl-incf stripped)))))
    stripped))

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
    (should (= 0 (my/gptel--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/disabled-when-nil ()
  "Setting keep-recent to nil disables trimming entirely."
  (let ((my/gptel-retry-keep-recent-tool-results nil)
        (info (test--make-info
               (list (test--make-tool-msg "big content here that is definitely long enough")
                     (test--make-tool-msg "another big result that should be long enough"))
               1)))
    (should (= 0 (my/gptel--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/empty-messages ()
  "Empty messages vector → 0 truncated."
  (let ((info (test--make-info '() 1)))
    (should (= 0 (my/gptel--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/nil-data ()
  "Nil :data → 0 truncated."
  (let ((info (list :data nil :retries 1)))
    (should (= 0 (my/gptel--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/short-content-not-truncated ()
  "Content shorter than replacement text is not truncated."
  (let ((info (test--make-info
               (list (test--make-tool-msg "ok")
                     (test--make-tool-msg "ok")
                     (test--make-tool-msg "ok"))
               1)))
    ;; "ok" is shorter than the truncation text, so nothing should be truncated
    (should (= 0 (my/gptel--trim-tool-results-for-retry info)))))

;;; ---- Progressive trimming: retry 1 (retries=1) ----

(ert-deftest trim-tool-results/retry-1-keeps-1-of-3 ()
  "Retry 1 with default=2: keep max(0, 2-1)=1 recent, truncate 2 of 3."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "first tool result with enough length to be truncated by the replacement"))
         (msg2 (test--make-tool-msg "second tool result with enough length to be truncated by replacement"))
         (msg3 (test--make-tool-msg "third tool result that is recent and should be kept intact because it is newest"))
         (info (test--make-info (list msg1 msg2 msg3) 1))
         (result (my/gptel--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 2 result))
    ;; First two truncated
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    ;; Third (most recent) kept intact
    (should (string-match-p "third tool result" (plist-get (aref messages 2) :content)))))

(ert-deftest trim-tool-results/retry-1-keeps-1-of-2 ()
  "Retry 1 with default=2: keep 1 of 2 tool messages."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "old result with enough content length to be truncated properly"))
         (msg2 (test--make-tool-msg "recent result that should be kept intact because it is the newest one"))
         (info (test--make-info (list msg1 msg2) 1))
         (result (my/gptel--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 1 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (string-match-p "recent result" (plist-get (aref messages 1) :content)))))

(ert-deftest trim-tool-results/retry-1-single-tool-kept ()
  "Retry 1 with default=2 and only 1 tool: nothing to truncate (1 <= keep=1)."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "only tool result, should be kept because count <= keep"))
         (info (test--make-info (list msg1) 1))
         (result (my/gptel--trim-tool-results-for-retry info)))
    (should (= 0 result))))

;;; ---- Progressive trimming: retry 2 (retries=2) ----

(ert-deftest trim-tool-results/retry-2-keeps-0 ()
  "Retry 2 with default=2: keep max(0, 2-2)=0, truncate ALL."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "first tool result with enough length to definitely be truncated"))
         (msg2 (test--make-tool-msg "second tool result with enough length to definitely be truncated"))
         (msg3 (test--make-tool-msg "third most recent tool result also truncated because keep is zero"))
         (info (test--make-info (list msg1 msg2 msg3) 2))
         (result (my/gptel--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 3 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 2) :content)))))

;;; ---- Progressive trimming: retry 3+ (retries=3) ----

(ert-deftest trim-tool-results/retry-3-keeps-0 ()
  "Retry 3 with default=2: keep max(0, 2-3)=0, truncate ALL."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "first tool result content that is long enough to be truncated"))
         (msg2 (test--make-tool-msg "second tool result content that is long enough to be truncated"))
         (info (test--make-info (list msg1 msg2) 3))
         (result (my/gptel--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 2 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))))

;;; ---- Default retries value ----

(ert-deftest trim-tool-results/no-retries-defaults-to-1 ()
  "When :retries is missing from INFO, defaults to 1."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "old result content that is definitely long enough for truncation"))
         (msg2 (test--make-tool-msg "recent result content that should be kept intact as the newest"))
         ;; No :retries in info
         (info (test--make-info (list msg1 msg2)))
         (result (my/gptel--trim-tool-results-for-retry info))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; retries defaults to 1, keep = max(0, 2-1) = 1
    (should (= 1 result))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (string-match-p "recent result" (plist-get (aref messages 1) :content)))))

;;; ---- Custom keep-recent values ----

(ert-deftest trim-tool-results/keep-3-retry-1 ()
  "With default=3 and retry 1: keep 2, truncate rest."
  (let* ((my/gptel-retry-keep-recent-tool-results 3)
         (msgs (list
                (test--make-tool-msg "tool result 1 old enough to be truncated on retry one with keep three")
                (test--make-tool-msg "tool result 2 old enough to be truncated on retry one with keep three")
                (test--make-tool-msg "tool result 3 kept because it is within the recent two window")
                (test--make-tool-msg "tool result 4 kept because it is within the recent two window")))
         (info (test--make-info msgs 1))
         (result (my/gptel--trim-tool-results-for-retry info))
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
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (user-msg (test--make-user-msg "user input text"))
         (asst-msg (test--make-assistant-msg "thinking hard about this"))
         (tool1 (test--make-tool-msg "old tool result content that is long enough for truncation replacement"))
         (tool2 (test--make-tool-msg "recent tool content that should be kept intact as it is newest tool"))
         (info (test--make-info (list user-msg asst-msg tool1 user-msg tool2) 1))
         (result (my/gptel--trim-tool-results-for-retry info))
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
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msg1 (test--make-tool-msg "old content that is long enough to be truncated by replacement text"))
         (msg2 (test--make-tool-msg "recent content that should be kept intact as it is newest tool msg"))
         (info (test--make-info (list msg1 msg2) 1)))
    ;; First trim
    (should (= 1 (my/gptel--trim-tool-results-for-retry info)))
    ;; Second trim with same retries — already truncated, replacement not longer than itself
    (should (= 0 (my/gptel--trim-tool-results-for-retry info)))))

(ert-deftest trim-tool-results/progressive-across-retries ()
  "Simulates escalating retries: retry 1 trims some, retry 2 trims rest."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msgs (list
                (test--make-tool-msg "tool result A with enough content to be truncated by the replacement text")
                (test--make-tool-msg "tool result B with enough content to be truncated by the replacement text")
                (test--make-tool-msg "tool result C the most recent one should be kept on first retry attempt")))
         (info (test--make-info msgs 1))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; Retry 1: keep=1, truncate 2
    (should (= 2 (my/gptel--trim-tool-results-for-retry info)))
    (should (equal test--truncation-text (plist-get (aref messages 0) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (string-match-p "tool result C" (plist-get (aref messages 2) :content)))
    ;; Retry 2: keep=0, truncate remaining 1
    (plist-put info :retries 2)
    (should (= 1 (my/gptel--trim-tool-results-for-retry info)))
    (should (equal test--truncation-text (plist-get (aref messages 2) :content)))))

;;; ===========================================================================
;;; Reasoning content trimming tests
;;; ===========================================================================

(ert-deftest trim-reasoning/strips-reasoning-from-assistant-msgs ()
  "Strips reasoning_content from all assistant messages."
  (let* ((msg1 (test--make-assistant-msg "I'm thinking about the code structure"))
         (msg2 (test--make-assistant-msg "Analyzing the file contents carefully"))
         (msg3 (test--make-user-msg "user text"))
         (info (test--make-info (list msg1 msg2 msg3)))
         (result (my/gptel--trim-reasoning-content info))
         (messages (plist-get (plist-get info :data) :messages)))
    (should (= 2 result))
    (should (null (plist-get (aref messages 0) :reasoning_content)))
    (should (null (plist-get (aref messages 1) :reasoning_content)))
    ;; Main content preserved
    (should (equal "Some response text" (plist-get (aref messages 0) :content)))
    (should (equal "Some response text" (plist-get (aref messages 1) :content)))))

(ert-deftest trim-reasoning/ignores-messages-without-reasoning ()
  "Assistant messages without reasoning_content are not counted."
  (let* ((msg1 (test--make-assistant-msg nil))  ; no reasoning
         (msg2 (test--make-assistant-msg "has reasoning content"))
         (info (test--make-info (list msg1 msg2)))
         (result (my/gptel--trim-reasoning-content info)))
    (should (= 1 result))))

(ert-deftest trim-reasoning/ignores-non-assistant-messages ()
  "User and tool messages are not touched."
  (let* ((user-msg (test--make-user-msg "user text"))
         (tool-msg (test--make-tool-msg "tool result"))
         (info (test--make-info (list user-msg tool-msg)))
         (result (my/gptel--trim-reasoning-content info)))
    (should (= 0 result))))

(ert-deftest trim-reasoning/empty-messages ()
  "Empty messages → 0 stripped."
  (let ((info (test--make-info '())))
    (should (= 0 (my/gptel--trim-reasoning-content info)))))

(ert-deftest trim-reasoning/nil-data ()
  "Nil :data → 0 stripped."
  (let ((info (list :data nil)))
    (should (= 0 (my/gptel--trim-reasoning-content info)))))

(ert-deftest trim-reasoning/idempotent ()
  "Running reasoning trim twice returns 0 on second run."
  (let* ((msg1 (test--make-assistant-msg "deep thoughts"))
         (info (test--make-info (list msg1))))
    (should (= 1 (my/gptel--trim-reasoning-content info)))
    (should (= 0 (my/gptel--trim-reasoning-content info)))))

;;; ===========================================================================
;;; Integration: progressive trimming + reasoning trim together
;;; ===========================================================================

(ert-deftest integration/retry-1-trims-tools-not-reasoning ()
  "Retry 1: tool results trimmed progressively, reasoning kept."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msgs (list
                (test--make-assistant-msg "reasoning round 1")
                (test--make-tool-msg "tool 1 old result long enough for truncation by the replacement text string")
                (test--make-assistant-msg "reasoning round 2")
                (test--make-tool-msg "tool 2 recent result that should be kept intact on first retry attempt")))
         (info (test--make-info msgs 1))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; Retry 1: keep=1, truncate tool 1 only
    (let ((trimmed (my/gptel--trim-tool-results-for-retry info)))
      (should (= 1 trimmed)))
    ;; Reasoning NOT stripped on retry 1
    (should (equal "reasoning round 1" (plist-get (aref messages 0) :reasoning_content)))
    (should (equal "reasoning round 2" (plist-get (aref messages 2) :reasoning_content)))))

(ert-deftest integration/retry-2-trims-all-tools-and-reasoning ()
  "Retry 2: all tool results truncated AND reasoning stripped."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (msgs (list
                (test--make-assistant-msg "reasoning round 1")
                (test--make-tool-msg "tool 1 result content that is long enough for truncation by replacement")
                (test--make-assistant-msg "reasoning round 2")
                (test--make-tool-msg "tool 2 result content that is long enough for truncation by replacement")))
         (info (test--make-info msgs 2))
         (messages (plist-get (plist-get info :data) :messages)))
    ;; Retry 2: keep=0, truncate ALL tools
    (let ((trimmed (my/gptel--trim-tool-results-for-retry info)))
      (should (= 2 trimmed)))
    (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
    (should (equal test--truncation-text (plist-get (aref messages 3) :content)))
    ;; Reasoning stripped on retry 2
    (let ((reasoning-stripped (my/gptel--trim-reasoning-content info)))
      (should (= 2 reasoning-stripped)))
    (should (null (plist-get (aref messages 0) :reasoning_content)))
    (should (null (plist-get (aref messages 2) :reasoning_content)))))

(ert-deftest integration/full-progressive-sequence ()
  "Simulates a full retry sequence: 3 retries with escalating trimming."
  (let* ((my/gptel-retry-keep-recent-tool-results 2)
         (make-fresh-msgs
          (lambda ()
            (list
             (test--make-assistant-msg "thinking 1")
             (test--make-tool-msg "tool A very long result content that needs to be truncated on retry attempt")
             (test--make-assistant-msg "thinking 2")
             (test--make-tool-msg "tool B another long result that also needs truncation on retry attempts")
             (test--make-assistant-msg "thinking 3")
             (test--make-tool-msg "tool C the most recent result that may or may not survive trimming")))))
    ;; Retry 1 (retries=1): keep=1, truncate 2 of 3 tools, no reasoning trim
    (let* ((info (test--make-info (funcall make-fresh-msgs) 1))
           (messages (plist-get (plist-get info :data) :messages)))
      (should (= 2 (my/gptel--trim-tool-results-for-retry info)))
      (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
      (should (equal test--truncation-text (plist-get (aref messages 3) :content)))
      (should (string-match-p "tool C" (plist-get (aref messages 5) :content)))
      ;; Reasoning intact
      (should (equal "thinking 1" (plist-get (aref messages 0) :reasoning_content))))
    ;; Retry 2 (retries=2): keep=0, truncate ALL tools, strip reasoning
    (let* ((info (test--make-info (funcall make-fresh-msgs) 2))
           (messages (plist-get (plist-get info :data) :messages)))
      (should (= 3 (my/gptel--trim-tool-results-for-retry info)))
      (should (= 3 (my/gptel--trim-reasoning-content info)))
      ;; All tools truncated
      (should (equal test--truncation-text (plist-get (aref messages 1) :content)))
      (should (equal test--truncation-text (plist-get (aref messages 3) :content)))
      (should (equal test--truncation-text (plist-get (aref messages 5) :content)))
      ;; All reasoning gone
      (should (null (plist-get (aref messages 0) :reasoning_content)))
      (should (null (plist-get (aref messages 2) :reasoning_content)))
      (should (null (plist-get (aref messages 4) :reasoning_content))))
    ;; Retry 3 (retries=3): same as retry 2, nothing left to trim
    (let* ((info (test--make-info (funcall make-fresh-msgs) 3))
           (messages (plist-get (plist-get info :data) :messages)))
      (should (= 3 (my/gptel--trim-tool-results-for-retry info)))
      (should (= 3 (my/gptel--trim-reasoning-content info))))))

(provide 'test-gptel-trim)
;;; test-gptel-trim.el ends here
