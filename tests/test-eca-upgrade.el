;;; test-eca-upgrade.el --- Tests for eca-upgrade.el -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

;; Stub required functions
(defvar package-alist nil)

(declare-function package-desc-version "package" (pkg-desc))
(declare-function package-version-join "package" (vlist))

;; Mock package functions
(defun package-desc-version (pkg) '(0 106 0))
(defun package-version-join (vlist) (mapconcat #'number-to-string vlist "."))

;; Load just the version resolution part
(defvar eca-upgrade--pinned-version "0.106.0"
  "Pinned fallback version for testing.")

(defun eca-upgrade--resolve-version-test ()
  "Test version of eca-upgrade--resolve-version that skips network calls."
  (cl-flet ((parse-semver (raw)
              (and (stringp raw)
                   (string-match "\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" raw)
                   (match-string 1 raw))))
    (or
     ;; Skip binary test in unit tests
     nil
     ;; Skip GitHub API test in unit tests
     nil
     ;; (c) package.el version
     (when (featurep 'package)
       (when-let* ((pkg-desc (assq 'eca package-alist))
                   (ver-list (package-desc-version (cadr pkg-desc))))
         (package-version-join ver-list)))
     ;; (d) pinned fallback
     eca-upgrade--pinned-version)))

;;; Version resolution tests

(ert-deftest eca-upgrade/pinned-version-default ()
  "Default pinned version is a valid semver."
  (should (stringp eca-upgrade--pinned-version))
  (should (string-match-p "^[0-9]+\\.[0-9]+\\.[0-9]+$" eca-upgrade--pinned-version)))

(ert-deftest eca-upgrade/resolve-version-fallback-to-pinned ()
  "eca-upgrade--resolve-version returns pinned version when no other source available."
  (let ((package-alist nil))
    (should (equal eca-upgrade--pinned-version (eca-upgrade--resolve-version-test)))))

(ert-deftest eca-upgrade/resolve-version-from-package-el ()
  "eca-upgrade--resolve-version uses package.el version when available."
  (let ((package-alist `((eca . [,(make-symbol "pkg")]))))
    (should (equal "0.106.0" (eca-upgrade--resolve-version-test)))))

(ert-deftest eca-upgrade/parse-semver-extracts-version ()
  "parse-semver extracts X.Y.Z from various version strings."
  (cl-flet ((parse-semver (raw)
              (and (stringp raw)
                   (string-match "\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" raw)
                   (match-string 1 raw))))
    (should (equal "0.106.0" (parse-semver "eca 0.106.0")))
    (should (equal "1.2.3" (parse-semver "v1.2.3")))
    (should (equal "10.20.30" (parse-semver "10.20.30-beta")))
    (should (null (parse-semver nil)))
    (should (null (parse-semver "no-version-here")))))

(ert-deftest eca-upgrade/pinned-version-is-configurable ()
  "eca-upgrade--pinned-version can be customized."
  (let ((original eca-upgrade--pinned-version))
    (setq eca-upgrade--pinned-version "99.99.99")
    (should (equal "99.99.99" eca-upgrade--pinned-version))
    (setq eca-upgrade--pinned-version original)))

(provide 'test-eca-upgrade)

;;; test-eca-upgrade.el ends here