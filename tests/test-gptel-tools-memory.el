;;; test-gptel-tools-memory.el --- Tests for mementum memory tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-memory.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-memory.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-memory)

;;; Customization tests

(ert-deftest test-memory/dir-default ()
  "Memory directory should default to mementum/memories."
  (should (equal gptel-tools-memory-dir "mementum/memories")))

(ert-deftest test-memory/knowledge-dir-default ()
  "Knowledge directory should default to mementum/knowledge."
  (should (equal gptel-tools-memory-knowledge-dir "mementum/knowledge")))

;;; Cache tests

(ert-deftest test-memory/invalidate-cache ()
  "Cache invalidation should set cached root to nil."
  (setq gptel-tools-memory--cached-root "/some/path")
  (gptel-tools-memory--invalidate-cache)
  (should-not gptel-tools-memory--cached-root))

;;; Path resolution tests

(ert-deftest test-memory/resolve-path-adds-extension ()
  "Path resolution should add .md extension."
  (let ((gptel-tools-memory--cached-root "/tmp/project"))
    (let ((path (gptel-tools-memory--resolve-path "my-insight")))
      (should (string-suffix-p ".md" path)))))

(ert-deftest test-memory/resolve-path-keeps-extension ()
  "Path resolution should keep existing .md extension."
  (let ((gptel-tools-memory--cached-root "/tmp/project"))
    (let ((path (gptel-tools-memory--resolve-path "my-insight.md")))
      (should (string-suffix-p ".md" path)))))

(ert-deftest test-memory/resolve-path-knowledge ()
  "Path resolution should use knowledge directory when knowledge-p."
  (let ((gptel-tools-memory--cached-root "/tmp/project"))
    (let ((path (gptel-tools-memory--resolve-path "pattern" t)))
      (should (string-match-p "knowledge" path)))))

(ert-deftest test-memory/resolve-path-memory ()
  "Path resolution should use memories directory by default."
  (let ((gptel-tools-memory--cached-root "/tmp/project"))
    (let ((path (gptel-tools-memory--resolve-path "insight" nil)))
      (should (string-match-p "memories" path)))))

(provide 'test-gptel-tools-memory)
;;; test-gptel-tools-memory.el ends here