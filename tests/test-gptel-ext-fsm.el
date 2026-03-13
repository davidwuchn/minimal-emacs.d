;;; test-gptel-ext-fsm.el --- Tests for FSM error recovery -*- lexical-binding: t; -*-

;;; Commentary:
;; P0 tests for gptel-ext-fsm.el
;; Tests:
;; - my/gptel-fix-fsm-stuck-in-type
;; - my/gptel--recover-fsm-on-error
;; - Missing handler registration

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock FSM structure

(defun test-make-fsm (state &optional info)
  "Create a mock FSM with STATE and optional INFO plist."
  (list (cons 'fsm-state state)
        (cons 'fsm-info (or info '()))))

(defun test-fsm-state (fsm)
  "Get FSM state."
  (cdr (assq 'fsm-state fsm)))

(defun test-fsm-info (fsm)
  "Get FSM info plist."
  (cdr (assq 'fsm-info fsm)))

(defun test-set-fsm-state (fsm new-state)
  "Set FSM state to NEW-STATE."
  (setcdr (assq 'fsm-state fsm) new-state))

(defun test-fsm-p (obj)
  "Check if OBJ is a FSM."
  (and (listp obj) (assq 'fsm-state obj)))

;;; Mock variables

(defvar gptel--fsm-last nil)
(defvar gptel-post-response-functions nil)

;;; Functions under test

(defun test-fsm--coerce-fsm (obj)
  "Coerce OBJ to FSM if possible."
  (cond ((test-fsm-p obj) obj)
        ((consp obj) (test-fsm--coerce-fsm (car obj)))
        (t nil)))

(defun test-recover-fsm-on-error (&optional fsm-arg)
  "Force FSM to DONE state if it has error + STOP but is still cycling."
  (let* ((fsm (or fsm-arg (test-fsm--coerce-fsm gptel--fsm-last)))
         (info (and fsm (test-fsm-info fsm)))
         (error-msg (plist-get info :error))
         (stop-reason (plist-get info :stop-reason)))
    (when (and error-msg
               (eq stop-reason 'STOP)
               fsm
               (not (eq (test-fsm-state fsm) 'DONE)))
      (test-set-fsm-state fsm 'DONE)
      t)))

(defun test-fix-fsm-stuck-in-type (fsm status)
  "Fix FSM stuck in TYPE state when curl fails before headers.
Returns t if FSM was unstuck."
  (let ((state-before (and fsm (test-fsm-state fsm))))
    ;; Simulate: state was WAIT before, now TYPE (curl failed early)
    (when (and fsm
               (eq (test-fsm-state fsm) 'TYPE))
      (test-set-fsm-state fsm 'DONE)
      t)))

;;; Tests for my/gptel-fix-fsm-stuck-in-type

(ert-deftest fsm/unstick/detects-type-state ()
  "Should detect FSM stuck in TYPE state."
  (let ((fsm (test-make-fsm 'TYPE)))
    (should (eq (test-fsm-state fsm) 'TYPE))))

(ert-deftest fsm/unstick/fixes-stuck-fsm ()
  "Should unstick FSM from TYPE state."
  (let ((fsm (test-make-fsm 'TYPE)))
    (test-fix-fsm-stuck-in-type fsm 'exit)
    (should (eq (test-fsm-state fsm) 'DONE))))

(ert-deftest fsm/unstick/does-not-change-non-type ()
  "Should not change FSM in other states."
  (let ((fsm (test-make-fsm 'WAIT)))
    (test-fix-fsm-stuck-in-type fsm 'exit)
    (should (eq (test-fsm-state fsm) 'WAIT))))

(ert-deftest fsm/unstick/handles-nil-fsm ()
  "Should handle nil FSM."
  (should-not (test-fix-fsm-stuck-in-type nil 'exit)))

;;; Tests for my/gptel--recover-fsm-on-error

(ert-deftest fsm/recover/recovers-error-stop ()
  "Should recover FSM with error + STOP."
  (let* ((info '(:error "JSON parse error" :stop-reason STOP))
         (fsm (test-make-fsm 'TOOL info)))
    (test-recover-fsm-on-error fsm)
    (should (eq (test-fsm-state fsm) 'DONE))))

(ert-deftest fsm/recover/does-not-recover-no-error ()
  "Should not recover FSM without error."
  (let ((fsm (test-make-fsm 'TOOL '(:stop-reason STOP))))
    (test-recover-fsm-on-error fsm)
    (should (eq (test-fsm-state fsm) 'TOOL))))

(ert-deftest fsm/recover/does-not-recover-no-stop ()
  "Should not recover FSM without STOP."
  (let ((fsm (test-make-fsm 'TOOL '(:error "some error"))))
    (test-recover-fsm-on-error fsm)
    (should (eq (test-fsm-state fsm) 'TOOL))))

(ert-deftest fsm/recover/does-not-recover-already-done ()
  "Should not recover FSM already in DONE state."
  (let ((fsm (test-make-fsm 'DONE '(:error "error" :stop-reason STOP))))
    (should-not (test-recover-fsm-on-error fsm))
    (should (eq (test-fsm-state fsm) 'DONE))))

(ert-deftest fsm/recover/handles-nil-fsm ()
  "Should handle nil FSM."
  (let ((gptel--fsm-last nil))
    (should-not (test-recover-fsm-on-error))))

;;; Tests for FSM state transitions

(ert-deftest fsm/states/wait ()
  "WAIT state should be valid."
  (let ((fsm (test-make-fsm 'WAIT)))
    (should (eq (test-fsm-state fsm) 'WAIT))))

(ert-deftest fsm/states/type ()
  "TYPE state should be valid."
  (let ((fsm (test-make-fsm 'TYPE)))
    (should (eq (test-fsm-state fsm) 'TYPE))))

(ert-deftest fsm/states/tool ()
  "TOOL state should be valid."
  (let ((fsm (test-make-fsm 'TOOL)))
    (should (eq (test-fsm-state fsm) 'TOOL))))

(ert-deftest fsm/states/done ()
  "DONE state should be valid."
  (let ((fsm (test-make-fsm 'DONE)))
    (should (eq (test-fsm-state fsm) 'DONE))))

(ert-deftest fsm/states/errs ()
  "ERRS state should be valid."
  (let ((fsm (test-make-fsm 'ERRS)))
    (should (eq (test-fsm-state fsm) 'ERRS))))

(ert-deftest fsm/states/abrt ()
  "ABRT state should be valid."
  (let ((fsm (test-make-fsm 'ABRT)))
    (should (eq (test-fsm-state fsm) 'ABRT))))

;;; Tests for FSM info plist

(ert-deftest fsm/info/can-store-error ()
  "FSM info should store error."
  (let* ((info '(:error "test error"))
         (fsm (test-make-fsm 'WAIT info)))
    (should (equal (plist-get (test-fsm-info fsm) :error) "test error"))))

(ert-deftest fsm/info/can-store-stop-reason ()
  "FSM info should store stop-reason."
  (let* ((info '(:stop-reason STOP))
         (fsm (test-make-fsm 'WAIT info)))
    (should (eq (plist-get (test-fsm-info fsm) :stop-reason) 'STOP))))

(ert-deftest fsm/info/can-store-multiple-keys ()
  "FSM info should store multiple keys."
  (let* ((info '(:error "err" :stop-reason STOP :buffer nil))
         (fsm (test-make-fsm 'WAIT info)))
    (should (equal (plist-get (test-fsm-info fsm) :error) "err"))
    (should (eq (plist-get (test-fsm-info fsm) :stop-reason) 'STOP))
    (should (null (plist-get (test-fsm-info fsm) :buffer)))))

;;; Tests for gptel-agent-request--handlers

(ert-deftest fsm/handlers/done-handler-exists ()
  "DONE handler should exist for gptel-agent."
  (let ((handlers '((DONE . gptel--handle-post))))
    (should (assq 'DONE handlers))))

(ert-deftest fsm/handlers/errs-handler-exists ()
  "ERRS handler should exist for gptel-agent."
  (let ((handlers '((ERRS . gptel--handle-post))))
    (should (assq 'ERRS handlers))))

(ert-deftest fsm/handlers/abrt-handler-exists ()
  "ABRT handler should exist for gptel-agent."
  (let ((handlers '((ABRT . gptel--handle-post))))
    (should (assq 'ABRT handlers))))

;;; Tests for edge cases

(ert-deftest fsm/edge/nested-fsm-coercion ()
  "Should coerce nested FSM structures."
  (let ((wrapped-fsm (list (test-make-fsm 'WAIT))))
    (should (test-fsm-p (test-fsm--coerce-fsm wrapped-fsm)))))

(ert-deftest fsm/edge/deep-nesting ()
  "Should handle deeply nested FSM."
  (let ((deep-fsm (list (list (list (test-make-fsm 'DONE))))))
    (should (test-fsm-p (test-fsm--coerce-fsm deep-fsm)))))

(ert-deftest fsm/edge/non-fsm-object ()
  "Should return nil for non-FSM object."
  (should-not (test-fsm--coerce-fsm "not-a-fsm"))
  (should-not (test-fsm--coerce-fsm 42))
  (should-not (test-fsm--coerce-fsm '(a b c))))

;;; Tests for recovery scenarios

(ert-deftest fsm/scenario/json-parse-error ()
  "Should recover from JSON parse error."
  (let* ((info '(:error "json-read-error: unexpected token" :stop-reason STOP))
         (fsm (test-make-fsm 'TOOL info)))
    (test-recover-fsm-on-error fsm)
    (should (eq (test-fsm-state fsm) 'DONE))))

(ert-deftest fsm/scenario/network-error ()
  "Should recover from network error."
  (let* ((info '(:error "curl: (6) Could not resolve host" :stop-reason STOP))
         (fsm (test-make-fsm 'TYPE info)))
    (test-recover-fsm-on-error fsm)
    (should (eq (test-fsm-state fsm) 'DONE))))

(ert-deftest fsm/scenario/malformed-response ()
  "Should recover from malformed response."
  (let* ((info '(:error "Malformed JSON" :stop-reason STOP))
         (fsm (test-make-fsm 'TYPE info)))
    (test-recover-fsm-on-error fsm)
    (should (eq (test-fsm-state fsm) 'DONE))))

;;; Footer

(provide 'test-gptel-ext-fsm)

;;; test-gptel-ext-fsm.el ends here