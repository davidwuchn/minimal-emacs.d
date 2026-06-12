;;; test-void-defvar-fixer.el --- TDD for void-defvar audit and fixer -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(unless (featurep 'gptel-auto-workflow-self-heal-semantic)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-self-heal-semantic.el"
                          default-directory)))

(unless (fboundp 'gptel-auto-workflow--fix-void-defvars)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el"
                          default-directory)))

(defun test-void-defvar--tmp-file (content)
  (let ((file (make-temp-file "ov5-void-defvar-" nil ".el")))
    (with-temp-file file (insert content))
    file))

(defun test-void-defvar--cleanup (file)
  (when (and file (file-exists-p file))
    (delete-file file)))

;; ── Audit tests ──

(ert-deftest test-void-defvar/audit-detects-bare-defvar ()
  "Audit must detect (defvar foo) without a value."
  (let* ((content "(defvar my-test-var)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (let ((result (gptel-auto-workflow--audit-void-defvars file)))
          (should (= 1 result)))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/audit-detects-bare-defvar-on-next-line ()
  "Audit must detect (defvar foo\\n) with close paren on the next line."
  (let* ((content "(defvar my-test-var\n)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (let ((result (gptel-auto-workflow--audit-void-defvars file)))
          (should (= 1 result)))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/audit-skips-defvar-with-value ()
  "Audit must NOT flag (defvar foo nil) that already has a value."
  (let* ((content "(defvar my-test-var nil)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (let ((result (gptel-auto-workflow--audit-void-defvars file)))
          (should (= 0 result)))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/audit-skips-defvar-with-value-and-docstring ()
  "Audit must NOT flag (defvar foo nil \"doc\") that already has a value."
  (let* ((content "(defvar my-test-var nil \"A test variable.\")\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (let ((result (gptel-auto-workflow--audit-void-defvars file)))
          (should (= 0 result)))
      (test-void-defvar--cleanup file))))

;; ── Fixer tests ──

(ert-deftest test-void-defvar/fixer-adds-nil-to-bare-defvar ()
  "Fixer must add nil to bare (defvar foo) without a matching defcustom."
  (let* ((content "(defvar my-test-void-var)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-void-defvars file)))
            (should (= 1 fixed)))
          (let ((result (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            (should (string-match-p "(defvar my-test-void-var nil)" result))))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/fixer-adds-nil-to-bare-defvar-on-next-line ()
  "Fixer must add nil to bare (defvar foo\\n). Expects nil inserted
before the close paren, which may keep the newline between var and nil."
  (let* ((content "(defvar my-test-void-var2\n)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-void-defvars file)))
            (should (= 1 fixed)))
          (let ((result (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            ;; The fixer inserts nil before the close paren. If the close
            ;; paren was on the next line, the nil may appear after a
            ;; newline. Either format is valid.
            (should (string-match-p "(defvar my-test-void-var2[ \n]*nil)" result))))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/fixer-skips-when-defcustom-exists ()
  "Fixer must NOT add nil when a (defcustom NAME ...) exists in the same file.
The defcustom already provides the default value."
  (let* ((content "(defcustom my-defcustom-var t\n  \"A custom variable.\"\n  :type 'boolean)\n\n(defvar my-defcustom-var)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-void-defvars file)))
            (should (= 0 fixed)))
          (let ((result (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            (should (string-match-p "(defvar my-defcustom-var)" result))
            (should-not (string-match-p "(defvar my-defcustom-var nil)" result))))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/fixer-fixes-standalone-defvar-with-unrelated-defcustom ()
  "Fixer must fix a bare defvar even when an unrelated defcustom exists."
  (let* ((content "(defcustom other-var t\n  \"Another var.\"\n  :type 'boolean)\n\n(defvar my-standalone-var)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-void-defvars file)))
            (should (= 1 fixed)))
          (let ((result (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            (should (string-match-p "(defvar my-standalone-var nil)" result))))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/fixer-no-op-when-already-has-value ()
  "Fixer must be a no-op on (defvar foo nil) that already has a value."
  (let* ((content "(defvar my-test-var nil)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (let ((fixed (gptel-auto-workflow--fix-void-defvars file)))
          (should (= 0 fixed)))
      (test-void-defvar--cleanup file))))

(ert-deftest test-void-defvar/fixer-multiple-bare-mixed-with-defcustom ()
  "Fixer must fix bare defvars without defcustom but skip those with one."
  (let* ((content "(defcustom shared-var nil\n  \"Shared.\"\n  :type 'boolean)\n\n(defvar shared-var)\n\n(defvar standalone-var)\n")
         (file (test-void-defvar--tmp-file content)))
    (unwind-protect
        (progn
          (let ((fixed (gptel-auto-workflow--fix-void-defvars file)))
            (should (= 1 fixed)))
          (let ((result (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string))))
            (should (string-match-p "(defvar standalone-var nil)" result))
            ;; shared-var should remain bare because defcustom exists
            (should (string-match-p "(defvar shared-var)" result))
            (should-not (string-match-p "(defvar shared-var nil)" result))))
      (test-void-defvar--cleanup file))))

(provide 'test-void-defvar-fixer)
;;; test-void-defvar-fixer.el ends here
