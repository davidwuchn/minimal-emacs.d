;;; test-bare-path-diagnostic.el --- Tests for bare path diagnostic -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-bare-path-diagnostic.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load the module under test directly
(load-file "lisp/modules/gptel-auto-workflow-bare-path-diagnostic.el")

(defun test-bare-path--make-temp-dir (prefix)
  "Create a temporary directory with PREFIX and return its path."
  (let ((dir (make-temp-name (expand-file-name prefix temporary-file-directory))))
    (make-directory dir t)
    dir))

(ert-deftest bare-path-diagnostic/detects-directory-files-bare-string ()
  "Should detect (directory-files \"some-dir\" ...) as a bare path violation."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files \"relative-dir\" t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :function) "directory-files"))
            (should (string= (plist-get (car violations) :raw-path) "relative-dir"))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/detects-with-temp-file-bare-string ()
  "Should detect (with-temp-file \"output.txt\" ...) as a bare path violation."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (with-temp-file \"output.txt\"\n    (insert \"data\")))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :function) "with-temp-file"))
            (should (string= (plist-get (car violations) :raw-path) "output.txt"))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/detects-find-file-bare-string ()
  "Should detect (find-file \"config.el\") as a bare path violation."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (find-file \"config.el\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :function) "find-file"))
            (should (string= (plist-get (car violations) :raw-path) "config.el"))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/skips-absolute-paths ()
  "Should NOT flag absolute paths (/tmp/... or ~/...)."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files \"/tmp/absolute-dir\" t \"\\.el\\'\"))\n")
            (insert "(defun test-fn2 ()\n  (find-file \"~/config.el\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/skips-expand-file-name-with-root ()
  "Should NOT flag paths wrapped in expand-file-name with a root."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (expand-file-name \"relative-dir\" some-root) t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/skips-workspace-expand-paths ()
  "Should NOT flag paths wrapped in gptel-auto-workflow--expand-workspace-path."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (gptel-auto-workflow--expand-workspace-path \"lisp/modules\") t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/suggested-fix-is-expand-workspace-path ()
  "Suggested fix should wrap the bare path in gptel-auto-workflow--expand-workspace-path."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-bare.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (insert-file-contents \"data/input.tsv\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 1))
            (should (string= (plist-get (car violations) :suggested-fix)
                             "(gptel-auto-workflow--expand-workspace-path \"data/input.tsv\")"))))
      (delete-directory test-dir t))))

(ert-deftest bare-path-diagnostic/no-violations-clean-file ()
  "Should return empty list when file has no bare path violations."
  (let* ((test-dir (test-bare-path--make-temp-dir "bare-path-test-"))
         (test-file (expand-file-name "test-clean.el" test-dir)))
    (unwind-protect
        (progn
          (with-temp-file test-file
            (insert "(defun test-fn ()\n  (directory-files (expand-file-name \"lisp\" some-root) t \"\\.el\\'\"))\n"))
          (let ((violations (gptel-auto-workflow--diagnose-bare-paths test-dir)))
            (should (= (length violations) 0))))
      (delete-directory test-dir t))))

(provide 'test-bare-path-diagnostic)
;;; test-bare-path-diagnostic.el ends here
