;;; test-gptel-auto-workflow-mementum.el --- Tests for mementum integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-mementum.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-mementum.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-mementum)

;;; Customization tests

(ert-deftest test-mementum/enabled-default ()
  "Mementum should be enabled by default."
  (should gptel-auto-workflow-mementum-enabled))

(ert-deftest test-mementum/dir-default ()
  "Mementum dir should default to mementum."
  (should (equal gptel-auto-workflow-mementum-dir "mementum")))

(ert-deftest test-mementum/memory-dir-default ()
  "Memory dir should default to mementum/memories."
  (should (equal gptel-auto-workflow-mementum-memory-dir "mementum/memories")))

(ert-deftest test-mementum/knowledge-dir-default ()
  "Knowledge dir should default to mementum/knowledge."
  (should (equal gptel-auto-workflow-mementum-knowledge-dir "mementum/knowledge")))

;;; Symbol map tests

(ert-deftest test-mementum/symbol-map-exists ()
  "Symbol map should be defined."
  (should (listp gptel-auto-workflow--mementum-symbol-map)))

(ert-deftest test-mementum/symbol-prefix-insight ()
  "Symbol prefix for insight should be insight."
  (should (equal (gptel-auto-workflow--mementum-symbol-prefix '💡) "insight")))

(ert-deftest test-mementum/symbol-prefix-mistake ()
  "Symbol prefix for mistake should be mistake."
  (should (equal (gptel-auto-workflow--mementum-symbol-prefix '❌) "mistake")))

(ert-deftest test-mementum/symbol-prefix-unknown ()
  "Symbol prefix for unknown should be memory."
  (should (equal (gptel-auto-workflow--mementum-symbol-prefix 'unknown) "memory")))

;;; Slug tests

(ert-deftest test-mementum/slug-lowercases ()
  "Slug should lowercase text."
  (should (string-match-p "^[a-z]" (gptel-auto-workflow--mementum-slug "UPPERCASE"))))

(ert-deftest test-mementum/slug-replaces-spaces ()
  "Slug should replace spaces with hyphens."
  (should (string-match-p "-" (gptel-auto-workflow--mementum-slug "two words"))))

(provide 'test-gptel-auto-workflow-mementum)
;;; test-gptel-auto-workflow-mementum.el ends here