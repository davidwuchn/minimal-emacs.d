;;; test-self-heal-conflict-guard.el --- TDD tests for new self-heal guards -*- lexical-binding: t; -*-

;; Tests for the new self-heal functions added in commits
;; 8057b0ddb (conflict-marker guard) and f8bba6a1e (inverted route).
;;
;; These tests fill coverage gaps: Pi5 added the functions but did
;; not add explicit unit tests.  If the functions regress (e.g.,
;; return wrong type, miss edge cases), these tests catch it.

;;; Code:

(require 'ert)
(require 'cl-lib)

(add-to-list 'load-path
             (expand-file-name "lisp/modules"
                               (file-name-directory (or load-file-name
                                                        (buffer-file-name)
                                                        default-directory))))
(require 'gptel-auto-workflow-self-heal-semantic)

(ert-deftest test-self-heal-conflict/has-conflict-p-true-on-marker ()
  "A file with `<<<<<<<' on a line returns non-nil."
  (let* ((file (make-temp-file "ov5-test-conflict-" nil ".el"))
         (content "line one\n<<<<<<< HEAD\nline three\n"))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (should (gptel-auto-workflow--self-heal-file-has-conflict-p file)))
      (delete-file file))))

(ert-deftest test-self-heal-conflict/has-conflict-p-nil-on-clean-file ()
  "A clean file returns nil."
  (let* ((file (make-temp-file "ov5-test-clean-" nil ".el"))
         (content "(defun foo ()\n  1)\n\n(provide 'foo)\n;;; foo.el ends here\n"))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (should-not (gptel-auto-workflow--self-heal-file-has-conflict-p file)))
      (delete-file file))))

(ert-deftest test-self-heal-conflict/has-conflict-p-nil-on-marker-in-string ()
  "A file with `<<<<<<<' only in a string returns nil (no false positive).
The regex must only match conflict markers at the start of a line,
not those inside string literals."
  (let* ((file (make-temp-file "ov5-test-string-" nil ".el"))
         (content "(defun foo ()\n  (message \"<<<<<<< is a conflict marker\"))\n"))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (should-not (gptel-auto-workflow--self-heal-file-has-conflict-p file)))
      (delete-file file))))

(ert-deftest test-self-heal-conflict/has-conflict-p-handles-indented-marker ()
  "A file with indented `<<<<<<<' (e.g., 4 spaces) returns non-nil."
  (let* ((file (make-temp-file "ov5-test-indent-" nil ".el"))
         (content "    <<<<<<< HEAD\n"))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (should (gptel-auto-workflow--self-heal-file-has-conflict-p file)))
      (delete-file file))))

(ert-deftest test-self-heal-conflict/has-conflict-p-returns-nil-for-empty-file ()
  "An empty file returns nil (no error)."
  (let* ((file (make-temp-file "ov5-test-empty-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file file (insert ""))
          (should-not (gptel-auto-workflow--self-heal-file-has-conflict-p file)))
      (delete-file file))))

(ert-deftest test-self-heal-route/direct-for-ov5-test-fixture ()
  "Files matching the `ov5-test-' pattern get :mode 'direct."
  (let* ((file (expand-file-name "ov5-test-fake.el" "/tmp/")))
    (let* ((route (gptel-auto-workflow--self-heal-route-for-file file)))
      (should (eq 'direct (plist-get route :mode)))
      (should (eq 'direct-safe (plist-get route :reason))))))

(ert-deftest test-self-heal-route/ov5-worktree-for-lisp-modules-file ()
  "Files under lisp/modules/ default to :mode 'ov5-worktree (inverted default).
This is the core behavior change in f8bba6a1e — worktree is the new default,
NOT a per-file allowlist."
  (let* ((file "/home/davidwu/.emacs.d/lisp/modules/some-file.el"))
    (let* ((route (gptel-auto-workflow--self-heal-route-for-file file)))
      (should (eq 'ov5-worktree (plist-get route :mode)))
      (should (eq 'default-deferred (plist-get route :reason))))))

(ert-deftest test-self-heal-route/direct-for-file-outside-lisp-modules ()
  "Files outside lisp/modules/ get :mode 'direct (regardless of name).
This is the safety valve — if a path is not in lisp/modules/, it's not
in the protected code area, so direct mutation is safe."
  (let* ((file "/tmp/some-file.el"))
    (let* ((route (gptel-auto-workflow--self-heal-route-for-file file)))
      (should (eq 'direct (plist-get route :mode)))
      (should (eq 'direct-safe (plist-get route :reason))))))

(ert-deftest test-self-heal-route/route-includes-file-path ()
  "Every route plist must include the original FILE under :file.
The dispatcher uses :file to pass through to the actual healer."
  (let* ((file "/tmp/test.el"))
    (let* ((route (gptel-auto-workflow--self-heal-route-for-file file)))
      (should (equal file (plist-get route :file))))))

(ert-deftest test-self-heal-route-mode/returns-mode-only ()
  "route-mode is a convenience that returns just the :mode keyword.
It must match route-for-file's :mode."
  (let* ((file "/home/davidwu/.emacs.d/lisp/modules/foo.el")
         (test-file "/tmp/ov5-test-bar.el"))
    ;; lisp/modules/ -> worktree
    (should (eq 'ov5-worktree (gptel-auto-workflow--self-heal-route-mode file)))
    ;; ov5-test- -> direct
    (should (eq 'direct (gptel-auto-workflow--self-heal-route-mode test-file)))))

;;; ── Tests for the new check-parens sanity guard in fix-provide-inside-defun ──

(ert-deftest test-fix-provide-inside-defun/skips-already-balanced-file ()
  "The fix function must skip files where parens are already balanced.
Pi5 added a check-parens guard in 8057b0ddb: if the file parses
without error, the paren depth issue was a false positive and we
should NOT modify the file.

Without this guard, the fix would insert spurious close parens into
already-correct files (the same bug pattern that originally caused
the production.el silent-truncation)."
  (let* ((file (make-temp-file "ov5-test-fix-balanced-" nil ".el"))
         (content "(defun foo ()\n  1)\n\n(provide 'foo)\n;;; foo.el ends here\n")
         (gptel-auto-workflow--fix-provide-inside-defun))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          ;; Call the fix. It should return 0 (no fix needed) for a
          ;; balanced file.
          (let ((result (gptel-auto-workflow--fix-provide-inside-defun file)))
            (should (= result 0))
            ;; File should be unchanged
            (with-temp-buffer
              (insert-file-contents file)
              (should (string= content (buffer-string))))))
      (delete-file file))))

(ert-deftest test-fix-provide-inside-defun/skips-conflict-file ()
  "The fix function must skip files with unresolved conflict markers.
Conflict-marked files should not be touched even if they have
paren issues."
  (let* ((file (make-temp-file "ov5-test-fix-conflict-" nil ".el"))
         (content "<<<<<<< HEAD\n(defun foo ()\n  1)\n=======\nold version\n>>>>>>> branch\n")
         (gptel-auto-workflow--fix-provide-inside-defun))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (let ((result (gptel-auto-workflow--fix-provide-inside-defun file)))
            ;; Should return 0 (skipped)
            (should (= result 0))
            ;; File should be UNCHANGED
            (with-temp-buffer
              (insert-file-contents file)
              (should (string= content (buffer-string))))))
      (delete-file file))))

(ert-deftest test-fix-provide-inside-defun/dry-run-on-balanced-file-leaves-content-untouched ()
  "Sanity check: fix on a balanced file does not modify the file.
This is the regression test for the check-parens guard. Without the
guard, the fix would have inserted spurious close parens."
  (let* ((file (make-temp-file "ov5-test-fix-dryrun-" nil ".el"))
         (content "(defun foo ()\n  1)\n\n(provide 'foo)\n;;; foo.el ends here\n"))
    (unwind-protect
        (progn
          (with-temp-file file (insert content))
          (gptel-auto-workflow--fix-provide-inside-defun file)
          (with-temp-buffer
            (insert-file-contents file)
            (should (string= content (buffer-string)))))
      (delete-file file))))

(provide 'test-self-heal-conflict-guard)
;;; test-self-heal-conflict-guard.el ends here
