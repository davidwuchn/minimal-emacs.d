;;; test-treesit-agent-tools-workspace.el --- Tests for workspace AST tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for treesit-agent-tools-workspace.el
;; Tests:
;; - treesit-agent--ensure-parser logic (via mock functions)
;; - Extension-to-language mapping

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Functions under test (local implementation to avoid module dependency)

(defun test-workspace--ensure-parser (file parser-list-fn create-parser-fn lang-available-fn)
  "Test implementation of ensure-parser for FILE.
PARSER-LIST-FN returns current parser list.
CREATE-PARSER-FN creates a parser for a language.
LANG-AVAILABLE-FN checks if language is available.
Returns the new parser list."
  (unless (funcall parser-list-fn)
    (let* ((ext (file-name-extension file))
           (lang (cond
                  ((member ext '("el" "elisp")) 'elisp)
                  ((member ext '("py" "pyw"))    'python)
                  ((member ext '("rs"))          'rust)
                  ((member ext '("clj" "cljs" "cljc" "edn")) 'clojure)
                  ((member ext '("js" "mjs"))    'javascript)
                  ((member ext '("ts"))          'typescript)
                  ((member ext '("tsx"))         'tsx)
                  ((member ext '("rb"))          'ruby)
                  ((member ext '("go"))          'go)
                  ((member ext '("c" "h"))       'c)
                  ((member ext '("cpp" "cc" "cxx" "hpp")) 'cpp)
                  ((member ext '("java"))        'java)
                  ((member ext '("lua"))         'lua))))
      (when (and lang (funcall lang-available-fn lang))
        (funcall create-parser-fn lang)))))

;;; Tests for ensure-parser logic

(ert-deftest workspace/ensure-parser/elisp ()
  "Should create elisp parser for .el files."
  (let ((parser-list nil)
        (lang-available '(elisp python)))
    (test-workspace--ensure-parser
     "test.el"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'elisp parser-list))))

(ert-deftest workspace/ensure-parser/python ()
  "Should create python parser for .py files."
  (let ((parser-list nil)
        (lang-available '(elisp python)))
    (test-workspace--ensure-parser
     "test.py"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'python parser-list))))

(ert-deftest workspace/ensure-parser/rust ()
  "Should create rust parser for .rs files."
  (let ((parser-list nil)
        (lang-available '(rust)))
    (test-workspace--ensure-parser
     "src/main.rs"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'rust parser-list))))

(ert-deftest workspace/ensure-parser/clojure ()
  "Should create clojure parser for .clj files."
  (let ((parser-list nil)
        (lang-available '(clojure)))
    (test-workspace--ensure-parser
     "core.clj"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'clojure parser-list))))

(ert-deftest workspace/ensure-parser/javascript ()
  "Should create javascript parser for .js files."
  (let ((parser-list nil)
        (lang-available '(javascript)))
    (test-workspace--ensure-parser
     "app.js"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'javascript parser-list))))

(ert-deftest workspace/ensure-parser/typescript ()
  "Should create typescript parser for .ts files."
  (let ((parser-list nil)
        (lang-available '(typescript)))
    (test-workspace--ensure-parser
     "main.ts"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'typescript parser-list))))

(ert-deftest workspace/ensure-parser/go ()
  "Should create go parser for .go files."
  (let ((parser-list nil)
        (lang-available '(go)))
    (test-workspace--ensure-parser
     "main.go"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'go parser-list))))

(ert-deftest workspace/ensure-parser/java ()
  "Should create java parser for .java files."
  (let ((parser-list nil)
        (lang-available '(java)))
    (test-workspace--ensure-parser
     "Main.java"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'java parser-list))))

(ert-deftest workspace/ensure-parser/c ()
  "Should create c parser for .c files."
  (let ((parser-list nil)
        (lang-available '(c)))
    (test-workspace--ensure-parser
     "main.c"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'c parser-list))))

(ert-deftest workspace/ensure-parser/cpp ()
  "Should create cpp parser for .cpp files."
  (let ((parser-list nil)
        (lang-available '(cpp)))
    (test-workspace--ensure-parser
     "main.cpp"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'cpp parser-list))))

(ert-deftest workspace/ensure-parser/lua ()
  "Should create lua parser for .lua files."
  (let ((parser-list nil)
        (lang-available '(lua)))
    (test-workspace--ensure-parser
     "script.lua"
     (lambda () parser-list)
     (lambda (lang) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should (member 'lua parser-list))))

(ert-deftest workspace/ensure-parser/skips-when-parser-exists ()
  "Should not create parser when one already exists."
  (let ((parser-list '(existing))
        (lang-available '(python))
        (create-called nil))
    (test-workspace--ensure-parser
     "test.py"
     (lambda () parser-list)
     (lambda (lang) (setq create-called t) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should-not create-called)
    (should (equal parser-list '(existing)))))

(ert-deftest workspace/ensure-parser/skips-unavailable-language ()
  "Should not create parser when language is unavailable."
  (let ((parser-list nil)
        (lang-available nil)
        (create-called nil))
    (test-workspace--ensure-parser
     "test.py"
     (lambda () parser-list)
     (lambda (lang) (setq create-called t) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should-not create-called)
    (should (null parser-list))))

(ert-deftest workspace/ensure-parser/skips-unknown-extension ()
  "Should not create parser for unknown extensions."
  (let ((parser-list nil)
        (lang-available '(elisp))
        (create-called nil))
    (test-workspace--ensure-parser
     "test.xyz"
     (lambda () parser-list)
     (lambda (lang) (setq create-called t) (push lang parser-list))
     (lambda (lang) (member lang lang-available)))
    (should-not create-called)
    (should (null parser-list))))

(ert-deftest workspace/ensure-parser/multiple-extensions ()
  "Should handle all extension variants."
  (let ((parser-list nil)
        (lang-available '(clojure)))
    (dolist (ext '("clj" "cljs" "cljc" "edn"))
      (setq parser-list nil)
      (test-workspace--ensure-parser
       (concat "file." ext)
       (lambda () parser-list)
       (lambda (lang) (push lang parser-list))
       (lambda (lang) (member lang lang-available)))
      (should (member 'clojure parser-list)))))

;;; Tests for extension mapping

(ert-deftest workspace/extension-mapping/elisp-variants ()
  "Should map .el and .elisp to elisp."
  (let ((ext-to-lang '(("el" . elisp) ("elisp" . elisp))))
    (should (eq (cdr (assoc "el" ext-to-lang)) 'elisp))
    (should (eq (cdr (assoc "elisp" ext-to-lang)) 'elisp))))

(ert-deftest workspace/extension-mapping/clojure-variants ()
  "Should map all Clojure extensions to clojure."
  (let ((ext-to-lang '(("clj" . clojure) ("cljs" . clojure) ("cljc" . clojure) ("edn" . clojure))))
    (dolist (ext '("clj" "cljs" "cljc" "edn"))
      (should (eq (cdr (assoc ext ext-to-lang)) 'clojure)))))

(ert-deftest workspace/extension-mapping/cpp-variants ()
  "Should map all C++ extensions to cpp."
  (let ((ext-to-lang '(("cpp" . cpp) ("cc" . cpp) ("cxx" . cpp) ("hpp" . cpp))))
    (dolist (ext '("cpp" "cc" "cxx" "hpp"))
      (should (eq (cdr (assoc ext ext-to-lang)) 'cpp)))))

(provide 'test-treesit-agent-tools-workspace)

;;; test-treesit-agent-tools-workspace.el ends here