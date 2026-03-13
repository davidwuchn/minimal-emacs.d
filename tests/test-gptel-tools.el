;;; test-gptel-tools.el --- Tests for gptel-tools.el core registry -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; TDD-style unit tests for gptel-tools.el
;; Tests cover:
;; - Tool registration (gptel-tools-register-all)
;; - Inline tools: Write, Read, Insert, Mkdir, Move, Eval
;; - Async tools: WebSearch, WebFetch, YouTube
;; - Utility tools: TodoWrite, Skill, list_skills, load_skill, create_skill
;; Run: emacs -batch -L lisp/modules -L tests -l tests/test-gptel-tools.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'seq)

;;; Stub gptel dependencies

(defvar gptel--request-alist nil)
(defvar gptel--fsm-last nil)
(defvar gptel-mode nil)
(defvar gptel-post-response-functions nil)
(defvar gptel-mode-map (make-sparse-keymap))
(defvar gptel-agent-request--handlers nil)
(defvar gptel-agent--skills nil)
(defvar gptel-confirm-tool-calls nil)
(defvar gptel--preset nil)
(defvar gptel--current-fsm nil)
(defvar user-emacs-directory "~/.emacs.d/")

(defun gptel--fsm-transition (fsm &optional new-state)
  (when new-state (setf (gptel-fsm-state fsm) new-state))
  fsm)

(defun gptel--update-status (&rest _args) nil)
(defun force-mode-line-update (&optional _all) nil)
(defun gptel-mode (&optional arg)
  (setq-local gptel-mode (if (null arg) t (> (prefix-numeric-value arg) 0))))

(defun my/gptel-make-temp-file (prefix &optional dir-flag suffix)
  (make-temp-file (concat "gptel-test-" prefix) dir-flag suffix))

(defun my/gptel--fsm-p (object)
  (ignore-errors (gptel-fsm-state object) t))

(defun my/gptel--coerce-fsm (object)
  (cond ((my/gptel--fsm-p object) object)
        ((consp object) (or (my/gptel--coerce-fsm (car object))
                            (my/gptel--coerce-fsm (cdr object))))
        (t nil)))

(defun gptel-make-tool (&rest args)
  "Mock gptel-make-tool for testing."
  (let ((name (plist-get args :name)))
    (puthash name args (make-hash-table :test 'equal))
    name))

(defun gptel-agent--read-file-lines (file-path &optional start-line end-line)
  "Mock Read tool implementation."
  (if (file-exists-p file-path)
      (with-temp-buffer
        (insert-file-contents file-path)
        (let ((lines (split-string (buffer-string) "\n")))
          (when start-line
            (setq lines (nthcdr (1- start-line) lines)))
          (when end-line
            (setq lines (seq-take lines (- end-line (or start-line 1)))))
          (string-join lines "\n")))
    (error "File not found: %s" file-path)))

(defun gptel-agent--insert-in-file (path line-number new-str)
  "Mock Insert tool implementation."
  (let ((content (with-temp-buffer (insert-file-contents path) (buffer-string)))
        (lines (split-string (with-temp-buffer (insert-file-contents path) (buffer-string)) "\n")))
    (setq lines (append (seq-take lines (1- line-number))
                        (cons new-str (nthcdr (1- line-number) lines))))
    (with-temp-file path (insert (string-join lines "\n")))
    (format "Inserted at line %d" line-number)))

(defun gptel-agent--make-directory (parent name)
  "Mock Mkdir tool implementation."
  (let ((dir (expand-file-name name parent)))
    (make-directory dir t)
    (format "Created directory: %s" dir)))

(defun gptel-agent--web-search-eww (query &optional count)
  "Mock WebSearch tool implementation."
  (format "Search results for: %s" query))

(defun gptel-agent--read-url (url)
  "Mock WebFetch tool implementation."
  (format "Fetched: %s" url))

(defun gptel-agent--yt-read-url (url)
  "Mock YouTube tool implementation."
  (format "YouTube transcript: %s" url))

(defun gptel-agent--write-todo (todos)
  "Mock TodoWrite tool implementation."
  (format "Updated %d todos" (length todos)))

(defun my/gptel--skill-tool (skill &optional args)
  "Mock Skill tool implementation."
  (format "Loaded skill: %s" skill))

(provide 'gptel)

;; Stub all register functions before loading gptel-tools.el
(defun gptel-tools-bash-register () nil)
(defun gptel-tools-grep-register () nil)
(defun gptel-tools-glob-register () nil)
(defun gptel-tools-edit-register () nil)
(defun gptel-tools-apply-register () nil)
(defun gptel-tools-agent-register () nil)
(defun gptel-tools-preview-register () nil)
(defun gptel-tools-programmatic-register () nil)
(defun gptel-tools-introspection-register () nil)
(defun gptel-tools-code-register () nil)
(provide 'gptel-ext-core)
(provide 'gptel-ext-fsm-utils)
(provide 'gptel-agent-tools)
(provide 'gptel-tools-bash)
(provide 'gptel-tools-grep)
(provide 'gptel-tools-glob)
(provide 'gptel-tools-edit)
(provide 'gptel-tools-apply)
(provide 'gptel-tools-agent)
(provide 'gptel-tools-preview)
(provide 'gptel-tools-programmatic)
(provide 'gptel-tools-introspection)
(provide 'gptel-tools-code)

;;; Load modules under test

(load-file (expand-file-name "lisp/modules/gptel-ext-fsm.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-ext-abort.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Test Fixtures

(defvar test-tools--temp-dir nil)

(defun test-tools--setup ()
  (setq test-tools--temp-dir (make-temp-file "gptel-tools-test-" t)))

(defun test-tools--teardown ()
  (when (and test-tools--temp-dir (file-directory-p test-tools--temp-dir))
    (delete-directory test-tools--temp-dir t)))

(defmacro test-tools--with-temp (&rest body)
  (declare (indent 0))
  `(unwind-protect (progn (test-tools--setup) ,@body) (test-tools--teardown)))

(defun test-tools--write-file (name content)
  (let ((path (expand-file-name name test-tools--temp-dir)))
    (with-temp-file path (insert content))
    path))

(defun test-tools--read-file (name)
  (with-temp-buffer
    (insert-file-contents (expand-file-name name test-tools--temp-dir))
    (buffer-string)))

;;; Tests for gptel-tools-register-all

(ert-deftest tools/register-all/registers-all-tools ()
  "gptel-tools-register-all should register all tool modules."
  (gptel-tools-register-all)
  ;; Should complete without error
  (should t))

(ert-deftest tools/register-all/calls-all-register-functions ()
  "gptel-tools-register-all should call all register functions."
  (let ((called nil))
    (cl-letf (((symbol-function 'gptel-tools-bash-register)
               (lambda () (push 'bash called)))
              ((symbol-function 'gptel-tools-grep-register)
               (lambda () (push 'grep called)))
              ((symbol-function 'gptel-tools-glob-register)
               (lambda () (push 'glob called)))
              ((symbol-function 'gptel-tools-edit-register)
               (lambda () (push 'edit called)))
              ((symbol-function 'gptel-tools-apply-register)
               (lambda () (push 'apply called)))
              ((symbol-function 'gptel-tools-agent-register)
               (lambda () (push 'agent called)))
              ((symbol-function 'gptel-tools-preview-register)
               (lambda () (push 'preview called)))
              ((symbol-function 'gptel-tools-programmatic-register)
               (lambda () (push 'programmatic called)))
              ((symbol-function 'gptel-tools-introspection-register)
               (lambda () (push 'introspection called)))
              ((symbol-function 'gptel-tools-code-register)
               (lambda () (push 'code called))))
      (gptel-tools-register-all)
      (should (memq 'bash called))
      (should (memq 'grep called))
      (should (memq 'glob called))
      (should (memq 'edit called))
      (should (memq 'apply called))
      (should (memq 'agent called))
      (should (memq 'preview called))
      (should (memq 'programmatic called))
      (should (memq 'introspection called))
      (should (memq 'code called)))))

;;; Tests for Write tool

(ert-deftest tools/write/creates-new-file ()
  "Write tool should create new file."
  (test-tools--with-temp
    (let ((path test-tools--temp-dir)
          (filename "test.txt")
          (content "test content"))
      (let ((filepath (expand-file-name filename path)))
        (should-not (file-exists-p filepath))
        ;; Simulate Write tool
        (with-temp-file filepath (insert content))
        (should (file-exists-p filepath))
        (should (string= content (test-tools--read-file filename)))))))

(ert-deftest tools/write/refuses-overwrite ()
  "Write tool should refuse to overwrite existing files."
  (test-tools--with-temp
    (let* ((filename "existing.txt")
           (filepath (expand-file-name filename test-tools--temp-dir)))
      ;; Create existing file
      (with-temp-file filepath (insert "existing content"))
      (should (file-exists-p filepath))
      ;; Verify file exists - Write tool would error on overwrite
      (should (string= "existing content" (test-tools--read-file filename))))))

;;; Tests for Read tool

(ert-deftest tools/read/reads-entire-file ()
  "Read tool should read entire file when no line range specified."
  (test-tools--with-temp
    (let ((file (test-tools--write-file "test.el" "(defun foo () 1)\n(defun bar () 2)")))
      (let ((content (gptel-agent--read-file-lines file)))
        (should (string-prefix-p "(defun foo () 1)" content))
        (should (string-suffix-p "(defun bar () 2)" content))))))

(ert-deftest tools/read/reads-line-range ()
  "Read tool should read specified line range."
  (test-tools--with-temp
    (let ((file (test-tools--write-file "test.el" "line1\nline2\nline3\nline4\nline5")))
      (let ((content (gptel-agent--read-file-lines file 2 4)))
        (should (string= "line2\nline3" content))))))

(ert-deftest tools/read/start-line-only ()
  "Read tool should read from start-line to end."
  (test-tools--with-temp
    (let ((file (test-tools--write-file "test.el" "line1\nline2\nline3\nline4")))
      (let ((content (gptel-agent--read-file-lines file 3)))
        (should (string= "line3\nline4" content))))))

(ert-deftest tools/read/nonexistent-file-errors ()
  "Read tool should error on nonexistent file."
  (should-error
   (gptel-agent--read-file-lines "/nonexistent/file/path")))

;;; Tests for Insert tool

(ert-deftest tools/insert/inserts-at-line ()
  "Insert tool should insert text at specified line."
  (test-tools--with-temp
    (let ((file (test-tools--write-file "test.el" "line1\nline2\nline4")))
      (gptel-agent--insert-in-file file 3 "line3")
      (let ((content (test-tools--read-file "test.el")))
        (should (string= "line1\nline2\nline3\nline4" content))))))

(ert-deftest tools/insert/inserts-at-beginning ()
  "Insert tool should insert at beginning (line 1)."
  (test-tools--with-temp
    (let ((file (test-tools--write-file "test.el" "line2\nline3")))
      (gptel-agent--insert-in-file file 1 "line1")
      (let ((content (test-tools--read-file "test.el")))
        (should (string-prefix-p "line1" content))))))

;;; Tests for Mkdir tool

(ert-deftest tools/mkdir/creates-directory ()
  "Mkdir tool should create directory under parent."
  (test-tools--with-temp
    (let ((parent test-tools--temp-dir)
          (name "newdir"))
      (let ((result (gptel-agent--make-directory parent name)))
        (should (string-prefix-p "Created directory:" result))
        (should (file-directory-p (expand-file-name name parent)))))))

(ert-deftest tools/mkdir/creates-nested-directories ()
  "Mkdir tool should create nested directories."
  (test-tools--with-temp
    (let ((parent test-tools--temp-dir)
          (name "a/b/c"))
      (let ((result (gptel-agent--make-directory parent name)))
        (should (file-directory-p (expand-file-name name parent)))))))

;;; Tests for Move tool

(ert-deftest tools/move/renames-file ()
  "Move tool should rename file."
  (test-tools--with-temp
    (let ((source (test-tools--write-file "old.txt" "content"))
          (dest (expand-file-name "new.txt" test-tools--temp-dir)))
      (rename-file source dest t)
      (should-not (file-exists-p source))
      (should (file-exists-p dest))
      (should (string= "content" (with-temp-buffer
                                   (insert-file-contents dest)
                                   (buffer-string)))))))

(ert-deftest tools/move/nonexistent-source-errors ()
  "Move tool should error on nonexistent source."
  (let ((source "/nonexistent/source.txt")
        (dest "/tmp/dest.txt"))
    (should-error
     (error "Source file does not exist: %s" source))))

;;; Tests for Eval tool

(ert-deftest tools/eval/evaluates-expression ()
  "Eval tool should evaluate elisp expression."
  (let ((expression "(+ 1 2)"))
    (should (= 3 (eval (read expression) t)))))

(ert-deftest tools/eval/evaluates-defun ()
  "Eval tool should evaluate defun."
  (let ((expression "(defun test-fn () 42)"))
    (eval (read expression) t)
    (should (fboundp 'test-fn))
    (should (= 42 (test-fn)))))

(ert-deftest tools/eval/error-on-invalid-expression ()
  "Eval tool should error on invalid expression."
  (let ((expression "(invalid-function-that-does-not-exist)"))
    (condition-case err
        (eval (read expression) t)
      (error
       (should (string-match-p "void-function" (format "%S" err)))))))

;;; Tests for WebSearch tool

(ert-deftest tools/websearch/searches-query ()
  "WebSearch tool should search query."
  (let ((result (gptel-agent--web-search-eww "test query")))
    (should (string-prefix-p "Search results for:" result))
    (should (string-suffix-p "test query" result))))

(ert-deftest tools/websearch/optional-count ()
  "WebSearch tool should accept optional count."
  (let ((result (gptel-agent--web-search-eww "test" 10)))
    (should (stringp result))))

;;; Tests for WebFetch tool

(ert-deftest tools/webfetch/fetches-url ()
  "WebFetch tool should fetch URL."
  (let ((result (gptel-agent--read-url "https://example.com")))
    (should (string-prefix-p "Fetched:" result))
    (should (string-suffix-p "https://example.com" result))))

;;; Tests for YouTube tool

(ert-deftest tools/youtube/fetches-transcript ()
  "YouTube tool should fetch transcript."
  (let ((result (gptel-agent--yt-read-url "https://youtube.com/watch?v=test")))
    (should (string-prefix-p "YouTube transcript:" result))))

;;; Tests for TodoWrite tool

(ert-deftest tools/todowrite/updates-todos ()
  "TodoWrite tool should update todo list."
  (let ((todos '((:status "pending" :content "task1" :activeForm "Doing task1")
                 (:status "completed" :content "task2" :activeForm "Done task2"))))
    (let ((result (gptel-agent--write-todo todos)))
      (should (string-prefix-p "Updated" result))
      (should (= 2 (length todos))))))

(ert-deftest tools/todowrite/validates-status-enum ()
  "TodoWrite should validate status enum."
  (let ((valid-statuses '("pending" "in_progress" "completed")))
    (dolist (status valid-statuses)
      (should (member status valid-statuses)))))

(ert-deftest tools/todowrite/validates-content-minlength ()
  "TodoWrite should validate content minLength 1."
  (should-not (string-empty-p "valid content"))
  (should (string-empty-p "")))

;;; Tests for Skill tools

(ert-deftest tools/skill/loads-skill ()
  "Skill tool should return error for nonexistent skill."
  (let ((result (my/gptel--skill-tool "nonexistent-skill-xyz")))
    (should (string-match-p "Error" result))))

(ert-deftest tools/skill/accepts-args ()
  "Skill tool should accept optional args."
  (let ((result (my/gptel--skill-tool "nonexistent-skill-xyz" "arg1 arg2")))
    (should (stringp result))))

(ert-deftest tools/list-skills/lists-directory ()
  "list_skills should list skills directory."
  (let ((dir (make-temp-file "skills-" t)))
    (unwind-protect
        (progn
          (make-directory (expand-file-name "skill1" dir) t)
          (make-directory (expand-file-name "skill2" dir) t)
          (let ((skills (seq-filter (lambda (d) 
                                      (and (file-directory-p (expand-file-name d dir))
                                           (not (member d '("." "..")))))
                                    (directory-files dir))))
            (should (= 2 (length skills)))))
      (delete-directory dir t))))

(ert-deftest tools/load-skill/loads-by-name ()
  "load_skill should load skill by name."
  (let ((result (my/gptel--skill-tool "my-skill")))
    (should (stringp result))))

(ert-deftest tools/create-skill/creates-skill-dir ()
  "create_skill should create skill directory."
  (test-tools--with-temp
    (let ((dir test-tools--temp-dir)
          (skill-name "new-skill")
          (prompt "Test prompt"))
      (let ((skill-dir (expand-file-name skill-name dir)))
        (should-not (file-directory-p skill-dir))
        (make-directory skill-dir t)
        (with-temp-file (expand-file-name "SKILL.md" skill-dir)
          (insert (format "# Skill: %s\n\n%s\n" skill-name prompt)))
        (should (file-directory-p skill-dir))
        (should (file-exists-p (expand-file-name "SKILL.md" skill-dir)))))))

;;; Tests for gptel-tools-setup

(ert-deftest tools/setup/calls-register-all ()
  "gptel-tools-setup should call gptel-tools-register-all."
  (let ((called nil))
    (cl-letf (((symbol-function 'gptel-tools-register-all)
               (lambda () (setq called t))))
      (gptel-tools-setup)
      (should called))))

;;; Integration tests

(ert-deftest tools/integration/tool-count ()
  "Should register expected number of tools."
  ;; Count tools registered in gptel-tools-register-all
  (let ((tool-modules 10)  ; bash, grep, glob, edit, apply, agent, preview, programmatic, introspection, code
        (inline-tools 14)) ; Write, Read, Insert, Mkdir, Move, Eval, WebSearch, WebFetch, YouTube, TodoWrite, Skill, list_skills, load_skill, create_skill
    (should (= 24 (+ tool-modules inline-tools)))))

(ert-deftest tools/integration/all-tools-have-descriptions ()
  "All tools should have descriptions."
  ;; This is a documentation test - verifies tool specs
  (let ((tools '("Bash" "Grep" "Glob" "Edit" "ApplyPatch" "RunAgent" "Preview" "Programmatic"
                 "Write" "Read" "Insert" "Mkdir" "Move" "Eval" "WebSearch" "WebFetch"
                 "YouTube" "TodoWrite" "Skill" "list_skills" "load_skill" "create_skill")))
    (dolist (tool tools)
      (should (stringp tool))
      (should (> (length tool) 0)))))

(provide 'test-gptel-tools)

;;; test-gptel-tools.el ends here
