;;; test-programmatic.el --- ERT tests for Programmatic sandbox -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "lisp/modules/gptel-sandbox.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Minimal stubs

(cl-defstruct (gptel-test-tool (:constructor gptel-test-tool-create))
  name function args async confirm)

(defalias 'gptel-tool-name #'gptel-test-tool-name)
(defalias 'gptel-tool-function #'gptel-test-tool-function)
(defalias 'gptel-tool-args #'gptel-test-tool-args)
(defalias 'gptel-tool-async #'gptel-test-tool-async)
(defalias 'gptel-tool-confirm #'gptel-test-tool-confirm)

(defvar gptel-confirm-tool-calls nil)

(defun gptel--to-string (value)
  "Test stub for coercing VALUE to string."
  (cond
   ((stringp value) value)
   ((null value) "")
   (t (format "%s" value))))

(defvar test-programmatic--tools nil)

(defun gptel-get-tool (name)
  "Return a test tool by NAME."
  (cdr (assoc name test-programmatic--tools)))

(defun test-programmatic--sync-tool (name fn args &optional confirm)
  "Create a sync test tool."
  (gptel-test-tool-create :name name :function fn :args args :async nil :confirm confirm))

(defun test-programmatic--async-tool (name fn args &optional confirm)
  "Create an async test tool."
  (gptel-test-tool-create :name name :function fn :args args :async t :confirm confirm))

(defun test-programmatic--run (code)
  "Run CODE synchronously via the async sandbox API and return its result."
  (let ((result :pending))
    (gptel-sandbox-execute-async (lambda (value) (setq result value)) code)
    (while (eq result :pending)
      (sleep-for 0.01))
    result))

(defmacro test-programmatic--with-tools (bindings &rest body)
  "Bind BINDINGS as the active test tool registry around BODY."
  (declare (indent 1))
  `(let ((test-programmatic--tools ,bindings)
         (my/gptel-programmatic-result-limit 80)
         (my/gptel-programmatic-max-tool-calls 3)
         (my/gptel-programmatic-timeout 1)
         (my/gptel-programmatic-allowed-tools '("Read" "Grep"))
         (my/gptel-programmatic-confirming-tools '("Edit" "ApplyPatch"))
         (gptel-confirm-tool-calls 'auto)
         (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                           (funcall callback t))))
     ,@body))

;;; Tests

(ert-deftest programmatic/allows-serial-sync-tool-orchestration ()
  (test-programmatic--with-tools
      `(("Read" . ,(test-programmatic--sync-tool
                     "Read"
                     (lambda (file-path &optional start-line end-line)
                       (format "%s:%s:%s" file-path start-line end-line))
                     '((:name "file_path")
                       (:name "start_line" :optional t)
                       (:name "end_line" :optional t))))
        ("Grep" . ,(test-programmatic--sync-tool
                     "Grep"
                     (lambda (regex path &optional _glob _context-lines)
                       (format "%s in %s" regex path))
                     '((:name "regex")
                       (:name "path")
                       (:name "glob" :optional t)
                       (:name "context_lines" :optional t)))))
    (should
     (equal
      (test-programmatic--run
       "(setq hits (tool-call \"Grep\" :regex \"TODO\" :path \".\"))
(setq snippet (tool-call \"Read\" :file_path \"foo.el\" :start_line 1 :end_line 3))
(result (concat hits \" | \" snippet))")
      "TODO in . | foo.el:1:3"))))

(ert-deftest programmatic/allows-async-tool-orchestration ()
  (test-programmatic--with-tools
      `(("Grep" . ,(test-programmatic--async-tool
                     "Grep"
                     (lambda (callback regex path &optional _glob _context-lines)
                       (run-at-time 0 nil (lambda ()
                                            (funcall callback (format "%s@%s" regex path)))))
                     '((:name "regex")
                       (:name "path")
                       (:name "glob" :optional t)
                       (:name "context_lines" :optional t)))))
    (should
     (equal
      (test-programmatic--run
       "(setq hits (tool-call \"Grep\" :regex \"TODO\" :path \"src\"))
(result hits)")
      "TODO@src"))))

(ert-deftest programmatic/rejects-unsupported-expression-form ()
  (test-programmatic--with-tools nil
    (should (string-match-p
             "Unsupported statement\\|Unsupported expression form"
             (test-programmatic--run "(message \"hi\")")))))

(ert-deftest programmatic/rejects-disallowed-tool ()
  (test-programmatic--with-tools
      `(("Bash" . ,(test-programmatic--sync-tool
                     "Bash"
                     (lambda (command) command)
                     '((:name "command")))))
    (should (string-match-p
             "not allowed inside Programmatic"
             (test-programmatic--run
              "(setq x (tool-call \"Bash\" :command \"pwd\"))
(result x)")))))

(ert-deftest programmatic/rejects-confirming-tool ()
  (test-programmatic--with-tools
      `(("Read" . ,(test-programmatic--sync-tool
                     "Read"
                     (lambda (file-path &optional _start _end) file-path)
                     '((:name "file_path")
                       (:name "start_line" :optional t)
                       (:name "end_line" :optional t))
                      t)))
    (let ((gptel-confirm-tool-calls t)
          (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                            (funcall callback nil))))
      (should (string-match-p
               "requires confirmation"
               (condition-case err
                   (progn
                     (gptel-sandbox--check-tool
                      (gptel-get-tool "Read")
                      '("foo.el" nil nil))
                     "")
                 (error (error-message-string err))))))))

(ert-deftest programmatic/allows-supported-confirming-tool-with-approval ()
  (let (seen)
    (test-programmatic--with-tools
        `(("Edit" . ,(test-programmatic--async-tool
                       "Edit"
                       (lambda (callback path &optional old new diffp)
                         (setq seen (list path old new diffp))
                         (funcall callback (format "edited:%s" path)))
                       '((:name "path")
                         (:name "old_str" :optional t)
                         (:name "new_str_or_diff")
                         (:name "diffp" :optional t))
                       t)))
      (let ((my/gptel-programmatic-allowed-tools '("Edit"))
            (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                              (funcall callback t))))
        (should
         (equal
          (test-programmatic--run
           "(setq result (tool-call \"Edit\" :path \"foo.el\" :new_str_or_diff \"patch\" :diffp t))
(result result)")
          "edited:foo.el"))
        (should (equal seen '("foo.el" nil "patch" t)))))))

(ert-deftest programmatic/rejects-supported-confirming-tool-when-denied ()
  (test-programmatic--with-tools
      `(("Edit" . ,(test-programmatic--async-tool
                     "Edit"
                     (lambda (callback &rest _args)
                       (funcall callback "should-not-run"))
                     '((:name "path")
                       (:name "old_str" :optional t)
                       (:name "new_str_or_diff")
                       (:name "diffp" :optional t))
                     t)))
    (let ((my/gptel-programmatic-allowed-tools '("Edit"))
          (gptel-confirm-tool-calls t)
          (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                            (funcall callback nil))))
      (should (string-match-p
               "rejected by user: Edit"
               (test-programmatic--run
                "(setq result (tool-call \"Edit\" :path \"foo.el\" :new_str_or_diff \"patch\" :diffp t))
(result result)"))))))

(ert-deftest programmatic/enforces-max-tool-calls ()
  (test-programmatic--with-tools
      `(("Read" . ,(test-programmatic--sync-tool
                     "Read"
                     (lambda (file-path &optional _start _end) file-path)
                     '((:name "file_path")
                       (:name "start_line" :optional t)
                       (:name "end_line" :optional t)))))
    (should (string-match-p
             "max nested tool calls"
             (test-programmatic--run
              "(tool-call \"Read\" :file_path \"a.el\")
(tool-call \"Read\" :file_path \"b.el\")
(tool-call \"Read\" :file_path \"c.el\")
(tool-call \"Read\" :file_path \"d.el\")
(result \"done\")")))))

(ert-deftest programmatic/truncates-large-results ()
  (test-programmatic--with-tools nil
    (let ((result (test-programmatic--run
                   "(result (concat \"abcdefghijklmnopqrstuvwxyz\"
                                    \"abcdefghijklmnopqrstuvwxyz\"
                                    \"abcdefghijklmnopqrstuvwxyz\"
                                    \"abcdefghijklmnopqrstuvwxyz\"))")))
      (should (string-match-p "Programmatic result truncated" result)))))

(ert-deftest programmatic/renders-structured-results ()
  (test-programmatic--with-tools nil
    (let ((result (test-programmatic--run
                   "(result (list :kind \"summary\" :items (list \"a\" \"b\")))")))
      (should (string-match-p ":kind" result))
      (should (string-match-p "summary" result))
      (should (string-match-p "a" result))
      (should (string-match-p "b" result)))))

(ert-deftest programmatic/supports-let-when-and-unless ()
  (test-programmatic--with-tools
      `(("Read" . ,(test-programmatic--sync-tool
                     "Read"
                     (lambda (file-path &optional _start _end) (format "read:%s" file-path))
                     '((:name "file_path")
                       (:name "start_line" :optional t)
                       (:name "end_line" :optional t)))))
    (should
     (equal
      (test-programmatic--run
       "(setq base \"foo.el\")
(setq name
 (let* ((flag t))
   (if flag base \"bar.el\")))
(setq snippet (tool-call \"Read\" :file_path name))
(result
 (let ((prefix nil))
   (when snippet
     (setq prefix \"ok:\"))
   (unless (string= prefix \"bad:\")
     (concat prefix snippet))))")
      "ok:read:foo.el"))))

(ert-deftest programmatic/supports-structured-data-helpers ()
  (test-programmatic--with-tools nil
    (should
     (equal
      (test-programmatic--run
       "(result
 (let* ((item (list :name \"alpha\" :meta (list :kind \"demo\")))
        (pair (cons 'lang \"elisp\"))
        (kind (plist-get (plist-get item :meta) :kind))
        (lang (cdr (assoc 'lang (list pair))))
        (fallback (alist-get 'missing (list pair) \"none\")))
   (format \"%s:%s:%s:%s\" (plist-get item :name) kind lang fallback)))")
      "alpha:demo:elisp:none"))))

(provide 'test-programmatic)

;;; test-programmatic.el ends here
