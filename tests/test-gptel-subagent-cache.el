;;; test-gptel-subagent-cache.el --- Tests for subagent cache -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for subagent result caching in gptel-tools-agent.el
;; Covers cache hit/miss, TTL expiration, and disabled caching.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar my/gptel-subagent-cache-ttl 300)
(defvar my/gptel--subagent-cache (make-hash-table :test 'equal))

(declare-function my/gptel--subagent-cache-key "gptel-tools-agent")
(declare-function my/gptel--subagent-cache-get "gptel-tools-agent")
(declare-function my/gptel--subagent-cache-put "gptel-tools-agent")
(declare-function my/gptel--subagent-cache-clear "gptel-tools-agent")

(defun test--subagent-cache-setup ()
  "Clear cache and reset TTL for each test."
  (clrhash my/gptel--subagent-cache)
  (setq my/gptel-subagent-cache-ttl 300))

;;; Tests for cache key generation

(ert-deftest subagent-cache/key/consistent ()
  "Cache key should be consistent for same inputs."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (let ((key1 (my/gptel--subagent-cache-key "executor" "test prompt"))
        (key2 (my/gptel--subagent-cache-key "executor" "test prompt")))
    (should (equal key1 key2))))

(ert-deftest subagent-cache/key/different-agent-types ()
  "Cache key should differ for different agent types."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (let ((key1 (my/gptel--subagent-cache-key "executor" "test prompt"))
        (key2 (my/gptel--subagent-cache-key "reviewer" "test prompt")))
    (should-not (equal key1 key2))))

(ert-deftest subagent-cache/key/different-prompts ()
  "Cache key should differ for different prompts."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (let ((key1 (my/gptel--subagent-cache-key "executor" "prompt one"))
        (key2 (my/gptel--subagent-cache-key "executor" "prompt two")))
    (should-not (equal key1 key2))))

;;; Tests for cache put/get

(ert-deftest subagent-cache/put-then-get ()
  "Should retrieve cached result after put."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (my/gptel--subagent-cache-put "executor" "test prompt" "cached result")
  (should (equal (my/gptel--subagent-cache-get "executor" "test prompt") "cached result")))

(ert-deftest subagent-cache/miss-returns-nil ()
  "Should return nil for cache miss."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (should-not (my/gptel--subagent-cache-get "executor" "unknown prompt")))

(ert-deftest subagent-cache/overwrites-existing ()
  "Should overwrite existing cache entry."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (my/gptel--subagent-cache-put "executor" "test prompt" "first result")
  (my/gptel--subagent-cache-put "executor" "test prompt" "second result")
  (should (equal (my/gptel--subagent-cache-get "executor" "test prompt") "second result")))

(ert-deftest subagent-cache/empty-string-is-not-cacheable ()
  "Empty subagent results should not be cached or replayed as cache hits."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (my/gptel--subagent-cache-put "executor" "test prompt" "")
  (should (= (hash-table-count my/gptel--subagent-cache) 0))
  (let ((key (my/gptel--subagent-cache-key "executor" "manual prompt")))
    (puthash key (cons (float-time) "") my/gptel--subagent-cache)
    (should-not (my/gptel--subagent-cache-get "executor" "manual prompt"))
    (should (= (hash-table-count my/gptel--subagent-cache) 0))))

(ert-deftest subagent-cache/multiple-entries ()
  "Should store multiple cache entries independently."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (my/gptel--subagent-cache-put "executor" "prompt one" "result one")
  (my/gptel--subagent-cache-put "reviewer" "prompt two" "result two")
  (should (equal (my/gptel--subagent-cache-get "executor" "prompt one") "result one"))
  (should (equal (my/gptel--subagent-cache-get "reviewer" "prompt two") "result two")))

;;; Tests for TTL expiration

(ert-deftest subagent-cache/ttl-expired-returns-nil ()
  "Should return nil and evict expired entry."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (setq my/gptel-subagent-cache-ttl 1)
  (my/gptel--subagent-cache-put "executor" "test prompt" "cached result")
  (sleep-for 1.1)
  (should-not (my/gptel--subagent-cache-get "executor" "test prompt")))

(ert-deftest subagent-cache/ttl-not-expired-returns-result ()
  "Should return result when TTL not expired."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (setq my/gptel-subagent-cache-ttl 300)
  (my/gptel--subagent-cache-put "executor" "test prompt" "cached result")
  (should (equal (my/gptel--subagent-cache-get "executor" "test prompt") "cached result")))

;;; Tests for disabled caching (TTL=0)

(ert-deftest subagent-cache/ttl-zero-disables-put ()
  "Should not cache when TTL is 0."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (setq my/gptel-subagent-cache-ttl 0)
  (my/gptel--subagent-cache-put "executor" "test prompt" "cached result")
  (should (= (hash-table-count my/gptel--subagent-cache) 0)))

(ert-deftest subagent-cache/ttl-zero-disables-get ()
  "Should return nil when TTL is 0."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (setq my/gptel-subagent-cache-ttl 0)
  (should-not (my/gptel--subagent-cache-get "executor" "test prompt")))

;;; Tests for cache clear

(ert-deftest subagent-cache/clear-empties-cache ()
  "Should remove all entries."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (my/gptel--subagent-cache-put "executor" "prompt one" "result one")
  (my/gptel--subagent-cache-put "reviewer" "prompt two" "result two")
  (my/gptel--subagent-cache-clear)
  (should (= (hash-table-count my/gptel--subagent-cache) 0)))

;;; Tests for complex result types

(ert-deftest subagent-cache/stores-plist ()
  "Should store plist results."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (let ((result '(:status "done" :output "file created" :lines 42)))
    (my/gptel--subagent-cache-put "executor" "test prompt" result)
    (should (equal (my/gptel--subagent-cache-get "executor" "test prompt") result))))

(ert-deftest subagent-cache/stores-multiline-string ()
  "Should store multiline string results."
  (test--subagent-cache-setup)
  (load-file "lisp/modules/gptel-tools-agent.el")
  (let ((result "Line 1\nLine 2\nLine 3\n\nEnd"))
    (my/gptel--subagent-cache-put "executor" "test prompt" result)
    (should (equal (my/gptel--subagent-cache-get "executor" "test prompt") result))))

(provide 'test-gptel-subagent-cache)

;;; test-gptel-subagent-cache.el ends here
