;;; test-gptel-auto-workflow-bootstrap.el --- Tests for headless bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-bootstrap.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-bootstrap.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-bootstrap)

;;; Constants tests

(ert-deftest test-bootstrap/package-archives-const ()
  "Package archives constant should be defined."
  (should (listp gptel-auto-workflow-bootstrap--package-archives)))

(ert-deftest test-bootstrap/package-priorities-const ()
  "Package priorities constant should be defined."
  (should (listp gptel-auto-workflow-bootstrap--package-archive-priorities)))

(ert-deftest test-bootstrap/required-packages-const ()
  "Required packages constant should have yaml and magit."
  (should (member 'yaml gptel-auto-workflow-bootstrap--required-packages))
  (should (member 'magit gptel-auto-workflow-bootstrap--required-packages)))

;;; Elpa dirs tests

(ert-deftest test-bootstrap/elpa-dirs-returns-list ()
  "Elpa dirs should return a list."
  (should (listp (gptel-auto-workflow-bootstrap--elpa-dirs default-directory))))

(ert-deftest test-bootstrap/elpa-dirs-nil-for-missing ()
  "Elpa dirs should return nil for missing elpa."
  (should-not (gptel-auto-workflow-bootstrap--elpa-dirs "/nonexistent")))

;;; Load path seeding tests

(ert-deftest test-bootstrap/seed-load-path-exists ()
  "Seed load path function should exist."
  (should (fboundp 'gptel-auto-workflow-bootstrap--seed-load-path)))

;;; Gptel ready tests

(ert-deftest test-bootstrap/gptel-ready-p-exists ()
  "Gptel ready check function should exist."
  (should (fboundp 'gptel-auto-workflow-bootstrap--gptel-ready-p)))

(provide 'test-gptel-auto-workflow-bootstrap)
;;; test-gptel-auto-workflow-bootstrap.el ends here