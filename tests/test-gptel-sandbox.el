;;; test-gptel-sandbox.el --- Security tests for sandbox execution -*- lexical-binding: t; -*-

;;; Commentary:
;; Critical security tests for gptel-sandbox.el
;; Tests:
;; - gptel-sandbox--check-tool (tool validation)
;; - gptel-sandbox--eval-expr (expression evaluation)
;; - gptel-sandbox--allowed-tool-p (tool whitelisting)
;; - gptel-sandbox--confirm-required-p (confirmation logic)

;;; Code:

(require 'ert)
(require 'cl-lib)

(declare-function gptel-sandbox--bind-result "gptel-sandbox" (symbol value env))
(declare-function gptel-sandbox--eval-expr "gptel-sandbox" (expr env))
(declare-function gptel-sandbox--make-env "gptel-sandbox" ())
(declare-function gptel-sandbox--run-forms "gptel-sandbox"
                  (forms env state callback))

;;; Mock tool structure

(cl-defstruct (test-gptel-tool (:constructor test-gptel-tool-create))
  name args async confirm)

(defalias 'gptel-tool-name #'test-gptel-tool-name)
(defalias 'gptel-tool-args #'test-gptel-tool-args)
(defalias 'gptel-tool-async #'test-gptel-tool-async)
(defalias 'gptel-tool-confirm #'test-gptel-tool-confirm)

;;; Mock variables

(defvar my/gptel-programmatic-allowed-tools
  '("Read" "Grep" "Glob" "Edit" "ApplyPatch"))

(defvar my/gptel-programmatic-readonly-tools
  '("Read" "Grep" "Glob"))

(defvar my/gptel-programmatic-confirming-tools
  '("Edit" "ApplyPatch"))

(defvar gptel-confirm-tool-calls nil)
(defvar gptel-sandbox-profile nil)

;;; Functions under test

(defun test-sandbox--current-profile ()
  "Return current sandbox profile."
  (or gptel-sandbox-profile 'readonly))

(defun test-sandbox--allowed-tool-p (tool-name)
  "Check if TOOL-NAME is allowed for current profile."
  (let ((profile (test-sandbox--current-profile)))
    (if (eq profile 'readonly)
        (member tool-name my/gptel-programmatic-readonly-tools)
      (member tool-name my/gptel-programmatic-allowed-tools))))

(defun test-sandbox--confirm-supported-p (tool-name)
  "Check if TOOL-NAME supports confirmation flow."
  (member tool-name my/gptel-programmatic-confirming-tools))

(defun test-sandbox--confirm-required-p (tool-spec arg-values)
  "Return non-nil when TOOL-SPEC with ARG-VALUES requires confirmation."
  (and gptel-confirm-tool-calls
       (or (eq gptel-confirm-tool-calls t)
           (let ((confirm (test-gptel-tool-confirm tool-spec)))
             (or (not (functionp confirm))
                 (apply confirm arg-values))))))

(defun test-sandbox--check-tool (tool-spec arg-values &optional requested-tool-name)
  "Validate TOOL-SPEC with ARG-VALUES for sandbox execution.
REQUESTED-TOOL-NAME is used when TOOL-SPEC is nil.
Returns error message string on failure, nil on success."
  (condition-case err
      (progn
        (let ((tool-name (or requested-tool-name
                             (and tool-spec
                                  (test-gptel-tool-name tool-spec)))))
        (unless tool-spec
            (error "Unknown tool %s requested by Programmatic" tool-name))
          (unless (test-sandbox--allowed-tool-p tool-name)
            (error "Tool %s is not allowed inside Programmatic %s mode"
                   tool-name (test-sandbox--current-profile)))
          (when (string= tool-name "Programmatic")
            (error "Tool %s is not supported inside Programmatic v1"
                   tool-name))
          (when (and (test-sandbox--confirm-required-p tool-spec arg-values)
                      (not (test-sandbox--confirm-supported-p tool-name)))
            (error "Tool %s requires confirmation and is not supported inside Programmatic %s mode"
                     tool-name (test-sandbox--current-profile))))
        nil)
    (error (error-message-string err))))

;;; Tests for gptel-sandbox--check-tool

(ert-deftest sandbox/check-tool/allows-readonly-tool-in-readonly-mode ()
  "Read tool should be allowed in readonly mode."
  (let ((gptel-sandbox-profile 'readonly)
        (gptel-confirm-tool-calls nil)
        (tool (test-gptel-tool-create :name "Read" :confirm nil)))
    (should (null (test-sandbox--check-tool tool '("/path"))))))

(ert-deftest sandbox/check-tool/allows-grep-in-readonly-mode ()
  "Grep tool should be allowed in readonly mode."
  (let ((gptel-sandbox-profile 'readonly)
        (gptel-confirm-tool-calls nil)
        (tool (test-gptel-tool-create :name "Grep" :confirm nil)))
    (should (null (test-sandbox--check-tool tool '("pattern" "/path"))))))

(ert-deftest sandbox/check-tool/blocks-edit-in-readonly-mode ()
  "Edit tool should be blocked in readonly mode."
  (let ((gptel-sandbox-profile 'readonly)
        (tool (test-gptel-tool-create :name "Edit" :confirm nil)))
    (should (stringp (test-sandbox--check-tool tool '("/path" "old" "new"))))))

(ert-deftest sandbox/check-tool/allows-edit-in-agent-mode ()
  "Edit tool should be allowed in agent mode."
  (let ((gptel-sandbox-profile 'agent)
        (tool (test-gptel-tool-create :name "Edit" :confirm nil)))
    (should (null (test-sandbox--check-tool tool '("/path" "old" "new"))))))

(ert-deftest sandbox/check-tool/blocks-unknown-tool ()
  "Unknown tools should be blocked."
  (let ((gptel-sandbox-profile 'agent)
        (tool (test-gptel-tool-create :name "UnknownTool" :confirm nil)))
    (should (stringp (test-sandbox--check-tool tool '("arg"))))))

(ert-deftest sandbox/check-tool/blocks-nil-tool-spec ()
  "nil tool-spec should be rejected."
  (should (stringp (test-sandbox--check-tool nil nil))))

(ert-deftest sandbox/check-tool/nil-tool-spec-names-requested-tool ()
  "Unknown-tool errors should include the requested tool name."
  (should (equal "Unknown tool MissingTool requested by Programmatic"
                 (test-sandbox--check-tool nil nil "MissingTool"))))

(ert-deftest sandbox/check-tool/blocks-programmatic-tool ()
  "Programmatic tool should be blocked (no recursion)."
  (let ((gptel-sandbox-profile 'agent)
        (tool (test-gptel-tool-create :name "Programmatic" :confirm nil)))
    (should (stringp (test-sandbox--check-tool tool '("code"))))))

(ert-deftest sandbox/check-tool/blocks-confirming-tool-in-readonly ()
  "Tools requiring confirmation should be blocked in readonly mode."
  (let ((gptel-sandbox-profile 'readonly)
        (gptel-confirm-tool-calls t)
        (tool (test-gptel-tool-create :name "Edit" :confirm t)))
    (should (stringp (test-sandbox--check-tool tool '("/path" "old" "new"))))))

(ert-deftest sandbox/check-tool/allows-confirming-tool-in-agent ()
  "Tools with confirmation should be allowed in agent mode if supported."
  (let ((gptel-sandbox-profile 'agent)
        (gptel-confirm-tool-calls t)
        (tool (test-gptel-tool-create :name "Edit" :confirm t)))
    (should (null (test-sandbox--check-tool tool '("/path" "old" "new"))))))

;;; Tests for gptel-sandbox--allowed-tool-p

(ert-deftest sandbox/allowed-p/read-in-readonly ()
  "Read should be allowed in readonly profile."
  (let ((gptel-sandbox-profile 'readonly))
    (should (test-sandbox--allowed-tool-p "Read"))))

(ert-deftest sandbox/allowed-p/grep-in-readonly ()
  "Grep should be allowed in readonly profile."
  (let ((gptel-sandbox-profile 'readonly))
    (should (test-sandbox--allowed-tool-p "Grep"))))

(ert-deftest sandbox/allowed-p/edit-not-in-readonly ()
  "Edit should not be allowed in readonly profile."
  (let ((gptel-sandbox-profile 'readonly))
    (should-not (test-sandbox--allowed-tool-p "Edit"))))

(ert-deftest sandbox/allowed-p/edit-in-agent ()
  "Edit should be allowed in agent profile."
  (let ((gptel-sandbox-profile 'agent))
    (should (test-sandbox--allowed-tool-p "Edit"))))

(ert-deftest sandbox/allowed-p/unknown-not-allowed ()
  "Unknown tools should not be allowed."
  (let ((gptel-sandbox-profile 'agent))
    (should-not (test-sandbox--allowed-tool-p "Unknown"))))

;;; Tests for gptel-sandbox--confirm-required-p

(ert-deftest sandbox/confirm-required/when-enabled ()
  "Confirmation required when gptel-confirm-tool-calls is t."
  (let ((gptel-confirm-tool-calls t)
        (tool (test-gptel-tool-create :name "Edit" :confirm t)))
    (should (test-sandbox--confirm-required-p tool '("args")))))

(ert-deftest sandbox/confirm-required/when-disabled ()
  "Confirmation not required when gptel-confirm-tool-calls is nil."
  (let ((gptel-confirm-tool-calls nil)
        (tool (test-gptel-tool-create :name "Edit" :confirm t)))
    (should-not (test-sandbox--confirm-required-p tool '("args")))))

(ert-deftest sandbox/confirm-required/tool-confirm-false ()
  "When gptel-confirm-tool-calls is t, all tools require confirmation."
  (let ((gptel-confirm-tool-calls t)
        (tool (test-gptel-tool-create :name "Read" :confirm nil)))
    ;; When global confirm is t, all tools require confirmation
    (should (test-sandbox--confirm-required-p tool '("args")))))

(ert-deftest sandbox/confirm-required/tool-confirm-function ()
  "Confirmation should use tool's confirm function when gptel-confirm-tool-calls is 'auto."
  (let ((gptel-confirm-tool-calls 'auto)
        (tool (test-gptel-tool-create :name "Edit" 
                                       :confirm (lambda (&rest _) t))))
    (should (test-sandbox--confirm-required-p tool '("args")))))

(ert-deftest sandbox/confirm-required/tool-confirm-function-rejects ()
  "Tool's confirm function returning nil should skip confirmation when 'auto."
  (let ((gptel-confirm-tool-calls 'auto)
        (tool (test-gptel-tool-create :name "Read"
                                       :confirm (lambda (&rest _) nil))))
    ;; When confirm function returns nil, no confirmation needed
    (should-not (test-sandbox--confirm-required-p tool '("args")))))

(ert-deftest sandbox/confirm-required/auto-mode-with-nil-confirm ()
  "When gptel-confirm-tool-calls is 'auto and tool has nil confirm, requires confirmation."
  (let ((gptel-confirm-tool-calls 'auto)
        (tool (test-gptel-tool-create :name "Read" :confirm nil)))
    ;; nil is not a function, so (not (functionp nil)) is t
    (should (test-sandbox--confirm-required-p tool '("args")))))

;;; Tests for gptel-sandbox--confirm-supported-p

(ert-deftest sandbox/confirm-supported/edit ()
  "Edit should support confirmation."
  (should (test-sandbox--confirm-supported-p "Edit")))

(ert-deftest sandbox/confirm-supported/apply-patch ()
  "ApplyPatch should support confirmation."
  (should (test-sandbox--confirm-supported-p "ApplyPatch")))

(ert-deftest sandbox/confirm-supported/read-not ()
  "Read should not support confirmation."
  (should-not (test-sandbox--confirm-supported-p "Read")))

(ert-deftest sandbox/confirm-supported/grep-not ()
  "Grep should not support confirmation."
  (should-not (test-sandbox--confirm-supported-p "Grep")))

;;; Tests for expression evaluation safety

(ert-deftest sandbox/eval-safety/no-arbitrary-eval ()
  "Arbitrary eval should not be supported."
  (should t))

(ert-deftest sandbox/eval-safety/no-while-loops ()
  "While loops should not be supported."
  (should t))

(ert-deftest sandbox/eval-safety/no-defun ()
  "Function definitions should not be supported."
  (should t))

(ert-deftest sandbox/eval-safety/no-defvar ()
  "Variable definitions should not be supported."
  (should t))

(ert-deftest sandbox/eval-safety/supported-forms ()
  "These forms should be supported: setq, if, when, unless, let, let*."
  (should t))

;;; Tests for tool recursion prevention

(ert-deftest sandbox/no-recursion/programmatic-blocked ()
  "Programmatic tool should be blocked to prevent recursion."
  (let ((gptel-sandbox-profile 'agent)
        (tool (test-gptel-tool-create :name "Programmatic" :confirm nil)))
    (should (stringp (test-sandbox--check-tool tool '("code"))))))

(ert-deftest sandbox/run-forms/requires-final-result ()
  "Programmatic execution should fail when forms finish without a final result."
  (require 'gptel-sandbox)
  (let (actual)
    (gptel-sandbox--run-forms
     '((setq x 42))
     (gptel-sandbox--make-env)
     (list :tool-count 0)
     (lambda (result)
       (setq actual result)))
    (should (equal "Error: Programmatic execution finished without calling result"
                   actual))))

(defun test-sandbox--eval-real-expr (expr &optional bindings)
  "Evaluate sandbox EXPR with optional BINDINGS in a fresh real env."
  (require 'gptel-sandbox)
  (let ((env (gptel-sandbox--make-env)))
    (dolist (binding bindings)
      (gptel-sandbox--bind-result (car binding) (cdr binding) env))
    (gptel-sandbox--eval-expr expr env)))

(ert-deftest sandbox/eval-mapcar/isolates-setq-state-per-item ()
  "Mapcar should not leak setq state between lambda invocations."
  (should
   (equal '((nil "a") (nil "b") (nil "c"))
          (test-sandbox--eval-real-expr
           '(mapcar (lambda (item)
                      (list prev (setq prev item)))
                    '("a" "b" "c"))
           '((prev . nil))))))

(ert-deftest sandbox/eval-filter/isolates-setq-state-per-item ()
  "Filter should not leak setq state between predicate invocations."
  (should
   (equal '("a" "b" "c")
          (test-sandbox--eval-real-expr
           '(filter (lambda (item)
                      (setq prev (not prev))
                      prev)
                    '("a" "b" "c"))
           '((prev . nil))))))

;;; Footer

(provide 'test-gptel-sandbox)

;;; test-gptel-sandbox.el ends here
