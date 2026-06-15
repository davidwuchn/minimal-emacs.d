;;; test-world-store-context.el --- Context unification tests -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for context unification (.edn sidecars, approval, risk).

;;; Code:

(require 'ert)

(condition-case err
    (require 'gptel-ext-world-store)
  (error
   (message "[world-store-test] Module load failed: %s" (error-message-string err))
   (defun ov5-world-store-connect () (error "brepl unavailable"))
   (defun ov5-world-store-disconnect () nil)
   (defun ov5-world-store-connected-p () nil)))

(defun test-world-store--skip-if-unavailable ()
  "Skip test if World Store/Datahike pod is unavailable."
  (unless (and (fboundp 'ov5-world-store--datahike-pod-available-p)
               (ov5-world-store--datahike-pod-available-p))
    (ert-skip "World Store/Datahike pod unavailable")))

(defvar test-world-store--context-counter 200)

(defun test-world-store--next-context-id ()
  "Generate a unique test ID."
  (setq test-world-store--context-counter (1+ test-world-store--context-counter))
  test-world-store--context-counter)

(defun test-world-store--with-context-store (body)
  "Run BODY with a fresh World Store connection."
  (let* ((id (test-world-store--next-context-id))
         (db-path (format "/tmp/ov5-ws-context-test-%d" id))
         (nrepl-port (+ 8100 id))
         (ov5-world-store-directory db-path)
         (ov5-world-store-nrepl-port nrepl-port))
    (test-world-store--skip-if-unavailable)
    (when (file-exists-p db-path)
      (delete-directory db-path t))
    (unwind-protect
        (progn
          (ov5-world-store-connect)
          (funcall body))
      (ov5-world-store-disconnect)
      (when (file-exists-p db-path)
        (delete-directory db-path t)))))

;; -----------------------------------------------------------------------------
;; Context Unification Tests

(ert-deftest world-store/unify-context-sidecar ()
  "Test unifying a context sidecar with an experiment."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-context-store
   (lambda ()
     ;; Create an experiment
     (ov5-world-store-transact
      '((:experiment/id "ctx-test#1"
         :experiment/target "foo.el"
         :experiment/decision "kept")))
     ;; Create a context sidecar
     (let* ((ctx-dir (make-temp-file "ov5-ctx-" t))
            (ctx-file (expand-file-name "1.edn" ctx-dir)))
       (with-temp-file ctx-file
         (insert "(:id 1 :target \"foo.el\" :business-rationale \"fix bug\" :causal-chain ((\"cause\" . \"effect\")) :decision-rationale \"good fix\" :learned \"test lesson\" :expected-impact \"better code\" :observed-impact \"confirmed\" :risk-score 0.2)\n"))
       ;; Unify context
       (let ((code (format "(load-file \"clj/ov5/world_store/context.clj\") (ns ov5.world-store.context) (ws/connect \"%s\") (unify-context-sidecar \"%s\")" ov5-world-store-directory ctx-file)))
         (ov5-world-store--brepl-eval code))
       ;; Verify unified entity has context data
       (let ((entity (ov5-world-store-entity :experiment/id "ctx-test#1")))
         (should (string-match-p ":context/business-rationale" entity))
         (should (string-match-p "fix bug" entity))
         (should (string-match-p ":context/learned" entity))
         (should (string-match-p "test lesson" entity)))
       ;; Cleanup
       (delete-directory ctx-dir t)))))

(ert-deftest world-store/unify-approval-history ()
  "Test unifying approval history with experiments."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-context-store
   (lambda ()
     ;; Create experiments
     (ov5-world-store-transact
      '((:experiment/id "app-test#1"
         :experiment/target "bar.el"
         :experiment/decision "kept")))
     ;; Create approval history
     (let ((app-file (make-temp-file "ov5-app-")))
       (with-temp-file app-file
         (insert "((:experiment-id 1 :target \"bar.el\" :decision \"kept\" :approval-type :auto-approved :timestamp \"2026-06-11T12:00:00Z\" :risk-score 0.3))\n"))
       ;; Unify approval
       (let ((code (format "(load-file \"clj/ov5/world_store/context.clj\") (ns ov5.world-store.context) (ws/connect \"%s\") (unify-approval-history \"%s\")" ov5-world-store-directory app-file)))
         (ov5-world-store--brepl-eval code))
       ;; Verify
       (let ((entity (ov5-world-store-entity :experiment/id "app-test#1")))
         (should (string-match-p ":approval/type" entity))
         (should (string-match-p ":auto-approved" entity)))
       ;; Cleanup
       (delete-file app-file)))))

(ert-deftest world-store/unify-risk-patterns ()
  "Test unifying risk patterns with experiments."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-context-store
   (lambda ()
     ;; Create experiment
     (ov5-world-store-transact
      '((:experiment/id "risk-test#1"
         :experiment/target "baz.el"
         :experiment/decision "kept")))
     ;; Create risk patterns
     (let ((risk-file (make-temp-file "ov5-risk-")))
       (with-temp-file risk-file
         (insert "((:pattern-name \"baz.el\" :approval-type :auto-approved :risk-factors (:scope-factor 0.1 :complexity-factor 0.2) :count 1 :confidence 0.8 :timestamp \"2026-06-11T12:00:00Z\"))\n"))
       ;; Unify risk
       (let ((code (format "(load-file \"clj/ov5/world_store/context.clj\") (ns ov5.world-store.context) (ws/connect \"%s\") (unify-risk-patterns \"%s\")" ov5-world-store-directory risk-file)))
         (ov5-world-store--brepl-eval code))
       ;; Verify
       (let ((entity (ov5-world-store-entity :experiment/id "risk-test#1")))
         (should (string-match-p ":risk/scope-factor" entity))
         (should (string-match-p "0.1" entity))
         (should (string-match-p ":risk/confidence" entity))
         (should (string-match-p "0.8" entity)))
       ;; Cleanup
       (delete-file risk-file)))))

;;; test-world-store-context.el ends here
