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
  "pending-decisions-p must return t or nil, never a non-boolean symbol."
  (let ((result (gptel-auto-workflow--pending-decisions-p)))
    (should (memq result '(t nil)))
    (should (not (and (symbolp result)
                      (not (eq result t))
                      (not (eq result nil)))))
    (should-not (functionp result))))

(ert-deftest test-pending-decisions-p-no-decisions-dir ()
  "When decisions dir does not exist, should return nil."
  (let ((gptel-auto-workflow-human-decision-gate t))
    (should (null (gptel-auto-workflow--pending-decisions-p)))))

(ert-deftest test-pending-decisions-p-gate-disabled ()
  "When human decision gate is disabled, should return nil."
  (let ((gptel-auto-workflow-human-decision-gate nil))
    (should (null (gptel-auto-workflow--pending-decisions-p)))))

(ert-deftest test-pending-decisions-p-proposed-returns-t ()
  "When decisions dir has a status: proposed file, return t."
  (let* ((tmpdir (make-temp-file "ov5-test-decisions-" t))
         (decisions-dir (expand-file-name "mementum/decisions/" tmpdir))
         (gptel-auto-workflow-human-decision-gate t))
    (make-directory decisions-dir t)
    (with-temp-file (expand-file-name "DECISION-test.md" decisions-dir)
      (insert "---\nid: DECISION-test\nstatus: proposed\n---\n"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--decisions-dir)
                   (lambda () decisions-dir)))
          (should (eq t (gptel-auto-workflow--pending-decisions-p))))
      (delete-directory tmpdir t))))

(ert-deftest test-pending-decisions-p-approved-returns-nil ()
  "When decisions are approved or auto-approved, return nil."
  (let* ((tmpdir (make-temp-file "ov5-test-decisions-" t))
         (decisions-dir (expand-file-name "mementum/decisions/" tmpdir))
         (gptel-auto-workflow-human-decision-gate t))
    (make-directory decisions-dir t)
    (with-temp-file (expand-file-name "DECISION-approved.md" decisions-dir)
      (insert "---\nid: DECISION-approved\nstatus: approved\n---\n"))
    (with-temp-file (expand-file-name "DECISION-auto.md" decisions-dir)
      (insert "---\nid: DECISION-auto\nstatus: auto-approved\n---\n"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--decisions-dir)
                   (lambda () decisions-dir)))
          (should (null (gptel-auto-workflow--pending-decisions-p))))
      (delete-directory tmpdir t))))

(provide 'test-pending-decisions-guard)
;;; test-pending-decisions-guard.el ends here
