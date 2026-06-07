;;; test-gptel-tools-agent-staging-baseline.el --- Tests for staging baseline cache -*- lexical-binding: t -*-

;;; Commentary:

;; TDD tests for staging baseline cache invalidation.
;; When test files change, the cached baseline should be invalidated
;; so the next baseline check uses the new test expectations.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load dependencies for the module under test
(load-file (expand-file-name "../lisp/modules/gptel-tools-agent-staging-baseline.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

;; ─── Test Helpers ───

(defvar test-staging-baseline--temp-dir nil)

(defun test-staging-baseline--setup ()
  "Set up a clean test environment."
  (setq test-staging-baseline--temp-dir (make-temp-file "baseline-test-" t))
  (with-temp-file (expand-file-name "test1.el" test-staging-baseline--temp-dir)
    (insert ";; mock test 1"))
  (with-temp-file (expand-file-name "test2.el" test-staging-baseline--temp-dir)
    (insert ";; mock test 2")))

(defun test-staging-baseline--teardown ()
  "Clean up test environment."
  (when (and test-staging-baseline--temp-dir
             (file-directory-p test-staging-baseline--temp-dir))
    (delete-directory test-staging-baseline--temp-dir t))
  (setq gptel-auto-workflow--cached-baseline-results nil
        gptel-auto-workflow--cached-baseline-test-mtimes nil))

;; ─── Test 1: Cache variable exists ───

(ert-deftest tdd/baseline/cache-var-exists ()
  "Test that the cache variable exists."
  (should (boundp 'gptel-auto-workflow--cached-baseline-test-mtimes)))

;; ─── Test 2: Stale check function exists ───

(ert-deftest tdd/baseline/stale-check-function-exists ()
  "Test that the stale check function exists."
  (should (fboundp 'gptel-auto-workflow--baseline-cache-stale-p)))

;; ─── Test 3: Stale when cached mtime differs ───

(ert-deftest tdd/baseline/stale-when-cached-mtime-differs ()
  "Cache should be stale when cached mtime differs from current."
  (test-staging-baseline--setup)
  (unwind-protect
      (progn
        (let* ((test-file (expand-file-name "test1.el" test-staging-baseline--temp-dir))
               (initial-mtime (float-time (nth 5 (file-attributes test-file))))
               (cached-mtimes (make-hash-table :test 'equal)))
          (puthash test-file (- initial-mtime 100) cached-mtimes)
          (setq gptel-auto-workflow--cached-baseline-test-mtimes cached-mtimes)
          (should (gptel-auto-workflow--baseline-cache-stale-p))))
    (test-staging-baseline--teardown)))

;; ─── Test 4: Not stale when mtimes match ───

(ert-deftest tdd/baseline/not-stale-when-mtimes-match ()
  "Cache should not be stale when cached mtime matches current."
  (test-staging-baseline--setup)
  (unwind-protect
      (progn
        ;; Get the actual current mtimes of all test files
        (let* ((current-mtimes (gptel-auto-workflow--get-test-files-mtime-hash))
               (cached-mtimes (make-hash-table :test 'equal)))
          ;; Copy the current mtimes to the cache
          (maphash (lambda (k v) (puthash k v cached-mtimes)) current-mtimes)
          (setq gptel-auto-workflow--cached-baseline-test-mtimes cached-mtimes)
          (should-not (gptel-auto-workflow--baseline-cache-stale-p))))
    (test-staging-baseline--teardown)))

;; ─── Test 5: Stale when new file added ───

(ert-deftest tdd/baseline/stale-when-new-file-added ()
  "Cache should be stale when a new test file is added (different count)."
  (test-staging-baseline--setup)
  (unwind-protect
      (progn
        (let* ((test-file (expand-file-name "test1.el" test-staging-baseline--temp-dir))
               (cached-mtimes (make-hash-table :test 'equal)))
          ;; Cache only has test1.el
          (puthash test-file (float-time (nth 5 (file-attributes test-file))) cached-mtimes)
          (setq gptel-auto-workflow--cached-baseline-test-mtimes cached-mtimes)
          ;; But tests/ has both test1.el and test2.el
          (should (gptel-auto-workflow--baseline-cache-stale-p))))
    (test-staging-baseline--teardown)))

(provide 'test-gptel-tools-agent-staging-baseline)
;;; test-gptel-tools-agent-staging-baseline.el ends here
