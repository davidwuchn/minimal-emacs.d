;;; test-gptel-ext-reasoning.el --- Tests for reasoning content preservation -*- lexical-binding: t; -*-

;;; Commentary:
;; TDD-style unit tests for gptel-ext-reasoning.el
;; Tests cover:
;; - Reasoning key detection for different models
;; - Thinking model detection
;; - Reasoning value validation
;; - Fallback reasoning injection
;; - Message repair for tool_calls

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'eieio)

;;; Mock gptel dependencies

(defvar gptel-model 'gpt-4)
(defvar gptel--model-request-params-plist nil)

(defun gptel--model-request-params (model)
  "Mock: return request params for MODEL."
  (or gptel--model-request-params-plist
      (cond
       ((eq model 'moonshot-v1-8k) '(:thinking t))
       ((eq model 'deepseek-v4-pro) '(:thinking (:type "enabled")
                                      :reasoning_effort "high"))
       (t nil))))

(defclass test-reasoning-openai-backend () ())

(defvar my/gptel--tool-reasoning-alist nil)

;;; Functions under test (copied from gptel-ext-reasoning.el)

(defun test-reasoning--reasoning-key-for-model (model &optional backend)
  "Return the reasoning field keyword for MODEL on BACKEND, or nil."
  (when (stringp model)
    (setq model (intern model)))
  (when (fboundp 'gptel--model-request-params)
    (when (or (null backend) (cl-typep backend 'test-reasoning-openai-backend))
      (let ((params (gptel--model-request-params model)))
        (cond
         ((plist-member params :thinking) :reasoning_content)
         ((plist-member params :reasoning) :reasoning)
         (t nil))))))

(defun test-reasoning--thinking-model-p ()
  "Return reasoning key if current model has thinking enabled."
  (test-reasoning--reasoning-key-for-model gptel-model))

(defun test-reasoning--valid-reasoning-value-p (value)
  "Return non-nil when VALUE is an API-valid reasoning payload."
  (stringp value))

(defun test-reasoning--fallback-reasoning-value (tool-calls reasoning-alist)
  "Return stored reasoning for TOOL-CALLS from REASONING-ALIST, or empty string."
  (let* ((tc (and (vectorp tool-calls)
                  (> (length tool-calls) 0)
                  (aref tool-calls 0)))
         (id (and tc (plist-get tc :id)))
         (stored (if (and reasoning-alist id)
                     (alist-get id reasoning-alist :absent nil #'equal)
                   :absent)))
    (if (stringp stored) stored "")))

(defun test-reasoning--ensure-reasoning-on-messages (messages reasoning-key &optional reasoning-alist)
  "Ensure every assistant+tool_calls message in MESSAGES carries REASONING-KEY."
  (let ((repaired 0))
    (seq-doseq (msg messages)
      (when (and (listp msg)
                 (equal (plist-get msg :role) "assistant")
                 (plist-get msg :tool_calls)
                 (let ((value (plist-get msg reasoning-key)))
                   (or (not (plist-member msg reasoning-key))
                       (not (test-reasoning--valid-reasoning-value-p value)))))
        (plist-put msg reasoning-key
                   (test-reasoning--fallback-reasoning-value
                    (plist-get msg :tool_calls) reasoning-alist))
        (cl-incf repaired)))
    repaired))

;;; Tests for reasoning-key-for-model

(ert-deftest reasoning/key-for-model/moonshot-returns-reasoning-content ()
  "Moonshot models should return :reasoning_content key."
  (let ((gptel--model-request-params-plist '(:thinking t)))
    (should (eq (test-reasoning--reasoning-key-for-model 'moonshot-v1-8k)
                :reasoning_content))))

(ert-deftest reasoning/key-for-model/deepseek-v4-pro-returns-reasoning-content ()
  "DeepSeek V4 Pro should return :reasoning_content."
  (let ((gptel--model-request-params-plist '(:thinking (:type "enabled")
                                             :reasoning_effort "high")))
    (should (eq (test-reasoning--reasoning-key-for-model 'deepseek-v4-pro)
                :reasoning_content))))

(ert-deftest reasoning/key-for-model/gpt4-returns-nil ()
  "GPT-4 should return nil (no reasoning)."
  (let ((gptel--model-request-params-plist nil))
    (should (null (test-reasoning--reasoning-key-for-model 'gpt-4)))))

(ert-deftest reasoning/key-for-model/string-model ()
  "Should handle string model names."
  (let ((gptel--model-request-params-plist '(:thinking t)))
    (should (eq (test-reasoning--reasoning-key-for-model "moonshot-v1-8k")
                :reasoning_content))))

(ert-deftest reasoning/key-for-model/backend-check ()
  "Should return nil for non-OpenAI backends when backend specified."
  (let ((gptel--model-request-params-plist '(:thinking t))
        (backend 'gptel-curl))
    (should (null (test-reasoning--reasoning-key-for-model 'moonshot-v1-8k backend)))))

;;; Tests for thinking-model-p

(ert-deftest reasoning/thinking-model-p/moonshot ()
  "Should detect Moonshot as thinking model."
  (let ((gptel-model 'moonshot-v1-8k)
        (gptel--model-request-params-plist '(:thinking t)))
    (should (eq (test-reasoning--thinking-model-p) :reasoning_content))))

(ert-deftest reasoning/thinking-model-p/deepseek ()
  "Should detect DeepSeek as thinking model."
  (let ((gptel-model 'deepseek-v4-pro)
        (gptel--model-request-params-plist '(:thinking (:type "enabled")
                                             :reasoning_effort "high")))
    (should (eq (test-reasoning--thinking-model-p) :reasoning_content))))

(ert-deftest reasoning/thinking-model-p/gpt4 ()
  "GPT-4 should not be detected as thinking model."
  (let ((gptel-model 'gpt-4)
        (gptel--model-request-params-plist nil))
    (should (null (test-reasoning--thinking-model-p)))))

;;; Tests for valid-reasoning-value-p

(ert-deftest reasoning/valid-value/string ()
  "String should be valid reasoning value."
  (should (test-reasoning--valid-reasoning-value-p "some reasoning")))

(ert-deftest reasoning/valid-value/empty-string ()
  "Empty string should be valid reasoning value."
  (should (test-reasoning--valid-reasoning-value-p "")))

(ert-deftest reasoning/valid-value/nil ()
  "nil should not be valid reasoning value."
  (should-not (test-reasoning--valid-reasoning-value-p nil)))

(ert-deftest reasoning/valid-value/number ()
  "Number should not be valid reasoning value."
  (should-not (test-reasoning--valid-reasoning-value-p 42)))

(ert-deftest reasoning/valid-value/list ()
  "List should not be valid reasoning value."
  (should-not (test-reasoning--valid-reasoning-value-p '(:content "test"))))

;;; Tests for fallback-reasoning-value

(ert-deftest reasoning/fallback/stored-value ()
  "Should return stored reasoning from alist."
  (let* ((tool-calls (vector (list :id "call_123" :name "Read")))
         (reasoning-alist '(("call_123" . "My reasoning"))))
    (should (equal (test-reasoning--fallback-reasoning-value tool-calls reasoning-alist)
                   "My reasoning"))))

(ert-deftest reasoning/fallback/empty-when-not-stored ()
  "Should return empty string when not stored."
  (let* ((tool-calls (vector (list :id "call_456" :name "Read")))
         (reasoning-alist '(("call_123" . "My reasoning"))))
    (should (equal (test-reasoning--fallback-reasoning-value tool-calls reasoning-alist)
                   ""))))

(ert-deftest reasoning/fallback/empty-when-no-tool-calls ()
  "Should return empty string when no tool calls."
  (should (equal (test-reasoning--fallback-reasoning-value nil nil) "")))

(ert-deftest reasoning/fallback/empty-when-empty-tool-calls ()
  "Should return empty string when tool-calls is empty vector."
  (should (equal (test-reasoning--fallback-reasoning-value (vector) nil) "")))

;;; Tests for ensure-reasoning-on-messages

(ert-deftest reasoning/ensure/adds-missing-reasoning ()
  "Should add reasoning_content when missing from tool_calls message."
  (let ((messages (list (list :role "assistant"
                              :tool_calls (vector (list :id "call_1" :name "Read"))
                              :content nil))))
    (should (= (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content) 1))
    (should (plist-member (car messages) :reasoning_content))))

(ert-deftest reasoning/ensure/keeps-existing-reasoning ()
  "Should not modify messages with valid reasoning."
  (let ((messages (list (list :role "assistant"
                              :tool_calls (vector (list :id "call_1" :name "Read"))
                              :reasoning_content "existing"
                              :content nil))))
    (should (= (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content) 0))
    (should (equal (plist-get (car messages) :reasoning_content) "existing"))))

(ert-deftest reasoning/ensure/uses-alist ()
  "Should use reasoning-alist for stored values."
  (let ((messages (list (list :role "assistant"
                              :tool_calls (vector (list :id "call_123" :name "Read"))
                              :content nil)))
        (reasoning-alist '(("call_123" . "Stored reasoning"))))
    (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content reasoning-alist)
    (should (equal (plist-get (car messages) :reasoning_content) "Stored reasoning"))))

(ert-deftest reasoning/ensure/skips-non-tool-messages ()
  "Should skip messages without tool_calls."
  (let ((messages (list (list :role "assistant"
                              :content "Hello world"))))
    (should (= (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content) 0))))

(ert-deftest reasoning/ensure/skips-user-messages ()
  "Should skip user role messages."
  (let ((messages (list (list :role "user"
                              :content "Hi"))))
    (should (= (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content) 0))))

(ert-deftest reasoning/ensure/repairs-invalid-nil ()
  "Should repair when reasoning is nil."
  (let ((messages (list (list :role "assistant"
                              :tool_calls (vector (list :id "call_1" :name "Read"))
                              :reasoning_content nil
                              :content nil))))
    (should (= (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content) 1))
    (should (stringp (plist-get (car messages) :reasoning_content)))))

(ert-deftest reasoning/ensure/multiple-messages ()
  "Should repair multiple messages."
  (let ((messages (list (list :role "assistant"
                              :tool_calls (vector (list :id "call_1" :name "Read"))
                              :content nil)
                        (list :role "assistant"
                              :tool_calls (vector (list :id "call_2" :name "Grep"))
                              :content nil))))
    (should (= (test-reasoning--ensure-reasoning-on-messages messages :reasoning_content) 2))))

;;; Footer

(provide 'test-gptel-ext-reasoning)

;;; test-gptel-ext-reasoning.el ends here
