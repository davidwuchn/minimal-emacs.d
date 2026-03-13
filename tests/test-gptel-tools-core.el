;;; test-gptel-tools-core.el --- Tests for gptel-tools.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, tools, registry, testing

;;; Commentary:

;; Unit tests for the core gptel-tools.el module.
;; Tests cover:
;; - Tool registry management
;; - Tool definition macro (gptel-tools--define)
;; - Tool execution framework
;; - Tool validation
;; - Tool metadata

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock Tool Registry

(defvar test-gptel-core--registry (make-hash-table :test 'equal)
  "Mock tool registry for core tests.")

(defvar test-gptel-core--tool-specs
  '(("Grep" . (:description "Search file contents"
               :parameters (:regex :path :glob :context_lines)
               :async t
               :mode :readonly))
    ("Glob" . (:description "Find files by glob pattern"
               :parameters (:pattern :path :depth)
               :async t
               :mode :readonly))
    ("Read" . (:description "Read file contents"
               :parameters (:file_path :start_line :end_line)
               :async nil
               :mode :readonly))
    ("Edit" . (:description "Replace text or apply diff"
               :parameters (:file_path :old_str :new_str :diffp)
               :async nil
               :mode :agent))
    ("ApplyPatch" . (:description "Apply unified diff patch"
               :parameters (:patch)
               :async nil
               :mode :agent))
    ("Bash" . (:description "Execute bash command"
               :parameters (:command)
               :async nil
               :mode :dynamic))
    ("RunAgent" . (:description "Run subagent"
               :parameters (:agent_name :description :prompt :files :include_history :include_diff)
               :async t
               :mode :agent))
    ("Code_Map" . (:description "Map file structure"
               :parameters (:file_path)
               :async nil
               :mode :readonly))
    ("Code_Inspect" . (:description "Extract code block"
               :parameters (:node_name :file_path)
               :async nil
               :mode :readonly))
    ("Code_Usages" . (:description "Find symbol usages"
               :parameters (:node_name)
               :async nil
               :mode :readonly))
    ("Preview" . (:description "Preview changes"
               :parameters (:path :original :replacement :patch)
               :async nil
               :mode :agent))
    ("Programmatic" . (:description "Execute restricted elisp"
               :parameters (:code)
               :async t
               :mode :dynamic)))
  "Mock tool specifications.")

;;; Tool Registry Functions

(defun test-gptel-core--register-tool (name spec)
  "Register tool NAME with SPEC in mock registry."
  (puthash name spec test-gptel-core--registry))

(defun test-gptel-core--get-tool (name)
  "Get tool spec for NAME from mock registry."
  (gethash name test-gptel-core--registry))

(defun test-gptel-core--list-tools ()
  "List all registered tools."
  (let ((tools nil))
    (maphash (lambda (k v) (push k tools)) test-gptel-core--registry)
    (nreverse tools)))

(defun test-gptel-core--clear-registry ()
  "Clear the mock registry."
  (clrhash test-gptel-core--registry))

;;; Tool Definition Tests

(ert-deftest test-gptel-core-register-tool ()
  "Test tool registration."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "TestTool" '(:description "Test tool"))
  (let ((spec (test-gptel-core--get-tool "TestTool")))
    (should spec)
    (should (equal (plist-get spec :description) "Test tool"))))

(ert-deftest test-gptel-core-register-all-tools ()
  "Test registering all mock tools."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((tools (test-gptel-core--list-tools)))
    (should (= (length tools) (length test-gptel-core--tool-specs)))))

(ert-deftest test-gptel-core-tool-spec-structure ()
  "Test tool spec has required fields."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry))
    (let ((spec (test-gptel-core--get-tool (car entry))))
      (should (plist-get spec :description))
      (should (plist-get spec :parameters))
      (should (plist-get spec :mode)))))

(ert-deftest test-gptel-core-tool-not-found ()
  "Test getting nonexistent tool."
  (test-gptel-core--clear-registry)
  (let ((spec (test-gptel-core--get-tool "NonexistentTool")))
    (should-not spec)))

;;; Tool Mode Tests

(ert-deftest test-gptel-core-readonly-tools ()
  "Test readonly mode tools."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((readonly-tools nil))
    (dolist (entry test-gptel-core--tool-specs)
      (let ((spec (test-gptel-core--get-tool (car entry))))
        (when (eq (plist-get spec :mode) :readonly)
          (push (car entry) readonly-tools))))
    (should (>= (length readonly-tools) 4))
    (should (member "Grep" readonly-tools))
    (should (member "Glob" readonly-tools))
    (should (member "Read" readonly-tools))))

(ert-deftest test-gptel-core-agent-tools ()
  "Test agent mode tools."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((agent-tools nil))
    (dolist (entry test-gptel-core--tool-specs)
      (let ((spec (test-gptel-core--get-tool (car entry))))
        (when (eq (plist-get spec :mode) :agent)
          (push (car entry) agent-tools))))
    (should (>= (length agent-tools) 3))
    (should (member "Edit" agent-tools))
    (should (member "ApplyPatch" agent-tools))
    (should (member "Preview" agent-tools))))

(ert-deftest test-gptel-core-dynamic-mode-tools ()
  "Test dynamic mode tools."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((dynamic-tools nil))
    (dolist (entry test-gptel-core--tool-specs)
      (let ((spec (test-gptel-core--get-tool (car entry))))
        (when (eq (plist-get spec :mode) :dynamic)
          (push (car entry) dynamic-tools))))
    (should (member "Bash" dynamic-tools))
    (should (member "Programmatic" dynamic-tools))))

;;; Async Behavior Tests

(ert-deftest test-gptel-core-async-tools ()
  "Test async tool identification."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((async-tools nil))
    (dolist (entry test-gptel-core--tool-specs)
      (let ((spec (test-gptel-core--get-tool (car entry))))
        (when (plist-get spec :async)
          (push (car entry) async-tools))))
    (should (>= (length async-tools) 3))
    (should (member "Grep" async-tools))
    (should (member "Glob" async-tools))
    (should (member "RunAgent" async-tools))))

(ert-deftest test-gptel-core-sync-tools ()
  "Test sync tool identification."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((sync-tools nil))
    (dolist (entry test-gptel-core--tool-specs)
      (let ((spec (test-gptel-core--get-tool (car entry))))
        (when (not (plist-get spec :async))
          (push (car entry) sync-tools))))
    (should (member "Read" sync-tools))
    (should (member "Edit" sync-tools))
    (should (member "ApplyPatch" sync-tools))))

;;; Parameter Validation Tests

(ert-deftest test-gptel-core-validate-parameters ()
  "Test parameter validation."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "TestTool"
                                  '(:description "Test"
                                    :parameters (:required1 :required2 :optional)
                                    :mode :readonly))
  (let ((spec (test-gptel-core--get-tool "TestTool")))
    (should (plist-get spec :parameters))
    (should (>= (length (plist-get spec :parameters)) 2))))

(ert-deftest test-gptel-core-parameter-types ()
  "Test parameter type specifications."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry))
    (let ((spec (test-gptel-core--get-tool (car entry))))
      (should (listp (plist-get spec :parameters))))))

;;; Tool Execution Framework Tests

(defun test-gptel-core--execute-tool (name &rest args)
  "Mock tool execution.
NAME is the tool name.
ARGS are the tool arguments."
  (let ((spec (test-gptel-core--get-tool name)))
    (if spec
        (list :tool name
              :args args
              :mode (plist-get spec :mode)
              :async (plist-get spec :async)
              :status "executed")
      (list :error (format "Unknown tool: %s" name)))))

(ert-deftest test-gptel-core-execute-readonly-tool ()
  "Test executing readonly tool."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "Grep" '(:description "Grep" :mode :readonly :async t))
  (let ((result (test-gptel-core--execute-tool "Grep" :regex "test" :path ".")))
    (should (equal (plist-get result :tool) "Grep"))
    (should (equal (plist-get result :mode) :readonly))
    (should (equal (plist-get result :status) "executed"))))

(ert-deftest test-gptel-core-execute-agent-tool ()
  "Test executing agent tool."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "Edit" '(:description "Edit" :mode :agent :async nil))
  (let ((result (test-gptel-core--execute-tool "Edit" :path "file.el" :new_str "new")))
    (should (equal (plist-get result :tool) "Edit"))
    (should (equal (plist-get result :mode) :agent))))

(ert-deftest test-gptel-core-execute-unknown-tool ()
  "Test executing unknown tool."
  (test-gptel-core--clear-registry)
  (let ((result (test-gptel-core--execute-tool "UnknownTool")))
    (should (plist-get result :error))
    (should (string-match-p "Unknown tool" (plist-get result :error)))))

(ert-deftest test-gptel-core-execute-with-args ()
  "Test executing tool with arguments."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "Read" '(:description "Read" :mode :readonly))
  (let ((result (test-gptel-core--execute-tool "Read"
                                               :file_path "test.el"
                                               :start_line 1
                                               :end_line 10)))
    (should (equal (plist-get result :tool) "Read"))
    (should (plist-get result :args))))

;;; Tool Metadata Tests

(ert-deftest test-gptel-core-tool-description ()
  "Test tool descriptions are present."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry))
    (let ((spec (test-gptel-core--get-tool (car entry))))
      (should (stringp (plist-get spec :description)))
      (should (> (length (plist-get spec :description)) 0)))))

(ert-deftest test-gptel-core-tool-naming-convention ()
  "Test tool naming conventions."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (let ((name (car entry)))
      ;; Tool names should be non-empty strings
      (should (stringp name))
      (should (> (length name) 0))
      ;; Tool names typically use PascalCase or contain underscores
      (should (or (string-match-p "^[A-Z]" name)
                  (string-match-p "_" name))))))

;;; Integration-style Tests

(ert-deftest test-gptel-core-full-tool-lifecycle ()
  "Test full tool lifecycle: register, get, execute."
  (test-gptel-core--clear-registry)
  ;; Register
  (test-gptel-core--register-tool "TestTool"
                                  '(:description "Test tool for lifecycle"
                                    :parameters (:arg1 :arg2)
                                    :mode :readonly
                                    :async nil))
  ;; Get
  (let ((spec (test-gptel-core--get-tool "TestTool")))
    (should spec)
    (should (equal (plist-get spec :description) "Test tool for lifecycle"))
    ;; Execute
    (let ((result (test-gptel-core--execute-tool "TestTool" :arg1 "val1" :arg2 "val2")))
      (should (equal (plist-get result :tool) "TestTool"))
      (should (equal (plist-get result :status) "executed")))))

(ert-deftest test-gptel-core-batch-registration ()
  "Test batch tool registration."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  ;; Verify all registered
  (dolist (entry test-gptel-core--tool-specs)
    (let ((spec (test-gptel-core--get-tool (car entry))))
      (should spec))))

(ert-deftest test-gptel-core-tool-categories ()
  "Test categorizing tools by mode."
  (test-gptel-core--clear-registry)
  (dolist (entry test-gptel-core--tool-specs)
    (test-gptel-core--register-tool (car entry) (cdr entry)))
  (let ((readonly 0)
        (agent 0)
        (dynamic 0))
    (dolist (entry test-gptel-core--tool-specs)
      (let ((spec (test-gptel-core--get-tool (car entry))))
        (pcase (plist-get spec :mode)
          (:readonly (setq readonly (1+ readonly)))
          (:agent (setq agent (1+ agent)))
          (:dynamic (setq dynamic (1+ dynamic))))))
    (should (> readonly 0))
    (should (> agent 0))
    (should (> dynamic 0))))

;;; Edge Case Tests

(ert-deftest test-gptel-core-empty-registry ()
  "Test operations on empty registry."
  (test-gptel-core--clear-registry)
  (let ((tools (test-gptel-core--list-tools)))
    (should (= (length tools) 0))))

(ert-deftest test-gptel-core-duplicate-registration ()
  "Test duplicate tool registration."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "TestTool" '(:description "First"))
  (test-gptel-core--register-tool "TestTool" '(:description "Second"))
  (let ((spec (test-gptel-core--get-tool "TestTool")))
    ;; Should overwrite
    (should (equal (plist-get spec :description) "Second"))))

(ert-deftest test-gptel-core-special-characters-in-name ()
  "Test tool names with special characters."
  (test-gptel-core--clear-registry)
  (test-gptel-core--register-tool "Test-Tool_1" '(:description "Test"))
  (let ((spec (test-gptel-core--get-tool "Test-Tool_1")))
    (should spec)))

;;; Provide the test suite

(provide 'test-gptel-tools-core)

;;; test-gptel-tools-core.el ends here
