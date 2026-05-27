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

;;; Tool Markers (Traits)

;; Inspired by Serena's ToolMarker system. Each tool can carry multiple markers
;; that declare its capabilities, enabling trait-based toolset derivation instead
;; of hardcoded name lists.

(defconst nucleus-tool-markers
  '((:can-edit . ("ApplyPatch" "Edit" "Insert" "Mkdir" "Move" "Write"
                  "Code_Replace" "create_skill" "write_memory"))
    (:can-read . ("Bash" "Eval" "Glob" "Grep" "Read" "Programmatic"
                  "WebFetch" "WebSearch" "YouTube"
                  "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                  "Code_Map" "Code_Inspect" "Diagnostics" "Code_Usages"
                  "Skill" "TodoWrite" "RunAgent" "Preview"
                  "read_memory" "list_memories"))
    (:symbolic . ("Code_Map" "Code_Inspect" "Code_Replace" "Code_Usages"
                  "find_buffers_and_recent" "describe_symbol" "get_symbol_source"))
    (:web . ("WebFetch" "WebSearch" "YouTube"))
    (:memory . ("read_memory" "write_memory" "list_memories"))
    (:delegates . ("RunAgent"))
    (:requires-project . ("Code_Map" "Code_Inspect" "Code_Replace" "Code_Usages"
                          "Diagnostics" "find_buffers_and_recent"
                          "describe_symbol" "get_symbol_source"
                          "read_memory" "write_memory" "list_memories"))
    (:plan-excluded . ("YouTube" "Preview" "write_memory"))
    (:sandbox-excluded . ("Programmatic" "Bash" "Eval" "Skill" "TodoWrite"))
    (:file-inspector . ("Code_Map" "Code_Inspect" "Code_Replace" "Code_Usages"
                        "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                        "Read" "Grep" "Glob" "Preview" "Diagnostics")))
  "Marker traits for each registered tool.

:can-edit      — Tool modifies files or system state (requires confirmation)
:can-read      — Tool reads/queries without side effects
:symbolic      — Tool operates at symbol/code-structure level
:web           — Tool accesses external web resources
:memory        — Tool reads/writes persistent memory (mementum)
:delegates     — Tool delegates to sub-agents
:requires-project — Tool needs an active project context
:plan-excluded — Tool excluded from plan/readonly mode even though read-only
:sandbox-excluded — Tool excluded from all sandbox profiles (escapes sandbox or
                    requires user interaction incompatible with Programmatic)
:file-inspector  — Tool inspects file content at granularity that can cause
                    same-file inspection thrash

A tool may carry multiple markers. Markers enable:
  - Deriving toolsets by marker inclusion/exclusion
  - Unified classification replacing scattered lists
  - Conditional prompt generation based on available markers")

(defun nucleus-tools-with-marker (marker)
  "Return list of tool names carrying MARKER."
  (or (alist-get marker nucleus-tool-markers) '()))

(defun nucleus-tool-has-marker-p (tool-name marker)
  "Return non-nil if TOOL-NAME carries MARKER."
  (member tool-name (nucleus-tools-with-marker marker)))

(defun nucleus-tools-with-any-marker (&rest markers)
  "Return tools carrying any of MARKERS (union)."
  (seq-uniq (apply #'append (mapcar #'nucleus-tools-with-marker markers))))

(defun nucleus-tools-with-all-markers (&rest markers)
  "Return tools carrying all of MARKERS (intersection)."
  (when markers
    (let ((result (nucleus-tools-with-marker (car markers))))
      (dolist (m (cdr markers) (delete-dups result))
        (setq result (seq-intersection result (nucleus-tools-with-marker m) #'equal))))))

(defun nucleus-toolset-from-markers (include exclude)
  "Derive a toolset from marker specifications.

INCLUDE is a list of markers — tools carrying ANY included marker are candidates.
EXCLUDE is a list of markers — tools carrying ANY excluded marker are removed.
Either may be nil.

Returns a list of tool name strings."
  (let* ((candidates (if include
                         (apply #'nucleus-tools-with-any-marker include)
                       (apply #'nucleus-tools-with-any-marker :can-read :can-edit)))
         (excluded (when exclude
                     (apply #'nucleus-tools-with-any-marker exclude))))
    (seq-difference candidates excluded #'equal)))

;;; Progressive Tool Shortening

;; Inspired by Serena's _limit_length with shortened_result_factories.
;; When a tool's output exceeds a character budget, progressively shorter
;; summaries are tried until one fits.

(defcustom nucleus-tool-max-answer-chars 4000
  "Default maximum characters for tool results before truncation.
Tools can override this per-call via `max_answer_chars' parameter."
  :type 'integer
  :group 'nucleus-tools)

(defun nucleus-limit-result-length (result max-chars &optional shortened-factories)
  "Limit RESULT to MAX-CHARS, trying SHORTENED-FACTORIES progressively.

If RESULT fits within MAX-CHARS, return it unchanged.
If too long and SHORTENED-FACTORIES is provided, try each closure
(a zero-arg function returning a shorter string) in order until one fits.
If none fit or no factories given, return a truncation notice."
  (if (not (stringp result))
      result
    (let ((n-chars (length result)))
      (if (<= n-chars max-chars)
          result
        (let ((too-long-msg (format "Result too long (%d chars). Refine query or adjust max_answer_chars."
                                    n-chars)))
          (if shortened-factories
              (cl-loop for factory in shortened-factories
                       for candidate = (if (functionp factory) (funcall factory) "")
                       when (and (stringp candidate)
                                 (<= (length (concat too-long-msg "\n" candidate)) max-chars))
                       return (concat too-long-msg "\n" candidate)
                       finally return too-long-msg)
            too-long-msg))))))

;;; Project-Level Tool Configuration

;; Inspired by Serena's project.yml excluded_tools/included_optional_tools.
;; Per-project tool exclusion that applies on top of the base toolset.

(defcustom nucleus-project-excluded-tools nil
  "List of tool names to exclude from all toolsets for this project.
Applied after toolset selection but before `gptel-tools' is set.

Can be set via .dir-locals.el or (setq-local nucleus-project-excluded-tools ...).
Example: (setq-local nucleus-project-excluded-tools '(\"YouTube\" \"WebSearch\"))"
  :type '(repeat string)
  :group 'nucleus-tools
  :safe #'listp)

(defcustom nucleus-project-readonly-override nil
  "When non-nil, override the plan-mode toolset with this list of tool names.
Useful for projects that need custom readonly tool availability.
When nil (default), the standard :readonly toolset is used."
  :type '(choice (const nil) (repeat string))
  :group 'nucleus-tools
  :safe (lambda (v) (or (null v) (listp v))))

(defun nucleus--apply-project-exclusions (tools)
  "Remove project-excluded tools from TOOLS list.
Uses `nucleus-project-excluded-tools' as the exclusion set."
  (if nucleus-project-excluded-tools
      (seq-difference tools nucleus-project-excluded-tools #'equal)
    tools))

;;; Marker-Conditional Prompt Support

;; Inspired by Serena's Jinja2 prompt templates that conditionally include
;; instructions based on available markers. Provides Elisp equivalents.

(defun nucleus-active-markers ()
  "Return list of markers that have at least one active tool.
Active tools = current `gptel-tools' in buffer."
  (let ((active-tool-names (when (boundp 'gptel-tools)
                             (delq nil (mapcar #'nucleus--tool-name gptel-tools)))))
    (delq nil
          (mapcar (lambda (entry)
                    (let ((marker (car entry))
                          (tools (cdr entry)))
                      (when (seq-some (lambda (tool) (member tool active-tool-names)) tools)
                        marker)))
                  nucleus-tool-markers))))

(defun nucleus-marker-available-p (marker)
  "Return non-nil if MARKER has at least one active tool in current buffer."
  (memq marker (nucleus-active-markers)))

(defun nucleus-prompt-when-marker (marker text)
  "Return TEXT if MARKER has active tools, else empty string.
For use in prompt templates to conditionally include instructions."
  (if (nucleus-marker-available-p marker) text ""))


;;; Toolset Definitions

;; Primary toolsets (:readonly, :nucleus, :executor) are derived from markers.
;; Subagent toolsets are hand-curated for specific roles and cannot be
;; purely derived from markers — they have role-specific inclusions/exclusions.

(defconst nucleus-toolset-definitions
  '((:readonly   . (:derived (:can-read) (:can-edit :plan-excluded)))
    (:nucleus    . (:derived (:can-read :can-edit) nil
                             "read_memory" "list_memories" "write_memory"))
    (:executor   . (:derived (:can-read :can-edit) (:delegates)))
    (:researcher . ("Bash" "Eval" "Glob" "Grep" "Read" "Skill" "Programmatic"
                    "WebFetch" "WebSearch" "YouTube"
                    "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                    "Code_Map" "Code_Inspect" "Code_Usages" "Diagnostics"
                    "read_memory" "list_memories"))
    (:explorer . ("Glob" "Grep" "Read" "Code_Map" "Code_Inspect"))
    (:reviewer . ("Glob" "Grep" "Read" "Diagnostics"))
    (:analyzer . ("Bash" "Read" "Glob" "Grep" "Code_Map"
                  "Diagnostics" "Programmatic"))
    (:comparator . ("Read" "Glob" "Grep"))
    (:grader . ("Read" "Glob" "Grep" "Bash" "Eval")))
  "Toolset definitions for nucleus.

Primary toolsets use (:derived INCLUDE EXCLUDE) to compute from markers.
Subagent toolsets are hand-curated for specific roles.

:readonly   — Plan mode: can-read minus can-edit minus plan-excluded
:nucleus    — Full action: can-read + can-edit
:executor   — Action minus delegation (no RunAgent)
:researcher — Codebase + web research + memory read
:explorer   — Codebase exploration
:reviewer   — Code review + Diagnostics
:analyzer   — Benchmark analysis
:comparator — A/B comparison
:grader     — Assertion grading")

(defun nucleus--resolve-toolset (definition)
  "Resolve a toolset DEFINITION to a list of tool names.
Handles both derived and explicit definitions.
Supports (:derived INCLUDE EXCLUDE &rest EXTRA) to append extra tools."
  (if (and (consp definition) (eq (car definition) :derived))
      (let ((include (cadr definition))
            (exclude (caddr definition))
            (extra (cdddr definition)))
        (when (and (listp include) (listp exclude))
          (let ((base (nucleus-toolset-from-markers include exclude)))
            (if extra
                (append base (cl-remove-if (lambda (tool) (member tool base)) extra))
              base))))
    definition))

(defun nucleus--build-toolsets ()
  "Build the full toolsets alist from nucleus-toolset-definitions."
  (mapcar (lambda (entry)
            (cons (car entry)
                  (nucleus--resolve-toolset (cdr entry))))
          nucleus-toolset-definitions))

(defconst nucleus-toolsets (nucleus--build-toolsets)
  "Resolved toolset definitions for nucleus.
Computed from `nucleus-toolset-definitions' at load time.
See `nucleus-toolset-definitions' for documentation.")

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

(defvar nucleus--tool-availability-cache (make-hash-table :test 'equal)
  "Cache for tool availability checks to avoid repeated gptel-get-tool calls.

ASSUMPTION: Tools are registered before first availability check.
EDGE CASE: Tools registered after initial load will show as unavailable
  until cache is cleared. Call `nucleus-tools-invalidate-cache' to refresh.")

(defun nucleus-tools-invalidate-cache ()
  "Clear the tool availability cache.

Call this when new tools are registered after initial load,
or when debugging tool availability issues.

BEHAVIOR: Removes all cached availability results so subsequent
  calls to `nucleus--tool-available-p' will re-check registration.
TEST: After calling, `nucleus--tool-available-p' should return
  updated results for newly registered tools."
  (clrhash nucleus--tool-availability-cache)
  (when nucleus-tools-verbose
    (message "[nucleus-tools] Tool availability cache cleared")))

(defun nucleus--tool-available-p (tool-name)
  "Return non-nil if TOOL-NAME is registered, with caching."
  (let ((cached (gethash tool-name nucleus--tool-availability-cache 'unset)))
    (if (not (eq cached 'unset))
        cached
      (let* ((boundp (fboundp 'gptel-get-tool))
             (available (if boundp
                            (ignore-errors (gptel-get-tool tool-name))
                          t)))
        (puthash tool-name available nucleus--tool-availability-cache)
        (unless available
          (message "[nucleus] WARNING: Tool '%s' not registered" tool-name))
        available))))

(defun nucleus-get-tools (set-name)
  "Return tool list for SET-NAME, filtering out unregistered tools.

SET-NAME can be a symbol from `nucleus-toolsets' or a list of tool names.
Returns a list of currently registered tool name strings."
  (let ((tools (nucleus--declared-tools set-name)))
    (seq-filter #'nucleus--tool-available-p tools)))

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
  (cl-block nucleus-tool-sanity-check
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
          nil))))))

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
                (setq-local gptel-tools (nucleus--apply-project-exclusions
                                         (if (and (eq toolset-key :readonly)
                                                  nucleus-project-readonly-override)
                                             nucleus-project-readonly-override
                                           (nucleus-get-tools toolset-key))))
                (when nucleus-tools-verbose
                  (message "[nucleus-tools] Tool profile synced to %s (%d tools, %d excluded by project)"
                           active-preset (length gptel-tools)
                           (- (length (nucleus-get-tools toolset-key)) (length gptel-tools)))))
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
    (when expected
      (let ((available 0)
            (threshold (ceiling (* 0.5 total))))
        (catch 'ready
          (dolist (tool expected)
            (when (nucleus--tool-available-p tool)
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
    (nucleus-tools--validation-error arg-name :type "a string" val))
  
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
    (nucleus-tools--validation-error arg-name :type "a number" val))
  
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
  (let ((is-proper-list (ignore-errors (and (listp val) (proper-list-p val)))))
    (unless (or (vectorp val) is-proper-list)
      (nucleus-tools--validation-error arg-name :type "an array" val)))
  
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
          ;; Guard: if no args spec or not a proper list, skip validation silently
          (when (and specs (proper-list-p specs))
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
                       (nucleus-tools--validation-error arg-name :type "an integer" val)))
                    ((or "number" 'number)
                     (nucleus-tools--validate-number val arg-name spec))
                    ((or "boolean" 'boolean)
                     (unless (memq val '(t nil :json-false))
                       (nucleus-tools--validation-error arg-name :type "a boolean" val)))
                    ((or "array" 'array)
                     (nucleus-tools--validate-array val arg-name spec))
                    ((or "object" 'object)
                     (unless (or (hash-table-p val) (listp val))
                       (nucleus-tools--validation-error arg-name :type "an object" val)))
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
  ;; Clear stale cache entries from before gptel was loaded
  (nucleus-tools-invalidate-cache)
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
