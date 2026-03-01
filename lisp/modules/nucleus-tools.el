;;; nucleus-tools.el --- Tool definitions for nucleus -*- lexical-binding: t; -*-

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
  '((:core . ("ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
              "Insert" "Mkdir" "Move" "Read" "RunAgent" "Skill" "TodoWrite"
              "WebFetch" "WebSearch" "Write" "YouTube"
              "Code_Map" "Code_Inspect" "Code_Replace" "Diagnostics" "Code_Usages"))
     (:readonly . ("Bash" "Eval" "Glob" "Grep" "Read" "Skill"
                  "WebFetch" "WebSearch" "YouTube"
                  "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                  "Code_Map" "Code_Inspect" "Diagnostics" "Code_Usages"))
     (:researcher . ("Bash" "Eval" "Glob" "Grep" "Read" "Skill"
                     "WebFetch" "WebSearch" "YouTube"
                     "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                     "list_skills" "load_skill"
                     "Code_Map" "Code_Inspect" "Code_Usages" "Diagnostics"))
     (:nucleus . ("ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
                  "Insert" "Mkdir" "Move" "Read" "RunAgent" "Skill" "TodoWrite"
                  "WebFetch" "WebSearch" "Write" "YouTube"
                  "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                  "preview_file_change" "preview_patch"
                  "list_skills" "load_skill" "create_skill"
                  "Code_Map" "Code_Inspect" "Code_Replace" "Diagnostics" "Code_Usages"))
     (:explorer . ("Glob" "Grep" "Read"))
     (:reviewer . ("Glob" "Grep" "Read"))
     (:snippets . ("RunAgent" "Bash" "Edit" "ApplyPatch" "preview_file_change" "preview_patch"
                   "Grep" "Glob" "Read" "Write" "describe_symbol" "get_symbol_source"
                   "find_buffers_and_recent" "Skill" "list_skills" "load_skill"
                   "create_skill" "WebSearch" "WebFetch"
                   "Eval" "Insert" "Mkdir" "TodoWrite" "YouTube"
                   "Move" "Code_Map" "Code_Inspect" "Code_Replace" "Diagnostics" "Code_Usages")))
  "Canonical toolset definitions for nucleus.

:core — Base gptel-agent tools (23 tools)
:readonly — Read-only subset for plan mode (16 tools)
:researcher — Research: readonly + skill loading (19 tools, superset of :readonly)
:nucleus — Full action tools + preview + skill management (31 tools)
:explorer — Minimal read-only set for codebase exploration (3 tools: Glob/Grep/Read)
:reviewer — Minimal read-only set for code review (3 tools: Glob/Grep/Read)
:snippets — Tools with supplemental prompts injected (31 tools)

Tool contracts enforced in `nucleus--override-gptel-agent-presets':
  executor     → :nucleus     (31 tools) - code changes & execution
  researcher   → :researcher  (19 tools) - exploration & research
  introspector → :readonly    (16 tools) - Emacs introspection
  explorer     → :explorer     (3 tools) - read-only codebase exploration
  reviewer     → :reviewer     (3 tools) - read-only code review")

(defun nucleus-get-tools (set-name)
  "Return tool list for SET-NAME, filtering out unregistered tools.

SET-NAME can be a symbol from `nucleus-toolsets` or a list of tool names.
Returns a list of tool name strings."
  (let ((tools
         (pcase set-name
           ((and (pred symbolp) name)
            (or (alist-get name nucleus-toolsets)
                (user-error "Unknown toolset: %S" name)))
           ((and (pred listp) t-list) t-list)
           (_ (user-error "Invalid toolset specifier: %S" set-name)))))
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

Does nothing if a preset is already active (gptel--preset is set),
to avoid overriding gptel's preset application.

Use in `gptel-mode-hook` to ensure correct tools on buffer load."
  (when (boundp 'gptel-tools)
    ;; Don't override if gptel has already applied a preset
    (if (and (boundp 'gptel--preset)
             (memq gptel--preset '(gptel-plan gptel-agent)))
        (when nucleus-tools-verbose
          (message "[nucleus-tools] Tool profile left to preset: %S" gptel--preset))

      ;; No preset yet - apply defaults based on nucleus-agent-default
      (let ((active-preset (or preset
                               (and (boundp 'nucleus-agent-default)
                                    nucleus-agent-default)
                               'gptel-plan)))
        (pcase active-preset
          ('gptel-plan
           (setq-local gptel-tools (nucleus-get-tools :readonly))
           (when nucleus-tools-verbose
             (message "[nucleus-tools] Tool profile synced to plan (readonly)")))
          ('gptel-agent
           (setq-local gptel-tools (nucleus-get-tools :nucleus))
           (when nucleus-tools-verbose
             (message "[nucleus-tools] Tool profile synced to agent (nucleus)"))))))))

;;; Tool Registration Helpers

(cl-defun nucleus-register-tool (name function description args
                                   &key async confirm category include)
  "Register a gptel tool with NAME, FUNCTION, DESCRIPTION, and ARGS.

KEYWORDS:
  ASYNC — When non-nil, tool function is async (takes callback first arg)
  CONFIRM — When non-nil, require user confirmation before execution
  CATEGORY — Tool category (default: \"nucleus\")
  INCLUDE — When non-nil, include in default tool sets

Returns the tool struct from `gptel-make-tool`, or nil if gptel unavailable."
  (unless (fboundp 'gptel-make-tool)
    (message "[nucleus-tools] Cannot register tool %S: gptel-make-tool unavailable" name)
    (cl-return-from nucleus-register-tool nil))

  (condition-case err
      (gptel-make-tool
       :name name
       :function function
       :description description
       :args args
       :async (or async nil)
       :confirm (or confirm nil)
       :category (or category "nucleus")
       :include (or include t))
    (error
     (message "[nucleus-tools] Failed to register tool %S: %s" name
              (error-message-string err))
     nil)))

;;; Interactive Commands

(defun nucleus-verify-agent-tool-contracts ()
  "Verify that all agent tool contracts are correctly enforced.
Interactive command for debugging agent tool configuration."
  (interactive)
  (unless (and (boundp 'gptel-agent--agents) gptel-agent--agents)
    (user-error "gptel-agent--agents not available"))
  
  (let ((expected
         `(("executor" . ,(nucleus-get-tools :nucleus))
           ("researcher" . ,(nucleus-get-tools :researcher))
           ("introspector" . ,(nucleus-get-tools :readonly))
           ("explorer" . ,(nucleus-get-tools :explorer))
           ("reviewer" . ,(nucleus-get-tools :reviewer)))))
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
  executor     → :nucleus     (%d tools)
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
                 (length (nucleus-get-tools :nucleus))
                 (length (nucleus-get-tools :researcher))
                 (length (nucleus-get-tools :readonly))
                 (length (nucleus-get-tools :explorer))
                 (length (nucleus-get-tools :reviewer))))))))

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

;; Code should use (nucleus-get-tools :core) etc. directly.
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

(defun nucleus-tools--validate-string (val arg-name constraints)
  "Validate string VAL against CONSTRAINTS.
CONSTRAINTS may include :pattern, :minLength, :maxLength, :enum."
  (unless (stringp val)
    (user-error "Tool Contract Violation: expected '%s' to be a string, got %S" arg-name val))
  
  (when-let ((pattern (plist-get constraints :pattern)))
    (unless (string-match-p pattern val)
      (user-error "Tool Contract Violation: '%s' value '%s' does not match pattern '%s'"
                  arg-name val pattern)))
  
  (when-let ((min-len (plist-get constraints :minLength)))
    (when (< (length val) min-len)
      (user-error "Tool Contract Violation: '%s' length %d is less than minLength %d"
                  arg-name (length val) min-len)))
  
  (when-let ((max-len (plist-get constraints :maxLength)))
    (when (> (length val) max-len)
      (user-error "Tool Contract Violation: '%s' length %d exceeds maxLength %d"
                  arg-name (length val) max-len)))
  
  (when-let ((enum (plist-get constraints :enum)))
    (unless (member val enum)
      (user-error "Tool Contract Violation: '%s' value '%s' not in enum %S"
                  arg-name val enum))))

(defun nucleus-tools--validate-number (val arg-name constraints)
  "Validate number VAL against CONSTRAINTS.
CONSTRAINTS may include :minimum, :maximum, :exclusiveMinimum, :exclusiveMaximum."
  (unless (numberp val)
    (user-error "Tool Contract Violation: expected '%s' to be a number, got %S" arg-name val))
  
  (when-let ((min (plist-get constraints :minimum)))
    (when (< val min)
      (user-error "Tool Contract Violation: '%s' value %s is less than minimum %s"
                  arg-name val min)))
  
  (when-let ((max (plist-get constraints :maximum)))
    (when (> val max)
      (user-error "Tool Contract Violation: '%s' value %s exceeds maximum %s"
                  arg-name val max)))
  
  (when-let ((excl-min (plist-get constraints :exclusiveMinimum)))
    (when (<= val excl-min)
      (user-error "Tool Contract Violation: '%s' value %s must be > %s (exclusive)"
                  arg-name val excl-min)))
  
  (when-let ((excl-max (plist-get constraints :exclusiveMaximum)))
    (when (>= val excl-max)
      (user-error "Tool Contract Violation: '%s' value %s must be < %s (exclusive)"
                  arg-name val excl-max))))

(defun nucleus-tools--validate-array (val arg-name constraints)
  "Validate array VAL against CONSTRAINTS.
CONSTRAINTS may include :minItems, :maxItems, :items."
  (unless (or (vectorp val) (listp val))
    (user-error "Tool Contract Violation: expected '%s' to be an array, got %S" arg-name val))
  
  (let ((len (if (vectorp val) (length val) (length val))))
    (when-let ((min-items (plist-get constraints :minItems)))
      (when (< len min-items)
        (user-error "Tool Contract Violation: '%s' has %d items, minimum is %d"
                    arg-name len min-items)))
    
    (when-let ((max-items (plist-get constraints :maxItems)))
      (when (> len max-items)
        (user-error "Tool Contract Violation: '%s' has %d items, maximum is %d"
                    arg-name len max-items)))))

(defun nucleus-tools--validate-enum (val arg-name enum)
  "Validate VAL is in ENUM list."
  (unless (member val enum)
    (user-error "Tool Contract Violation: '%s' value %S not in allowed values %S"
                arg-name val enum)))

;;; Tool Contract Validation

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
    (let* ((actual-args (if async-p (cdr call-args) call-args))
           (i 0))
      ;; Check for missing required arguments or invalid types
      (dolist (spec (if (functionp args) (funcall args) args))
        (let* ((val (nth i actual-args))
               (type (plist-get spec :type))
               (arg-name (plist-get spec :name))
               (optional (plist-get spec :optional)))
          (cond
           ;; Check for missing required arguments
           ((and (null val) (not optional) (not (member type '("boolean" boolean))))
            (user-error "Tool Contract Violation (%s): missing or null required argument '%s'"
                        tool-name arg-name))
           
           ;; Validate non-null values
           ((not (null val))
            (pcase type
              ((or "string" 'string)
               (nucleus-tools--validate-string val arg-name spec))
              ((or "integer" 'integer)
               (nucleus-tools--validate-number val arg-name spec)
               (unless (integerp val)
                 (user-error "Tool Contract Violation (%s): expected '%s' to be an integer, got %S"
                             tool-name arg-name val)))
              ((or "number" 'number)
               (nucleus-tools--validate-number val arg-name spec))
              ((or "boolean" 'boolean)
               (unless (memq val '(t nil :json-false))
                 (user-error "Tool Contract Violation (%s): expected '%s' to be a boolean, got %S"
                             tool-name arg-name val)))
              ((or "array" 'array)
               (nucleus-tools--validate-array val arg-name spec))
              ((or "object" 'object)
               (unless (or (hash-table-p val) (listp val))
                 (user-error "Tool Contract Violation (%s): expected '%s' to be an object, got %S"
                             tool-name arg-name val)))
              (_ nil))))
        (cl-incf i)))
    (apply func call-args))))

(defun nucleus-tools--advise-make-tool (orig-fn &rest kwargs)
  "Advice for `gptel-make-tool' to enforce tool contracts at runtime.
Wraps the provided :function with argument type validation."
  (let* ((name (plist-get kwargs :name))
         (func (plist-get kwargs :function))
         (args (plist-get kwargs :args))
         (async-p (plist-get kwargs :async)))
    (when (and name func args)
      (setq kwargs (plist-put kwargs :function
                              (nucleus-tools--validate-contract name func args async-p))))
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
  
  ;; Enforce tool contracts
  (advice-add 'gptel-make-tool :around #'nucleus-tools--advise-make-tool))

(with-eval-after-load 'gptel
  (nucleus-tools-setup))

;;; Footer

(provide 'nucleus-tools)

;;; nucleus-tools.el ends here
