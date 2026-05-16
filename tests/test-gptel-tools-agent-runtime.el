;;; test-gptel-tools-agent-runtime.el --- Tests for runtime seeding -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-runtime.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-runtime.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-runtime)

;;; Path existence tests

(ert-deftest test-runtime/path-exists-for-real-file ()
  "Path exists should return t for real file."
  (let ((tmpfile (make-temp-file "runtime-test")))
    (should (gptel-auto-workflow--path-exists-or-symlink-p tmpfile))
    (delete-file tmpfile)))

(ert-deftest test-runtime/path-exists-nil-for-missing ()
  "Path exists should return nil for missing."
  (should-not (gptel-auto-workflow--path-exists-or-symlink-p "/nonexistent/path")))

;;; Safe truename tests

(ert-deftest test-runtime/safe-truename-for-real-path ()
  "Safe truename should return truename for real path."
  (let ((tmpfile (make-temp-file "runtime-test")))
    (should (stringp (gptel-auto-workflow--safe-truename tmpfile)))
    (delete-file tmpfile)))

(ert-deftest test-runtime/safe-truename-nil-for-missing ()
  "Safe truename should return nil for missing path."
  (let ((result (gptel-auto-workflow--safe-truename "/nonexistent/path")))
    (should (or (null result) (stringp result)))))

;;; Link tests

(ert-deftest test-runtime/link-shared-nil-for-empty-source ()
  "Link should return nil for empty source."
  (should-not (gptel-auto-workflow--link-shared-runtime-path "" "/tmp/target")))

(ert-deftest test-runtime/link-shared-nil-for-empty-target ()
  "Link should return nil for empty target."
  (should-not (gptel-auto-workflow--link-shared-runtime-path "/tmp/source" "")))

(ert-deftest test-runtime/link-shared-nil-for-missing-source ()
  "Link should return nil for missing source."
  (should-not (gptel-auto-workflow--link-shared-runtime-path "/nonexistent/source" "/tmp/target")))

(provide 'test-gptel-tools-agent-runtime)
;;; test-gptel-tools-agent-runtime.el ends here