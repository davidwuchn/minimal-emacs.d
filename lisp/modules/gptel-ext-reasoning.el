;;; gptel-ext-reasoning.el --- Thinking/reasoning content preservation -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Moonshot/Kimi (and other thinking-enabled models) require that every assistant
;; message with tool_calls carries a reasoning_content field in the conversation
;; history.  This module handles:
;;
;; PROBLEM 1: :reasoning-block state leaks across requests.
;;   gptel-curl--stream-filter tracks a :reasoning-block state machine for
;;   <think>-tag based reasoning.  After the first response completes, it sets
;;   :reasoning-block to 'done.  gptel--handle-wait clears :reasoning but NOT
;;   :reasoning-block.  On the second request, the JSON-field reasoning capture
;;   in gptel-curl--parse-stream is gated by (unless (eq :reasoning-block 'done))
;;   so ALL reasoning chunks for turn 2+ are silently dropped.  Fix: reset
;;   :reasoning-block to nil on each new WAIT via :after advice on gptel--handle-wait.
;;
;; PROBLEM 2: reasoning_content missing from replayed history.
;;   Even after fixing problem 1, when the conversation is re-read from the buffer
;;   (gptel--parse-buffer) or when the in-memory data :messages is built up over
;;   multiple tool-loop cycles, the assistant+tool_calls messages may lack
;;   reasoning_content.  Fix: a single pre-serialization sweep in
;;   gptel-curl--get-args patches any remaining gaps before JSON encoding.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'gptel)
(require 'gptel-openai)

(defvar-local my/gptel--tool-reasoning-alist nil
  "Alist of (TOOL-CALL-ID . REASONING-STRING) for the current gptel buffer.
Populated by `my/gptel--capture-tool-reasoning' after each tool call turn
so that `my/gptel--parse-buffer-inject-reasoning' can recover reasoning_content
when re-serializing the conversation for APIs that require it (e.g. Moonshot).")

(defun my/gptel--reasoning-key-for-model (model &optional backend)
  "Return the reasoning field keyword for MODEL on BACKEND, or nil.
Returns :reasoning_content for models with :thinking param (Moonshot, DeepSeek V4),
:reasoning for legacy models that still use :reasoning request params.
When BACKEND is non-nil, only returns a key for gptel-openai backends."
  (when (stringp model)
    (setq model (intern model)))
  (when (fboundp 'gptel--model-request-params)
    (when (or (null backend) (cl-typep backend 'gptel-openai))
      (let ((params (gptel--model-request-params model)))
        (cond
         ((plist-member params :thinking)  :reasoning_content)
         ((plist-member params :reasoning) :reasoning)
         (t nil))))))

(defun my/gptel--thinking-model-p ()
  "Return the reasoning field keyword if current model has thinking/reasoning enabled.
Returns :reasoning_content for models with :thinking enabled,
:reasoning for legacy models that still use :reasoning, nil otherwise."
  (my/gptel--reasoning-key-for-model gptel-model))

(defun my/gptel--reset-reasoning-block (fsm)
  "After-advice on `gptel--handle-wait': reset :reasoning-block to nil.
gptel--handle-wait clears :reasoning but leaves :reasoning-block set to
'done from the previous response.  This blocks JSON-field reasoning chunk
capture (gated by `unless (eq :reasoning-block 'done)') for all subsequent
requests in the same FSM.  Reset it here so each new request starts fresh."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm))))
    (when (plist-get info :reasoning-block)
      (plist-put info :reasoning-block nil))))



(defun my/gptel--capture-tool-reasoning (_tool-results info)
  "After tool results are displayed, store reasoning keyed by tool-call ID.
Stores the reasoning string (possibly empty) for every tool-call turn when
the active model has thinking enabled.  Empty string is stored deliberately:
Moonshot requires the field to be *present* in every assistant tool-call
message, even when the model produced no visible reasoning for that turn.
:after advice on `gptel--display-tool-results'."
  (when-let* ((start-marker (plist-get info :position))
              (buf (and (markerp start-marker) (marker-buffer start-marker))))
    (with-current-buffer buf
      ;; Only capture for thinking-enabled models.
      (when (my/gptel--thinking-model-p)
        (let ((reasoning (or (plist-get info :reasoning) "")))
          (dolist (tool-use (plist-get info :tool-use))
            (when-let* ((id (plist-get tool-use :id))
                        ((stringp id)))
              (setf (alist-get id my/gptel--tool-reasoning-alist nil nil #'equal)
                    reasoning))))))))

(defun my/gptel--valid-reasoning-value-p (value)
  "Return non-nil when VALUE is an API-valid reasoning payload."
  (stringp value))

(defun my/gptel--fallback-reasoning-value (tool-calls reasoning-alist)
  "Return stored reasoning for TOOL-CALLS from REASONING-ALIST, or empty string."
  (let* ((tc (and (vectorp tool-calls)
                  (> (length tool-calls) 0)
                  (aref tool-calls 0)))
         (id (and tc (plist-get tc :id)))
         (stored (if (and reasoning-alist id)
                     (alist-get id reasoning-alist :absent nil #'equal)
                   :absent)))
    (if (stringp stored) stored "")))

(defun my/gptel--ensure-reasoning-on-messages (messages reasoning-key &optional reasoning-alist)
  "Ensure every assistant+tool_calls message in MESSAGES carries REASONING-KEY.
MESSAGES may be a list or vector of plist messages.  For each assistant
tool-call message, repair missing or invalid reasoning values using
REASONING-ALIST, defaulting to the empty string.

Returns the number of messages repaired."
  (let ((repaired 0))
    (seq-doseq (msg messages)
      (when (and (listp msg)
                 (equal (plist-get msg :role) "assistant")
                 (plist-get msg :tool_calls)
                 (let ((value (plist-get msg reasoning-key)))
                   (or (not (plist-member msg reasoning-key))
                       (not (my/gptel--valid-reasoning-value-p value)))))
        (plist-put msg reasoning-key
                   (my/gptel--fallback-reasoning-value
                    (plist-get msg :tool_calls) reasoning-alist))
        (cl-incf repaired)))
    repaired))

(defun my/gptel--parse-buffer-inject-reasoning (orig backend &optional max-entries)
  "Around-advice on `gptel--parse-buffer': inject reasoning_content into tool-call messages.
For backends where thinking is enabled (e.g. Moonshot/Kimi), every assistant
message with tool_calls must carry reasoning_content or the API returns 400.
The field is injected even as empty string when no reasoning was captured for
that turn — the API requires presence, not a non-empty value."
  (let ((prompts (funcall orig backend max-entries)))
    ;; Only act for OpenAI-compatible backends with thinking/reasoning enabled.
    (when-let* (((cl-typep backend 'gptel-openai))
                (reasoning-key (my/gptel--thinking-model-p)))
      (my/gptel--ensure-reasoning-on-messages
       prompts reasoning-key my/gptel--tool-reasoning-alist))
    prompts))


(with-eval-after-load 'gptel-openai
  (advice-add 'gptel--parse-buffer
              :around #'my/gptel--parse-buffer-inject-reasoning))

;; Pre-serialization safety sweep: patch any remaining gaps right before JSON
;; encoding.  Covers the buffer re-parse path and any edge cases the streaming
;; injection misses (e.g. non-streaming responses, buffer-reloads).


(defun my/gptel--pre-serialize-inject-noop (info _uuid _include-headers)
  "Before-advice on `gptel-curl--get-args': inject dummy _noop tool for LiteLLM/Anthropic.
If tool_calls are present in message history but no active tools are selected,
many proxies crash with 400 Bad Request. We inject a dummy to satisfy validation."
  (when-let* ((data  (plist-get info :data))
              (msgs  (plist-get data :messages)))
    (let* ((tools (plist-get data :tools))
           (has-tools (and tools (> (length tools) 0))))
      (unless has-tools
        (let ((has-history-tools nil))
          (cl-loop for msg across msgs
                   do (when (and (listp msg)
                                  (or (plist-get msg :tool_calls)
                                      (equal (plist-get msg :role) "tool")))
                        (setq has-history-tools t)
                        (cl-return)))
          (when has-history-tools
            (message "gptel: history has tool_calls but no tools active; injecting dummy _noop")
            (let ((noop-tool
                   (list :type "function"
                         :function (list :name "_noop"
                                         :description "Placeholder proxy compatibility tool"
                                         :parameters (list :type "object" :properties (list :_dummy (list :type "string")))))))
               (plist-put info :data (plist-put data :tools (vector noop-tool))))))))))

(defun my/gptel--pre-serialize-inject-reasoning (info _uuid _include-headers)
  "Before-advice on `gptel-curl--get-args': ensure reasoning_content on tool-call messages.
For Moonshot (and any model with :thinking/:reasoning request-params), every
assistant message that contains tool_calls must carry a reasoning_content field."
  (let* ((model   (plist-get info :model))
         (backend (plist-get info :backend))
         (reasoning-key (my/gptel--reasoning-key-for-model model backend)))
    (when reasoning-key
      (let* ((data      (plist-get info :data))
             (msgs      (plist-get data :messages))
             (gptel-buf (plist-get info :buffer))
             (reasoning-alist
              (and gptel-buf (buffer-live-p gptel-buf)
                   (buffer-local-value 'my/gptel--tool-reasoning-alist gptel-buf))))
        (when (and msgs (> (length msgs) 0))
          (my/gptel--ensure-reasoning-on-messages
           msgs reasoning-key reasoning-alist))))))

;; --- Nil-named tool call guard (inject-prompt level) ---
;; gptel-curl--parse-stream injects the assistant+tool_calls message into
;; :data :messages at [DONE] time, BEFORE my/gptel--sanitize-tool-calls runs.
;; If the model emits a tool call with name=nil/"null" (an OpenRouter/litellm
;; artifact), that nil-named entry is baked into the stored assistant message.
;; On the next request, gptel--parse-buffer replays it verbatim and
;; OpenRouter/Anthropic rejects it with 400 "Invalid input".
;;
;; Fix: strip nil-named tool_calls from the assistant message at inject time,
;; before the message is appended to :data :messages.
(defun my/gptel--inject-prompt-strip-nil-tools (backend data new-prompt &rest _)
  "Strip nil/null-named tool_calls from assistant messages before injection.

Runs as :after advice on `gptel--inject-prompt'.  Prevents 400 errors from
OpenRouter/Anthropic when the model emits a tool call with a nil function name
(a known OpenRouter/litellm streaming artifact)."
  (ignore data)
  (when (cl-typep backend 'gptel-openai)
    (let ((msgs (cond
                 ((keywordp (car-safe new-prompt)) (list new-prompt))
                 ((listp new-prompt) new-prompt)
                 (t (list new-prompt)))))
      (dolist (msg msgs)
        (when (and (listp msg)
                   (equal (plist-get msg :role) "assistant"))
          (when-let* ((tcs (plist-get msg :tool_calls))
                      ((vectorp tcs)))
(let ((filtered (cl-remove-if
                              (lambda (tc)
                                (let* ((func (plist-get tc :function))
                                       (name (and func (plist-get func :name))))
                                  (or (null name)
                                      (eq name :null)
                                      (equal name "null")
                                      (equal name ""))))
                              tcs)))
              (if (= (length filtered) 0)
                  ;; No valid tool calls remain — demote to plain assistant message
                  ;; so the conversation stays well-formed.
                  (progn (plist-put msg :tool_calls nil)
                         ;; :content may be :null (gptel's JSON null sentinel) OR
                         ;; Elisp nil (json-serialize encodes nil as {}, causing
                         ;; DashScope/OpenAI 400 "got object instead of string").
                         (let ((c (plist-get msg :content)))
                           (when (or (eq c :null) (null c))
                             (plist-put msg :content ""))))
                (plist-put msg :tool_calls (vconcat filtered))))))))))

;; Immediate patch: stamp reasoning_content right when the message is injected
;; into data :messages so it never travels without the field.
(defun my/gptel--inject-prompt-patch-reasoning (backend data new-prompt &rest _)
  "After-advice on `gptel--inject-prompt': stamp reasoning_content on tool-call messages."
  (let* ((model-name (plist-get data :model))
         (model (and model-name
                     (if (symbolp model-name) model-name (intern model-name))))
         (reasoning-key (my/gptel--reasoning-key-for-model model backend)))
    (when reasoning-key
      (let ((msgs (cond
                   ((keywordp (car-safe new-prompt)) (list new-prompt))
                   ((listp new-prompt) new-prompt)
                   (t (list new-prompt)))))
        (my/gptel--ensure-reasoning-on-messages msgs reasoning-key)))))

;; --- Advice Registration ---
(with-eval-after-load 'gptel
  (advice-add 'gptel--display-tool-results
              :after #'my/gptel--capture-tool-reasoning))

(with-eval-after-load 'gptel-request
  ;; Reasoning/thinking content preservation
  (advice-add 'gptel--handle-wait         :after  #'my/gptel--reset-reasoning-block)
  (advice-add 'gptel-curl--get-args       :before #'my/gptel--pre-serialize-inject-reasoning)
  (advice-add 'gptel-curl--get-args       :before #'my/gptel--pre-serialize-inject-noop)
  (advice-add 'gptel--inject-prompt       :after  #'my/gptel--inject-prompt-strip-nil-tools)
  (advice-add 'gptel--inject-prompt       :after  #'my/gptel--inject-prompt-patch-reasoning))

(provide 'gptel-ext-reasoning)
;;; gptel-ext-reasoning.el ends here
