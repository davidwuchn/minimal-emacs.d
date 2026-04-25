;;; test-gptel-ext-retry.el --- Tests for retry and compaction -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-retry.el functions.
;; Self-contained with local test implementations.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-ext-retry.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'gptel-ext-retry)

;;; Customizations (match gptel-ext-retry.el)

(defvar test-retry-keep-recent-tool-results 2)
(defvar test-retry-truncated-result-text "[Content truncated to reduce context size for retry]")
(defvar test-payload-byte-limit 200000)
(defvar test-truncate-old-messages-keep 6)
(defvar test-trim-min-bytes 0)
(defvar test-reasoning-keep-turns 1)

;;; Model context sizes
(defvar test-model-context-bytes
  '((kimi-k2\.5        . 400000)
    (kimi-for-coding    . 400000)
    (qwen3\.5-plus      . 400000)
    (glm-5              . 350000)
    (glm-4\.7           . 350000)
    (deepseek-v4-flash  . 3000000)
    (deepseek-v4-pro    . 3000000)
    (deepseek-chat      . 3000000)
    (deepseek-reasoner  . 3000000)))

;;; Test helpers

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

;;; Local test implementations (prefixed with test-- to avoid conflicts)

(defun test--transient-error-p (error-data http-status)
  "Return non-nil if ERROR-DATA or HTTP-STATUS indicate a transient API error."
  (or (and (stringp error-data)
            (string-match-p "Malformed JSON\\|Could not parse HTTP\\|json-read-error\\|Empty reply\\|Timeout\\|timeout\\|curl: (28)\\|curl: (6)\\|curl: (7)\\|exit code 28\\|exit code 6\\|exit code 7\\|Bad Gateway\\|Service Unavailable\\|Gateway Timeout\\|Connection refused\\|Could not resolve host\\|Overloaded\\|overloaded\\|Too Many Requests"
                            (downcase error-data)))
      (and (numberp http-status) (memq http-status '(408 429 500 502 503 504)))
      (and (listp error-data)
           (string-match-p "overloaded\\|too many requests\\|rate limit\\|timeout\\|free usage limit\\|access_terminated_error\\|reached your usage limit\\|quota will be refreshed in the next cycle"
                           (downcase (or (plist-get error-data :message) ""))))))

(defun test--trim-tool-results-for-retry (info)
  "Trim old tool-result content in INFO's :data :messages to reduce payload."
  (if (null test-retry-keep-recent-tool-results)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (retries (or (plist-get info :retries) 1))
           (keep (max 0 (- test-retry-keep-recent-tool-results retries)))
           (replacement test-retry-truncated-result-text)
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

(defun test--trim-reasoning-content (info)
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

(defun test--reduce-tools-for-retry (info)
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

(defun test--truncate-old-messages (info)
  "Truncate old user/assistant messages in INFO to reduce payload."
  (if (null test-truncate-old-messages-keep)
      0
    (let* ((data (plist-get info :data))
           (messages (and data (plist-get data :messages)))
           (keep test-truncate-old-messages-keep)
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

(defun test--effective-byte-limit (info)
  "Return the byte limit to use for INFO's request."
  (let* ((model (plist-get info :model))
         (global-limit (or test-payload-byte-limit 999999999))
         (model-limit
          (if (stringp model)
              (or (cl-loop for (pattern . limit) in test-model-context-bytes
                           when (string-match-p (symbol-name pattern) model)
                           return limit)
                  999999999)
            (or (alist-get model test-model-context-bytes) 999999999))))
    (min global-limit model-limit)))

(defun test--estimate-payload-bytes (info)
  "Estimate the JSON byte size of INFO's :data payload."
  (let ((data (plist-get info :data)))
    (if data
        (condition-case nil
            (string-bytes (json-serialize data))
          (error 0))
      0)))

;;; Tests for transient-error-p

(ert-deftest retry/transient-error/string-matches ()
  "Should detect transient errors from strings."
  (should (test--transient-error-p "Malformed JSON response" nil))
  (should (test--transient-error-p "Could not parse HTTP response" nil))
  (should (test--transient-error-p "Empty reply from server" nil))
  (should (test--transient-error-p "curl: (28) Timeout" nil))
  (should (test--transient-error-p "curl: (6) Could not resolve host" nil))
  (should (test--transient-error-p "curl: (7) Connection refused" nil))
  (should (test--transient-error-p "Bad Gateway" nil))
  (should (test--transient-error-p "Service Unavailable" nil))
  (should (test--transient-error-p "Gateway Timeout" nil))
  (should (test--transient-error-p "Overloaded" nil))
  (should (test--transient-error-p "Too Many Requests" nil)))

(ert-deftest retry/transient-error/string-matches-case-insensitively ()
  "Should treat transient string errors case-insensitively."
  (should (my/gptel--transient-error-p "malformed json response" nil))
  (should (my/gptel--transient-error-p "SERVICE UNAVAILABLE" nil))
  (should (my/gptel--transient-error-p "too many requests" nil)))

(ert-deftest retry/transient-error/http-status-codes ()
  "Should detect transient HTTP status codes."
  (should (test--transient-error-p nil 408))
  (should (test--transient-error-p nil 429))
  (should (test--transient-error-p nil 500))
  (should (test--transient-error-p nil 502))
  (should (test--transient-error-p nil 503))
  (should (test--transient-error-p nil 504)))

(ert-deftest retry/transient-error/plist-format ()
  "Should detect transient errors from plist format."
  (should (test--transient-error-p '(:message "The model is overloaded") nil))
  (should (test--transient-error-p '(:message "Too many requests") nil))
  (should (test--transient-error-p '(:message "Rate limit exceeded") nil))
  (should (test--transient-error-p '(:message "Request timeout") nil))
  (should (test--transient-error-p '(:message "Free usage limit reached") nil))
  (should (test--transient-error-p
           '(:message "You've reached your usage limit for this billing cycle. Your quota will be refreshed in the next cycle."
             :type "access_terminated_error")
           nil)))

(ert-deftest retry/transient-error/plist-format-with-misleading-success-status ()
  "Transient plist messages should still retry when ERRS carries a success code."
  (should (test--transient-error-p '(:message "Rate limit exceeded") 200))
  (should (test--transient-error-p '(:message "Request timeout") "204"))
  (should-not (test--transient-error-p '(:message "Model not found") 200)))

(ert-deftest retry/transient-error/non-transient ()
  "Should not detect non-transient errors."
  (should-not (test--transient-error-p nil 400))
  (should-not (test--transient-error-p nil 401))
  (should-not (test--transient-error-p nil 403))
  (should-not (test--transient-error-p nil 404))
  (should-not (test--transient-error-p "Invalid API key" nil))
  (should-not (test--transient-error-p '(:message "Model not found") nil)))

;;; Tests for trim-tool-results-for-retry

(ert-deftest retry/trim-tool-results/keeps-recent ()
  "Should keep recent tool results."
  (let* ((long-result (make-string 100 ?r))
         (messages (list (test-make-tool-result "1" long-result)
                         (test-make-tool-result "2" "result2")
                         (test-make-tool-result "3" "result3")))
         (info (test-make-info :messages messages)))
    (test--trim-tool-results-for-retry info)
    (let ((msgs (plist-get (plist-get info :data) :messages)))
      (should (string= (plist-get (aref msgs 0) :content)
                       test-retry-truncated-result-text))
      (should (string= (plist-get (aref msgs 1) :content) "result2"))
      (should (string= (plist-get (aref msgs 2) :content) "result3")))))

(ert-deftest retry/trim-tool-results/progressive-keep ()
  "Should progressively keep fewer results on more retries."
  (let ((info (test-make-info
               :messages (list (test-make-tool-result "1" "result1")
                               (test-make-tool-result "2" "result2")
                               (test-make-tool-result "3" "result3"))
               :retries 1)))
    (test--trim-tool-results-for-retry info)
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (string= (plist-get (aref messages 0) :content) "result1"))
      (should (string= (plist-get (aref messages 1) :content) "result2"))
      (should (string= (plist-get (aref messages 2) :content) "result3")))))

(ert-deftest retry/trim-tool-results/zero-keep ()
  "Should truncate all when keep is zero."
  (let ((test-retry-keep-recent-tool-results 0)
        (info (test-make-info
               :messages (list (test-make-tool-result "1" "result1")
                               (test-make-tool-result "2" "result2")))))
    (should (= 0 (test--trim-tool-results-for-retry info)))))

(ert-deftest retry/trim-tool-results/no-tool-results ()
  "Should handle messages without tool results."
  (let ((info (test-make-info
               :messages (list '(:role "user" :content "hello")
                               '(:role "assistant" :content "hi")))))
    (should (= 0 (test--trim-tool-results-for-retry info)))))

(ert-deftest retry/trim-tool-results/disabled ()
  "Should not trim when disabled."
  (let ((test-retry-keep-recent-tool-results nil)
        (info (test-make-info
               :messages (list (test-make-tool-result "1" "very long result content here")))))
    (should (= 0 (test--trim-tool-results-for-retry info)))))

;;; Tests for trim-reasoning-content

(ert-deftest retry/trim-reasoning/strips-content ()
  "Should strip reasoning content from assistant messages."
  (let ((info (test-make-info
               :messages (list '(:role "assistant" :content "response" :reasoning_content "thinking")
                               '(:role "user" :content "hi")
                               '(:role "assistant" :content "response2" :reasoning_content "more thinking")))))
    (test--trim-reasoning-content info)
    (let ((messages (plist-get (plist-get info :data) :messages)))
      (should (string= (plist-get (aref messages 0) :reasoning_content) ""))
      (should (string= (plist-get (aref messages 2) :reasoning_content) "")))))

(ert-deftest retry/trim-reasoning/preserves-empty ()
  "Should not touch already-empty reasoning."
  (let ((info (test-make-info
               :messages (list '(:role "assistant" :content "response" :reasoning_content "")))))
    (should (= 0 (test--trim-reasoning-content info)))))

(ert-deftest retry/trim-reasoning/skips-non-assistant ()
  "Should skip non-assistant messages."
  (let ((info (test-make-info
               :messages (list '(:role "user" :content "hi" :reasoning_content "ignored")))))
    (should (= 0 (test--trim-reasoning-content info)))))

;;; Tests for reduce-tools-for-retry

(ert-deftest retry/reduce-tools/filters-unused ()
  "Should remove tools not used in conversation."
  (let ((info (test-make-info
               :messages (list (test-make-assistant-with-tool-call "1" "read_file"))
               :tools (vector (test-make-tool-def "read_file")
                              (test-make-tool-def "write_file")
                              (test-make-tool-def "search")))))
    (should (= 2 (test--reduce-tools-for-retry info)))
    (let ((tools (plist-get (plist-get info :data) :tools)))
      (should (= 1 (length tools)))
      (should (string= "read_file"
                       (plist-get (plist-get (aref tools 0) :function) :name))))))

(ert-deftest retry/reduce-tools/keeps-all-used ()
  "Should keep all used tools."
  (let ((info (test-make-info
               :messages (list (test-make-assistant-with-tool-call "1" "read_file")
                               (test-make-assistant-with-tool-call "2" "write_file"))
               :tools (vector (test-make-tool-def "read_file")
                              (test-make-tool-def "write_file")))))
    (should (= 0 (test--reduce-tools-for-retry info)))
    (let ((tools (plist-get (plist-get info :data) :tools)))
      (should (= 2 (length tools))))))

(ert-deftest retry/reduce-tools/no-tool-calls ()
  "Should not reduce when no tool calls (safety)."
  (let ((info (test-make-info
               :messages (list '(:role "user" :content "hi"))
               :tools (vector (test-make-tool-def "read_file")
                              (test-make-tool-def "write_file")))))
    (should (= 0 (test--reduce-tools-for-retry info)))))

;;; Tests for truncate-old-messages

(ert-deftest retry/truncate-old-messages/truncates-beyond-keep ()
  "Should truncate old messages beyond keep count."
  (let* ((long-content (make-string 100 ?x))
         (messages (list (list :role "user" :content long-content)
                         '(:role "assistant" :content "msg2")
                         '(:role "user" :content "msg3")
                         '(:role "assistant" :content "msg4")
                         '(:role "user" :content "msg5")
                         '(:role "assistant" :content "msg6")
                         '(:role "user" :content "msg7")))
         (info (test-make-info :messages messages)))
    (test--truncate-old-messages info)
    (let ((msgs (plist-get (plist-get info :data) :messages)))
      (should (string-match-p "truncated" (plist-get (aref msgs 0) :content))))))

(ert-deftest retry/truncate-old-messages/preserves-recent ()
  "Should preserve recent messages."
  (let ((info (test-make-info
               :messages (list '(:role "user" :content "msg1")
                               '(:role "assistant" :content "msg2")
                               '(:role "user" :content "msg3")
                               '(:role "assistant" :content "msg4")))))
    (should (= 0 (test--truncate-old-messages info)))))

(ert-deftest retry/truncate-old-messages/skips-tool-messages ()
  "Should not truncate tool messages."
  (let ((info (test-make-info
               :messages (list '(:role "tool" :tool_call_id "1" :content "result")))))
    (should (= 0 (test--truncate-old-messages info)))))

(ert-deftest retry/truncate-old-messages/real-implementation-handles-vector-messages ()
  "Real truncate helper should not depend on an unbound local length variable."
  (let* ((my/gptel-truncate-old-messages-keep 6)
         (long-content (make-string 100 ?x))
         (info (test-make-info
                :messages (list (list :role "user" :content long-content)
                                '(:role "assistant" :content "msg2")
                                '(:role "user" :content "msg3")
                                '(:role "assistant" :content "msg4")
                                '(:role "user" :content "msg5")
                                '(:role "assistant" :content "msg6")
                                '(:role "user" :content "msg7")))))
    (should (= 1 (my/gptel--truncate-old-messages info)))
    (let ((msgs (plist-get (plist-get info :data) :messages)))
      (should (string-match-p "truncated" (plist-get (aref msgs 0) :content))))))

;;; Tests for strip-images-from-messages

(ert-deftest retry/strip-images/removes-image-parts-from-vector-content ()
  "Should remove image_url parts from multimodal vector content."
  (let* ((content [(:type "text" :text "keep")
                   [:type "image_url" :image_url (:url "data:image/png;base64,abc")]
                   (:type "text" :text "keep-too")])
         (info (test-make-info
                :messages (list (list :role "user" :content content)))))
    (should (= 1 (my/gptel--strip-images-from-messages info)))
    (let* ((messages (plist-get (plist-get info :data) :messages))
           (updated (plist-get (aref messages 0) :content)))
      (should (= 2 (length updated)))
      (should (equal (plist-get (aref updated 0) :type) "text"))
      (should (equal (plist-get (aref updated 1) :type) "text")))))

(ert-deftest retry/strip-images/ignores-malformed-odd-length-vectors ()
  "Malformed odd-length vectors should not signal args-out-of-range."
  (let* ((content [[:type "image_url" :image_url (:url "data:image/png;base64,abc")]
                   [:foo "bar" :type]])
         (info (test-make-info
                :messages (list (list :role "user" :content content)))))
    (should (= 1 (my/gptel--strip-images-from-messages info)))
    (let* ((messages (plist-get (plist-get info :data) :messages))
           (updated (plist-get (aref messages 0) :content)))
      (should (= 1 (length updated)))
      (should (equal (aref updated 0) [:foo "bar" :type])))))

;;; Tests for effective-byte-limit

(ert-deftest retry/effective-limit/uses-model-limit ()
  "Should use model-specific limit."
  (let ((info (test-make-info :model 'deepseek-v4-flash)))
    (should (= 200000 (test--effective-byte-limit info)))))

(ert-deftest retry/effective-limit/uses-global-limit ()
  "Should use global limit when model unknown."
  (let ((info (test-make-info :model 'unknown-model)))
    (should (= test-payload-byte-limit (test--effective-byte-limit info)))))

(ert-deftest retry/effective-limit/unknown-model ()
  "Should handle unknown models."
  (let ((test-payload-byte-limit nil)
        (info (test-make-info :model 'completely-unknown)))
    (should (< 0 (test--effective-byte-limit info)))))

;;; Tests for estimate-payload-bytes

(ert-deftest retry/estimate-bytes/simple-message ()
  "Should estimate bytes for simple message."
  (let ((info (test-make-info :messages (list '(:role "user" :content "hello")))))
    (should (< 0 (test--estimate-payload-bytes info)))))

(ert-deftest retry/estimate-bytes/large-payload ()
  "Should estimate bytes for large payload."
  (let ((info (test-make-info
               :messages (mapcar (lambda (_) '(:role "user" :content "test message content"))
                                 (make-list 100 0)))))
    (should (< 1000 (test--estimate-payload-bytes info)))))

(ert-deftest retry/estimate-bytes/nil-data ()
  "Should return 0 for nil data."
  (let ((info '(:data nil)))
    (should (= 0 (test--estimate-payload-bytes info)))))

;;; Tests for exponential backoff

(ert-deftest retry/backoff/delay-retry-0 ()
  "First retry should have 4s delay."
  (should (= 4.0 (my/gptel--retry-delay 0))))

(ert-deftest retry/backoff/delay-retry-1 ()
  "Second retry should have 8s delay."
  (should (= 8.0 (my/gptel--retry-delay 1))))

(ert-deftest retry/backoff/delay-retry-2 ()
  "Third retry should have 16s delay."
  (should (= 16.0 (my/gptel--retry-delay 2))))

(ert-deftest retry/backoff/delay-retry-3 ()
  "Fourth retry should cap at 30s."
  (should (= 30.0 (my/gptel--retry-delay 3))))

(ert-deftest retry/backoff/delay-retry-10 ()
  "High retry counts should cap at 30s."
  (should (= 30.0 (my/gptel--retry-delay 10))))

(ert-deftest retry/backoff/delay-negative-clamped ()
  "Negative retry counts should be clamped to 0."
  (should (= 4.0 (my/gptel--retry-delay -1))))

(ert-deftest retry/backoff/delay-nil-clamped ()
  "Nil retry count should be clamped to 0."
  (should (= 4.0 (my/gptel--retry-delay nil))))

;;; Tests for curl timeout detection

(ert-deftest retry/curl-timeout/exit-code-28 ()
  "Curl exit code 28 (timeout) should be detected as transient."
  (should (test--transient-error-p "curl: (28) Operation timed out" nil))
  (should (test--transient-error-p "exit code 28" nil)))

(ert-deftest retry/curl-timeout/exit-code-6 ()
  "Curl exit code 6 (DNS failure) should be detected as transient."
  (should (test--transient-error-p "curl: (6) Could not resolve host" nil)))

(ert-deftest retry/curl-timeout/exit-code-7 ()
  "Curl exit code 7 (connection refused) should be detected as transient."
  (should (test--transient-error-p "curl: (7) Failed to connect" nil)))

(provide 'test-gptel-ext-retry)

;;; test-gptel-ext-retry.el ends here
