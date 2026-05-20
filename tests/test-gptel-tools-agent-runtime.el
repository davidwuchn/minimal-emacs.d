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

(ert-deftest test-runtime/link-shared-symlink-same-target ()
  "Link should return t when symlink already points to source."
  (let* ((real-file (make-temp-file "runtime-real"))
         (link-file (make-temp-file "runtime-link")))
    (delete-file link-file)
    (make-symbolic-link real-file link-file)
    (should (gptel-auto-workflow--link-shared-runtime-path real-file link-file))
    (delete-file link-file)
    (delete-file real-file)))

(ert-deftest test-runtime/link-shared-symlink-different-target ()
  "Link should replace symlink pointing to a different target."
  (let* ((real-file (make-temp-file "runtime-real"))
         (other-file (make-temp-file "runtime-other"))
         (link-file (make-temp-file "runtime-link")))
    (delete-file link-file)
    (make-symbolic-link other-file link-file)
    (should (gptel-auto-workflow--link-shared-runtime-path real-file link-file))
    ;; After link, link should point to real-file
    (should (file-symlink-p link-file))
    (should (string= (file-truename link-file) (file-truename real-file)))
    (delete-file link-file)
    (delete-file real-file)
    (delete-file other-file)))

(provide 'test-gptel-tools-agent-runtime)
;;; test-gptel-tools-agent-runtime.el ends here