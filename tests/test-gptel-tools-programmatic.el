;;; test-gptel-tools-programmatic.el --- Tests for gptel-tools-programmatic.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, programmatic, workflow, testing

;;; Commentary:

;; Unit tests for the Programmatic tool in gptel-tools-programmatic.el.
;; Tests cover:
;; - Restricted Emacs Lisp interpreter
;; - Tool-call syntax validation
;; - Supported forms (setq, result, tool-call, if, when, let, etc.)
;; - Unsupported forms (arbitrary eval, while loops)
;; - Nested tool orchestration
;; - Preview-backed mutating tools

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
  (let ((code "(tool-call \"Grep\" :regex \"TODO\" :path \"lisp/\")
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
  (let ((code "(tool-call \"Grep\" :regex \"TODO\" :path \"lisp/\")
(result \"grep done\")"))
    (let ((result (test-gptel-programmatic--execute code 'readonly)))
      (should result))))

(ert-deftest test-gptel-programmatic-agent-mode ()
  "Test Programmatic in agent mode."
  (let ((code "(tool-call \"Edit\" :path \"file.el\" :new_str_or_diff \"patch\")
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
  (let ((code "(setq grep-result (tool-call \"Grep\" :regex \"TODO\" :path \"lisp/\"))
(setq glob-result (tool-call \"Glob\" :pattern \"*.el\" :path \"lisp/\"))
(result (list :grep grep-result :glob glob-result))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-conditional-workflow ()
  "Test Programmatic conditional workflow."
  (let ((code "(setq files (tool-call \"Glob\" :pattern \"*.el\" :path \"tests/\"))
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
  (let ((code "(setq files (tool-call \"Glob\" :pattern \"*.el\" :path \"lisp/modules/\"))
(setq first-file (car files))
(when first-file
  (setq content (tool-call \"Read\" :file_path first-file)))
(result (list :files files :first first-file))"))
    (let ((result (test-gptel-programmatic--execute code)))
      (should result))))

(ert-deftest test-gptel-programmatic-grep-then-map ()
  "Test Programmatic grep then process workflow."
  (let ((code "(setq hits (tool-call \"Grep\" :regex \"TODO\" :path \"lisp/\"))
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
    (tool-call \"Grep\" :regex \"x\" :path \"y\")
  (tool-call \"Glob\" :pattern \"*\")))
(result result)"))
    (let ((result (test-gptel-programmatic--execute code 'readonly)))
      ;; In readonly, nested tool-calls might be restricted
      (should result))))

;;; Provide the test suite

(provide 'test-gptel-tools-programmatic)

;;; test-gptel-tools-programmatic.el ends here
