;;; nucleus-tools.el --- Tool definitions for nucleus -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Canonical tool definitions for nucleus gptel-agent presets.
;; This module consolidates tool lists and provides sanity checking.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;;; Customization

(defgroup nucleus-tools nil
  "Tool definitions and sanity checking for nucleus."
  :group 'nucleus)

(defcustom nucleus-tools-verbose nil
  "When non-nil, log tool sanity check messages."
  :type 'boolean
  :group 'nucleus-tools)

(defcustom nucleus-tools-sanity-check nil
  "When non-nil, run tool sanity check on preset changes.
Disable if experiencing recursion issues."
  :type 'boolean
  :group 'nucleus-tools)

(defcustom nucleus-tools-strict-validation t
  "When non-nil, enforce strict tool contract validation at runtime.
May impact performance but catches tool misuse early.

When enabled, validates:
  - Argument types (string, integer, number, boolean, array, object)
  - String constraints (pattern, minLength, maxLength, enum)
  - Number constraints (minimum, maximum, exclusive bounds)
  - Array constraints (minItems, maxItems)"
  :type 'boolean
  :group 'nucleus-tools)

;;; Toolset Definitions

(defconst nucleus-toolsets
  '((:readonly . ("Bash" "Eval" "Glob" "Grep" "Read" "RunAgent" "Skill" "TodoWrite"
                  "Programmatic"
                  "WebFetch" "WebSearch"
                  "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                  "Code_Map" "Code_Inspect" "Diagnostics" "Code_Usages"))
    (:researcher . ("Bash" "Eval" "Glob" "Grep" "Read" "Skill" "Programmatic"
                    "WebFetch" "WebSearch" "YouTube"
                    "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                    "Code_Map" "Code_Inspect" "Code_Usages" "Diagnostics"))
    (:nucleus . ("ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
                 "Insert" "Mkdir" "Move" "Read" "Skill" "TodoWrite"
                 "RunAgent"
                 "WebFetch" "WebSearch" "Write" "YouTube" "Programmatic"
                 "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                 "Preview"
                 "create_skill"
                 "Code_Map" "Code_Inspect" "Code_Replace" "Diagnostics" "Code_Usages"))
    (:executor . ("ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
                  "Insert" "Mkdir" "Move" "Read" "Skill" "TodoWrite"
                  "WebFetch" "WebSearch" "Write" "YouTube" "Programmatic"
                  "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                  "Preview"
                  "create_skill"
                  "Code_Map" "Code_Inspect" "Code_Replace" "Diagnostics" "Code_Usages"))
    (:explorer . ("Glob" "Grep" "Read" "Code_Map" "Code_Inspect"))
    (:reviewer . ("Glob" "Grep" "Read" "Diagnostics"))
    (:analyzer . ("Bash" "Read" "Glob" "Grep" "Code_Map"
                  "Diagnostics" "Programmatic"))
    (:comparator . ("Read" "Glob" "Grep"))
    (:grader . ("Read" "Glob" "Grep" "Bash" "Eval")))
  "Canonical toolset definitions for nucleus.

:readonly — Emacs introspection (18 tools): Eval, RunAgent, web search
:researcher — Codebase + web research (17 tools): Full analysis capability
:nucleus — Top-level action tools (28 tools): Includes RunAgent for orchestration
:executor — Subagent execution tools (27 tools): No RunAgent (prevent recursive delegation)
:explorer — Codebase exploration (5 tools): Glob, Grep, Read, Code_Map, Code_Inspect
:reviewer — Code review (4 tools): Read-only + Diagnostics
:analyzer — Benchmark analysis (7 tools): Live runtime analyzer tools
:comparator — A/B comparison (3 tools): Read, Glob, Grep
:grader — Assertion grading (5 tools): Read, Glob, Grep, Bash, Eval

:snippets is derived from :nucleus at runtime (see `nucleus-get-tools').

Tool contracts enforced in `nucleus--override-gptel-agent-presets':
  executor     → :executor    (27 tools) - code changes & execution (no RunAgent)
  researcher   → :researcher  (17 tools) - web + codebase + Eval
  introspector → :readonly    (18 tools) - Emacs introspection + web search
  explorer     → :explorer     (5 tools) - codebase exploration + Code tools
  reviewer     → :reviewer     (4 tools) - code review + Diagnostics
  analyzer     → :analyzer     (7 tools) - benchmark result analysis
  comparator   → :comparator   (3 tools) - blind A/B comparison
  grader       → :grader       (5 tools) - assertion grading")

(defconst nucleus-agent-tool-contracts
  '(("executor"     . :executor)
    ("researcher"   . :researcher)
    ("introspector" . :readonly)
    ("explorer"     . :explorer)
    ("reviewer"     . :reviewer)
    ("analyzer"     . :analyzer)
    ("comparator"   . :comparator)
    ("grader"       . :grader))
  "Mapping from gptel-agent agent names to their expected nucleus toolset keys.
Used by `nucleus--override-gptel-agent-presets' and contract validation.")

(defun nucleus--declared-tools (set-name)
  "Return declared tool names for SET-NAME without registration filtering.

SET-NAME can be a symbol from `nucleus-toolsets' or a list of tool names.
:snippets is derived from :nucleus (tools that have prompt snippets)."
  (pcase set-name
    (:snippets
     ;; Derived from :nucleus — all tools get prompt snippets
     (or (alist-get :nucleus nucleus-toolsets)
         (user-error "Unknown toolset: :nucleus (needed for :snippets)")))
    ((and (pred symbolp) name)
     (or (alist-get name nucleus-toolsets)
         (user-error "Unknown toolset: %S" name)))
    ((and (pred listp) t-list) t-list)
    (_ (user-error "Invalid toolset specifier: %S" set-name))))

(defun nucleus-get-tools (set-name)
  "Return tool list for SET-NAME, filtering out unregistered tools.

SET-NAME can be a symbol from `nucleus-toolsets' or a list of tool names.
Returns a list of currently registered tool name strings."
  (let ((tools (nucleus--declared-tools set-name)))
    (seq-filter (lambda (tool-name)
                  (let ((found (if (fboundp 'gptel-get-tool)
                                   (ignore-errors (gptel-get-tool tool-name))
                                  t)))
                    (unless found
                      (message "[nucleus] WARNING: Tool '%s' requested in set '%s' but not registered" tool-name set-name))
                    found))
                tools)))

;;; Tool Name Resolution

(defun nucleus--tool-name (tool)
  "Return TOOL name as a string when possible.

Handles string, plist, and gptel-tool struct formats."
  (cond
   ((stringp tool) tool)
   ((and (fboundp 'gptel-tool-name) tool)
    (ignore-errors (gptel-tool-name tool)))
   ((and (listp tool) (plist-get tool :name))
    (plist-get tool :name))
   (t nil)))

(defun nucleus--tool-names-from-tools (tools)
  "Return tool name strings from TOOLS list."
  (delq nil (mapcar #'nucleus--tool-name tools)))

;;; Tool Sanity Checking

(defvar-local nucleus--tool-sanity-last-report nil
  "Last tool sanity mismatch reported in this buffer.")

(defun nucleus--expected-tools-for-preset (&optional preset)
  "Return expected tool names for PRESET.

PRESET defaults to `gptel--preset` if not provided.
Returns nil if preset is unknown."
  (pcase (or preset (and (boundp 'gptel--preset) gptel--preset))
    ('gptel-plan (nucleus-get-tools :readonly))
    ('gptel-agent (nucleus-get-tools :nucleus))
    (_ nil)))

(cl-defun nucleus-tool-sanity-check (&optional preset context)
  "Check if current `gptel-tools` matches expected tools for PRESET.

Logs a message when there's a mismatch.  Use CONTEXT to identify
the caller (e.g., \"after-preset\", \"mode-hook\").

Returns non-nil if tools match, nil if mismatch or unavailable."
  (unless nucleus-tools-sanity-check
    (cl-return-from nucleus-tool-sanity-check nil))
  (unless (and (boundp 'gptel-tools) (listp gptel-tools))
    (when nucleus-tools-verbose
      (message "[nucleus-tools] gptel-tools not available"))
    (cl-return-from nucleus-tool-sanity-check nil))

  (let* ((preset (or preset (and (boundp 'gptel--preset) gptel--preset)))
         (expected (nucleus--expected-tools-for-preset preset))
         (actual (nucleus--tool-names-from-tools gptel-tools)))

    (unless (and expected actual)
      (when nucleus-tools-verbose
        (message "[nucleus-tools] Cannot check: preset=%S expected=%S actual=%S"
                 preset expected actual))
      (cl-return-from nucleus-tool-sanity-check nil))

    (let* ((missing (seq-filter (lambda (n) (not (member n actual))) expected))
           (extra (seq-filter (lambda (n) (not (member n expected))) actual))
           (report (list preset missing extra)))

      (cond
       ((and (not missing) (not extra))
        ;; All good - clear last report
        (setq-local nucleus--tool-sanity-last-report nil)
        (when nucleus-tools-verbose
          (message "[nucleus-tools] OK: preset=%S tools=%d" preset (length actual)))
        t)

       ((not (equal report nucleus--tool-sanity-last-report))
        ;; New mismatch - log it
        (setq-local nucleus--tool-sanity-last-report report)
        (message "[nucleus-tools] MISMATCH%s preset=%S missing=[%s] extra=[%s]"
                 (if context (format " %s" context) "")
                 preset
                 (if missing (string-join missing ", ") "none")
                 (if extra (string-join extra ", ") "none"))
        nil)

       (t
        ;; Same mismatch as before - don't spam
        nil)))))

;;; Tool Profile Syncing

(defun nucleus-sync-tool-profile (&optional preset)
  "Sync `gptel-tools` to match the active PRESET.

Does nothing if no nucleus preset is active — plain `gptel' buffers
\(created via `M-x gptel') are left alone with no tools.

Only syncs tools when `gptel--preset' is explicitly `gptel-plan' or
`gptel-agent', or when PRESET is provided by the caller.

Race condition guard: If essential tools are not registered yet,
defers sync via idle timer to allow tool registration to complete."
  (when (boundp 'gptel-tools)
    (let ((active-preset (or preset
                             (and (boundp 'gptel--preset)
                                  (memq gptel--preset '(gptel-plan gptel-agent))
                                  gptel--preset))))
      (if (not active-preset)
          (when nucleus-tools-verbose
            (message "[nucleus-tools] No nucleus preset active, skipping tool sync"))
        (let ((toolset-key (pcase active-preset
                             ('gptel-plan :readonly)
                             ('gptel-agent :nucleus))))
          (if (nucleus--tools-ready-p toolset-key)
              (progn
                (setq-local gptel-tools (nucleus-get-tools toolset-key))
                (when nucleus-tools-verbose
                  (message "[nucleus-tools] Tool profile synced to %s (%d tools)"
                           active-preset (length gptel-tools))))
            (progn
              (when nucleus-tools-verbose
                (message "[nucleus-tools] Tools not ready, deferring sync for %s" active-preset))
              (run-with-idle-timer 0.5 nil
                                   (lambda ()
                                     (when (buffer-live-p (current-buffer))
                                       (nucleus-sync-tool-profile preset)))))))))))

(defun nucleus--tools-ready-p (toolset-key)
  "Check if essential tools for TOOLSET-KEY are registered.
Returns non-nil if at least 50% of expected tools are available."
  (let* ((expected (alist-get toolset-key nucleus-toolsets))
         (total (length expected)))
    (when (and expected (fboundp 'gptel-get-tool))
      (let ((available 0)
            (threshold (ceiling (* 0.5 total))))
        (catch 'ready
          (dolist (tool expected)
            (when (ignore-errors (gptel-get-tool tool))
              (cl-incf available)
              (when (>= available threshold)
                (throw 'ready t))))
          nil)))))

;;; Interactive Commands

(defun nucleus-verify-agent-tool-contracts ()
  "Verify that all agent tool contracts are correctly enforced.
Interactive command for debugging agent tool configuration."
  (interactive)
  (unless (and (boundp 'gptel-agent--agents) gptel-agent--agents)
    (user-error "gptel-agent--agents not available"))
  
  (let ((expected
         (mapcar (lambda (c) (cons (car c) (nucleus--declared-tools (cdr c))))
                 nucleus-agent-tool-contracts)))
    (let* ((results
            (cl-loop for (agent-name . expected-tools) in expected
                     for cell = (assoc agent-name gptel-agent--agents)
                     if cell
                     collect (let* ((actual-tools (plist-get (cdr cell) :tools))
                                    (actual-names (if (listp (car actual-tools))
                                                      actual-tools
                                                    (mapcar (lambda (tool) (if (stringp tool) tool (plist-get tool :name)))
                                                            actual-tools)))
                                    (missing (seq-difference expected-tools actual-names #'string=))
                                    (extra (seq-difference actual-names expected-tools #'string=)))
                               (list agent-name (length expected-tools) (length actual-names) missing extra))
                     else collect (list agent-name 0 0 '("NOT FOUND") nil)))
           (all-valid (cl-loop for (_ _ _ missing extra) in results
                               always (and (not missing) (not extra)))))
      (if all-valid
          (message "✓ All agent tool contracts valid: %d agents verified" (length results))
        (display-message-or-buffer
         (format "*Agent Tool Contract Verification*

Agent Tool Contracts Status:
%s

Legend: ✓ valid  ✗ mismatch  ? not found

Expected toolsets:
  executor     → :executor    (%d tools)
  researcher   → :researcher  (%d tools)
  introspector → :readonly    (%d tools)
  explorer     → :explorer     (%d tools)
  reviewer     → :reviewer     (%d tools)"
                 (with-output-to-string
                   (cl-loop for (agent-name expected-count actual-count missing extra) in results
                            do (format t "  %-14s %s  expected=%d  actual=%d  missing=%s  extra=%s\n"
                                       agent-name
                                       (if (and (not missing) (not extra)) "✓" "✗")
                                       expected-count
                                       actual-count
                                       (if missing (length missing) 0)
                                       (if extra (length extra) 0))))
                  (length (nucleus--declared-tools :executor))
                  (length (nucleus--declared-tools :researcher))
                  (length (nucleus--declared-tools :readonly))
                  (length (nucleus--declared-tools :explorer))
                  (length (nucleus--declared-tools :reviewer))))))))

(defun nucleus-test-tool-validation ()
  "Test tool contract validation with sample inputs.
Interactive demonstration of JSON Schema-like validators."
  (interactive)
  (let* ((test-cases
          `(("string with pattern"
             ,(lambda () (nucleus-tools--validate-string "test-123" "cmd" '(:pattern . "^test-[0-9]+$"))))
            ("string minLength"
             ,(lambda () (nucleus-tools--validate-string "ab" "name" '(:minLength . 3))))
            ("string maxLength"
             ,(lambda () (nucleus-tools--validate-string "verylongstring" "name" '(:maxLength . 10))))
            ("string enum"
             ,(lambda () (nucleus-tools--validate-string "invalid" "status" '(:enum "active" "inactive"))))
            ("number minimum"
             ,(lambda () (nucleus-tools--validate-number 5 "count" '(:minimum . 10))))
            ("number maximum"
             ,(lambda () (nucleus-tools--validate-number 100 "count" '(:maximum . 50))))
            ("array minItems"
             ,(lambda () (nucleus-tools--validate-array '(1 2) "items" '(:minItems . 5))))
            ("array maxItems"
             ,(lambda () (nucleus-tools--validate-array '(1 2 3 4 5 6) "items" '(:maxItems . 3))))))
         (results '()))
    (cl-loop for (name test-fn) in test-cases
             do (condition-case err
                    (progn (funcall test-fn)
                           (push (list name "PASS" nil) results))
                  (error
                   (push (list name "FAIL" (error-message-string err)) results))))
    (display-message-or-buffer
     (format "*Tool Validation Test Results*

%s

Legend: PASS = validation correctly rejected invalid input
        FAIL = validation error (expected for these test cases)"
             (with-output-to-string
               (cl-loop for (name status msg) in (nreverse results)
                        do (format t "  %-25s %s%s\n"
                                   name
                                   status
                                   (if msg (format ": %s" (truncate-string-to-width msg 50)) ""))))))))

(defun nucleus-tool-sanity-check-interactively ()
  "Run tool sanity check and display results.

Interactive command for debugging tool configuration issues."
  (interactive)
  (let* ((preset (and (boundp 'gptel--preset) gptel--preset))
         (expected (nucleus--expected-tools-for-preset preset))
         (actual (and (boundp 'gptel-tools)
                      (nucleus--tool-names-from-tools gptel-tools))))

    (unless (and preset expected actual)
      (user-error "Cannot check: preset=%S gptel-tools=%S" preset gptel-tools))

    (let* ((missing (seq-filter (lambda (n) (not (member n actual))) expected))
           (extra (seq-filter (lambda (n) (not (member n expected))) actual))
           (match (and (not missing) (not extra))))

      (if match
          (message "✓ Tool check OK: %d tools for preset %S" (length actual) preset)
        (display-message-or-buffer
         (format
          "✗ Tool MISMATCH for preset %S

Missing (%d): %s
Extra (%d): %s

Current tools: %S
Expected tools: %S"
          preset
          (length missing) (if missing (string-join missing ", ") "none")
          (length extra) (if extra (string-join extra ", ") "none")
          actual
          expected))))))

;;; Backward Compatibility

;; Code should use (nucleus-get-tools :readonly) etc. directly.
;; These variable aliases are deprecated and will be removed in a future version.
;; For now, they're not defined to avoid load-time evaluation issues.

;;; JSON Schema Validators
;;
;; Supported constraints per type:
;;
;; String:
;;   :pattern      REGEX   - Must match regex pattern
;;   :minLength    INT     - Minimum string length
;;   :maxLength    INT     - Maximum string length
;;   :enum         LIST    - Must be one of listed values
;;
;; Number/Integer:
;;   :minimum          NUM - Minimum value (inclusive)
;;   :maximum          NUM - Maximum value (inclusive)
;;   :exclusiveMinimum NUM - Minimum value (exclusive)
;;   :exclusiveMaximum NUM - Maximum value (exclusive)
;;   :normalize        FN  - Normalize raw argument before validation/call
;;
;; Array:
;;   :minItems     INT     - Minimum array length
;;   :maxItems     INT     - Maximum array length
;;
;; Example tool definition with validators:
;;   (gptel-make-tool
;;    :name "Example"
;;    :args '((:name "command"
;;             :type string
;;             :pattern "^[a-z]+$"
;;             :minLength 1
;;             :maxLength 100)
;;            (:name "timeout"
;;             :type integer
;;             :minimum 1
;;             :maximum 300)
;;            (:name "mode"
;;             :type string
;;             :enum ("safe" "normal" "aggressive"))))

(defun nucleus-tools--validation-error (arg-name constraint val &rest fmt-args)
  "Signal a tool contract validation error.

ARG-NAME is the argument being validated.
CONSTRAINT is the constraint keyword (e.g., :pattern, :minimum).
VAL is the actual value that failed validation.
FMT-ARGS are additional format arguments for the message."
  (let ((msg (pcase constraint
               (:pattern "Tool Contract Violation: '%s' value '%s' does not match pattern '%s'")
               (:minLength "Tool Contract Violation: '%s' length %d is less than minLength %d")
               (:maxLength "Tool Contract Violation: '%s' length %d exceeds maxLength %d")
               (:enum "Tool Contract Violation: '%s' value '%s' not in enum %S")
               (:minimum "Tool Contract Violation: '%s' value %s is less than minimum %s")
               (:maximum "Tool Contract Violation: '%s' value %s exceeds maximum %s")
               (:exclusiveMinimum "Tool Contract Violation: '%s' value %s must be > %s (exclusive)")
               (:exclusiveMaximum "Tool Contract Violation: '%s' value %s must be < %s (exclusive)")
               (:minItems "Tool Contract Violation: '%s' has %d items, minimum is %d")
               (:maxItems "Tool Contract Violation: '%s' has %d items, maximum is %d")
               (:type "Tool Contract Violation: expected '%s' to be %s, got %S")
               (:required "Tool Contract Violation (%s): missing or null required argument '%s'")
               (_ "Tool Contract Violation: '%s' failed validation for %s"))))
    (if (eq constraint :type)
        (user-error msg arg-name (car fmt-args) val)
      (apply #'user-error msg arg-name val fmt-args))))

(defun nucleus-tools--validate-string (val arg-name constraints)
  "Validate string VAL against CONSTRAINTS.
CONSTRAINTS may include :pattern, :minLength, :maxLength, :enum."
  (unless (stringp val)
    (nucleus-tools--validation-error arg-name :type val "a string"))
  
  (when-let ((pattern (plist-get constraints :pattern)))
    (unless (string-match-p pattern val)
      (nucleus-tools--validation-error arg-name :pattern val pattern)))
  
  (when-let ((min-len (plist-get constraints :minLength)))
    (when (< (length val) min-len)
      (nucleus-tools--validation-error arg-name :minLength (length val) min-len)))
  
  (when-let ((max-len (plist-get constraints :maxLength)))
    (when (> (length val) max-len)
      (nucleus-tools--validation-error arg-name :maxLength (length val) max-len)))
  
  (when-let ((enum (plist-get constraints :enum)))
    (unless (member val enum)
      (nucleus-tools--validation-error arg-name :enum val enum))))

(defun nucleus-tools--validate-number (val arg-name constraints)
  "Validate number VAL against CONSTRAINTS.
CONSTRAINTS may include :minimum, :maximum, :exclusiveMinimum, :exclusiveMaximum."
  (unless (numberp val)
    (nucleus-tools--validation-error arg-name :type val "a number"))
  
  (when-let ((min (plist-get constraints :minimum)))
    (when (< val min)
      (nucleus-tools--validation-error arg-name :minimum val min)))
  
  (when-let ((max (plist-get constraints :maximum)))
    (when (> val max)
      (nucleus-tools--validation-error arg-name :maximum val max)))
  
  (when-let ((excl-min (plist-get constraints :exclusiveMinimum)))
    (when (<= val excl-min)
      (nucleus-tools--validation-error arg-name :exclusiveMinimum val excl-min)))
  
  (when-let ((excl-max (plist-get constraints :exclusiveMaximum)))
    (when (>= val excl-max)
      (nucleus-tools--validation-error arg-name :exclusiveMaximum val excl-max))))

(defun nucleus-tools--validate-array (val arg-name constraints)
  "Validate array VAL against CONSTRAINTS.
CONSTRAINTS may include :minItems, :maxItems, :items."
  (unless (or (vectorp val) (listp val))
    (nucleus-tools--validation-error arg-name :type val "an array"))
  
  (let ((len (length val)))
    (when-let ((min-items (plist-get constraints :minItems)))
      (when (< len min-items)
        (nucleus-tools--validation-error arg-name :minItems len min-items)))
    
    (when-let ((max-items (plist-get constraints :maxItems)))
      (when (> len max-items)
        (nucleus-tools--validation-error arg-name :maxItems len max-items)))))

;;; Tool Contract Validation

(defun nucleus-tools--normalize-arg-value (val spec)
  "Return VAL normalized according to SPEC."
  (let ((normalize (plist-get spec :normalize)))
    (if (functionp normalize)
        (funcall normalize val)
      val)))

(defun nucleus-tools--public-arg-spec (spec)
  "Return SPEC with local-only contract keys removed."
  (let (result)
    (while spec
      (let ((key (pop spec))
            (value (pop spec)))
        (unless (eq key :normalize)
          (setq result (plist-put result key value)))))
    result))

(defun nucleus-tools--validate-contract (tool-name func args async-p)
  "Wrap FUNC with runtime contract validation based on ARGS schema.
Ensure that incoming arguments match the type definitions in ARGS.

Supports JSON Schema-like validators:
  - type: string, integer, number, boolean, array, object
  - string: pattern, minLength, maxLength, enum
  - number: minimum, maximum, exclusiveMinimum, exclusiveMaximum
  - array: minItems, maxItems, items
  - enum: list of allowed values"
  (lambda (&rest call-args)
    (condition-case err
        (let* ((actual-args (if async-p (cdr call-args) call-args))
               (normalized-args (copy-sequence actual-args))
               (i 0)
               (specs (if (functionp args) (funcall args) args)))
          ;; Guard: if no args spec, skip validation silently
          (when specs
            (dolist (spec specs)
              (let* ((raw-val (nth i normalized-args))
                     (val (if (null raw-val)
                              raw-val
                            (nucleus-tools--normalize-arg-value raw-val spec)))
                     (type (plist-get spec :type))
                     (arg-name (plist-get spec :name))
                     (optional (plist-get spec :optional)))
                (unless (equal raw-val val)
                  (setf (nth i normalized-args) val))
                (cond
                 ;; Check for missing required arguments
                 ((and (null val) (not optional)
                       (not (or (equal type "boolean") (eq type 'boolean))))
                  (nucleus-tools--validation-error tool-name :required arg-name))

                 ;; Validate non-null values
                 ((not (null val))
                  (pcase type
                    ((or "string" 'string)
                     (nucleus-tools--validate-string val arg-name spec))
                    ((or "integer" 'integer)
                     (nucleus-tools--validate-number val arg-name spec)
                     (unless (integerp val)
                       (nucleus-tools--validation-error arg-name :type val "an integer")))
                    ((or "number" 'number)
                     (nucleus-tools--validate-number val arg-name spec))
                    ((or "boolean" 'boolean)
                     (unless (memq val '(t nil :json-false))
                       (nucleus-tools--validation-error arg-name :type val "a boolean")))
                    ((or "array" 'array)
                     (nucleus-tools--validate-array val arg-name spec))
                    ((or "object" 'object)
                     (unless (or (hash-table-p val) (listp val))
                       (nucleus-tools--validation-error arg-name :type val "an object")))
                    (_ nil))))
                (cl-incf i))))
          (if async-p
              (apply func (car call-args) normalized-args)
            (apply func normalized-args)))
      (user-error
       (if async-p
           (let ((callback (car call-args)))
             (if (functionp callback)
                 (funcall callback (format "Error: %s" (error-message-string err)))
               (signal (car err) (cdr err))))
         (signal (car err) (cdr err)))))))

(defun nucleus-tools--advise-make-tool (orig-fn &rest kwargs)
  "Advice for `gptel-make-tool' to enforce tool contracts at runtime.
Wraps the provided :function with argument type validation."
  (let* ((name (plist-get kwargs :name))
         (func (plist-get kwargs :function))
         (args (plist-get kwargs :args))
         (async-p (plist-get kwargs :async))
         (public-args
          (cond
           ((functionp args)
            (lambda ()
              (mapcar #'nucleus-tools--public-arg-spec (funcall args))))
           ((listp args)
            (mapcar #'nucleus-tools--public-arg-spec args))
           (t args))))
    (when (and name func args)
      (setq kwargs (plist-put kwargs :function
                              (nucleus-tools--validate-contract name func args async-p)))
      (setq kwargs (plist-put kwargs :args public-args)))
    (apply orig-fn kwargs)))

(defun nucleus-tools-setup ()
  "Setup nucleus-tools module.

Call this after gptel loads to register hooks and tools."
  ;; Register mode hook for tool profile syncing
  (when (boundp 'gptel-mode-hook)
    (add-hook 'gptel-mode-hook #'nucleus-sync-tool-profile)
    ;; Sanity check disabled by default to prevent recursion
    (when nucleus-tools-sanity-check
      (add-hook 'gptel-mode-hook #'nucleus-tool-sanity-check)))
  
  ;; Enforce tool contracts (depth 20: innermost, after security ACL at depth 10)
  (advice-add 'gptel-make-tool :around #'nucleus-tools--advise-make-tool '((depth . 20))))

(with-eval-after-load 'gptel
  (nucleus-tools-setup))

;;; Footer

(provide 'nucleus-tools)

;;; nucleus-tools.el ends here
