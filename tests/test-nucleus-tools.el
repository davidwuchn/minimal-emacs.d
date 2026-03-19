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
                   (:researcher . 19)
                   (:nucleus . 30)
                   (:executor . 29)
                   (:explorer . 5)
                   (:reviewer . 4))))
    (dolist (entry counts)
      (let ((tools (alist-get (car entry) nucleus-toolsets)))
        (should (= (length tools) (cdr entry)))))))

;;; Provide

(provide 'test-nucleus-tools)

;;; test-nucleus-tools.el ends here
