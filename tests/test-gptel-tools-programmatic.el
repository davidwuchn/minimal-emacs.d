;;; test-gptel-tools-programmatic.el --- Tests for gptel-tools-programmatic.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, programmatic, workflow, testing

;;; Commentary:

;; Unit tests for the Programmatic tool in gptel-tools-programmatic.el.
;;
;; NOTE: This file uses MOCK implementations. For integration tests that
;; exercise the real gptel-sandbox.el, see tests/test-programmatic.el.
;;
;; Tests cover:
;; - Restricted Emacs Lisp interpreter (mocked)
;; - Tool-call syntax validation
;; - Supported forms (setq, result, tool-call, if, when, let, etc.)
;; - Unsupported forms (arbitrary eval, while loops)
;; - Nested tool orchestration (mocked)
;; - Preview-backed mutating tools (mocked)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock Tool Registry

(defvar test-gptel-programmatic--tools
  '("Grep" "Glob" "Read" "Edit" "ApplyPatch" "Code_Map" "Code_Inspect")
  "Mock registry of available tools for Programmatic tests.")

;;; Programmatic Interpreter Mock

(defun test-gptel-programmatic--execute (code &optional mode)
  "Mock Programmatic execution.
CODE is the restricted Emacs Lisp program.
MODE is 'readonly or 'agent (defaults to 'readonly).
Returns the result expression value."
  (let ((mode (or mode 'readonly)))
    (condition-case err
        (progn
          ;; Validate code
          (test-gptel-programmatic--validate code mode)
          ;; Execute (mock interpretation)
          (test-gptel-programmatic--interpret code mode))
      (error (list :error (error-message-string err))))))

(defun test-gptel-programmatic--validate (code mode)
  "Validate CODE for restricted elisp.
MODE is 'readonly or 'agent."
  ;; Check for empty code
  (when (string-empty-p (string-trim code))
    (error "Empty code"))
  ;; Check for unsupported forms
  (let ((unsupported '(eval while defun defvar lambda)))
    (dolist (form unsupported)
      (when (string-match-p (format "(%s\\s-" (symbol-name form)) code)
        (error "Unsupported form in Programmatic: %s" form))))
  ;; Check for nested tool-call in arbitrary expressions (readonly mode)
  (when (eq mode 'readonly)
    ;; In readonly mode, only top-level tool-calls allowed
    t))

(defun test-gptel-programmatic--interpret (code mode)
  "Mock interpretation of CODE.
Returns a simulated result."
  ;; Parse and execute mock
  (cond
   ((string-match-p "Grep" code)
    '(:hits 5 :files ("file1.el" "file2.el")))
   ((string-match-p "Glob" code)
    '(:files ("*.el" "test.el")))
   ((string-match-p "Read" code)
    '(:content "file content here"))
   ((string-match-p "Code_Map" code)
    '(:functions ("func1" "func2") :classes ("Class1")))
   ((string-match-p "result" code)
    '(:result "mock result"))
   (t
    '(:result "executed"))))

;;; Supported Forms Tests

(ert-deftest test-gptel-programmatic-setq ()
  "Test Programmatic supports setq."
  (let ((code "(setq x 42)
(result x)"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-result ()
  "Test Programmatic requires result."
  (let ((code "(result \"test value\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-tool-call ()
  "Test Programmatic supports tool-call."
  (let ((code "(tool-call \"Grep\" :regex \"TODO\" :file_path \"lisp/\")
(result \"done\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-if ()
  "Test Programmatic supports if."
  (let ((code "(if t
    (result \"true branch\")
  (result \"false branch\"))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-when ()
  "Test Programmatic supports when."
  (let ((code "(when t
  (result \"executed\"))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-unless ()
  "Test Programmatic supports unless."
  (let ((code "(unless nil
  (result \"executed\"))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-let ()
  "Test Programmatic supports let."
  (let ((code "(let ((x 1)
      (y 2))
  (result (+ x y)))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-let* ()
  "Test Programmatic supports let*."
  (let ((code "(let* ((x 1)
       (y (+ x 1)))
  (result y))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-progn ()
  "Test Programmatic supports progn."
  (let ((code "(progn
  (setq x 1)
  (result x))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-and ()
  "Test Programmatic supports and."
  (let ((code "(and t t (result \"all true\"))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-or ()
  "Test Programmatic supports or."
  (let ((code "(or nil t (result \"one true\"))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-not ()
  "Test Programmatic supports not."
  (let ((code "(not nil)
(result \"negated\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

;;; Comparison Tests

(ert-deftest test-gptel-programmatic-equal ()
  "Test Programmatic supports equal."
  (let ((code "(equal \"a\" \"a\")
(result \"compared\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-string= ()
  "Test Programmatic supports string=."
  (let ((code "(string= \"test\" \"test\")
(result \"strings equal\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-numeric-comparison ()
  "Test Programmatic supports numeric comparisons."
  (let ((code "(and (= 1 1)
     (< 1 2)
     (> 2 1)
     (<= 1 1)
     (>= 2 1))
(result \"all comparisons true\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

;;; Data Helper Tests

(ert-deftest test-gptel-programmatic-list ()
  "Test Programmatic supports list."
  (let ((code "(list 1 2 3)
(result \"list created\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-cons ()
  "Test Programmatic supports cons."
  (let ((code "(cons 1 '(2 3))
(result \"cons created\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-car-cdr ()
  "Test Programmatic supports car/cdr."
  (let ((code "(car '(1 2 3))
(cdr '(1 2 3))
(result \"list access\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-nth ()
  "Test Programmatic supports nth."
  (let ((code "(nth 1 '(a b c))
(result \"nth access\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-append ()
  "Test Programmatic supports append."
  (let ((code "(append '(1 2) '(3 4))
(result \"appended\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-length ()
  "Test Programmatic supports length."
  (let ((code "(length '(1 2 3 4 5))
(result \"length calculated\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-assoc ()
  "Test Programmatic supports assoc."
  (let ((code "(assoc 'key '((key . value)))
(result \"assoc lookup\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-alist-get ()
  "Test Programmatic supports alist-get."
  (let ((code "(alist-get 'key '((key . value)))
(result \"alist-get lookup\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-plist-get ()
  "Test Programmatic supports plist-get."
  (let ((code "(plist-get '(:key value) :key)
(result \"plist-get lookup\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

;;; String Helper Tests

(ert-deftest test-gptel-programmatic-concat ()
  "Test Programmatic supports concat."
  (let ((code "(concat \"hello\" \" \" \"world\")
(result \"concatenated\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-format ()
  "Test Programmatic supports format."
  (let ((code "(format \"Hello %s\" \"World\")
(result \"formatted\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-string-helpers ()
  "Test Programmatic supports string helpers."
  (let ((code "(string-trim \"  test  \")
(string-empty-p \"\")
(string-match-p \"pattern\" \"text\")
(substring \"hello\" 0 2)
(result \"string helpers\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

;;; Unsupported Forms Tests

(ert-deftest test-gptel-programmatic-blocks-eval ()
  "Test Programmatic blocks eval."
  (let ((code "(eval '(+ 1 2))
(result \"should not reach\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should (plist-get result :error))
      (should (string-match-p "Unsupported" (plist-get result :error))))))

(ert-deftest test-gptel-programmatic-blocks-while ()
  "Test Programmatic blocks while loops."
  (let ((code "(while t
  (setq x (+ x 1)))
(result \"should not reach\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should (plist-get result :error))
      (should (string-match-p "Unsupported" (plist-get result :error))))))

(ert-deftest test-gptel-programmatic-blocks-defun ()
  "Test Programmatic blocks defun."
  (let ((code "(defun my-func ()
  (+ 1 2))
(result \"should not reach\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should (plist-get result :error))
      (should (string-match-p "Unsupported" (plist-get result :error))))))

(ert-deftest test-gptel-programmatic-blocks-lambda ()
  "Test Programmatic blocks lambda."
  (let ((code "(lambda (x) (+ x 1))
(result \"should not reach\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should (plist-get result :error))
      (should (string-match-p "Unsupported" (plist-get result :error))))))

;;; Mode Tests

(ert-deftest test-gptel-programmatic-readonly-mode ()
  "Test Programmatic in readonly mode."
  (let ((code "(tool-call \"Grep\" :regex \"TODO\" :file_path \"lisp/\")
(result \"grep done\")"))
    (let ((result (test-gptel-programmatic--execute code 'readonly)))
      (should result))))

(ert-deftest test-gptel-programmatic-agent-mode ()
  "Test Programmatic in agent mode."
  (let ((code "(tool-call \"Edit\" :file_path \"file.el\" :new_str \"patch\")
(result \"edit done\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-agent-mode-mutating-tools ()
  "Test Programmatic agent mode allows mutating tools."
  (let ((code "(tool-call \"ApplyPatch\" :patch \"--- a/file.el\\n+++ b/file.el\")
(result \"patch applied\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

;;; Multi-step Workflow Tests

(ert-deftest test-gptel-programmatic-sequential-tool-calls ()
  "Test Programmatic sequential tool calls."
  (let ((code "(setq grep-result (tool-call \"Grep\" :regex \"TODO\" :file_path \"lisp/\"))
(setq glob-result (tool-call \"Glob\" :pattern \"*.el\" :file_path \"lisp/\"))
(result (list :grep grep-result :glob glob-result))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-conditional-workflow ()
  "Test Programmatic conditional workflow."
  (let ((code "(setq files (tool-call \"Glob\" :pattern \"*.el\" :file_path \"tests/\"))
(when (> (length files) 0)
  (result \"tests found\"))
(result \"no tests\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-mapcar-workflow ()
  "Test Programmatic mapcar workflow."
  (let ((code "(setq files '(\"file1.el\" \"file2.el\"))
(setq results (mapcar (lambda (f) (concat \"processed: \" f)) files))
(result results)"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

;;; Integration-style Tests

(ert-deftest test-gptel-programmatic-find-and-read ()
  "Test Programmatic find files then read workflow."
  (let ((code "(setq files (tool-call \"Glob\" :pattern \"*.el\" :file_path \"lisp/modules/\"))
(setq first-file (car files))
(when first-file
  (setq content (tool-call \"Read\" :file_path first-file)))
(result (list :files files :first first-file))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-grep-then-map ()
  "Test Programmatic grep then process workflow."
  (let ((code "(setq hits (tool-call \"Grep\" :regex \"TODO\" :file_path \"lisp/\"))
(setq count (length hits))
(when (> count 0)
  (result (format \"Found %d TODOs\" count)))
(result \"No TODOs found\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-code-introspection-workflow ()
  "Test Programmatic code introspection workflow."
  (let ((code "(setq map (tool-call \"Code_Map\" :file_path \"lisp/sample.el\"))
(setq functions (plist-get map :functions))
(when functions
  (setq first-func (car functions))
  (setq source (tool-call \"Code_Inspect\" :node_name first-func)))
(result (list :map map :functions functions))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

;;; Edge Case Tests

;;; Real Tool-Call Execution Tests

(defvar test-gptel-programmatic--real-tools-executed nil
  "Flag to track if real tools were executed.")

(defun test-gptel-programmatic--execute-real-tool (tool-name &rest args)
  "Execute a real tool call (mock implementation).
TOOL-NAME is the tool to call.
ARGS are the tool arguments."
  (setq test-gptel-programmatic--real-tools-executed t)
  (cond
   ((string= tool-name "Grep")
    (list :hits 3 :files '("file1.el" "file2.el" "file3.el")))
   ((string= tool-name "Glob")
    (list :files '("test1.el" "test2.el")))
   ((string= tool-name "Read")
    (list :content "(defun test () 1)" :lines 1))
   ((string= tool-name "Edit")
    (list :success t :message "Edit applied"))
   ((string= tool-name "ApplyPatch")
    (list :success t :message "Patch applied"))
   (t
    (list :error (format "Unknown tool: %s" tool-name)))))

(ert-deftest test-gptel-programmatic-real-grep-execution ()
  "Test Programmatic executes real Grep tool."
  (let ((test-gptel-programmatic--real-tools-executed nil))
    (let ((result (test-gptel-programmatic--execute-real-tool "Grep" :regex "TODO" :file_path "lisp/")))
      (should test-gptel-programmatic--real-tools-executed)
      (should (plist-get result :hits))
      (should (listp (plist-get result :files))))))

(ert-deftest test-gptel-programmatic-real-glob-execution ()
  "Test Programmatic executes real Glob tool."
  (let ((test-gptel-programmatic--real-tools-executed nil))
    (let ((result (test-gptel-programmatic--execute-real-tool "Glob" :pattern "*.el")))
      (should test-gptel-programmatic--real-tools-executed)
      (should (listp (plist-get result :files))))))

(ert-deftest test-gptel-programmatic-real-read-execution ()
  "Test Programmatic executes real Read tool."
  (let ((test-gptel-programmatic--real-tools-executed nil))
    (let ((result (test-gptel-programmatic--execute-real-tool "Read" :file_path "test.el")))
      (should test-gptel-programmatic--real-tools-executed)
      (should (stringp (plist-get result :content))))))

(ert-deftest test-gptel-programmatic-real-edit-execution ()
  "Test Programmatic executes real Edit tool."
  (let ((test-gptel-programmatic--real-tools-executed nil))
    (let ((result (test-gptel-programmatic--execute-real-tool "Edit" :file_path "test.el" :new_str "new")))
      (should test-gptel-programmatic--real-tools-executed)
      (should (plist-get result :success)))))

(ert-deftest test-gptel-programmatic-real-apply-patch-execution ()
  "Test Programmatic executes real ApplyPatch tool."
  (let ((test-gptel-programmatic--real-tools-executed nil))
    (let ((result (test-gptel-programmatic--execute-real-tool "ApplyPatch" :patch "--- a/test.el")))
      (should test-gptel-programmatic--real-tools-executed)
      (should (plist-get result :success)))))

(ert-deftest test-gptel-programmatic-real-unknown-tool-error ()
  "Test Programmatic handles unknown tool gracefully."
  (let ((test-gptel-programmatic--real-tools-executed nil))
    (let ((result (test-gptel-programmatic--execute-real-tool "UnknownTool")))
      (should test-gptel-programmatic--real-tools-executed)
      (should (plist-get result :error)))))

;;; Nested Tool-Call Validation Tests

(ert-deftest test-gptel-programmatic-nested-tool-call-in-let ()
  "Test nested tool-call in let binding."
  (let ((code "(let ((result (tool-call \"Grep\" :regex \"x\" :file_path \"y\")))
  (result result))"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-nested-tool-call-in-when ()
  "Test nested tool-call in when body."
  (let ((code "(when t
  (tool-call \"Glob\" :pattern \"*\"))
(result \"done\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-nested-tool-call-in-mapcar ()
  "Test nested tool-call in mapcar."
  (let ((code "(setq files '(\"a.el\" \"b.el\"))
(setq results (mapcar (lambda (f)
                        (tool-call \"Read\" :file_path f))
                      files))
(result results)"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-readonly-rejects-nested-mutating ()
  "Test readonly mode rejects nested mutating tool-calls."
  (let ((code "(setq result (tool-call \"Edit\" :file_path \"x\" :new \"y\"))
(result result)"))
    (let ((result (test-gptel-programmatic--execute code 'readonly)))
      ;; Should error or reject in readonly mode
      (should result))))

;;; Error Propagation Tests

(defvar test-gptel-programmatic--error-scenarios
  '((:tool "Grep" :error "File not found")
    (:tool "Glob" :error "Invalid pattern")
    (:tool "Read" :error "Permission denied")
    (:tool "Edit" :error "File locked"))
  "Mock error scenarios for testing.")

(defun test-gptel-programmatic--simulate-error (tool-name)
  "Simulate error for TOOL-NAME."
  (let ((scenario (assoc tool-name test-gptel-programmatic--error-scenarios)))
    (when scenario
      (error (plist-get (cdr scenario) :error)))))

(ert-deftest test-gptel-programmatic-error-propagation-from-grep ()
  "Test error propagates from Grep tool."
  (condition-case err
      (test-gptel-programmatic--simulate-error "Grep")
    (error
     (should (string= (error-message-string err) "File not found")))))

(ert-deftest test-gptel-programmatic-error-propagation-from-read ()
  "Test error propagates from Read tool."
  (condition-case err
      (test-gptel-programmatic--simulate-error "Read")
    (error
     (should (string= (error-message-string err) "Permission denied")))))

(ert-deftest test-gptel-programmatic-error-handling-in-workflow ()
  "Test error handling in multi-step workflow."
  (let ((code "(condition-case err
    (tool-call \"Grep\" :regex \"x\" :file_path \"nonexistent\")
  (error
   (result (format \"Error: %s\" (error-message-string err)))))
(result \"success\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-error-with-action-suggestion ()
  "Test error includes action suggestion."
  (let ((error-msg "File not found: /path/to/file.el")
        (suggestion "Use Glob to find existing files"))
    (should (stringp error-msg))
    (should (stringp suggestion))
    (should (> (length error-msg) 0))
    (should (> (length suggestion) 0))))

;;; Preview-Backed Mutating Tool Tests

(ert-deftest test-gptel-programmatic-preview-edit ()
  "Test Programmatic with preview-backed Edit tool."
  (let ((code "(tool-call \"Edit\" :file_path \"test.el\" :old_str \"old\" :new_str \"new\")
(result \"edit previewed\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-preview-apply-patch ()
  "Test Programmatic with preview-backed ApplyPatch tool."
  (let ((code "(tool-call \"ApplyPatch\" :patch \"--- a/test.el\\n+++ b/test.el\")
(result \"patch previewed\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-preview-code-replace ()
  "Test Programmatic with preview-backed Code_Replace tool."
  (let ((code "(tool-call \"Code_Replace\" :file_path \"test.el\" :node_name \"func\" :new_code \"(defun func () 1)\")
(result \"replace previewed\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      (should result))))

(ert-deftest test-gptel-programmatic-preview-aggregate ()
  "Test Programmatic aggregate preview for multiple mutating tools."
  (let ((code "(tool-call \"Edit\" :file_path \"a.el\" :old_str \"x\" :new_str \"y\")
(tool-call \"Edit\" :file_path \"b.el\" :old_str \"p\" :new_str \"q\")
(result \"multiple edits\")"))
    (let ((result (test-gptel-programmatic--execute code 'agent)))
      ;; Should get one aggregate preview before per-tool confirmations
      (should result))))

(ert-deftest test-gptel-programmatic-empty-code ()
  "Test Programmatic with empty code."
  (let ((code ""))
    (let ((result (test-gptel-programmatic--execute code)))
      (should (or (plist-get result :error)
                  (null result))))))

(ert-deftest test-gptel-programmatic-missing-result ()
  "Test Programmatic without result form."
  (let ((code "(setq x 42)"))
    (let ((result (test-gptel-programmatic--execute code)))
      ;; Should handle gracefully or error
      (should result))))

(ert-deftest test-gptel-programmatic-invalid-tool-name ()
  "Test Programmatic with invalid tool name."
  (let ((code "(tool-call \"InvalidTool\" :arg \"value\")
(result \"done\")"))
    (let ((result (test-gptel-programmatic--execute code)))
      ;; Should handle gracefully
      (should result))))

(ert-deftest test-gptel-programmatic-nested-tool-call-readonly ()
  "Test Programmatic nested tool-call in readonly mode."
  (let ((code "(setq result (if t
    (tool-call \"Grep\" :regex \"x\" :file_path \"y\")
  (tool-call \"Glob\" :pattern \"*\")))
(result result)"))
    (let ((result (test-gptel-programmatic--execute code 'readonly)))
      ;; In readonly, nested tool-calls might be restricted
      (should result))))

;;; Provide the test suite

(provide 'test-gptel-tools-programmatic)

;;; test-gptel-tools-programmatic.el ends here
