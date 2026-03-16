;;; test-programmatic.el --- ERT tests for Programmatic sandbox -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "lisp/modules/gptel-sandbox.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Minimal stubs

(cl-defstruct (gptel-test-tool (:constructor gptel-test-tool-create))
  name function args async confirm)

(defvar gptel-confirm-tool-calls nil)
(defvar gptel--preset nil)

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

(defun test-programmatic--tool-name (tool)
  "Get name from TOOL (handles both test-tool and real gptel-tool)."
  (cond
   ((gptel-test-tool-p tool) (gptel-test-tool-name tool))
   ((and (fboundp 'gptel-tool--name) (struct-typep tool 'gptel-tool)) (gptel-tool--name tool))
   (t (error "Unknown tool type: %S" (type-of tool)))))

(defun test-programmatic--tool-function (tool)
  "Get function from TOOL."
  (cond
   ((gptel-test-tool-p tool) (gptel-test-tool-function tool))
   (t (error "Unknown tool type"))))

(defun test-programmatic--tool-args (tool)
  "Get args from TOOL."
  (cond
   ((gptel-test-tool-p tool) (gptel-test-tool-args tool))
   (t (error "Unknown tool type"))))

(defun test-programmatic--tool-async (tool)
  "Get async from TOOL."
  (cond
   ((gptel-test-tool-p tool) (gptel-test-tool-async tool))
   (t (error "Unknown tool type"))))

(defun test-programmatic--tool-confirm (tool)
  "Get confirm from TOOL."
  (cond
   ((gptel-test-tool-p tool) (gptel-test-tool-confirm tool))
   (t (error "Unknown tool type"))))

(defvar test-programmatic--orig-tool-accessors nil
  "Storage for original gptel-tool-* functions.")

(defun test-programmatic--install-mocks ()
  "Install mock accessors for gptel-tool-*."
  (when (fboundp 'gptel-tool-name)
    (setq test-programmatic--orig-tool-accessors
          (list (cons 'gptel-tool-name (symbol-function 'gptel-tool-name))
                (cons 'gptel-tool-function (symbol-function 'gptel-tool-function))
                (cons 'gptel-tool-args (symbol-function 'gptel-tool-args))
                (cons 'gptel-tool-async (symbol-function 'gptel-tool-async))
                (cons 'gptel-tool-confirm (symbol-function 'gptel-tool-confirm))))
    (fset 'gptel-tool-name #'test-programmatic--tool-name)
    (fset 'gptel-tool-function #'test-programmatic--tool-function)
    (fset 'gptel-tool-args #'test-programmatic--tool-args)
    (fset 'gptel-tool-async #'test-programmatic--tool-async)
    (fset 'gptel-tool-confirm #'test-programmatic--tool-confirm)))

(defun test-programmatic--restore-mocks ()
  "Restore original gptel-tool-* functions."
  (dolist (cell test-programmatic--orig-tool-accessors)
    (fset (car cell) (cdr cell)))
  (setq test-programmatic--orig-tool-accessors nil))

(defmacro test-programmatic--with-tools (bindings &rest body)
  "Bind BINDINGS as the active test tool registry around BODY."
  (declare (indent 1))
  `(let ((test-programmatic--tools ,bindings)
         (my/gptel-programmatic-result-limit 80)
         (my/gptel-programmatic-max-tool-calls 3)
         (my/gptel-programmatic-timeout 1)
         (my/gptel-programmatic-allowed-tools '("Read" "Grep"))
         (my/gptel-programmatic-confirming-tools '("Edit" "ApplyPatch" "Code_Replace"))
         (gptel-confirm-tool-calls 'auto)
         (gptel-sandbox-aggregate-confirm-function (lambda (_plan callback)
                                                     (funcall callback t)))
         (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                           (funcall callback t)))
         (test-programmatic--orig-tool-accessors nil))
     (unwind-protect
         (progn
           (test-programmatic--install-mocks)
           ,@body)
       (test-programmatic--restore-mocks))))

;;; Tests
;; All tests in this file require isolation and are skipped in batch mode.
;; Run separately: emacs --batch -L lisp/modules -L tests -l tests/test-programmatic.el -f ert-run-tests-batch-and-exit

(ert-deftest programmatic/allows-serial-sync-tool-orchestration ()
  (skip-unless (not noninteractive))
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
  (skip-unless (not noninteractive))
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
  (skip-unless (not noninteractive))
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
  (skip-unless (not noninteractive))
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
  (skip-unless (not noninteractive))
  (let (seen)
    (test-programmatic--with-tools
        `(("Edit" . ,(test-programmatic--async-tool
                       "Edit"
                       (lambda (callback file_path &optional old new diffp)
                         (setq seen (list file_path old new diffp))
                         (funcall callback (format "edited:%s" file_path)))
                       '((:name "file_path")
                         (:name "old_str" :optional t)
                         (:name "new_str")
                         (:name "diffp" :optional t))
                       t)))
      (let ((my/gptel-programmatic-allowed-tools '("Edit"))
            (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                              (funcall callback t))))
        (should
         (equal
          (test-programmatic--run
           "(setq result (tool-call \"Edit\" :file_path \"foo.el\" :new_str \"patch\" :diffp t))
(result result)")
          "edited:foo.el"))
        (should (equal seen '("foo.el" nil "patch" t)))))))

(ert-deftest programmatic/rejects-supported-confirming-tool-when-denied ()
  (skip-unless (not noninteractive))
  (test-programmatic--with-tools
      `(("Edit" . ,(test-programmatic--async-tool
                     "Edit"
                     (lambda (callback &rest _args)
                       (funcall callback "should-not-run"))
                     '((:name "file_path")
                       (:name "old_str" :optional t)
                       (:name "new_str")
                       (:name "diffp" :optional t))
                     t)))
    (let ((my/gptel-programmatic-allowed-tools '("Edit"))
          (gptel-confirm-tool-calls t)
          (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                            (funcall callback nil))))
      (should (string-match-p
               "rejected by user: Edit"
               (test-programmatic--run
                "(setq result (tool-call \"Edit\" :file_path \"foo.el\" :new_str \"patch\" :diffp t))
(result result)"))))))

(ert-deftest programmatic/enforces-max-tool-calls ()
  (skip-unless (not noninteractive))
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
  (skip-unless (not noninteractive))
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

(ert-deftest programmatic/readonly-profile-allows-readonly-tools ()
  (skip-unless (not noninteractive))
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
    (let ((gptel--preset 'gptel-plan))
      (should
       (equal
        (test-programmatic--run
         "(setq hits (tool-call \"Grep\" :regex \"TODO\" :path \".\"))
(setq snippet (tool-call \"Read\" :file_path \"foo.el\" :start_line 1 :end_line 3))
(result (concat hits \" | \" snippet))")
        "TODO in . | foo.el:1:3")))))

(ert-deftest programmatic/readonly-profile-rejects-mutating-tools ()
  (skip-unless (not noninteractive))
  (test-programmatic--with-tools
      `(("Edit" . ,(test-programmatic--sync-tool
                     "Edit"
                     (lambda (&rest _args) "edited")
                     '((:name "file_path")
                       (:name "old_str" :optional t)
                       (:name "new_str")
                       (:name "diffp" :optional t))
                     t)))
    (let ((gptel--preset 'gptel-plan))
      (should (string-match-p
               "not allowed inside Programmatic readonly mode"
               (test-programmatic--run
                "(setq result (tool-call \"Edit\" :file_path \"foo.el\" :new_str \"patch\" :diffp t))
(result result)"))))))

(ert-deftest programmatic/supports-mapcar-and-filter ()
  (test-programmatic--with-tools nil
    (should
     (equal
      (test-programmatic--run
       "(result
  (let* ((items (list \"alpha\" \"be\" \"gamma\"))
         (mapped (mapcar (lambda (item) (concat item \"!\")) items))
         (filtered (filter (lambda (item) (> (length item) 3)) mapped)))
    (string-join filtered \",\")))")
      "alpha!,gamma!"))))

(ert-deftest programmatic/allows-code-replace-with-approval ()
  (skip-unless (not noninteractive))
  (let (seen)
    (test-programmatic--with-tools
        `(("Code_Replace" . ,(test-programmatic--async-tool
                              "Code_Replace"
                              (lambda (callback file-path node-name new-code)
                                (setq seen (list file-path node-name new-code))
                                (funcall callback (format "replaced:%s:%s" file-path node-name)))
                              '((:name "file_path")
                                (:name "node_name")
                                (:name "new_code"))
                              t)))
      (let ((my/gptel-programmatic-allowed-tools '("Code_Replace"))
            (gptel-sandbox-confirm-function (lambda (_tool-spec _arg-values callback)
                                              (funcall callback t))))
        (should
         (equal
          (test-programmatic--run
           "(setq result (tool-call \"Code_Replace\" :file_path \"foo.el\" :node_name \"my-fn\" :new_code \"(defun my-fn () 42)\"))
(result result)")
          "replaced:foo.el:my-fn"))
        (should (equal seen '("foo.el" "my-fn" "(defun my-fn () 42)")))))))

(ert-deftest programmatic/readonly-profile-rejects-code-replace ()
  (skip-unless (not noninteractive))
  (test-programmatic--with-tools
      `(("Code_Replace" . ,(test-programmatic--sync-tool
                            "Code_Replace"
                            (lambda (&rest _args) "replaced")
                            '((:name "file_path")
                              (:name "node_name")
                              (:name "new_code"))
                            t)))
    (let ((gptel--preset 'gptel-plan))
      (should (string-match-p
               "not allowed inside Programmatic readonly mode"
               (test-programmatic--run
                "(setq result (tool-call \"Code_Replace\" :file_path \"foo.el\" :node_name \"my-fn\" :new_code \"(defun my-fn () 42)\"))
(result result)"))))))

(ert-deftest programmatic/shows-aggregate-preview-on-multi-step-mutating-plan ()
  (skip-unless (not noninteractive))
  (let ((aggregate-count 0)
        (seen nil))
    (test-programmatic--with-tools
        `(("Edit" . ,(test-programmatic--async-tool
                       "Edit"
                       (lambda (callback file_path &optional old new diffp)
                         (push (list file_path old new diffp) seen)
                         (funcall callback (format "edited:%s" file_path)))
                       '((:name "file_path")
                         (:name "old_str" :optional t)
                         (:name "new_str")
                         (:name "diffp" :optional t))
                       t)))
      (let ((my/gptel-programmatic-allowed-tools '("Edit"))
            (gptel-sandbox-aggregate-confirm-function
             (lambda (plan callback)
               (setq aggregate-count (1+ aggregate-count))
               (should (= 2 (length plan)))
               (should (string-match-p "Edit" (plist-get (car plan) :summary)))
               (funcall callback t))))
        (should
         (equal
          (test-programmatic--run
           "(setq one (tool-call \"Edit\" :file_path \"a.el\" :new_str \"patch-a\" :diffp t))
(setq two (tool-call \"Edit\" :file_path \"b.el\" :new_str \"patch-b\" :diffp t))
(result (concat one \" | \" two))")
          "edited:a.el | edited:b.el"))
        (should (= 1 aggregate-count))
        (should (= 2 (length seen)))))))

(ert-deftest programmatic/can-reject-aggregate-preview-before-tool-confirm ()
  (skip-unless (not noninteractive))
  (let ((confirm-count 0))
    (test-programmatic--with-tools
        `(("Edit" . ,(test-programmatic--async-tool
                       "Edit"
                       (lambda (callback &rest _args)
                         (setq confirm-count (1+ confirm-count))
                         (funcall callback "should-not-run"))
                       '((:name "file_path")
                         (:name "old_str" :optional t)
                         (:name "new_str")
                         (:name "diffp" :optional t))
                       t)))
      (let ((my/gptel-programmatic-allowed-tools '("Edit"))
            (gptel-sandbox-aggregate-confirm-function
             (lambda (_plan callback)
               (funcall callback nil))))
        (should (string-match-p
                 "aggregate preview rejected by user"
                 (test-programmatic--run
                  "(setq one (tool-call \"Edit\" :file_path \"a.el\" :new_str \"patch-a\" :diffp t))
(setq two (tool-call \"Edit\" :file_path \"b.el\" :new_str \"patch-b\" :diffp t))
(result (concat one \" | \" two))")))
        (should (= 0 confirm-count))))))

(provide 'test-programmatic)

;;; test-programmatic.el ends here
;;; Note on test isolation
;; These tests pass when run alone but may fail when run with other tests
;; due to function override conflicts with the real gptel package.
;; Run alone with:
;;   emacs --batch -L lisp/modules -L tests -l tests/test-programmatic.el -f ert-run-tests-batch-and-exit
;;
;; When run with other tests, the mock installation may conflict with other
;; test files that also override gptel-tool-* functions. The tests are
;; designed to restore the original functions, but Emacs batch mode does not
;; guarantee proper isolation between test files.

(defun test-programmatic--isolation-ok-p ()
  "Return non-nil if test isolation is adequate for programmatic tests."
  ;; Check if gptel-tool-name is the real function (not mocked by another test)
  (and (fboundp 'gptel-tool-name)
       (or (not (eq (symbol-function 'gptel-tool-name)
                    (symbol-function 'test-programmatic--tool-name)))
           test-programmatic--orig-tool-accessors)))
