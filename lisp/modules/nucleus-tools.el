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

;;; Toolset Definitions

(defconst nucleus-toolsets
  '((:core . ("Agent" "ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
             "Insert" "Mkdir" "Move" "Read" "RunAgent" "Skill" "TodoWrite"
             "WebFetch" "WebSearch" "Write" "YouTube"
             "lsp_diagnostics" "lsp_references" "lsp_workspace_symbol"
             "lsp_definition" "lsp_hover" "lsp_rename"
             "AST_Map" "AST_Read" "AST_Replace"))
    (:readonly . ("Agent" "BashRO" "Eval" "Glob" "Grep" "Read" "Skill"
                 "WebFetch" "WebSearch" "YouTube"
                 "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                 "lsp_diagnostics" "lsp_references" "lsp_workspace_symbol"
                 "lsp_definition" "lsp_hover" "AST_Map" "AST_Read"))
    (:nucleus . ("Agent" "ApplyPatch" "Bash" "Edit" "Eval" "Glob" "Grep"
                 "Insert" "Mkdir" "Move" "Read" "RunAgent" "Skill" "TodoWrite"
                 "WebFetch" "WebSearch" "Write" "YouTube"
                 "find_buffers_and_recent" "describe_symbol" "get_symbol_source"
                 "lsp_diagnostics" "lsp_references" "lsp_workspace_symbol"
                 "lsp_definition" "lsp_hover" "lsp_rename"
                 "preview_file_change" "preview_patch"
                 "list_skills" "load_skill" "create_skill"
                 "AST_Map" "AST_Read" "AST_Replace"))
    (:snippets . ("Agent" "RunAgent" "Bash" "Edit" "ApplyPatch" "preview_file_change" "preview_patch"
                 "Grep" "Glob" "Read" "Write" "describe_symbol" "get_symbol_source"
                 "find_buffers_and_recent" "Skill" "list_skills" "load_skill"
                 "create_skill" "WebSearch" "WebFetch"
                 "Eval" "Insert" "Mkdir" "TodoWrite" "YouTube"
                 "Move" "lsp_diagnostics" "lsp_references" "lsp_workspace_symbol"
                 "lsp_definition" "lsp_hover" "lsp_rename"
                 "AST_Map" "AST_Read" "AST_Replace")))
  "Canonical toolset definitions for nucleus.

:core — Base gptel-agent tools (17 tools)
:readonly — Read-only subset for plan mode (12 tools)
:nucleus — Core + preview + skill management (21 tools)
:snippets — Tools with supplemental prompts injected")

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
                  (if (fboundp 'gptel-get-tool)
                      (ignore-errors (gptel-get-tool tool-name))
                    t))
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

;;; Integration Hooks

(defun nucleus-tools--validate-contract (tool-name func args async-p)
  "Wrap FUNC with runtime contract validation based on ARGS schema.
Ensure that incoming arguments match the type definitions in ARGS."
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
           ((and (null val) (not optional) (not (member type '("boolean" boolean))))
            (user-error "Tool Contract Violation (%s): missing or null required argument '%s'" tool-name arg-name))
           ((not (null val))
            (pcase type
              ((or "string" 'string)
               (unless (stringp val)
                 (user-error "Tool Contract Violation (%s): expected '%s' to be a string, got %S" tool-name arg-name val)))
              ((or "integer" 'integer)
               (unless (integerp val)
                 (user-error "Tool Contract Violation (%s): expected '%s' to be an integer, got %S" tool-name arg-name val)))
              ((or "number" 'number)
               (unless (numberp val)
                 (user-error "Tool Contract Violation (%s): expected '%s' to be a number, got %S" tool-name arg-name val)))
              ((or "boolean" 'boolean)
               (unless (memq val '(t nil :json-false))
                 (user-error "Tool Contract Violation (%s): expected '%s' to be a boolean, got %S" tool-name arg-name val)))
              ((or "array" 'array)
               (unless (or (vectorp val) (listp val))
                 (user-error "Tool Contract Violation (%s): expected '%s' to be an array, got %S" tool-name arg-name val)))
              ((or "object" 'object)
               (unless (or (hash-table-p val) (listp val))
                 (user-error "Tool Contract Violation (%s): expected '%s' to be an object, got %S" tool-name arg-name val))))))
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
    (add-hook 'gptel-mode-hook #'nucleus-tool-sanity-check))
  
  ;; Enforce tool contracts
  (advice-add 'gptel-make-tool :around #'nucleus-tools--advise-make-tool))

(with-eval-after-load 'gptel
  (nucleus-tools-setup))

;;; Footer

(provide 'nucleus-tools)

;;; nucleus-tools.el ends here
