;;; test-nucleus-tools.el --- Tests for nucleus-tools.el -*- lexical-binding: t; -*-

;; Author: David Wu

;;; Commentary:

;; Tests for nucleus toolset definitions and validation.
;; Run alone: emacs --batch -L lisp/modules -L tests -l tests/test-nucleus-tools.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Load module (may be affected by other tests' mocks)

;; Load nucleus-tools which requires gptel - but we'll mock what we need
(defvar nucleus-toolsets)
(defvar nucleus-agent-tool-contracts)

;; Check if we need to load or if already loaded
(unless (featurep 'nucleus-tools)
  (require 'nucleus-tools))

;;; Test Fixtures

(defvar test-nucleus--toolsets-backup nil)

;;; Toolset Definition Tests

(ert-deftest test-nucleus-toolsets-defined ()
  "Test that nucleus-toolsets is defined and non-empty."
  (should (boundp 'nucleus-toolsets))
  (should (listp nucleus-toolsets))
  (should (> (length nucleus-toolsets) 0)))

(ert-deftest test-nucleus-toolsets-all-lists ()
  "Test that all toolset values are lists of strings."
  (dolist (entry nucleus-toolsets)
    (let ((tools (cdr entry)))
      (should (listp tools))
      (dolist (tool tools)
        (should (stringp tool))))))

(ert-deftest test-nucleus-toolsets-readonly-subset ()
  "Test that :readonly is subset of :nucleus."
  (let ((readonly (alist-get :readonly nucleus-toolsets))
        (nucleus (alist-get :nucleus nucleus-toolsets)))
    (dolist (tool readonly)
      (should (member tool nucleus)))))

(ert-deftest test-nucleus-toolsets-explorer-subset ()
  "Test that :explorer is subset of :readonly."
  (let ((explorer (alist-get :explorer nucleus-toolsets))
        (readonly (alist-get :readonly nucleus-toolsets)))
    (dolist (tool explorer)
      (should (member tool readonly)))))

(ert-deftest test-nucleus-toolsets-reviewer-subset ()
  "Test that :reviewer is subset of :readonly."
  (let ((reviewer (alist-get :reviewer nucleus-toolsets))
        (readonly (alist-get :readonly nucleus-toolsets)))
    (dolist (tool reviewer)
      (should (member tool readonly)))))

(ert-deftest test-nucleus-toolsets-analyzer-has-live-runtime-tools ()
  "Test that analyzer keeps the live runtime tools required by the daemon."
  (let ((analyzer (alist-get :analyzer nucleus-toolsets)))
    (should (equal analyzer '("Bash" "Read" "Glob" "Grep" "Code_Map"
                              "Diagnostics" "Programmatic")))))

(ert-deftest test-nucleus-toolsets-executor-is-nucleus-minus-runagent ()
  "Test that :executor matches :nucleus except for RunAgent." 
  (let* ((executor (alist-get :executor nucleus-toolsets))
         (nucleus (alist-get :nucleus nucleus-toolsets))
         (nucleus-without-runagent (remove "RunAgent" (copy-sequence nucleus))))
    (should (member "RunAgent" nucleus))
    (should-not (member "RunAgent" executor))
    (should (equal executor nucleus-without-runagent))))

(ert-deftest test-nucleus-toolsets-no-duplicates ()
  "Test that no toolset has duplicate tools."
  (dolist (entry nucleus-toolsets)
    (let ((tools (cdr entry)))
      (should (= (length tools)
                 (length (delete-dups (copy-sequence tools))))))))

;;; Agent Tool Contracts Tests

(ert-deftest test-nucleus-agent-tool-contracts-defined ()
  "Test that nucleus-agent-tool-contracts is defined."
  (should (boundp 'nucleus-agent-tool-contracts))
  (should (listp nucleus-agent-tool-contracts)))

(ert-deftest test-nucleus-agent-tool-contracts-valid-keys ()
  "Test that agent names are strings."
  (dolist (entry nucleus-agent-tool-contracts)
    (should (stringp (car entry)))
    (should (symbolp (cdr entry)))))

(ert-deftest test-nucleus-agent-tool-contracts-valid-toolsets ()
  "Test that all contract toolsets exist in nucleus-toolsets."
  (dolist (entry nucleus-agent-tool-contracts)
    (let ((toolset-key (cdr entry)))
      (should (assq toolset-key nucleus-toolsets)))))

(ert-deftest test-nucleus-agent-tool-contracts-executor-uses-executor-toolset ()
  "Test that executor agent is pinned to the non-recursive toolset."
  (should (equal (cdr (assoc "executor" nucleus-agent-tool-contracts)) :executor)))

;;; nucleus-get-tools Tests
;; These tests require isolation and are skipped in batch mode.
;; Run alone: emacs --batch -L lisp/modules -L tests -l tests/test-nucleus-tools.el -f ert-run-tests-batch-and-exit

(ert-deftest test-nucleus-get-tools-symbol ()
  "Test nucleus-get-tools with a toolset symbol."
  (skip-unless (not noninteractive))
  (let ((tools (nucleus-get-tools :readonly)))
    (should (listp tools))
    (should (> (length tools) 0))
    (dolist (tool tools)
      (should (stringp tool)))))

(ert-deftest test-nucleus-get-tools-list ()
  "Test nucleus-get-tools with a list of tools."
  (skip-unless (not noninteractive))
  (let ((tools (nucleus-get-tools '("Read" "Bash"))))
    (should (equal tools '("Read" "Bash")))))

(ert-deftest test-nucleus-get-tools-snippets ()
  "Test that :snippets returns same tools as :nucleus."
  (skip-unless (and (fboundp 'gptel-get-tool)
                    (not (eq (symbol-function 'gptel-get-tool)
                             (symbol-function (if (fboundp 'gptel--get-tool)
                                                  'gptel--get-tool
                                                'ignore))))))
  (let ((snippets (nucleus-get-tools :snippets))
        (nucleus (nucleus-get-tools :nucleus)))
    (should (equal snippets nucleus))))

;;; Tool Count Tests

(ert-deftest test-nucleus-toolset-counts ()
  "Test expected tool counts per toolset."
  (let ((counts '((:readonly . 18)
                  (:researcher . 17)
                   (:nucleus . 28)
                   (:executor . 27)
                    (:explorer . 5)
                    (:reviewer . 4)
                    (:analyzer . 7))))
    (dolist (entry counts)
      (let ((tools (alist-get (car entry) nucleus-toolsets)))
        (should (= (length tools) (cdr entry)))))))

(ert-deftest test-nucleus-tools-type-validation-error-orders-message-correctly ()
  "Type validation errors should report expected type before actual value."
  (let ((err (should-error
              (nucleus-tools--validation-error "context_lines" :type "40" "an integer")
              :type 'user-error)))
    (should (string-match-p "context_lines" (error-message-string err)))
    (should (string-match-p "an integer" (error-message-string err)))
    (should (string-match-p "\"40\"" (error-message-string err)))))

(ert-deftest test-nucleus-tools-contract-normalizes-before-validation-and-call ()
  "Contract validation should normalize args before validating and calling FUNC."
  (let* ((captured nil)
         (normalize (lambda (val)
                      (if (and (stringp val)
                               (string-match-p "\\`[0-9]+\\'" val))
                          (min 30 (string-to-number val))
                        val)))
         (wrapped
          (nucleus-tools--validate-contract
           "Demo"
           (lambda (count)
             (setq captured count)
             count)
           `((:name "count"
              :type integer
              :maximum 30
              :normalize ,normalize))
           nil)))
    (should (= 30 (funcall wrapped "40")))
    (should (= 30 captured))))

(ert-deftest test-nucleus-tools-async-contract-error-uses-callback ()
  "Async tool contract errors should return tool errors, not signal."
  (let* ((called nil)
         (callback-result nil)
         (wrapped
          (nucleus-tools--validate-contract
           "Edit"
           (lambda (callback file_path &optional old_str new_str)
             (setq called (list file_path old_str new_str))
             (funcall callback "ok"))
           '((:name "file_path" :type string)
             (:name "old_str" :type string :optional t)
             (:name "new_str" :type string))
           t)))
    (funcall wrapped (lambda (result) (setq callback-result result))
             "file.el" nil nil)
    (should-not called)
    (should (stringp callback-result))
    (should (string-prefix-p "Error: Tool Contract Violation" callback-result))
    (should (string-match-p "missing or null required argument" callback-result))
    (should (string-match-p "new_str" callback-result))))

(ert-deftest test-nucleus-tools-sync-contract-error-still-signals ()
  "Synchronous tool contract errors should keep signaling."
  (let ((wrapped
         (nucleus-tools--validate-contract
          "Edit"
          (lambda (file_path &optional old_str new_str)
            (list file_path old_str new_str))
          '((:name "file_path" :type string)
            (:name "old_str" :type string :optional t)
            (:name "new_str" :type string))
          nil)))
    (should-error (funcall wrapped "file.el" nil nil) :type 'user-error)))

(ert-deftest test-nucleus-tools-advise-make-tool-strips-local-contract-keys ()
  "Provider-facing tool args should not include local-only contract metadata."
  (let* ((normalize (lambda (val) val))
         (captured nil)
         (result
          (nucleus-tools--advise-make-tool
           (lambda (&rest kwargs)
             (setq captured kwargs)
             :ok)
           :name "Demo"
           :function (lambda (&rest _) nil)
           :args `((:name "count"
                    :type integer
                    :normalize ,normalize))
           :async nil)))
    (should (eq result :ok))
    (should-not (plist-member (car (plist-get captured :args)) :normalize))
    (should (functionp (plist-get captured :function)))))

(ert-deftest test-nucleus-tools-grep-normalize-context-lines-caps-numeric-strings ()
  "Grep context lines should accept integer-like strings and cap to 30."
  (require 'gptel-tools-grep)
  (should (= 30 (gptel-tools-grep--normalize-context-lines "40")))
  (should (= 5 (gptel-tools-grep--normalize-context-lines "5")))
  (should (= 0 (gptel-tools-grep--normalize-context-lines -3)))
  (should (equal "many" (gptel-tools-grep--normalize-context-lines "many"))))

(ert-deftest test-nucleus-tools-grep-prompt-signature-matches-registered-args ()
  "The Grep tool prompt should advertise the registered Grep arg names."
  (require 'nucleus-prompts)
  (require 'nucleus-tools-validate)
  (nucleus-load-tool-prompts)
  (let* ((prompt (alist-get 'Grep nucleus-tool-prompts))
         (signature (and prompt
                         (nucleus--extract-prompt-signature 'Grep prompt))))
    (should (stringp prompt))
    (should (equal signature '(regex path glob context_lines)))))

(ert-deftest test-nucleus-tools-edit-prompt-signature-matches-registered-args ()
  "The Edit tool prompt should advertise the registered Edit arg names."
  (require 'nucleus-prompts)
  (require 'nucleus-tools-validate)
  (nucleus-load-tool-prompts)
  (let* ((prompt (alist-get 'Edit nucleus-tool-prompts))
         (signature (and prompt
                         (nucleus--extract-prompt-signature 'Edit prompt))))
    (should (stringp prompt))
    (should (equal signature '(file_path old_str new_str diffp)))))

;;; Provide

(provide 'test-nucleus-tools)

;;; test-nucleus-tools.el ends here
