;;; test-pending-decisions-guard.el --- TDD guard against function corruption -*- lexical-binding: t; no-byte-compile: t; -*-

;; This test ensures gptel-auto-workflow--pending-decisions-p returns
;; a boolean (t or nil), not a symbol or function reference.
;; Corruption of this function blocks the entire pipeline.

(require 'ert)

;; Load the module under test
(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-auto-workflow-production)

(ert-deftest test-pending-decisions-p-returns-boolean ()
  "pending-decisions-p must return t or nil, never a symbol or function."
  (let ((result (gptel-auto-workflow--pending-decisions-p)))
    (should (or (eq result t) (eq result nil)))
    (should-not (symbolp result))  ; fails if returns 'gptel-auto-workflow-...
    (should-not (functionp result))))

(ert-deftest test-pending-decisions-p-no-decisions-dir ()
  "When decisions dir does not exist, should return nil."
  (let ((gptel-auto-workflow-human-decision-gate t))
    (should (null (gptel-auto-workflow--pending-decisions-p)))))

(ert-deftest test-pending-decisions-p-gate-disabled ()
  "When human decision gate is disabled, should return nil."
  (let ((gptel-auto-workflow-human-decision-gate nil))
    (should (null (gptel-auto-workflow--pending-decisions-p)))))

(provide 'test-pending-decisions-guard)
;;; test-pending-decisions-guard.el ends here
