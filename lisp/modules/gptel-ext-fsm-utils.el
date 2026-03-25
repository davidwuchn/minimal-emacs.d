;;; gptel-ext-fsm-utils.el --- Shared FSM helpers -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; FSM coercion utilities with ID tracking for nested subagent scenarios.
;;
;; DESIGN PRINCIPLES (builds on discoveries from nested agent runs):
;; - Explicit assumptions: FSMs are uniquely identified by ID
;; - Testable definitions: Each FSM has predictable ID format
;; - Clear structure: ID tracking prevents wrong FSM in nested scenarios
;; - Adapts to new information: Context-aware FSM selection

;;; Code:

(require 'gptel)
(require 'cl-lib)

;;; FSM ID Registry

(defvar my/gptel--fsm-registry (make-hash-table :test 'equal :weakness 'value)
  "Registry mapping FSM IDs to FSM structs.
Uses weak values so FSMs can be garbage collected when no longer referenced.")

(defvar my/gptel--fsm-id-counter 0
  "Counter for generating unique FSM IDs.")

(defun my/gptel--fsm-generate-id ()
  "Generate a unique FSM ID.
Format: fsm-N-TIMESTAMP where N is counter and TIMESTAMP is epoch."
  (format "fsm-%d-%d" (cl-incf my/gptel--fsm-id-counter) (float-time)))

(defun my/gptel--fsm-register (fsm)
  "Register FSM in the registry and return its ID.
ASSUMPTION: FSM is a valid gptel-fsm struct.
BEHAVIOR: Assigns unique ID if not already registered.
EDGE CASE: Nil FSM returns nil."
  (when fsm
    (let ((existing-id (gethash fsm my/gptel--fsm-registry)))
      (or existing-id
          (let ((id (my/gptel--fsm-generate-id)))
            (puthash fsm id my/gptel--fsm-registry)
            (puthash id fsm my/gptel--fsm-registry)
            id)))))

(defun my/gptel--fsm-unregister (fsm-or-id)
  "Remove FSM from registry by FSM struct or ID.
ADAPTS to being called with either type."
  (when fsm-or-id
    (if (stringp fsm-or-id)
        (let ((fsm (gethash fsm-or-id my/gptel--fsm-registry)))
          (when fsm
            (remhash fsm my/gptel--fsm-registry)
            (remhash fsm-or-id my/gptel--fsm-registry)))
      (let ((id (gethash fsm-or-id my/gptel--fsm-registry)))
        (when id
          (remhash fsm-or-id my/gptel--fsm-registry)
          (remhash id my/gptel--fsm-registry))))))

(defun my/gptel--fsm-get-by-id (id)
  "Retrieve FSM by ID from registry.
TEST: Returns nil for unknown ID."
  (gethash id my/gptel--fsm-registry))

;;; FSM Predicates and Coercion

(defun my/gptel--fsm-p (object)
  "Return non-nil when OBJECT behaves like a `gptel-fsm'.
TEST: Should return t for valid FSM, nil otherwise."
  (ignore-errors
    (gptel-fsm-state object)
    t))

(defun my/gptel--coerce-fsm (object &optional context-id)
  "Return the FSM matching CONTEXT-ID from OBJECT, or first FSM if no match.

OBJECT may be an FSM struct, request-alist entry, or nested structure.
CONTEXT-ID when provided returns only FSM with matching ID.
This prevents wrong FSM selection in nested subagent scenarios.

BUILDS ON DISCOVERY: Parent and child FSMs can coexist in nested calls.
ADAPTS TO: Context-aware selection when ID provided.

Returns FSM struct or nil if not found."
  (cond
   ((my/gptel--fsm-p object)
    (let ((id (when context-id (gethash object my/gptel--fsm-registry))))
      (if (and context-id id (not (equal id context-id)))
          nil
        object)))
   ((consp object)
    (or (my/gptel--coerce-fsm (car object) context-id)
        (my/gptel--coerce-fsm (cdr object) context-id)))
   (t nil)))

(defun my/gptel--coerce-fsm-with-context (object)
  "Return FSM with context-aware selection.

In nested subagent scenarios, prefers the most recent FSM
(which is likely the child FSM currently being processed).

This fixes the TODO issue where first FSM was always returned,
potentially selecting wrong FSM in nested scenarios."
  (let* ((all-fsms (my/gptel--collect-all-fsms object))
         (count (length all-fsms)))
    (cond
     ((zerop count) nil)
     ((= count 1) (car all-fsms))
     (t
      ;; Multiple FSMs: prefer most recently registered
      ;; (likely the child FSM in nested scenarios)
      (car (last all-fsms))))))

(defun my/gptel--collect-all-fsms (object)
  "Collect all FSMs found in OBJECT as a list.
TEST: Should find all FSMs in nested structure."
  (let ((result '()))
    (my/gptel--collect-fsms-recursive object result)
    (nreverse result)))

(defun my/gptel--collect-fsms-recursive (object result)
  "Recursively collect FSMs from OBJECT into RESULT list."
  (cond
   ((my/gptel--fsm-p object)
    (push object result))
   ((consp object)
    (my/gptel--collect-fsms-recursive (car object) result)
    (my/gptel--collect-fsms-recursive (cdr object) result))))

(defun my/gptel--fsm-depth (object)
  "Return nesting depth of FSMs in OBJECT.
TEST: Single FSM returns 1, nested returns 2+.
Useful for detecting nested subagent scenarios."
  (length (my/gptel--collect-all-fsms object)))

(provide 'gptel-ext-fsm-utils)

;;; gptel-ext-fsm-utils.el ends here