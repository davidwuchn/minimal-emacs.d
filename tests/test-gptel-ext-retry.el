;;; test-gptel-ext-retry.el --- Tests for retry and compaction -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-retry.el:
;; - my/gptel--transient-error-p
;; - my/gptel--trim-tool-results-for-retry
;; - my/gptel--trim-reasoning-content
;; - my/gptel--reduce-tools-for-retry
;; - my/gptel--truncate-old-messages
;; - my/gptel--estimate-payload-bytes
;; - my/gptel--effective-byte-limit
;;
;; This test file is self-contained with local implementations of the
;; functions under test. Run with:
;;   emacs --batch -L tests -l test-gptel-ext-retry.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)

;;; Customizations (match gptel-ext-retry.el)

(defvar my/gptel-retry-keep-recent-tool-results 2)
(defvar my/gptel-retry-truncated-result-text "[Content truncated to reduce context size for retry]")
(defvar my/gptel-payload-byte-limit 200000)
(defvar my/gptel-truncate-old-messages-keep 6)
(defvar my/gptel-trim-min-bytes 0)
(defvar my/gptel-reasoning-keep-turns 1)

(defvar my/gptel-model-context-bytes
  '((kimi-k2\.5        . 400000)
    (kimi-for-coding    . 400000)
    (qwen3\.5-plus      . 400000)
    (qwen3-coder-next   . 400000)
    (qwen3-coder-plus   . 400000)
    (qwen3-max-2026-01-23 . 400000)
    (glm-5              . 350000)
    (glm-4\.7            . 350000)
    (MiniMax-M2\.5       . 300000)
    (deepseek-chat      . 200000)
    (deepseek-reasoner  . 200000)))

(defun test-make-info (&rest plist)
  "Create an info plist with :data."
  (list :data (list :messages (vconcat (plist-get plist :messages))
                    :tools (plist-get plist :tools))
        :model (or (plist-get plist :model) 'kimi-k2.5)
        :retries (or (plist-get plist :retries) 0)))

(defun test-make-tool-result (id content)
  "Create a tool result message."
  (list :role "tool" :tool_call_id id :content content))

(defun test-make-assistant-with-tool-call (id name)
  "Create an assistant message with a tool call."
  (list :role "assistant"
        :tool_calls (vector (list :id id
                                  :type "function"
                                  :function (list :name name :arguments "{}")))))

(defun test-make-tool-def (name)
  "Create a tool definition plist."
  (list :type "function"
        :function (list :name name :description (format "Tool %s" name))))

;;; Local implementations of functions under test

(defun my/gptel--transient-error-p (error-data http-status)
  "Return non-nil if ERROR-DATA or HTTP-STATUS indicate a transient API error."
  (or (and (stringp error-data)
           (string-match-p "Malformed JSON\\|Could not parse HTTP\\|json-read-error\\|Empty reply\\|Timeout\\|timeout\\|curl: (28)\\|curl: (6)\\|curl: (7)\\|Bad Gateway\\|Service Unavailable\\|Gateway Timeout\\|Connection refused\\|Could not resolve host\\|Overloaded\\|overloaded\\|Too Many Requests" error-data))
      (and (numberp http-status) (memq http-status '(408 429 500 502 503 504)))
      (and (listp error-data)
           (string-match-p "overloaded\\|too many requests\\|rate limit\\|timeout\\|free usage limit"
                           (downcase (or (plist-get error-data :message) ""))))))

(defun my/gptel--trim-tool-results-for-retry (info)
  "Trim old tool-result content in INFO's :data :messages to reduce payload."
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
                     (plist-get msg :reasoning_content)
                     (not (equal "" (plist-get msg :reasoning_content))))
            (plist-put msg :reasoning_content "")
            (cl-incf stripped)))))
    stripped))

(defun my/gptel--reduce-tools-for-retry (info)
  "Reduce the tools array in INFO to only tools referenced in conversation."
  (let* ((data (plist-get info :data))
         (messages (and data (plist-get data :messages)))
         (data-tools (and data (plist-get data :tools)))
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
            (setq removed (- original-count new-count))))))
    removed))

(defun my/gptel--truncate-old-messages (info)
  "Truncate old user/assistant messages in INFO to reduce payload."
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
              (when (and (member role '("user" "assistant"))
                         (stringp content)
                         (> (length content) (length truncation-text)))
                (plist-put msg :content truncation-text)
                (cl-incf truncated))))))
      truncated)))

(defun my/gptel--effective-byte-limit (info)
  "Return the byte limit to use for INFO's request."
  (let* ((model (plist-get info :model))
         (global-limit (or my/gptel-payload-byte-limit 999999999))
         (model-limit (or (alist-get model my/gptel-model-context-bytes) 999999999)))
    (min global-limit model-limit)))

(defun my/gptel--estimate-payload-bytes (info)
  "Estimate the JSON byte size of INFO's :data payload."
  (let ((data (plist-get info :data)))
    (if data
        (condition-case nil
            (string-bytes (json-serialize data))
          (error 0))
      0)))

;;; Tests for my/gptel--transient-error-p

(ert-deftest retry/transient-error/string-matches ()
  "Should detect transient errors from strings."
  (should (my/gptel--transient-error-p "Malformed JSON response" nil))
  (should (my/gptel--transient-error-p "Could not parse HTTP response" nil))
  (should (my/gptel--transient-error-p "Empty reply from server" nil))
  (should (my/gptel--transient-error-p "curl: (28) Timeout" nil))
  (should (my/gptel--transient-error-p "Service Unavailable" nil))
  (should (my/gptel--transient-error-p "Too Many Requests" nil)))

(ert-deftest retry/transient-error/http-status-codes ()
  "Should detect transient HTTP status codes."
  (should (my/gptel--transient-error-p nil 408))
  (should (my/gptel--transient-error-p nil 429))
  (should (my/gptel--transient-error-p nil 500))
  (should (my/gptel--transient-error-p nil 502))
  (should (my/gptel--transient-error-p nil 503))
  (should (my/gptel--transient-error-p nil 504)))

(ert-deftest retry/transient-error/non-transient ()
  "Should not match non-transient errors."
  (should-not (my/gptel--transient-error-p "Invalid API key" nil))
  (should-not (my/gptel--transient-error-p nil 400))
  (should-not (my/gptel--transient-error-p nil 401))
  (should-not (my/gptel--transient-error-p nil 403))
  (should-not (my/gptel--transient-error-p nil 404)))

(ert-deftest retry/transient-error/plist-format ()
  "Should detect transient errors from plist format."
  (should (my/gptel--transient-error-p (list :message "Overloaded, please retry") nil))
  (should (my/gptel--transient-error-p (list :message "Rate limit exceeded") nil))
  (should (my/gptel--transient-error-p (list :message "Timeout waiting for response") nil)))

;;; Tests for my/gptel--trim-tool-results-for-retry

(ert-deftest retry/trim-tool-results/keeps-recent ()
  "Should keep most recent tool results."
  (let ((info (test-make-info
               :messages (list (test-make-tool-result "1" "old result content that is definitely long enough to be truncated by the replacement text")
                               (test-make-tool-result "2" "newer result content that is definitely long enough to be truncated by the replacement text")
                               (test-make-tool-result "3" "newest result content that is definitely long enough to be truncated by the replacement text"))
               :retries 1)))
    (let ((trimmed (my/gptel--trim-tool-results-for-retry info)))
      ;; With retries=1, keep = max(0, 2-1) = 1
      ;; 3 tool results, keep 1, so 2 should be trimmed
      (should (= trimmed 2))
      (let ((msg (aref (plist-get (plist-get info :data) :messages) 0)))
        (should (equal (plist-get msg :content)
                       my/gptel-retry-truncated-result-text))))))

(ert-deftest retry/trim-tool-results/progressive-keep ()
  "Keep count should decrease with retries."
  (let ((info (test-make-info
               :messages (list (test-make-tool-result "1" "result 1 content is sufficiently long to be truncated by the replacement text")
                               (test-make-tool-result "2" "result 2 content is sufficiently long to be truncated by the replacement text")
                               (test-make-tool-result "3" "result 3 content is sufficiently long to be truncated by the replacement text")
                               (test-make-tool-result "4" "result 4 content is sufficiently long to be truncated by the replacement text"))
               :retries 1)))
    (let ((trimmed (my/gptel--trim-tool-results-for-retry info)))
      ;; With retries=1, keep = max(0, 2-1) = 1
      ;; 4 tool results, keep 1, so 3 should be trimmed
      (should (= trimmed 3)))))

(ert-deftest retry/trim-tool-results/zero-keep ()
  "On retry 3+, should truncate all tool results."
  (let ((info (test-make-info
               :messages (list (test-make-tool-result "1" "result content is long enough to be truncated by the replacement text for sure")
                               (test-make-tool-result "2" "another result content is long enough to be truncated by the replacement text for sure"))
               :retries 3)))
    (let ((trimmed (my/gptel--trim-tool-results-for-retry info)))
      (should (= trimmed 2)))))

(ert-deftest retry/trim-tool-results/no-tool-results ()
  "Should return 0 when no tool results exist."
  (let ((info (test-make-info
               :messages (list (list :role "user" :content "hello")
                               (list :role "assistant" :content "hi")))))
    (should (= (my/gptel--trim-tool-results-for-retry info) 0))))

(ert-deftest retry/trim-tool-results/disabled ()
  "Should return 0 when trimming is disabled."
  (let ((my/gptel-retry-keep-recent-tool-results nil)
        (info (test-make-info
               :messages (list (test-make-tool-result "1" "result")))))
    (should (= (my/gptel--trim-tool-results-for-retry info) 0))))

;;; Tests for my/gptel--trim-reasoning-content

(ert-deftest retry/trim-reasoning/strips-content ()
  "Should strip reasoning_content from assistant messages."
  (let ((info (test-make-info
               :messages (list (list :role "assistant"
                                     :content "response"
                                     :reasoning_content "thinking...")
                               (list :role "assistant"
                                     :content "response2"
                                     :reasoning_content "more thinking...")))))
    (let ((stripped (my/gptel--trim-reasoning-content info)))
      (should (= stripped 2))
      (let ((msgs (plist-get (plist-get info :data) :messages)))
        (should (equal (plist-get (aref msgs 0) :reasoning_content) ""))
        (should (equal (plist-get (aref msgs 1) :reasoning_content) ""))))))

(ert-deftest retry/trim-reasoning/preserves-empty ()
  "Should not count already-empty reasoning."
  (let ((info (test-make-info
               :messages (list (list :role "assistant"
                                     :content "response"
                                     :reasoning_content "")))))
    (should (= (my/gptel--trim-reasoning-content info) 0))))

(ert-deftest retry/trim-reasoning/skips-non-assistant ()
  "Should only process assistant messages."
  (let ((info (test-make-info
               :messages (list (list :role "user"
                                     :content "hello"
                                     :reasoning_content "should be ignored")))))
    (should (= (my/gptel--trim-reasoning-content info) 0))))

;;; Tests for my/gptel--reduce-tools-for-retry

(ert-deftest retry/reduce-tools/filters-unused ()
  "Should remove tools not used in conversation."
  (let ((info (test-make-info
               :messages (list (test-make-assistant-with-tool-call "tc1" "Read")
                               (test-make-tool-result "tc1" "file content"))
               :tools (vector (test-make-tool-def "Read")
                              (test-make-tool-def "Edit")
                              (test-make-tool-def "Write")
                              (test-make-tool-def "Bash")))))
    (let ((removed (my/gptel--reduce-tools-for-retry info)))
      (should (= removed 3))
      (let ((tools (plist-get (plist-get info :data) :tools)))
        (should (= (length tools) 1))
        (should (equal (plist-get (plist-get (aref tools 0) :function) :name) "Read"))))))

(ert-deftest retry/reduce-tools/keeps-all-used ()
  "Should keep all tools that were called."
  (let ((info (test-make-info
               :messages (list (test-make-assistant-with-tool-call "tc1" "Read")
                               (test-make-assistant-with-tool-call "tc2" "Edit"))
               :tools (vector (test-make-tool-def "Read")
                              (test-make-tool-def "Edit")
                              (test-make-tool-def "Write")))))
    (let ((removed (my/gptel--reduce-tools-for-retry info)))
      (should (= removed 1))
      (let ((tools (plist-get (plist-get info :data) :tools)))
        (should (= (length tools) 2))))))

(ert-deftest retry/reduce-tools/no-tool-calls ()
  "Should return 0 when no tool calls exist (safety: keep all tools)."
  (let ((info (test-make-info
               :messages (list (list :role "user" :content "hello"))
               :tools (vector (test-make-tool-def "Read")
                              (test-make-tool-def "Edit")))))
    (should (= (my/gptel--reduce-tools-for-retry info) 0))))

;;; Tests for my/gptel--truncate-old-messages

(ert-deftest retry/truncate-old-messages/truncates-beyond-keep ()
  "Should truncate messages beyond keep count."
  (let ((info (test-make-info
               :messages (list (list :role "user" :content "message 1 content is very long and will be truncated by the truncation function for sure")
                               (list :role "assistant" :content "response 1 content is very long and will be truncated by the truncation function for sure")
                               (list :role "user" :content "message 2 content is very long and will be truncated by the truncation function for sure")
                               (list :role "assistant" :content "response 2 content is very long and will be truncated by the truncation function for sure")
                               (list :role "user" :content "message 3 content is very long and will be truncated by the truncation function for sure")
                               (list :role "assistant" :content "response 3 content is very long and will be truncated by the truncation function for sure")
                               (list :role "user" :content "recent message"))
               :retries 0)))
    (let ((truncated (my/gptel--truncate-old-messages info)))
      (should (> truncated 0)))))

(ert-deftest retry/truncate-old-messages/preserves-recent ()
  "Should preserve recent messages."
  (let ((info (test-make-info
               :messages (list (list :role "user" :content "old content that is very long and will be truncated by the truncation function for sure")
                               (list :role "user" :content "recent"))
               :retries 0)))
    (my/gptel--truncate-old-messages info)
    (let ((msgs (plist-get (plist-get info :data) :messages)))
      (should (equal (plist-get (aref msgs 1) :content) "recent")))))

(ert-deftest retry/truncate-old-messages/skips-tool-messages ()
  "Should not truncate tool messages."
  (let ((info (test-make-info
               :messages (list (test-make-tool-result "1" "tool result content here")
                               (list :role "user" :content "recent"))
               :retries 0)))
    (let ((truncated (my/gptel--truncate-old-messages info)))
      (should (= truncated 0)))))

;;; Tests for my/gptel--effective-byte-limit

(ert-deftest retry/effective-limit/uses-model-limit ()
  "Should use model-specific limit when lower."
  (let ((info (list :model 'deepseek-chat))
        (my/gptel-payload-byte-limit 400000))
    (let ((limit (my/gptel--effective-byte-limit info)))
      (should (= limit 200000)))))

(ert-deftest retry/effective-limit/uses-global-limit ()
  "Should use global limit when lower."
  (let ((info (list :model 'kimi-k2.5))
        (my/gptel-payload-byte-limit 100000))
    (let ((limit (my/gptel--effective-byte-limit info)))
      (should (= limit 100000)))))

(ert-deftest retry/effective-limit/unknown-model ()
  "Should use global limit for unknown models."
  (let ((info (list :model 'unknown-model))
        (my/gptel-payload-byte-limit 200000))
    (let ((limit (my/gptel--effective-byte-limit info)))
      (should (= limit 200000)))))

;;; Tests for my/gptel--estimate-payload-bytes

(ert-deftest retry/estimate-bytes/simple-message ()
  "Should estimate bytes for simple message."
  (let ((info (list :data (list :messages (vector (list :role "user" :content "hello"))))))
    (let ((bytes (my/gptel--estimate-payload-bytes info)))
      (should (> bytes 0)))))

(ert-deftest retry/estimate-bytes/nil-data ()
  "Should return 0 for nil data."
  (let ((info (list :data nil)))
    (should (= (my/gptel--estimate-payload-bytes info) 0))))

(ert-deftest retry/estimate-bytes/large-payload ()
  "Should handle large payloads."
  (let* ((large-content (make-string 100000 ?x))
         (info (list :data (list :messages (vector (list :role "user" :content large-content))))))
    (let ((bytes (my/gptel--estimate-payload-bytes info)))
      (should (> bytes 100000)))))

;;; Footer

(provide 'test-gptel-ext-retry)
;;; test-gptel-ext-retry.el ends here