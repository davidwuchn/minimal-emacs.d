;;; test-gptel-tools-agent-prompt-build.el --- Tests for skill loading -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; Regression tests for gptel-auto-workflow--load-skill.
;; Bug: gptel-auto-workflow--load-skill calls gptel-agent-read-file
;; unconditionally, but gptel-agent-read-file may not be loaded in
;; test environments (or when gptel-agent is unavailable).
;; This caused void-function errors in test runs that combined
;; production-metrics + ontology-predict + monitoring-agent tests.
;;
;; The fix: gptel-auto-workflow--load-skill must guard against
;; missing gptel-agent-read-file, returning a safe empty plist.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-prompt-build)
(require 'gptel-tools-agent-benchmark)  ; for gptel-auto-workflow--project-root

(ert-deftest test-load-skill/handles-missing-gptel-agent-read-file ()
  "load-skill should NOT throw void-function when gptel-agent-read-file is unbound.

Reproduces the production-metrics+ontology-predict+monitoring-agent
test isolation bug: when the skill file IS found but gptel-agent
is not loaded, the call to gptel-agent-read-file fails."
  (let ((test-skill-dir (expand-file-name "test-fixtures/fake-skill"
                                          (file-name-directory
                                           (symbol-file 'gptel-auto-workflow--load-skill)))))
    ;; Ensure test dir exists with a fake SKILL.md
    (make-directory test-skill-dir t)
    (with-temp-file (expand-file-name "SKILL.md" test-skill-dir)
      (insert "---\nsystem: test body\n---\n"))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'gptel-auto-workflow--find-skill-file)
                     (lambda (name)
                       (expand-file-name (format "%s/SKILL.md" name) test-skill-dir))))
            ;; Unbind gptel-agent-read-file to simulate test env
            (fmakunbound 'gptel-agent-read-file)
            ;; Should not throw void-function error
            (let ((result (gptel-auto-workflow--load-skill "test-skill")))
              (should (listp result))
              (should (stringp (plist-get result :body))))))
      ;; Cleanup
      (delete-directory test-skill-dir t)
      (ignore-errors (require 'gptel-agent nil t)))))

(ert-deftest test-load-skill-content/handles-missing-gptel-agent ()
  "load-skill-content should not throw when load-skill hits missing gptel-agent."
  (let ((test-skill-dir (expand-file-name "test-fixtures/fake-skill2"
                                          (file-name-directory
                                           (symbol-file 'gptel-auto-workflow--load-skill-content)))))
    (make-directory test-skill-dir t)
    (with-temp-file (expand-file-name "SKILL.md" test-skill-dir)
      (insert "---\nsystem: test body\n---\n"))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'gptel-auto-workflow--find-skill-file)
                     (lambda (name)
                       (expand-file-name (format "%s/SKILL.md" name) test-skill-dir))))
            (fmakunbound 'gptel-agent-read-file)
            ;; Should not throw
            (let ((result (gptel-auto-workflow--load-skill-content "test-skill")))
              (should (stringp result)))))
      (delete-directory test-skill-dir t)
      (ignore-errors (require 'gptel-agent nil t)))))

(ert-deftest test-load-skill-content/handles-skill-not-found ()
  "load-skill-content should return empty string when skill file doesn't exist."
  (let ((result (gptel-auto-workflow--load-skill-content "definitely-not-a-real-skill-xyzzy")))
    (should (stringp result))
    (should (equal result ""))))

(ert-deftest test-load-skill-metadata/handles-missing-gptel-agent ()
  "load-skill-metadata should return nil when gptel-agent-read-file is unbound."
  (unwind-protect
      (progn
        (fmakunbound 'gptel-agent-read-file)
        (let ((result (gptel-auto-workflow--load-skill-metadata "test-skill")))
          (should (null result))))
    (ignore-errors (require 'gptel-agent nil t))))

;; ─── Allium Request Queue Serialization Tests ───

(ert-deftest regression/prompt/allium-queue-blocks-while-busy ()
  "When busy, enqueue does not immediately dequeue new thunks.
Manually simulating in-flight state: busy is t, two enqueued
thunks must wait until release before executing in FIFO order."
  (let ((gptel-auto-experiment--allium-queue nil)
        (gptel-auto-experiment--allium-busy nil)
        (executed nil))
    ;; Simulate a request already in-flight
    (setq gptel-auto-experiment--allium-busy t)
    (gptel-auto-experiment--allium-enqueue (lambda () (push 'a executed)))
    (gptel-auto-experiment--allium-enqueue (lambda () (push 'b executed)))
    ;; Nothing should have run — the slot is busy
    (should-not executed)
    (should (= (length gptel-auto-experiment--allium-queue) 2))
    ;; Release the slot → first thunk ('a) executes, claims the slot
    (setq gptel-auto-experiment--allium-busy nil)
    (gptel-auto-experiment--allium-release)
    (should (equal executed '(a)))
    (should gptel-auto-experiment--allium-busy)    ; dequeue re-set it
    (should (= (length gptel-auto-experiment--allium-queue) 1))
    ;; Release again → second thunk ('b) executes
    (gptel-auto-experiment--allium-release)
    (should (equal executed '(b a)))
    ;; After thunk B runs, busy remains t — the thunk does not call
    ;; release (in real code gptel-request's async callback does that).
    ;; Manually reset for a clean drain check.
    (setq gptel-auto-experiment--allium-busy nil)
    (gptel-auto-experiment--allium-release) ; no-op (queue empty)
    (should-not gptel-auto-experiment--allium-queue)))

(ert-deftest regression/prompt/allium-queue-distill-check-chain ()
  "distill→check callback chain: check is enqueued while distill is in-flight.
Mock gptel-request to NOT fire the callback (simulating in-flight).
Verify only one gptel-request fires initially; after release the second fires."
  (let ((gptel-auto-experiment--allium-queue nil)
        (gptel-auto-experiment--allium-busy nil)
        (req-count 0)
        (pending-cbs nil))
    (cl-letf (((symbol-function 'gptel-auto-experiment--allium-compiler-prompt)
               (lambda () "test"))
              ((symbol-function 'gptel-request)
               (lambda (_prompt &rest args)
                 (cl-incf req-count)
                 (let ((cb (plist-get args :callback)))
                   (when cb (push cb pending-cbs))))))
      ;; Fire distill — it should enqueue and dispatch immediately
      (let ((distill-done nil))
        (gptel-auto-experiment--allium-distill
         "input"
         (lambda (spec)
           (should spec)
           (gptel-auto-experiment--allium-check
            spec
            (lambda (_issues) (setq distill-done t)))))
        ;; One gptel-request dispatched (distill)
        (should (= req-count 1))
        (should gptel-auto-experiment--allium-busy)
        (should (= (length gptel-auto-experiment--allium-queue) 0))
        ;; Simulate distill response arriving
        (let ((cb (pop pending-cbs)))
          (should cb)
          ;; The callback body calls user-cb which calls check → enqueues.
          ;; Then unwind-protect calls release → dequeue → runs check thunk.
          (funcall cb "spec-ok" nil))
        ;; Two gptel-requests total: distill + check
        (should (= req-count 2))
        ;; Now fire the check response
        (let ((cb (pop pending-cbs)))
          (should cb)
          (funcall cb "issues-ok" nil))
        (should-not gptel-auto-experiment--allium-busy)
        (should-not gptel-auto-experiment--allium-queue)
        (should distill-done)))))

(ert-deftest regression/prompt/allium-queue-fallback-no-gptel-request ()
  "When gptel-request is not fboundp, callback receives nil synchronously.
Queue machinery is not used — the sync fallback path runs directly."
  (let ((gptel-auto-experiment--allium-queue nil)
        (gptel-auto-experiment--allium-busy nil)
        (called nil))
    (cl-letf (((symbol-function 'gptel-request) nil))
      (gptel-auto-experiment--allium-distill "test" (lambda (v) (setq called t) (should-not v)))
      (should called)
      (should-not gptel-auto-experiment--allium-busy))))

(provide 'test-gptel-tools-agent-prompt-build)
;;; test-gptel-tools-agent-prompt-build.el ends here
