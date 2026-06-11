;;; test-world-store-bootstrap.el --- Bootstrap tests for World Store -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-ext-world-store.el and clj/ov5/world_store.clj.
;; Each test uses an isolated database + nREPL port for independence.

;;; Code:

(require 'ert)

;; Load module under test (may fail if brepl unavailable; skip in that case)
(condition-case err
    (require 'gptel-ext-world-store)
  (error
   (message "[world-store-test] Module load failed: %s" (error-message-string err))
   (defun ov5-world-store-connect () (error "brepl unavailable"))
   (defun ov5-world-store-disconnect () nil)
   (defun ov5-world-store-connected-p () nil)))

(defvar test-world-store--test-counter 0
  "Counter for unique test IDs.")

(defun test-world-store--next-id ()
  "Generate a unique test ID."
  (setq test-world-store--test-counter (1+ test-world-store--test-counter))
  test-world-store--test-counter)

(defun test-world-store--with-store (body)
  "Run BODY with a fresh World Store connection.
Binds `ov5-world-store-directory' and `ov5-world-store-nrepl-port' uniquely."
  (let* ((id (test-world-store--next-id))
         (db-path (format "/tmp/ov5-ws-test-%d" id))
         (nrepl-port (+ 7800 id))
         (ov5-world-store-directory db-path)
         (ov5-world-store-nrepl-port nrepl-port))
    ;; Clean up any existing DB
    (when (file-exists-p db-path)
      (delete-directory db-path t))
    ;; Connect, run body, disconnect
    (unwind-protect
        (progn
          (ov5-world-store-connect)
          (funcall body))
      (ov5-world-store-disconnect)
      (when (file-exists-p db-path)
        (delete-directory db-path t)))))

;; -----------------------------------------------------------------------------
;; Connection Tests

(ert-deftest world-store/connect-and-disconnect ()
  "Test basic connection lifecycle."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (should (ov5-world-store-connected-p))
     (ov5-world-store-disconnect)
     (should-not (ov5-world-store-connected-p)))))

(ert-deftest world-store/reconnect-idempotent ()
  "Test that reconnecting is safe."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (should (ov5-world-store-connected-p))
     (should (ov5-world-store-connect))  ;; idempotent
     (should (ov5-world-store-connected-p)))))

;; -----------------------------------------------------------------------------
;; CRUD Tests

(ert-deftest world-store/transact-and-query ()
  "Test basic transact + query round-trip."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     ;; Transact an experiment
     (ov5-world-store-transact
      '((:experiment/id "exp-test-001"
         :experiment/target "test.el"
         :experiment/hypothesis "fix bug"
         :experiment/score-before 0.5
         :experiment/score-after 0.9
         :experiment/decision "kept"
         :experiment/backend "MiniMax"
         :experiment/strategy "direct")))
     ;; Query it back — Datalog returns #{[entity-id]} set
     (let ((result (ov5-world-store-query
                    "[:find ?e :where [?e :experiment/id \"exp-test-001\"]]")))
       (should (string-match-p "#{\\[" result))))))

(ert-deftest world-store/entity-lookup ()
  "Test entity lookup by attribute."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (ov5-world-store-transact
      '((:experiment/id "exp-test-002"
         :experiment/target "foo.el"
         :experiment/decision "discarded")))
     (let ((entity (ov5-world-store-entity :experiment/id "exp-test-002")))
       ;; Entity returns a plain map string
       (should (string-match-p ":experiment/id" entity))
       (should (string-match-p "exp-test-002" entity))
       (should (string-match-p ":experiment/target" entity))
       (should (string-match-p "foo.el" entity))))))

;; -----------------------------------------------------------------------------
;; Query Helper Tests

(ert-deftest world-store/experiments-by-target ()
  "Test target-based query."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (ov5-world-store-transact
      '((:experiment/id "exp-a" :experiment/target "bar.el" :experiment/decision "kept")
        (:experiment/id "exp-b" :experiment/target "bar.el" :experiment/decision "kept")))
     (let ((result (ov5-world-store-experiments-by-target "bar.el")))
       ;; Returns vector of maps as EDN string
       (should (string-match-p "exp-a" result))
       (should (string-match-p "exp-b" result))))))

(ert-deftest world-store/experiments-by-backend ()
  "Test backend-based query."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (ov5-world-store-transact
      '((:experiment/id "exp-c" :experiment/backend "Gemini" :experiment/decision "kept")
        (:experiment/id "exp-d" :experiment/backend "Gemini" :experiment/decision "discarded")))
     (let ((result (ov5-world-store-experiments-by-backend "Gemini")))
       (should (string-match-p "exp-c" result))
       (should (string-match-p "exp-d" result))))))

(ert-deftest world-store/backend-keep-rate ()
  "Test keep rate calculation."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (ov5-world-store-transact
      '((:experiment/id "exp-e" :experiment/backend "TestBackend" :experiment/decision "kept")
        (:experiment/id "exp-f" :experiment/backend "TestBackend" :experiment/decision "kept")
        (:experiment/id "exp-g" :experiment/backend "TestBackend" :experiment/decision "discarded")))
     (let ((rate (ov5-world-store-backend-keep-rate "TestBackend")))
       (should (numberp rate))
       (should (< 0.6 rate 0.7))))))

;; -----------------------------------------------------------------------------
;; Count Test

(ert-deftest world-store/experiment-count ()
  "Test experiment count."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-store
   (lambda ()
     (ov5-world-store-transact
      '((:experiment/id "count-1" :experiment/decision "kept")
        (:experiment/id "count-2" :experiment/decision "kept")))
     (let ((count (ov5-world-store-experiment-count)))
       (should (numberp count))
       (should (>= count 2))))))

;;; test-world-store-bootstrap.el ends here
