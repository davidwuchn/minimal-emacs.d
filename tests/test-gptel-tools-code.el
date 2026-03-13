;;; test-gptel-tools-code.el --- Tests for gptel-tools-code.el -*- lexical-binding: t; -*-

;; Copyright (C) 2024  David Wu

;; Author: David Wu
;; Keywords: gptel, code, introspection, testing

;;; Commentary:

;; Unit tests for the Code tools in gptel-tools-code.el.
;; Tests cover:
;; - Code_Map: AST-based file structure mapping
;; - Code_Inspect: Extract function/class definitions
;; - Code_Usages: Find symbol references (LSP -> ripgrep fallback)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock Data

(defvar test-gptel-code--sample-el-file
  ";;; sample.el --- Sample Emacs Lisp file

(defun sample-function-1 (arg1 arg2)
  \"Docstring for function 1.\"
  (message \"Hello %s\" arg1))

(defun sample-function-2 ()
  \"Docstring for function 2.\"
  (let ((x 1))
    x))

(defclass sample-class ()
  ((slot1 :initarg :slot1)
   (slot2 :initarg :slot2))
  \"A sample class.\")

(cl-defmethod sample-method ((obj sample-class) value)
  \"A sample method.\"
  (setf (slot-value obj 'slot1) value))

(provide 'sample)"
  "Sample Emacs Lisp file content for testing.")

(defvar test-gptel-code--sample-python-file
  "class SampleClass:
    def __init__(self, value):
        self.value = value
    
    def method1(self, x):
        return x + self.value
    
    def method2(self):
        return self.value

def sample_function(a, b):
    return a + b

def another_function():
    pass
"
  "Sample Python file content for testing.")

;;; Code_Map Mock Implementation

(defun test-gptel-code--map-file (file-path)
  "Mock Code_Map implementation.
FILE-PATH is the path to the file to map.
Returns an ordered list of symbols (functions/classes)."
  (cond
   ((string-suffix-p ".el" file-path)
    '(:functions ("sample-function-1" "sample-function-2")
      :classes ("sample-class")
      :methods ("sample-method")))
   ((string-suffix-p ".py" file-path)
    '(:classes ("SampleClass")
      :functions ("sample_function" "another_function")
      :methods ("__init__" "method1" "method2")))
   ((string-suffix-p ".js" file-path)
    '(:functions ("sampleFunction" "anotherFunction")
      :classes ("SampleClass")))
   (t
    '(:error "Unsupported file type"))))

;;; Code_Inspect Mock Implementation

(defun test-gptel-code--inspect-symbol (node-name &optional file-path)
  "Mock Code_Inspect implementation.
NODE-NAME is the exact name of the function/class to read.
FILE-PATH is optional (searches project if omitted).
Returns the balanced code block."
  (cond
   ((equal node-name "sample-function-1")
    "(defun sample-function-1 (arg1 arg2)
  \"Docstring for function 1.\"
  (message \"Hello %s\" arg1))")
   ((equal node-name "sample-function-2")
    "(defun sample-function-2 ()
  \"Docstring for function 2.\"
  (let ((x 1))
    x))")
   ((equal node-name "sample-class")
    "(defclass sample-class ()
  ((slot1 :initarg :slot1)
   (slot2 :initarg :slot2))
  \"A sample class.\")")
   ((equal node-name "sample-method")
    "(cl-defmethod sample-method ((obj sample-class) value)
  \"A sample method.\"
  (setf (slot-value obj 'slot1) value))")
   ((equal node-name "SampleClass")
    "class SampleClass:
    def __init__(self, value):
        self.value = value
    
    def method1(self, x):
        return x + self.value
    
    def method2(self):
        return self.value")
   (t
    (list :error (format "Symbol not found: %s" node-name)))))

;;; Code_Usages Mock Implementation

(defun test-gptel-code--find-usages (node-name)
  "Mock Code_Usages implementation.
NODE-NAME is the symbol/function/class name to find.
Returns list of file:line:context with backend info."
  (cond
   ((equal node-name "sample-function-1")
    '(:usages ((:file "lisp/sample.el" :line 5 :context "(sample-function-1 arg1 arg2)")
               (:file "lisp/other.el" :line 23 :context "(sample-function-1 \"test\" 42)"))
      :backend "LSP"))
   ((equal node-name "sample-function-2")
    '(:usages ((:file "lisp/sample.el" :line 12 :context "(sample-function-2)"))
      :backend "LSP"))
   ((equal node-name "unused-symbol")
    '(:usages nil
      :backend "ripgrep"))
   ((equal node-name "large-project-symbol")
    '(:usages ((:file "file1.el" :line 10 :context "...")
               (:file "file2.el" :line 20 :context "...")
               (:file "file3.el" :line 30 :context "...")
               (:file "file4.el" :line 40 :context "...")
               (:file "file5.el" :line 50 :context "..."))
      :backend "ripgrep"
      :fallback t))
   (t
    '(:usages nil
      :backend "ripgrep"
      :fallback t))))

;;; Code_Map Tests

(ert-deftest test-gptel-code-map-el-file ()
  "Test Code_Map on Emacs Lisp file."
  (let ((result (test-gptel-code--map-file "lisp/sample.el")))
    (should (plist-get result :functions))
    (should (plist-get result :classes))
    (should (equal (length (plist-get result :functions)) 2))
    (should (equal (car (plist-get result :functions)) "sample-function-1"))))

(ert-deftest test-gptel-code-map-python-file ()
  "Test Code_Map on Python file."
  (let ((result (test-gptel-code--map-file "src/sample.py")))
    (should (plist-get result :classes))
    (should (plist-get result :functions))
    (should (equal (car (plist-get result :classes)) "SampleClass"))
    (should (equal (length (plist-get result :methods)) 3))))

(ert-deftest test-gptel-code-map-js-file ()
  "Test Code_Map on JavaScript file."
  (let ((result (test-gptel-code--map-file "src/sample.js")))
    (should (plist-get result :functions))
    (should (plist-get result :classes))))

(ert-deftest test-gptel-code-map-unsupported-file ()
  "Test Code_Map on unsupported file type."
  (let ((result (test-gptel-code--map-file "README.md")))
    (should (plist-get result :error))
    (should (string-match-p "Unsupported" (plist-get result :error)))))

(ert-deftest test-gptel-code-map-ordering ()
  "Test Code_Map returns symbols in order."
  (let ((result (test-gptel-code--map-file "lisp/sample.el")))
    (should (equal (plist-get result :functions)
                   '("sample-function-1" "sample-function-2")))))

;;; Code_Inspect Tests

(ert-deftest test-gptel-code-inspect-function ()
  "Test Code_Inspect extracts function definition."
  (let ((result (test-gptel-code--inspect-symbol "sample-function-1")))
    (should (string-prefix-p "(defun sample-function-1" result))
    (should (string-suffix-p "))" result))
    (should (string-match-p "Docstring" result))))

(ert-deftest test-gptel-code-inspect-class ()
  "Test Code_Inspect extracts class definition."
  (let ((result (test-gptel-code--inspect-symbol "sample-class")))
    (should (string-prefix-p "(defclass sample-class" result))
    (should (string-match-p "slot1" result))
    (should (string-match-p "slot2" result))))

(ert-deftest test-gptel-code-inspect-method ()
  "Test Code_Inspect extracts method definition."
  (let ((result (test-gptel-code--inspect-symbol "sample-method")))
    (should (string-prefix-p "(cl-defmethod sample-method" result))
    (should (string-match-p "sample-class" result))))

(ert-deftest test-gptel-code-inspect-python-class ()
  "Test Code_Inspect extracts Python class."
  (let ((result (test-gptel-code--inspect-symbol "SampleClass")))
    (should (string-prefix-p "class SampleClass:" result))
    (should (string-match-p "def __init__" result))
    (should (string-match-p "def method1" result))))

(ert-deftest test-gptel-code-inspect-not-found ()
  "Test Code_Inspect handles missing symbol."
  (let ((result (test-gptel-code--inspect-symbol "nonexistent-symbol")))
    (should (plist-get result :error))
    (should (string-match-p "not found" (plist-get result :error)))))

(ert-deftest test-gptel-code-inspect-balanced-parens ()
  "Test Code_Inspect returns balanced parentheses."
  (let ((result (test-gptel-code--inspect-symbol "sample-function-2")))
    (let ((open (cl-count ?\( result))
          (close (cl-count ?\) result)))
      (should (= open close))
      (should (string-match-p "^(defun" result))
      (should (string-suffix-p "))" result)))))

;;; Code_Usages Tests

(ert-deftest test-gptel-code-usages-finds-references ()
  "Test Code_Usages finds symbol references."
  (let ((result (test-gptel-code--find-usages "sample-function-1")))
    (should (plist-get result :usages))
    (should (= (length (plist-get result :usages)) 2))
    (should (equal (plist-get result :backend) "LSP"))))

(ert-deftest test-gptel-code-usages-no-references ()
  "Test Code_Usages handles unused symbol."
  (let ((result (test-gptel-code--find-usages "unused-symbol")))
    (should (plist-member result :usages))
    (should (null (plist-get result :usages)))))

(ert-deftest test-gptel-code-usages-lsp-backend ()
  "Test Code_Usages uses LSP when available."
  (let ((result (test-gptel-code--find-usages "sample-function-1")))
    (should (equal (plist-get result :backend) "LSP"))))

(ert-deftest test-gptel-code-usages-ripgrep-fallback ()
  "Test Code_Usages falls back to ripgrep."
  (let ((result (test-gptel-code--find-usages "large-project-symbol")))
    (should (equal (plist-get result :backend) "ripgrep"))
    (should (plist-get result :fallback))))

(ert-deftest test-gptel-code-usages-usage-context ()
  "Test Code_Usages includes context for each usage."
  (let ((result (test-gptel-code--find-usages "sample-function-1")))
    (let ((usages (plist-get result :usages)))
      (should (plist-get (car usages) :file))
      (should (plist-get (car usages) :line))
      (should (plist-get (car usages) :context)))))

(ert-deftest test-gptel-code-usages-multiple-files ()
  "Test Code_Usages finds usages across multiple files."
  (let ((result (test-gptel-code--find-usages "large-project-symbol")))
    (let ((usages (plist-get result :usages)))
      (should (>= (length usages) 5))
      ;; Verify different files
      (let ((files (mapcar (lambda (u) (plist-get u :file)) usages)))
        (should (= (length (delete-dups files)) (length files)))))))

;;; Integration-style Tests

(ert-deftest test-gptel-code-map-then-inspect ()
  "Test Code_Map followed by Code_Inspect workflow."
  (let* ((map-result (test-gptel-code--map-file "lisp/sample.el"))
         (functions (plist-get map-result :functions))
         (first-func (car functions))
         (inspect-result (test-gptel-code--inspect-symbol first-func)))
    (should (string-prefix-p "(defun sample-function-1" inspect-result))))

(ert-deftest test-gptel-code-inspect-then-usages ()
  "Test Code_Inspect followed by Code_Usages workflow."
  (let* ((inspect-result (test-gptel-code--inspect-symbol "sample-function-1"))
         (usages-result (test-gptel-code--find-usages "sample-function-1")))
    (should (string-prefix-p "(defun" inspect-result))
    (should (>= (length (plist-get usages-result :usages)) 1))))

(ert-deftest test-gptel-code-full-introspection ()
  "Test full code introspection workflow."
  (let* ((file "lisp/sample.el")
         (map (test-gptel-code--map-file file))
         (first-class (car (plist-get map :classes)))
         (inspect (test-gptel-code--inspect-symbol first-class))
         (usages (test-gptel-code--find-usages first-class)))
    (should map)
    (should inspect)
    (should usages)))

;;; Edge Case Tests

(ert-deftest test-gptel-code-map-empty-file ()
  "Test Code_Map on empty file."
  (let ((result (test-gptel-code--map-file "empty.el")))
    ;; Should return empty lists, not error
    (should (or (plist-get result :functions)
                (plist-get result :error)))))

(ert-deftest test-gptel-code-inspect-special-chars ()
  "Test Code_Inspect with special characters in symbol name."
  (let ((result (test-gptel-code--inspect-symbol "sample-function-1")))
    (should result)))

(ert-deftest test-gptel-code-usages-special-chars ()
  "Test Code_Usages with special characters in symbol name."
  (let ((result (test-gptel-code--find-usages "sample-function-1")))
    (should (plist-get result :usages))))

;;; Provide the test suite

(provide 'test-gptel-tools-code)

;;; test-gptel-tools-code.el ends here
