;;; test-gptel-ext-context-cache.el --- Tests for context cache -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-context-cache.el
;; Tests the actual module functions, not stubs.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar gptel-model nil)
(defvar gptel-max-tokens nil)
(defvar gptel-backend nil)

(declare-function my/gptel--model-id-string "gptel-ext-context-cache")
(declare-function my/gptel--normalize-context-window "gptel-ext-context-cache")
(declare-function my/gptel--estimate-text-tokens "gptel-ext-context-cache")
(declare-function my/gptel--context-window "gptel-ext-context-cache")
(declare-function my/gptel--cache-put-context-window "gptel-ext-context-cache")
(declare-function my/gptel--cache-load-context-windows "gptel-ext-context-cache")
(declare-function my/gptel--alist-partial-match "gptel-ext-context-cache")
(declare-function my/gptel--lookup-context-window-in-gptel-tables "gptel-ext-context-cache")
(declare-function my/gptel--openrouter-fetch-context-window "gptel-ext-context-cache")
(declare-function my/gptel-fetch-all-model-metadata "gptel-ext-context-cache")

(defun test--context-cache-setup ()
  "Load module and reset state for each test."
  (setq gptel-model nil)
  (setq gptel-max-tokens nil)
  (setq gptel-backend nil)
  (load-file "lisp/modules/gptel-ext-context-cache.el"))

;;; Tests for my/gptel--model-id-string

(ert-deftest cache/model-id/string-input ()
  "Should return string unchanged."
  (test--context-cache-setup)
  (let ((gptel-model "gpt-4"))
    (should (equal (my/gptel--model-id-string) "gpt-4"))))

(ert-deftest cache/model-id/symbol-input ()
  "Should convert symbol to string."
  (test--context-cache-setup)
  (let ((gptel-model 'gpt-4o))
    (should (equal (my/gptel--model-id-string) "gpt-4o"))))

(ert-deftest cache/model-id/nil-input ()
  "Should handle nil model."
  (test--context-cache-setup)
  (let ((gptel-model nil))
    (should (equal (my/gptel--model-id-string) "nil"))))

(ert-deftest cache/model-id/number-input ()
  "Should format number as string."
  (test--context-cache-setup)
  (should (equal (my/gptel--model-id-string 123) "123")))

(ert-deftest cache/model-id/explicit-model-arg ()
  "Should use explicit model arg over gptel-model."
  (test--context-cache-setup)
  (let ((gptel-model "default"))
    (should (equal (my/gptel--model-id-string "explicit") "explicit"))))

;;; Tests for my/gptel--normalize-context-window

(ert-deftest cache/normalize/small-value ()
  "Should multiply small values by 1000."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 128) 128000)))

(ert-deftest cache/normalize/float-value ()
  "Should handle float values."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 8.192) 8192)))

(ert-deftest cache/normalize/large-value ()
  "Should keep large values as-is."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 32768) 32768)))

(ert-deftest cache/normalize/boundary-value ()
  "Should treat 1000 as boundary (not multiplied)."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 1000) 1000)))

(ert-deftest cache/normalize/just-under-boundary ()
  "Should keep values >= 1000 as-is (not multiply)."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 4999) 4999)))

(ert-deftest cache/normalize/at-new-boundary ()
  "Should multiply values < 1000 by 1000."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 999) 999000)))

(ert-deftest cache/normalize/nil-input ()
  "Should return nil for nil."
  (test--context-cache-setup)
  (should-not (my/gptel--normalize-context-window nil)))

(ert-deftest cache/normalize/string-input ()
  "Should return nil for string."
  (test--context-cache-setup)
  (should-not (my/gptel--normalize-context-window "128")))

(ert-deftest cache/normalize/very-small ()
  "Should handle very small values."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 0.128) 128)))

(ert-deftest cache/normalize/very-large ()
  "Should handle very large values."
  (test--context-cache-setup)
  (should (= (my/gptel--normalize-context-window 1000000) 1000000)))

;;; Tests for my/gptel--estimate-text-tokens

(ert-deftest cache/estimate/small-text ()
  "Should estimate tokens for small text."
  (test--context-cache-setup)
  (should (< (my/gptel--estimate-text-tokens 100) 50)))

(ert-deftest cache/estimate/large-text ()
  "Should estimate tokens for large text."
  (test--context-cache-setup)
  (should (> (my/gptel--estimate-text-tokens 10000) 2000)))

(ert-deftest cache/estimate/returns-float ()
  "Should return float."
  (test--context-cache-setup)
  (should (floatp (my/gptel--estimate-text-tokens 100))))

(ert-deftest cache/estimate/zero-chars ()
  "Should return 0 for zero chars."
  (test--context-cache-setup)
  (should (= (my/gptel--estimate-text-tokens 0) 0.0)))

;;; Tests for known model context windows

(ert-deftest cache/known-models/qwen-35-plus ()
  "Qwen3.5-Plus should have 1M context."
  (test--context-cache-setup)
  (should (assoc "qwen3.5-plus" my/gptel--known-model-context-windows))
  (should (= (cdr (assoc "qwen3.5-plus" my/gptel--known-model-context-windows)) 1000000)))

(ert-deftest cache/known-models/gpt-4o ()
  "GPT-4o should have 128k context."
  (test--context-cache-setup)
  (should (assoc "gpt-4o" my/gptel--known-model-context-windows))
  (should (= (cdr (assoc "gpt-4o" my/gptel--known-model-context-windows)) 128000)))

(ert-deftest cache/known-models/gemini-25 ()
  "Gemini 2.5 should have 1M context."
  (test--context-cache-setup)
  (should (assoc "gemini-2.5" my/gptel--known-model-context-windows))
  (should (= (cdr (assoc "gemini-2.5" my/gptel--known-model-context-windows)) 1048576)))

(ert-deftest cache/known-models/deepseek-v4-flash ()
  "DeepSeek V4 Flash should have 1M context."
  (test--context-cache-setup)
  (should (assoc "deepseek-v4-flash" my/gptel--known-model-context-windows))
  (should (= (cdr (assoc "deepseek-v4-flash" my/gptel--known-model-context-windows)) 1000000)))

(ert-deftest cache/known-models/deepseek-v4-pro ()
  "DeepSeek V4 Pro should have 1M context."
  (test--context-cache-setup)
  (should (assoc "deepseek-v4-pro" my/gptel--known-model-context-windows))
  (should (= (cdr (assoc "deepseek-v4-pro" my/gptel--known-model-context-windows)) 1000000)))

;;; Tests for provider contracts

(ert-deftest cache/provider-contracts/dashscope ()
  "DashScope contract should exist."
  (test--context-cache-setup)
  (should (assq 'dashscope my/gptel-provider-contracts)))

(ert-deftest cache/provider-contracts/openai ()
  "OpenAI contract should exist."
  (test--context-cache-setup)
  (should (assq 'openai my/gptel-provider-contracts)))

(ert-deftest cache/provider-contracts/anthropic ()
  "Anthropic contract should exist."
  (test--context-cache-setup)
  (should (assq 'anthropic my/gptel-provider-contracts)))

;;; Tests for my/gptel-get-model-metadata

(ert-deftest cache/metadata/qwen-35-plus ()
  "Should return metadata for Qwen3.5-Plus."
  (test--context-cache-setup)
  (let ((meta (my/gptel-get-model-metadata "qwen3.5-plus")))
    (should meta)
    (should (= (plist-get meta :context-window) 1000000))
    (should (plist-get meta :description))))

(ert-deftest cache/metadata/unknown-model ()
  "Should return nil for unknown model."
  (test--context-cache-setup)
  (should-not (my/gptel-get-model-metadata "completely-unknown-model-xyz")))

(ert-deftest cache/metadata/partial-match ()
  "Should match model name partially."
  (test--context-cache-setup)
  (let ((meta (my/gptel-get-model-metadata "qwen3.5-plus-today")))
    (should meta)
    (should (= (plist-get meta :context-window) 1000000))))

(ert-deftest cache/metadata/partial-match-nil-overrides-shorter-prefix ()
  "A longer partial match with nil should not fall back to a shorter prefix."
  (test--context-cache-setup)
  (should-not
   (my/gptel--alist-partial-match
    '(("qwen" . (:context-window 1000000))
      ("qwen3.5-plus" . nil))
    "qwen3.5-plus-preview")))

(ert-deftest cache/gptel-tables/string-model-finds-symbol-entry ()
  "String model ids should still find symbol-keyed gptel table entries."
  (test--context-cache-setup)
  (let ((test-table-symbol (make-symbol "test-gptel-models")))
    (set test-table-symbol '((gpt-4o :context-window 128)))
    (unwind-protect
        (cl-letf (((symbol-function 'my/gptel--gptel-model-tables)
                   (lambda () (list test-table-symbol))))
          (should (= (my/gptel--lookup-context-window-in-gptel-tables "gpt-4o")
                     128000)))
      (makunbound test-table-symbol))))

(ert-deftest cache/gptel-tables/string-fallback-handles-string-keys ()
  "String fallback should match string-keyed tables without signaling."
  (test--context-cache-setup)
  (let ((test-table-symbol (make-symbol "test-gptel-models")))
    (set test-table-symbol '(("minimax-m2.7-highspeed" :context-window 196608)))
    (unwind-protect
        (cl-letf (((symbol-function 'my/gptel--gptel-model-tables)
                   (lambda () (list test-table-symbol))))
           (should (= (my/gptel--lookup-context-window-in-gptel-tables "minimax-m2.7-highspeed")
                      196608)))
      (makunbound test-table-symbol))))

(ert-deftest cache/openrouter-fetch-context-window/ignores-non-list-data ()
  "Malformed OpenRouter payloads should not signal during single-model fetch."
  (test--context-cache-setup)
  (let ((my/gptel--context-window-cache (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'my/gptel--openrouter-fetch-with-callback)
               (lambda (_url callback &rest _rest)
                 (funcall callback [((id . "demo") (context_length . 1234))])
                 t))
              ((symbol-function 'message) (lambda (&rest _args) nil)))
      (should-not
       (condition-case err
           (my/gptel--openrouter-fetch-context-window "demo")
         (error err)))
      (should (= (hash-table-count my/gptel--context-window-cache) 0)))))

(ert-deftest cache/fetch-all-model-metadata/ignores-non-list-data ()
  "Malformed OpenRouter payloads should not signal during bulk metadata fetch."
  (test--context-cache-setup)
  (let ((my/gptel--context-window-cache (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'my/gptel--openrouter-fetch-with-callback)
               (lambda (_url callback &rest _rest)
                 (funcall callback [((id . "demo") (context_length . 1234))])
                 t))
              ((symbol-function 'my/gptel--cache-save-context-windows)
               (lambda (&rest _args) nil))
              ((symbol-function 'message) (lambda (&rest _args) nil)))
      (should-not
       (condition-case err
            (my/gptel-fetch-all-model-metadata)
          (error err)))
      (should (= (hash-table-count my/gptel--context-window-cache) 0)))))

(ert-deftest cache/load-context-windows/preserves-last-refresh ()
  "Loading the cache file should preserve the saved refresh timestamp."
  (test--context-cache-setup)
  (let* ((temp-dir (make-temp-file "context-cache" t))
         (my/gptel-context-window-cache-file
          (expand-file-name "gptel-context-window-cache.el" temp-dir))
         (my/gptel--context-window-cache (make-hash-table :test 'equal))
         (my/gptel--context-window-cache-data nil)
         (my/gptel--context-window-cache-last-refresh 7.0))
    (unwind-protect
        (progn
          (with-temp-file my/gptel-context-window-cache-file
            (insert "(setq my/gptel--context-window-cache-data '((\"demo\" . 1234)))\n")
            (insert "(setq my/gptel--context-window-cache-last-refresh 42.0)\n"))
          (my/gptel--cache-load-context-windows)
          (should (= (gethash "demo" my/gptel--context-window-cache) 1234))
          (should (equal my/gptel--context-window-cache-last-refresh 42.0))
          (should-not my/gptel--context-window-cache-data))
      (delete-directory temp-dir t))))

(provide 'test-gptel-ext-context-cache)

;;; test-gptel-ext-context-cache.el ends here
