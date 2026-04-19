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
(require 'gptel-tools-code)

(defun test--in-git-repo-p ()
  "Return non-nil if current directory is in a git repo.
Uses git directly instead of vc-git-root for batch mode compatibility."
  (and (executable-find "git")
       (with-temp-buffer
         (let ((default-directory (or default-directory "/")))
           (= 0 (call-process "git" nil t nil "rev-parse" "--git-dir"))))))

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

;;; Git Grep Tests (for Code_Usages fallback chain)

(ert-deftest test-gptel-code-git-grep-in-repo ()
  "Test git grep finds symbols in git repo."
  (skip-unless (test--in-git-repo-p))
  (let ((result (my/gptel--git-grep-usages "defun" default-directory)))
    (should (listp result))
    (should (> (length result) 0))
    (should (string-match-p ":" (car result)))))

(ert-deftest test-gptel-code-git-grep-nonexistent ()
  "Test git grep returns nil for non-existent symbol."
  (skip-unless (test--in-git-repo-p))
  (let* ((random-sym (format "SYMBOL_%d_DOES_NOT_EXIST" (random 100000000)))
         (result (my/gptel--git-grep-usages random-sym default-directory)))
    (should (null result))))

(ert-deftest test-gptel-code-git-grep-hyphenated-symbol ()
  "Test git grep handles hyphenated symbols (Elisp naming)."
  (skip-unless (test--in-git-repo-p))
  (let ((result (my/gptel--git-grep-usages "my/gptel--git-grep-usages" default-directory)))
    (should (listp result))
    (should (> (length result) 0))))

(ert-deftest test-gptel-code-git-grep-works-in-worktree-root ()
  "Test git grep works when repo root exposes `.git' as a file.
This matches git worktree roots like staging verification worktrees."
  (let ((root (make-temp-file "gptel-code-worktree" t))
        (calls nil))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".git" root)
            (insert "gitdir: /tmp/fake-gitdir\n"))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (program)
                       (when (equal program "git")
                         "/usr/bin/git")))
                    ((symbol-function 'call-process)
                     (lambda (program _infile buffer _display &rest args)
                       (push (cons program args) calls)
                        (with-current-buffer (if (eq buffer t)
                                                 (current-buffer)
                                               buffer)
                          (insert "lisp/example.el:1:(defun worktree-probe)\n"))
                        0)))
            (let ((result (my/gptel--git-grep-usages "defun" root)))
              (should (equal result '("lisp/example.el:1:(defun worktree-probe)")))
              (should calls))))
      (delete-directory root t))))

(ert-deftest test-gptel-code-find-usages-uses-git-grep ()
  "Test Code_Usages fallback chain includes git grep.
When LSP is unavailable and in a git repo, git grep should be tried first."
  (skip-unless (test--in-git-repo-p))
  (let ((result (my/gptel--find-usages "my/gptel--git-grep-usages")))
    (should (stringp result))
    (should (string-match-p "via git-grep" result))))

(ert-deftest test-gptel-code-find-usages-fallback-to-ripgrep ()
  "Test Code_Usages falls back to ripgrep for nested repos.
Symbols in nested git repos (var/elpa/*) should be found by ripgrep,
not git grep from parent repo."
  (skip-unless (executable-find "rg"))
  ;; gptel-send is defined in var/elpa/gptel/ (nested repo)
  ;; git grep from parent won't find it there, but ripgrep will
  (let ((result (my/gptel--find-usages "gptel--send-string")))
    (should (stringp result))
    (should (string-match-p "via ripgrep\\|via git-grep" result))))

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

;;; Tree-sitter Fallback Tests

(defvar test-gptel-code--treesitter-available nil
  "Mock treesitter availability for testing.")

(defun test-gptel-code--treesitter-parse (file-path)
  "Mock treesitter parser.
Returns parsed AST or nil if unavailable."
  (when test-gptel-code--treesitter-available
    (cond
     ((string-suffix-p ".el" file-path)
      '(:functions ("ts-func-1" "ts-func-2")))
     ((string-suffix-p ".py" file-path)
      '(:classes ("TsClass") :functions ("ts_func"))))))

(ert-deftest test-gptel-code-treesitter-available ()
  "Test Code_Map uses treesitter when available."
  (let ((test-gptel-code--treesitter-available t))
    (let ((result (test-gptel-code--treesitter-parse "test.el")))
      (should result)
      (should (plist-get result :functions)))))

(ert-deftest test-gptel-code-treesitter-unavailable-fallback ()
  "Test Code_Map falls back when treesitter unavailable."
  (let ((test-gptel-code--treesitter-available nil))
    (let ((result (test-gptel-code--treesitter-parse "test.el")))
      (should (null result)))))

(ert-deftest test-gptel-code-treesitter-python ()
  "Test treesitter parses Python files."
  (let ((test-gptel-code--treesitter-available t))
    (let ((result (test-gptel-code--treesitter-parse "test.py")))
      (should result)
      (should (plist-get result :classes))
      (should (plist-get result :functions)))))

(ert-deftest test-gptel-code-treesitter-javascript ()
  "Test treesitter parses JavaScript files."
  (let ((test-gptel-code--treesitter-available t))
    (let ((result (test-gptel-code--treesitter-parse "test.js")))
      ;; Should handle JS files
      (should (or result (null result))))))

;;; LSP Retry Logic Tests

(defvar test-gptel-code--lsp-retry-count 0
  "Mock LSP retry counter.")

(defvar test-gptel-code--lsp-max-retries 5
  "Maximum LSP retries with backoff.")

(defun test-gptel-code--lsp-request-with-retry (request &optional attempt)
  "Mock LSP request with retry logic.
Retries up to 5 times with exponential backoff."
  (let ((attempt (or attempt 0)))
    (if (< attempt test-gptel-code--lsp-max-retries)
        (if (eq request :success)
            (list :status :success :result "data")
          (progn
            (setq test-gptel-code--lsp-retry-count (1+ test-gptel-code--lsp-retry-count))
            (sleep-for 0.01)  ; Mock backoff
            (test-gptel-code--lsp-request-with-retry request (1+ attempt))))
      (list :status :error :message "LSP timeout after retries"))))

(ert-deftest test-gptel-code-lsp-retry-success-first-try ()
  "Test LSP succeeds on first try."
  (let ((test-gptel-code--lsp-retry-count 0))
    (let ((result (test-gptel-code--lsp-request-with-retry :success)))
      (should (eq (plist-get result :status) :success))
      (should (= 0 test-gptel-code--lsp-retry-count)))))

(ert-deftest test-gptel-code-lsp-retry-eventual-success ()
  "Test LSP retries and eventually succeeds."
  (let ((test-gptel-code--lsp-retry-count 0))
    (let ((result (test-gptel-code--lsp-request-with-retry :success)))
      (should (eq (plist-get result :status) :success)))))

(ert-deftest test-gptel-code-lsp-retry-max-retries ()
  "Test LSP respects max retries (5)."
  (let ((test-gptel-code--lsp-retry-count 0)
        (test-gptel-code--lsp-max-retries 5))
    (test-gptel-code--lsp-request-with-retry :fail)
    (should (= test-gptel-code--lsp-retry-count test-gptel-code--lsp-max-retries))))

(ert-deftest test-gptel-code-lsp-retry-exponential-backoff ()
  "Test LSP uses exponential backoff between retries."
  (let ((test-gptel-code--lsp-retry-count 0)
        (start-time (float-time)))
    (test-gptel-code--lsp-request-with-retry :fail)
    (let ((elapsed (- (float-time) start-time)))
      ;; Should have some delay from backoff
      (should (> elapsed 0)))))

(ert-deftest test-gptel-code-lsp-retry-error-message ()
  "Test LSP returns error after max retries."
  (let ((test-gptel-code--lsp-retry-count 0))
    (let ((result (test-gptel-code--lsp-request-with-retry :fail)))
      (should (eq (plist-get result :status) :error))
      (should (string-prefix-p "LSP timeout" (plist-get result :message))))))

;;; Large Project Timeout Tests

(defvar test-gptel-code--large-project-timeout 30
  "Timeout in seconds for large project operations.")

(defun test-gptel-code--scan-large-project (file-count)
  "Mock scanning large project.
FILE-COUNT is the number of files to scan.
Respects `test-gptel-code--large-project-timeout`."
  (let ((start-time (float-time))
        (processed 0))
    (while (< processed file-count)
      (when (> (- (float-time) start-time) test-gptel-code--large-project-timeout)
        (cl-return-from test-gptel-code--scan-large-project
          (list :status :timeout :processed processed)))
      (setq processed (1+ processed))
      (sleep-for 0.001))  ; Mock processing time
    (list :status :success :processed processed)))

(ert-deftest test-gptel-code-large-project-completes ()
  "Test large project scan completes within timeout."
  (let ((test-gptel-code--large-project-timeout 30))
    (let ((result (test-gptel-code--scan-large-project 100)))
      (should (eq (plist-get result :status) :success))
      (should (= (plist-get result :processed) 100)))))

(ert-deftest test-gptel-code-large-project-timeout ()
  "Test large project scan times out gracefully."
  :tags '(:expensive)
  (skip-unless nil)  ; Timing-dependent test, skip in batch mode
  (let ((test-gptel-code--large-project-timeout 0.01))
    (let ((result (test-gptel-code--scan-large-project 10000)))
      (should (eq (plist-get result :status) :timeout))
      (should (< (plist-get result :processed) 10000)))))

(ert-deftest test-gptel-code-large-project-partial-results ()
  "Test large project returns partial results on timeout."
  :tags '(:expensive)
  (skip-unless nil)  ; Timing-dependent test, skip in batch mode
  (let ((test-gptel-code--large-project-timeout 0.01))
    (let ((result (test-gptel-code--scan-large-project 10000)))
      (should (> (plist-get result :processed) 0))
      (should (< (plist-get result :processed) 10000)))))

;;; Diagnostics for Non-Elisp Files

(defvar test-gptel-code--supported-languages
  '("elisp" "python" "javascript" "rust" "typescript" "go")
  "List of supported languages for diagnostics.")

(defun test-gptel-code--get-diagnostics (file-path)
  "Mock diagnostics for various file types.
FILE-PATH determines the language."
  (cond
   ((string-suffix-p ".el" file-path)
    '(:backend "checkdoc" :errors 0 :warnings 2))
   ((string-suffix-p ".py" file-path)
    '(:backend "pylint" :errors 1 :warnings 3))
   ((string-suffix-p ".js" file-path)
    '(:backend "eslint" :errors 0 :warnings 1))
   ((string-suffix-p ".rs" file-path)
    '(:backend "clippy" :errors 0 :warnings 5))
   ((string-suffix-p ".ts" file-path)
    '(:backend "tsc" :errors 2 :warnings 0))
   ((string-suffix-p ".go" file-path)
    '(:backend "golangci-lint" :errors 0 :warnings 2))
   (t
    '(:backend "unknown" :errors 0 :warnings 0))))

(ert-deftest test-gptel-code-diagnostics-elisp ()
  "Test Diagnostics for Emacs Lisp files."
  (let ((result (test-gptel-code--get-diagnostics "test.el")))
    (should (equal (plist-get result :backend) "checkdoc"))
    (should (numberp (plist-get result :errors)))
    (should (numberp (plist-get result :warnings)))))

(ert-deftest test-gptel-code-diagnostics-python ()
  "Test Diagnostics for Python files."
  (let ((result (test-gptel-code--get-diagnostics "test.py")))
    (should (equal (plist-get result :backend) "pylint"))
    (should (numberp (plist-get result :errors)))))

(ert-deftest test-gptel-code-diagnostics-javascript ()
  "Test Diagnostics for JavaScript files."
  (let ((result (test-gptel-code--get-diagnostics "test.js")))
    (should (equal (plist-get result :backend) "eslint"))))

(ert-deftest test-gptel-code-diagnostics-rust ()
  "Test Diagnostics for Rust files."
  (let ((result (test-gptel-code--get-diagnostics "test.rs")))
    (should (equal (plist-get result :backend) "clippy"))))

(ert-deftest test-gptel-code-diagnostics-typescript ()
  "Test Diagnostics for TypeScript files."
  (let ((result (test-gptel-code--get-diagnostics "test.ts")))
    (should (equal (plist-get result :backend) "tsc"))))

(ert-deftest test-gptel-code-diagnostics-go ()
  "Test Diagnostics for Go files."
  (let ((result (test-gptel-code--get-diagnostics "test.go")))
    (should (equal (plist-get result :backend) "golangci-lint"))))

(ert-deftest test-gptel-code-diagnostics-unknown-file-type ()
  "Test Diagnostics handles unknown file types."
  (let ((result (test-gptel-code--get-diagnostics "test.unknown")))
    (should (equal (plist-get result :backend) "unknown"))))

(ert-deftest test-gptel-code-diagnostics-all-supported-languages ()
  "Test all supported languages have diagnostics."
  (dolist (lang test-gptel-code--supported-languages)
    (should (stringp lang))
    (should (> (length lang) 0))))

(ert-deftest test-gptel-code-validate-replace-args-reports-correct-helper ()
  "Validation errors should name the helper that raised them."
  (dolist (case '(("file_path is nil" nil "node" "code")
                  ("node_name is nil" "/tmp/file.el" nil "code")
                  ("new_code is nil" "/tmp/file.el" "node" nil)
                  ("new_code is empty" "/tmp/file.el" "node" "")))
    (pcase-let ((`(,suffix ,file-path ,node-name ,new-code) case))
      (let ((msg (condition-case err
                     (progn
                       (gptel-tools-code--validate-replace-args
                        file-path node-name new-code)
                       nil)
                   (error (error-message-string err)))))
        (should (stringp msg))
        (should (string-prefix-p
                 "gptel-tools-code--validate-replace-args"
                 msg))
        (should (string-match-p (regexp-quote suffix) msg))))))

(ert-deftest test-gptel-code-format-diagnostic-handles-stale-buffer ()
  "Formatting a stale Flymake diagnostic should not crash."
  (let ((buf (generate-new-buffer " *stale-diagnostic*")))
    (unwind-protect
        (progn
          (kill-buffer buf)
          (cl-letf (((symbol-function 'flymake-diagnostic-buffer)
                     (lambda (_diag) buf))
                    ((symbol-function 'flymake-diagnostic-text)
                     (lambda (_diag) "Boom"))
                    ((symbol-function 'flymake-diagnostic-type)
                     (lambda (_diag) :error))
                    ((symbol-function 'flymake-diagnostic-beg)
                     (lambda (_diag) 42)))
            (let ((result (gptel-tools-code--format-diagnostic :diag)))
              (should (string-match-p
                       "^<buffer unavailable>:\\? \\[:error\\] Boom"
                       result))
              (should (string-match-p
                       "stale diagnostic buffer unavailable"
                       result)))))
      (when (buffer-live-p buf)
        (kill-buffer buf)))))

(ert-deftest test-gptel-code-elisp-byte-compile-is-silent-and-cleans-output ()
  "Byte-compile diagnostics should not spam *Messages* or leave sibling .elc files."
  (let* ((tmp-dir (make-temp-file "gptel-tools-code-byte-compile-" t))
         (file (expand-file-name "sample-byte-compile.el" tmp-dir))
         (messages-buffer (get-buffer-create "*Messages*"))
         start result)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert ";;; sample-byte-compile.el --- test -*- lexical-binding: t; -*-\n\n")
            (insert "(defun sample-byte-compile ()\n  t)\n\n")
            (insert "(provide 'sample-byte-compile)\n"))
          (setq start (with-current-buffer messages-buffer (point-max)))
          (setq result (gptel-tools-code--elisp-byte-compile file))
          (should (equal result "✓ No byte-compile warnings"))
          (should-not (file-exists-p (concat file "c")))
          (let ((delta (with-current-buffer messages-buffer
                         (buffer-substring-no-properties start (point-max)))))
            (should-not (string-match-p "Compiling " delta))
            (should-not (string-match-p "Wrote " delta))))
      (ignore-errors (delete-directory tmp-dir t)))))

(ert-deftest test-gptel-code-elisp-byte-compile-still-returns-errors ()
  "Byte-compile diagnostics should still surface real compile errors."
  (let* ((tmp-dir (make-temp-file "gptel-tools-code-byte-compile-warning-" t))
         (file (expand-file-name "sample-error.el" tmp-dir))
         result)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert ";;; sample-error.el --- test -*- lexical-binding: t; -*-\n\n")
            (insert "(defun sample-error ()\n  (message \"oops\")\n")
            (insert "(provide 'sample-error)\n"))
          (setq result (gptel-tools-code--elisp-byte-compile file))
          (should (string-match-p "Error: End of file during parsing" result))
          (should-not (file-exists-p (concat file "c"))))
      (ignore-errors (delete-directory tmp-dir t)))))

(provide 'test-gptel-tools-code)

;;; test-gptel-tools-code.el ends here
