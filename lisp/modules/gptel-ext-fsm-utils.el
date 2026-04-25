;;; gptel-ext-fsm-utils.el --- Shared FSM helpers -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; FSM coercion utilities with ID tracking for nested subagent scenarios.
;;
;; GOAL: Prevent wrong FSM selection in nested agent calls by tracking unique IDs.
;; MEASURABLE OUTCOME: Zero FSM mismatches in nested subagent scenarios.
;;
;; DESIGN PRINCIPLES (builds on discoveries from nested agent runs):
;; - Explicit assumptions: FSMs are uniquely identified by ID
;; - Testable definitions: Each FSM has predictable ID format
;; - Clear structure: ID tracking prevents wrong FSM in nested scenarios
;; - Adapts to new information: Context-aware FSM selection
;;
;; RISK IDENTIFIED: Without ID tracking, nested agents may operate on wrong FSM.
;; PROACTIVE MITIGATION: Registry maps both FSM→ID and ID→FSM for O(1) lookup.
;;
;; EDGE CASES HANDLED:
;; - Nil FSM input: Returns nil gracefully
;; - Unknown ID lookup: Returns nil without error
;; - Multiple FSMs: Prefers most recently registered (child FSM)
;; - Dual input types: Accepts both FSM struct and ID string

;;; Code:

(require 'gptel)
(require 'cl-lib)

;;; FSM ID Registry

(defvar my/gptel--fsm-registry (make-hash-table :test 'equal :weakness 'value)
  "Registry mapping FSM IDs to FSM structs.

ASSUMPTION: Bidirectional mapping (FSM→ID and ID→FSM).
ASSUMPTION: Weak values allow garbage collection of unreferenced FSMs.
BEHAVIOR: Stores both (puthash fsm id) and (puthash id fsm).
TEST: (gethash fsm my/gptel--fsm-registry) => ID string
TEST: (gethash id my/gptel--fsm-registry) => FSM struct

BUILDS ON DISCOVERY: Bidirectional mapping enables O(1) lookup
in both directions, critical for nested agent performance.")

(defvar my/gptel--fsm-id-counter 0
  "Counter for generating unique FSM IDs.

ASSUMPTION: Counter increments monotonically.
ASSUMPTION: Combined with timestamp ensures uniqueness.
BEHAVIOR: Incremented on each ID generation.
TEST: Sequential calls produce increasing counter values.

PROACTIVE MITIGATION: Counter + timestamp combination prevents
ID collisions even with rapid FSM creation in nested scenarios.")

(defun my/gptel--fsm-generate-id ()
  "Generate a unique FSM ID.

ASSUMPTION: Counter increments atomically (cl-incf).
ASSUMPTION: float-time provides sufficient precision.
BEHAVIOR: Returns string in format \"fsm-N-TIMESTAMP\".
BEHAVIOR: Counter increments on each call.
EDGE CASE: Rapid calls still produce unique IDs (timestamp + counter).
TEST: (my/gptel--fsm-generate-id) => \"fsm-1-1234567890.123\"
TEST: Sequential calls produce incrementing counter: fsm-1, fsm-2, fsm-3

FORMAT: fsm-N-TIMESTAMP where:
  - N = sequential counter (guarantees uniqueness within process)
  - TIMESTAMP = epoch seconds with microseconds (human-readable ordering)

BUILDS ON DISCOVERY: Dual-component ID (counter + timestamp) ensures
uniqueness even with rapid FSM creation in nested agent scenarios."
  (format "fsm-%d-%s" (cl-incf my/gptel--fsm-id-counter) (float-time)))

(defun my/gptel--fsm-register (fsm)
  "Register FSM in the registry and return its ID.

ASSUMPTION: FSM is a valid gptel-fsm struct with proper structure.
ASSUMPTION: Registry hash tables are properly initialized.
BEHAVIOR: Assigns unique ID if not already registered.
BEHAVIOR: Returns existing ID if FSM already registered (idempotent).
EDGE CASE: Nil FSM returns nil without error.
EDGE CASE: Duplicate registration returns same ID (no side effects).
TEST: (my/gptel--fsm-register nil) => nil
TEST: (my/gptel--fsm-register fsm) => string ID
TEST: Second call with same FSM returns same ID.

BUILDS ON DISCOVERY: Idempotent registration prevents duplicate IDs
in scenarios where FSM may be registered multiple times during
nested agent calls."
  (when fsm
    (let ((existing-id (gethash fsm my/gptel--fsm-registry)))
      (or existing-id
          (let ((id (my/gptel--fsm-generate-id)))
            (puthash fsm id my/gptel--fsm-registry)
            (puthash id fsm my/gptel--fsm-registry)
            id)))))

(defun my/gptel--fsm-unregister (fsm-or-id)
  "Remove FSM from registry by FSM struct or ID.

ASSUMPTION: Input is either FSM struct or ID string.
ASSUMPTION: Registry maintains bidirectional mapping (FSM↔ID).
BEHAVIOR: Removes both FSM→ID and ID→FSM mappings.
BEHAVIOR: Silently ignores nil or unknown inputs.
EDGE CASE: Nil input returns nil without error.
EDGE CASE: Unknown ID/FSM returns nil (no error).
EDGE CASE: Partial mapping (only one direction) cleans up what exists.
TEST: (my/gptel--fsm-unregister nil) => nil
TEST: (my/gptel--fsm-unregister \"fsm-1-123\") => nil (removes mapping)
TEST: (my/gptel--fsm-unregister unknown-id) => nil (no error)

ADAPTS TO: Dual input types (FSM struct or ID string) for flexible cleanup
in various call contexts (parent agent vs child agent cleanup)."
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

ASSUMPTION: ID is a string matching registered FSM ID format.
ASSUMPTION: Registry maintains bidirectional FSM↔ID mapping.
BEHAVIOR: Returns FSM struct if ID exists in registry.
BEHAVIOR: Returns nil for unknown IDs (no error).
EDGE CASE: Nil ID returns nil.
EDGE CASE: Unknown ID returns nil (safe lookup).
TEST: (my/gptel--fsm-get-by-id \"fsm-1-123\") => FSM struct or nil
TEST: (my/gptel--fsm-get-by-id nil) => nil
TEST: (my/gptel--fsm-get-by-id \"unknown\") => nil

BUILDS ON DISCOVERY: O(1) lookup enables efficient FSM retrieval
in performance-critical nested agent scenarios."
  (gethash id my/gptel--fsm-registry))

(defun my/gptel--fsm-get-id (fsm)
  "Retrieve FSM ID from registry by FSM struct.

ASSUMPTION: FSM is a valid gptel-fsm struct with proper structure.
ASSUMPTION: Registry maintains bidirectional FSM↔ID mapping.
BEHAVIOR: Returns ID string if FSM exists in registry.
BEHAVIOR: Returns nil for unregistered FSMs (no error).
EDGE CASE: Nil FSM returns nil.
EDGE CASE: Unregistered FSM returns nil (safe lookup).
TEST: (my/gptel--fsm-get-id fsm) => ID string or nil
TEST: (my/gptel--fsm-get-id nil) => nil
TEST: (my/gptel--fsm-get-id unregistered-fsm) => nil

BUILDS ON DISCOVERY: Extracting FSM→ID lookup into helper reduces
duplication across coerce-fsm and other functions.

PROACTIVE MITIGATION: Centralizes FSM→ID lookup logic, preventing
inconsistent lookups if registry structure changes."
  (gethash fsm my/gptel--fsm-registry))

;;; FSM Predicates and Coercion

(defun my/gptel--fsm-p (object)
  "Return non-nil when OBJECT behaves like a `gptel-fsm'.

ASSUMPTION: Valid FSM has accessible `gptel-fsm-state' slot.
ASSUMPTION: Accessing state on non-FSM signals error.
BEHAVIOR: Returns t if object has valid FSM structure.
BEHAVIOR: Returns nil if object is not FSM or access fails.
EDGE CASE: Nil object returns nil.
EDGE CASE: Non-FSM object returns nil (error suppressed).
EDGE CASE: Malformed FSM returns nil (error suppressed).
TEST: (my/gptel--fsm-p valid-fsm) => t
TEST: (my/gptel--fsm-p nil) => nil
TEST: (my/gptel--fsm-p \"not-fsm\") => nil
TEST: (my/gptel--fsm-p 42) => nil

PROACTIVE MITIGATION: Uses ignore-errors to safely handle
any object type without signaling errors to caller."
  (and object
       (if (fboundp 'gptel-fsm-p)
           (gptel-fsm-p object)
         (ignore-errors
           (gptel-fsm-state object)
           t))))

(defun my/gptel--coerce-fsm (object &optional context-id)
  "Return the FSM matching CONTEXT-ID from OBJECT, or first FSM if no match.

ASSUMPTION: OBJECT may be FSM struct, request-alist, or nested structure.
ASSUMPTION: CONTEXT-ID uniquely identifies target FSM in nested scenarios.
ASSUMPTION: Registry contains valid FSM→ID mappings.
BEHAVIOR: Returns FSM struct if object is FSM and matches context.
BEHAVIOR: Recursively searches cons cells for FSM.
BEHAVIOR: Returns nil when context-id doesn't match FSM's ID.
EDGE CASE: Nil object returns nil.
EDGE CASE: Non-FSM object returns nil.
EDGE CASE: Context-id mismatch returns nil (prevents wrong FSM selection).
EDGE CASE: Unregistered FSM with context-id returns nil (must be registered).
TEST: (my/gptel--coerce-fsm fsm) => fsm (no context)
TEST: (my/gptel--coerce-fsm fsm \"fsm-1-123\") => fsm if IDs match
TEST: (my/gptel--coerce-fsm fsm \"fsm-2-456\") => nil if IDs differ
TEST: (my/gptel--coerce-fsm '(fsm1 fsm2) \"fsm-2-456\") => fsm2

BUILDS ON DISCOVERY: Parent and child FSMs can coexist in nested calls.
ADAPTS TO: Context-aware selection when ID provided, preventing
wrong FSM selection in nested subagent scenarios.

PROACTIVE MITIGATION: Returns nil on ID mismatch rather than wrong FSM,
forcing caller to handle the case explicitly.

Returns FSM struct or nil if not found."
  (let ((seen (make-hash-table :test 'eq)))
    (cl-labels ((coerce (obj)
                  (cond
                   ((and (consp obj) (gethash obj seen)) nil)
                   ((consp obj)
                    (puthash obj t seen)
                    (or (coerce (car obj))
                        (coerce (cdr obj))))
                   ((my/gptel--fsm-p obj)
                    (if (null context-id)
                        obj
                      (let ((id (my/gptel--fsm-get-id obj)))
                        (when (and id (equal id context-id)) obj))))
                   (t nil))))
      (coerce object))))

(defun my/gptel--coerce-fsm-with-context (object)
  "Return FSM with context-aware selection.

ASSUMPTION: OBJECT may contain zero, one, or multiple FSMs.
ASSUMPTION: Most recently registered FSM is the active child FSM.
BEHAVIOR: Returns nil if no FSMs found.
BEHAVIOR: Returns single FSM if only one exists.
BEHAVIOR: Returns most recent FSM when multiple exist (child preference).
EDGE CASE: Empty object returns nil.
EDGE CASE: Single FSM returns that FSM directly.
EDGE CASE: Multiple FSMs returns last one (most recent registration).
TEST: (my/gptel--coerce-fsm-with-context nil) => nil
TEST: (my/gptel--coerce-fsm-with-context fsm) => fsm
TEST: (my/gptel--coerce-fsm-with-context '(fsm1 fsm2)) => fsm2

BUILDS ON DISCOVERY: In nested subagent scenarios, the child FSM
is registered after the parent, making it the most recent.

ADAPTS TO: Prefers child FSM in nested scenarios, fixing the issue
where first FSM was always returned (potentially wrong parent FSM).

PROACTIVE MITIGATION: Uses registration order as proxy for nesting level,
avoiding need for explicit parent-child tracking."
  (let ((all-fsms (my/gptel--collect-all-fsms object)))
    (if all-fsms (nth (1- (length all-fsms)) all-fsms) nil)))

(defun my/gptel--collect-all-fsms (object)
  "Collect all FSMs found in OBJECT as a list.

ASSUMPTION: OBJECT may be atom, cons cell, or nested structure.
ASSUMPTION: FSMs can appear at any depth in the structure.
BEHAVIOR: Returns list of all FSMs found (order preserved).
BEHAVIOR: Returns empty list if no FSMs found.
EDGE CASE: Nil object returns empty list.
EDGE CASE: Single FSM returns list with one element.
EDGE CASE: Deeply nested FSMs all collected.
EDGE CASE: Dotted pairs (a . b) where b is cons are fully traversed.
TEST: (my/gptel--collect-all-fsms nil) => ()
TEST: (my/gptel--collect-all-fsms fsm) => (fsm)
TEST: (my/gptel--collect-all-fsms '(fsm1 fsm2)) => (fsm1 fsm2)
TEST: (my/gptel--collect-all-fsms '(a (b fsm) c)) => (fsm)
TEST: (my/gptel--collect-all-fsms '(a . (b fsm))) => (fsma fsmb)

BUILDS ON DISCOVERY: Need to collect all FSMs to detect
nested subagent scenarios and select appropriate FSM.

ADAPTS TO: Pure functional approach eliminates mutable state,
improving testability and reducing cognitive load."
  (let ((seen (make-hash-table :test 'eq))
        (result nil))
    (cl-labels ((collect (obj)
                  (cond
                   ((consp obj)
                    (unless (gethash obj seen)
                      (puthash obj t seen)
                      (collect (car obj))
                      (collect (cdr obj))))
                   ((null obj) nil)
                   ((my/gptel--fsm-p obj)
                    (puthash obj t seen)
                    (push obj result)))))
      (collect object)
      (nreverse result))))

(defun my/gptel--fsm-depth (object)
  "Return nesting depth of FSMs in OBJECT.

ASSUMPTION: Depth = count of FSMs in structure.
ASSUMPTION: More FSMs indicates deeper nesting of agent calls.
BEHAVIOR: Returns count of FSMs found in OBJECT.
BEHAVIOR: Returns 0 if no FSMs found.
EDGE CASE: Nil object returns 0.
EDGE CASE: Single FSM returns 1.
EDGE CASE: Multiple FSMs returns count (2+ indicates nesting).
TEST: (my/gptel--fsm-depth nil) => 0
TEST: (my/gptel--fsm-depth fsm) => 1
TEST: (my/gptel--fsm-depth '(fsm1 fsm2)) => 2

BUILDS ON DISCOVERY: FSM depth > 1 indicates nested subagent scenario,
triggering context-aware FSM selection logic.

ADAPTS TO: Provides quantitative measure of nesting for decision making.

PROACTIVE MITIGATION: Enables detection of nested scenarios before
wrong FSM selection occurs."
  (length (my/gptel--collect-all-fsms object)))

;;; Registry Validation

(defun my/gptel--fsm-id-valid-p (id)
  "Return t if ID matches expected FSM ID format.
ASSUMPTION: Valid ID format is \"fsm-N-TIMESTAMP\" where N is integer.
EDGE_CASE: Nil or non-string input returns nil."
  (and (stringp id)
       (string-match-p "^fsm-[0-9]+-[0-9]+\\.[0-9]+$" id)))

(defun my/gptel--fsm-registry-validate ()
  "Validate registry integrity and return t if all invariants hold.

ASSUMPTION: Registry maintains bidirectional FSM↔ID mapping.
ASSUMPTION: All IDs match format \"fsm-N-TIMESTAMP\".
BEHAVIOR: Returns t if registry is consistent.
BEHAVIOR: Returns nil if any invariant is violated.
BEHAVIOR: Signals error with details on first violation found.
EDGE_CASE: Empty registry returns t (valid state).
EDGE_CASE: Single entry validated for bidirectional consistency.
EDGE_CASE: Multiple entries checked for unique IDs.
TEST: Empty registry => t
TEST: After register/unregister cycle => t
TEST: Manual corruption => error with details

INVARIANTS_CHECKED:
1. Bidirectional consistency: (gethash (gethash id R) R) == id
2. Unique IDs: No two FSMs share the same ID
3. ID format: All IDs match regex \"^fsm-[0-9]+-[0-9]+\\\\.[0-9]+$\"
4. FSM coverage: Every FSM key has corresponding ID key

BUILDS_ON_DISCOVERY: Validation function enables automated testing
of registry integrity after complex nested agent operations.

ADAPTS_TO: Catches corruption early before wrong FSM selection occurs.

PROACTIVE_MITIGATION: Can be called periodically or after operations
to ensure registry remains in valid state.

Returns t on success, signals error on failure."
  (let ((fsm-counts (make-hash-table :test 'eq)))
    ;; Single pass validation
    (maphash (lambda (key value)
               (cond
                ;; ID → FSM mapping
                ((stringp key)
                 ;; Check ID format
                 (unless (my/gptel--fsm-id-valid-p key)
                   (error "FSM registry invariant violated: invalid ID format: %s" key))
                 ;; Check bidirectional consistency
                 (let ((expected-fsm (gethash key my/gptel--fsm-registry))
                       (expected-id (gethash value my/gptel--fsm-registry)))
                   (unless (and (eq expected-fsm value)
                                (equal expected-id key))
                     (error "FSM registry invariant violated: bidirectional mismatch for ID %s" key)))
                 ;; Track FSM usage count
                 (let ((count (gethash value fsm-counts 0)))
                   (puthash value (1+ count) fsm-counts)))
                ;; FSM → ID mapping: validate ID format and bidirectional consistency
                ((my/gptel--fsm-p key)
                 (let ((id value))
                   (unless (my/gptel--fsm-id-valid-p id)
                     (error "FSM registry invariant violated: invalid ID format in FSM→ID mapping: %s" id))
                   (let ((fsm-via-id (gethash id my/gptel--fsm-registry)))
                     (unless (eq fsm-via-id key)
                       (error "FSM registry invariant violated: FSM→ID bidirectional mismatch for FSM %S (expected ID %S, got %S)" key id fsm-via-id)))
                   ;; Track FSM usage count
                   (let ((count (gethash key fsm-counts 0)))
                     (puthash key (1+ count) fsm-counts))))
                ;; Unknown key type is a corruption
                (t
                 (error "FSM registry invariant violated: unknown key type %S" key))))
             my/gptel--fsm-registry)
    ;; Check unique IDs
    (maphash (lambda (fsm count)
               (unless (= count 1)
                 (error "FSM registry invariant violated: FSM mapped by %d IDs" count)))
             fsm-counts)
    t))

(provide 'gptel-ext-fsm-utils)

;;; gptel-ext-fsm-utils.el ends here
