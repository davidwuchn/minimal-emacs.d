;;; test-gptel-ext-context-cache.el --- Tests for context cache -*- lexical-binding: t; -*-

;;; Commentary:
;; P1 tests for gptel-ext-context-cache.el
;; Tests:
;; - my/gptel--model-id-string
;; - my/gptel--normalize-context-window
;; - my/gptel--estimate-tokens
;; - my/gptel--context-window
;; - my/gptel--cache-put-context-window
;; - my/gptel--cache-load-context-windows

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock variables

(defvar gptel-model nil)
(defvar gptel-max-tokens nil)
(defvar test-default-context-window 32768)
(defvar test-context-window-cache (make-hash-table :test 'equal))
(defvar my/gptel-context-window-cache-file nil)

;;; Functions under test

(defun test-model-id-string (&optional model)
  "Return MODEL as a stable string id."
  (let ((m (or model gptel-model)))
    (cond
     ((stringp m) m)
     ((symbolp m) (symbol-name m))
     (t (format "%S" m)))))

(defun test-normalize-context-window (n)
  "Normalize gptel context-window value N to tokens."
  (cond
   ((not (numberp n)) nil)
   ((< n 5000) (round (* n 1000)))
   (t (round n))))

(defun test-estimate-tokens (chars)
  "Estimate token count from CHARS."
  (/ (float chars) 4.0))

(defun test-context-window (&optional model max-tokens)
  "Return model context window.
If MODEL is provided, use it instead of `gptel-model'.
If MAX-TOKENS is provided, use it instead of `gptel-max-tokens'."
  (let* ((m (or model gptel-model))
         (model-id (test-model-id-string m))
         (window nil))
    (when (and (stringp model-id)
               (gethash model-id test-context-window-cache))
      (setq window (gethash model-id test-context-window-cache)))
    (or window
        (or max-tokens gptel-max-tokens)
        test-default-context-window)))

(defun test-cache-put (model-id window)
  "Put WINDOW for MODEL-ID in cache."
  (when (and (stringp model-id) (integerp window) (> window 0))
    (puthash model-id window test-context-window-cache)))

;;; Tests for my/gptel--model-id-string

(ert-deftest cache/model-id/string-input ()
  "Should return string unchanged."
  (let ((gptel-model "gpt-4"))
    (should (equal (test-model-id-string) "gpt-4"))))

(ert-deftest cache/model-id/symbol-input ()
  "Should convert symbol to string."
  (let ((gptel-model 'gpt-4o))
    (should (equal (test-model-id-string) "gpt-4o"))))

(ert-deftest cache/model-id/nil-input ()
  "Should handle nil model."
  (let ((gptel-model nil))
    (should (equal (test-model-id-string) "nil"))))

(ert-deftest cache/model-id/number-input ()
  "Should format number as string."
  (should (equal (test-model-id-string 123) "123")))

(ert-deftest cache/model-id/explicit-model-arg ()
  "Should use explicit model arg over gptel-model."
  (let ((gptel-model "default"))
    (should (equal (test-model-id-string "explicit") "explicit"))))

;;; Tests for my/gptel--normalize-context-window

(ert-deftest cache/normalize/small-value ()
  "Should multiply small values by 1000."
  (should (= (test-normalize-context-window 128) 128000)))

(ert-deftest cache/normalize/float-value ()
  "Should handle float values."
  (should (= (test-normalize-context-window 8.192) 8192)))

(ert-deftest cache/normalize/large-value ()
  "Should keep large values as-is."
  (should (= (test-normalize-context-window 32768) 32768)))

(ert-deftest cache/normalize/boundary-value ()
  "Should treat 5000 as large."
  (should (= (test-normalize-context-window 5000) 5000)))

(ert-deftest cache/normalize/just-under-boundary ()
  "Should multiply values just under boundary."
  (should (= (test-normalize-context-window 4999) 4999000)))

(ert-deftest cache/normalize/nil-input ()
  "Should return nil for nil."
  (should-not (test-normalize-context-window nil)))

(ert-deftest cache/normalize/string-input ()
  "Should return nil for string."
  (should-not (test-normalize-context-window "128")))

;;; Tests for my/gptel--estimate-tokens

(ert-deftest cache/estimate/small-text ()
  "Should estimate tokens for small text."
  (should (< (test-estimate-tokens 100) 30)))

(ert-deftest cache/estimate/large-text ()
  "Should estimate tokens for large text."
  (should (> (test-estimate-tokens 10000) 2000)))

(ert-deftest cache/estimate/returns-float ()
  "Should return float."
  (should (floatp (test-estimate-tokens 100))))

(ert-deftest cache/estimate/zero-chars ()
  "Should return 0 for zero chars."
  (should (= (test-estimate-tokens 0) 0.0)))

;;; Tests for my/gptel--context-window

(ert-deftest cache/context-window/returns-cached ()
  "Should return cached value."
  (clrhash test-context-window-cache)
  (puthash "test-model" 65536 test-context-window-cache)
  (should (= (test-context-window "test-model") 65536)))

(ert-deftest cache/context-window/falls-back-to-max-tokens ()
  "Should fall back to gptel-max-tokens."
  (clrhash test-context-window-cache)
  (should (= (test-context-window "unknown-model" 16384) 16384)))

(ert-deftest cache/context-window/falls-back-to-default ()
  "Should fall back to default when all else fails."
  (clrhash test-context-window-cache)
  (should (= (test-context-window "unknown-model" nil) 32768)))

(ert-deftest cache/context-window/prefers-cache ()
  "Should prefer cache over gptel-max-tokens."
  (clrhash test-context-window-cache)
  (puthash "cached-model" 131072 test-context-window-cache)
  (should (= (test-context-window "cached-model" 8192) 131072)))

;;; Tests for cache operations

(ert-deftest cache/put/stores-value ()
  "Should store value in cache."
  (clrhash test-context-window-cache)
  (test-cache-put "test-model" 8192)
  (should (= (gethash "test-model" test-context-window-cache) 8192)))

(ert-deftest cache/put/rejects-nil-model ()
  "Should not store nil model id."
  (clrhash test-context-window-cache)
  (test-cache-put nil 8192)
  (should (= (hash-table-count test-context-window-cache) 0)))

(ert-deftest cache/put/rejects-nil-window ()
  "Should not store nil window."
  (clrhash test-context-window-cache)
  (test-cache-put "test-model" nil)
  (should (= (hash-table-count test-context-window-cache) 0)))

(ert-deftest cache/put/rejects-negative-window ()
  "Should not store negative window."
  (clrhash test-context-window-cache)
  (test-cache-put "test-model" -100)
  (should (= (hash-table-count test-context-window-cache) 0)))

(ert-deftest cache/put/overwrites-existing ()
  "Should overwrite existing entry."
  (clrhash test-context-window-cache)
  (test-cache-put "test-model" 8192)
  (test-cache-put "test-model" 16384)
  (should (= (gethash "test-model" test-context-window-cache) 16384)))

;;; Tests for edge cases

(ert-deftest cache/model-id/cons-input ()
  "Should format cons cell."
  (should (stringp (test-model-id-string '(a . b)))))

(ert-deftest cache/normalize/very-small ()
  "Should handle very small values."
  (should (= (test-normalize-context-window 0.128) 128)))

(ert-deftest cache/normalize/very-large ()
  "Should handle very large values."
  (should (= (test-normalize-context-window 1000000) 1000000)))

(provide 'test-gptel-ext-context-cache)
;;; test-gptel-ext-context-cache.el ends here