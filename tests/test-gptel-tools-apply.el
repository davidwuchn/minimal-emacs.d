;;; test-gptel-tools-apply.el --- ERT tests for ApplyPatch tool -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; TDD-style unit tests for gptel-tools-apply.el
;; Run: emacs -batch -L lisp/modules -L tests -l tests/test-gptel-tools-apply.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'diff-mode)

;;; Stub gptel dependencies

(cl-defstruct (gptel-fsm (:constructor gptel-make-fsm))
  (state (quote INIT)) table handlers info)

(defvar gptel--request-alist nil)
(defvar gptel--fsm-last nil)
(defvar gptel-mode nil)
(defvar gptel-post-response-functions nil)
(defvar gptel-mode-map (make-sparse-keymap))
(defvar gptel-agent-request--handlers nil)
(defvar gptel-agent--skills nil)
(defvar gptel-confirm-tool-calls nil)
(defvar gptel--preset nil)

(defun gptel--fsm-transition (fsm &optional new-state)
  (when new-state (setf (gptel-fsm-state fsm) new-state))
  fsm)

(defun gptel--update-status (&rest _args) nil)
(defun force-mode-line-update (&optional _all) nil)
(defun gptel-mode (&optional arg)
  (setq-local gptel-mode (if (null arg) t (> (prefix-numeric-value arg) 0))))

(defun my/gptel-make-temp-file (prefix &optional dir-flag suffix)
  (make-temp-file (concat "gptel-test-" prefix) dir-flag suffix))

(defun my/gptel--fsm-p (object)
  (ignore-errors (gptel-fsm-state object) t))

(defun my/gptel--coerce-fsm (object)
  (cond ((my/gptel--fsm-p object) object)
        ((consp object) (or (my/gptel--coerce-fsm (car object))
                            (my/gptel--coerce-fsm (cdr object))))
        (t nil)))

(defun gptel-make-tool (&rest args) (plist-get args :name))
(defun project-current (&optional _prompt) nil)
(defun project-root (_proj) default-directory)

(provide 'gptel-ext-core)
(provide 'gptel-ext-fsm-utils)
(provide 'project)

;;; Load modules under test

(load-file (expand-file-name "lisp/modules/gptel-ext-fsm.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-ext-abort.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools-preview.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools-apply.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Test Fixtures

(defvar test-apply--temp-dir nil)

(defun test-apply--setup ()
  (setq test-apply--temp-dir (make-temp-file "gptel-apply-test-" t)))

(defun test-apply--teardown ()
  (when (and test-apply--temp-dir (file-directory-p test-apply--temp-dir))
    (delete-directory test-apply--temp-dir t)))

(defmacro test-apply--with-temp (&rest body)
  (declare (indent 0))
  `(unwind-protect (progn (test-apply--setup) ,@body) (test-apply--teardown)))

(defun test-apply--write-file (name content)
  (let ((path (expand-file-name name test-apply--temp-dir)))
    (with-temp-file path (insert content))
    path))

(defun test-apply--read-file (name)
  (with-temp-buffer
    (insert-file-contents (expand-file-name name test-apply--temp-dir))
    (buffer-string)))

(defun test-apply--apply-patch-sync (file patch-text)
  "Apply PATCH-TEXT to FILE synchronously for testing."
  (let ((default-directory (file-name-directory file))
        (tmp-patch (make-temp-file "test-patch-")))
    (unwind-protect
        (progn
          (with-temp-file tmp-patch (insert patch-text))
          (call-process "patch" nil t t "-p1" "--forward" "--batch"
                        (file-name-nondirectory file) "-i" tmp-patch))
      (delete-file tmp-patch))))

;;; Tests for my/gptel--patch-looks-like-unified-diff-p

(ert-deftest apply/unified-diff-p/git-diff-format ()
  "Should recognize git diff format."
  (should (my/gptel--patch-looks-like-unified-diff-p "diff --git a/file.el b/file.el")))

(ert-deftest apply/unified-diff-p/unified-diff-format ()
  "Should recognize unified diff format with --- and +++."
  (should (my/gptel--patch-looks-like-unified-diff-p "--- a/file.el
+++ b/file.el")))

(ert-deftest apply/unified-diff-p/both-markers-required ()
  "Should require both --- and +++ markers."
  (should-not (my/gptel--patch-looks-like-unified-diff-p "--- a/file.el"))
  (should-not (my/gptel--patch-looks-like-unified-diff-p "+++ b/file.el")))

(ert-deftest apply/unified-diff-p/not-a-patch ()
  "Should return nil for non-patch text."
  (should-not (my/gptel--patch-looks-like-unified-diff-p "just plain text"))
  (should-not (my/gptel--patch-looks-like-unified-diff-p "(defun foo () 1)")))

(ert-deftest apply/unified-diff-p/nil-input ()
  "Should handle nil input."
  (should-not (my/gptel--patch-looks-like-unified-diff-p nil)))

(ert-deftest apply/unified-diff-p/empty-string ()
  "Should handle empty string."
  (should-not (my/gptel--patch-looks-like-unified-diff-p "")))

;;; Tests for my/gptel--patch-looks-like-envelope-p

(ert-deftest apply/envelope-p/recognizes-envelope ()
  "Should recognize OpenCode envelope format."
  (should (my/gptel--patch-looks-like-envelope-p "*** Begin Patch")))

(ert-deftest apply/envelope-p/not-envelope ()
  "Should return nil for non-envelope text."
  (should-not (my/gptel--patch-looks-like-envelope-p "diff --git a/file.el"))
  (should-not (my/gptel--patch-looks-like-envelope-p "--- a/file.el")))

(ert-deftest apply/envelope-p/nil-input ()
  "Should handle nil input."
  (should-not (my/gptel--patch-looks-like-envelope-p nil)))

;;; Tests for my/gptel--parse-envelope-patch

(ert-deftest apply/parse-envelope/add-file ()
  "Should parse Add File hunk."
  (let* ((patch "*** Begin Patch
*** Add File: test.txt
+Hello World
+Line 2
*** End Patch")
         (hunks (my/gptel--parse-envelope-patch patch)))
    (should (= 1 (length hunks)))
    (let ((hunk (car hunks)))
      (should (eq 'add (gptel-envelope-hunk-type hunk)))
      (should (string= "test.txt" (gptel-envelope-hunk-path hunk)))
      (should (string= "Hello World\nLine 2" (gptel-envelope-hunk-contents hunk))))))

(ert-deftest apply/parse-envelope/delete-file ()
  "Should parse Delete File hunk."
  (let* ((patch "*** Begin Patch
*** Delete File: old.txt
*** End Patch")
         (hunks (my/gptel--parse-envelope-patch patch)))
    (should (= 1 (length hunks)))
    (let ((hunk (car hunks)))
      (should (eq 'delete (gptel-envelope-hunk-type hunk)))
      (should (string= "old.txt" (gptel-envelope-hunk-path hunk))))))

(ert-deftest apply/parse-envelope/update-file ()
  "Should parse Update File hunk."
  (let* ((patch "*** Begin Patch
*** Update File: existing.txt
@@
 old line
-removed line
+added line
*** End Patch")
         (hunks (my/gptel--parse-envelope-patch patch)))
    (should (= 1 (length hunks)))
    (let ((hunk (car hunks)))
      (should (eq 'update (gptel-envelope-hunk-type hunk)))
      (should (string= "existing.txt" (gptel-envelope-hunk-path hunk))))))

(ert-deftest apply/parse-envelope/move-file ()
  "Should parse Move to directive."
  (let* ((patch "*** Begin Patch
*** Update File: old-name.txt
*** Move to: new-name.txt
@@
 content
*** End Patch")
         (hunks (my/gptel--parse-envelope-patch patch)))
    (should (= 1 (length hunks)))
    (let ((hunk (car hunks)))
      (should (eq 'update (gptel-envelope-hunk-type hunk)))
      (should (string= "old-name.txt" (gptel-envelope-hunk-path hunk)))
      (should (string= "new-name.txt" (gptel-envelope-hunk-move-path hunk))))))

(ert-deftest apply/parse-envelope/multiple-hunks ()
  "Should parse multiple hunks."
  (let* ((patch "*** Begin Patch
*** Add File: new.txt
+content
*** Delete File: old.txt
*** Update File: existing.txt
@@
 line
*** End Patch")
         (hunks (my/gptel--parse-envelope-patch patch)))
    (should (= 3 (length hunks)))
    (should (eq 'add (gptel-envelope-hunk-type (nth 0 hunks))))
    (should (eq 'delete (gptel-envelope-hunk-type (nth 1 hunks))))
    (should (eq 'update (gptel-envelope-hunk-type (nth 2 hunks))))))

(ert-deftest apply/parse-envelope/empty-patch ()
  "Should handle empty envelope patch."
  (let* ((patch "*** Begin Patch
*** End Patch")
         (hunks (my/gptel--parse-envelope-patch patch)))
    (should (null hunks))))

;;; Tests for my/gptel--patch-has-absolute-paths-p

(ert-deftest apply/absolute-paths-p/unified-diff-absolute ()
  "Should detect absolute paths in unified diff."
  (should (my/gptel--patch-has-absolute-paths-p "--- /absolute/path/file.el
+++ /absolute/path/file.el")))

(ert-deftest apply/absolute-paths-p/git-diff-absolute ()
  "Should detect absolute paths in git diff."
  (should (my/gptel--patch-has-absolute-paths-p "diff --git /absolute/path/file.el /absolute/path/file.el")))

(ert-deftest apply/absolute-paths-p/users-path ()
  "Should detect /Users/ paths."
  (should (my/gptel--patch-has-absolute-paths-p "--- /Users/david/file.el")))

(ert-deftest apply/absolute-paths-p/relative-paths-ok ()
  "Should return nil for relative paths."
  (should-not (my/gptel--patch-has-absolute-paths-p "--- a/file.el
+++ b/file.el")))

(ert-deftest apply/absolute-paths-p/nil-input ()
  "Should handle nil input."
  (should-not (my/gptel--patch-has-absolute-paths-p nil)))

;;; Tests for my/gptel--extract-patch

(ert-deftest apply/extract-patch/strips-diff-fence ()
  "Should strip ```diff fence."
  (let ((text "```diff
--- a/file.el
+++ b/file.el
```"))
    (should (string= "--- a/file.el
+++ b/file.el"
                     (my/gptel--extract-patch text)))))

(ert-deftest apply/extract-patch/strips-patch-fence ()
  "Should strip ```patch fence."
  (let ((text "```patch
--- a/file.el
+++ b/file.el
```"))
    (should (string= "--- a/file.el
+++ b/file.el"
                     (my/gptel--extract-patch text)))))

(ert-deftest apply/extract-patch/strips-plain-fence ()
  "Should strip plain ``` fence."
  (let ((text "```
--- a/file.el
+++ b/file.el
```"))
    (should (string= "--- a/file.el
+++ b/file.el"
                     (my/gptel--extract-patch text)))))

(ert-deftest apply/extract-patch/passthrough-no-fence ()
  "Should pass through text without fences."
  (let ((text "--- a/file.el
+++ b/file.el"))
    (should (string= text (my/gptel--extract-patch text)))))

(ert-deftest apply/extract-patch/empty-string ()
  "Should handle empty string."
  (should (string= "" (my/gptel--extract-patch ""))))

;;; Tests for patch application (synchronous helper)

(ert-deftest apply/core/applies-simple-patch ()
  "Should apply simple unified diff patch."
  (test-apply--with-temp
    (let ((file (test-apply--write-file "test.el" "(defun foo () 1)\n")))
      (let ((patch "--- a/test.el
+++ b/test.el
@@ -1 +1 @@
-(defun foo () 1)
+(defun foo () 2)
"))
        (should (= 0 (test-apply--apply-patch-sync file patch)))
        (should (string= "(defun foo () 2)\n" (test-apply--read-file "test.el")))))))

(ert-deftest apply/core/applies-multi-line-patch ()
  "Should apply multi-line patch."
  (test-apply--with-temp
    (let ((file (test-apply--write-file "test.el" "(defun foo ()\n  1)\n")))
      (let ((patch "--- a/test.el
+++ b/test.el
@@ -1,2 +1,2 @@
 (defun foo ()
-  1)
+  2)
"))
        (should (= 0 (test-apply--apply-patch-sync file patch)))
        (should (string= "(defun foo ()\n  2)\n" (test-apply--read-file "test.el")))))))

(ert-deftest apply/core/invalid-patch-fails ()
  "Should fail for invalid patch."
  (test-apply--with-temp
    (let ((file (test-apply--write-file "test.el" "original\n")))
      (let ((patch "this is not a valid patch"))
        (should-not (= 0 (test-apply--apply-patch-sync file patch)))))))

(ert-deftest apply/core/nonexistent-file-fails ()
  "Should fail for nonexistent file."
  (let ((tmpdir (make-temp-file "test-" t)))
    (unwind-protect
        (let* ((file (expand-file-name "nonexistent.el" tmpdir))
               (patch "--- a/nonexistent.el
+++ b/nonexistent.el
@@ -1 +1 @@
-old
+new
"))
          (should-not (= 0 (test-apply--apply-patch-sync file patch))))
      (delete-directory tmpdir t))))

;;; Tests for gptel-tools-apply-register

(ert-deftest apply/register/registers-tool ()
  "gptel-tools-apply-register should register ApplyPatch tool."
  (should (fboundp 'gptel-tools-apply-register))
  (should (functionp 'gptel-tools-apply-register)))

(provide 'test-gptel-tools-apply)

;;; test-gptel-tools-apply.el ends here
