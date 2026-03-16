;;; test-gptel-tools-edit.el --- ERT tests for Edit tool -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; TDD-style unit tests for gptel-tools-edit.el
;; Run: emacs -batch -L lisp/modules -L tests -l tests/test-gptel-tools-edit.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'diff-mode)

;;; Stub gptel dependencies

(cl-defstruct (gptel-fsm (:constructor gptel-make-fsm))
  state info)

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

(defun gptel-agent--edit-files (path old-str new-str &optional diffp)
  (let ((content (with-temp-buffer (insert-file-contents path) (buffer-string))))
    (if (and old-str (stringp old-str) (string-match-p (regexp-quote old-str) content))
        (progn
          (with-temp-file path
            (insert (replace-regexp-in-string (regexp-quote old-str) new-str content t t)))
          (format "Edited %s" path))
      (error "String not found in %s" path))))

(defun gptel-make-tool (&rest args) (plist-get args :name))

(provide 'gptel)
(provide 'gptel-ext-core)
(provide 'gptel-ext-fsm-utils)
(provide 'gptel-agent-tools)

;;; Load modules under test

(load-file (expand-file-name "lisp/modules/gptel-ext-fsm.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-ext-abort.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools-preview.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools-edit.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Test Fixtures

(defvar test-edit--temp-dir nil)

(defun test-edit--setup ()
  (setq test-edit--temp-dir (make-temp-file "gptel-edit-test-" t)))

(defun test-edit--teardown ()
  (when (and test-edit--temp-dir (file-directory-p test-edit--temp-dir))
    (delete-directory test-edit--temp-dir t)))

(defmacro test-edit--with-temp (&rest body)
  (declare (indent 0))
  `(unwind-protect (progn (test-edit--setup) ,@body) (test-edit--teardown)))

(defun test-edit--write-file (name content)
  (let ((path (expand-file-name name test-edit--temp-dir)))
    (with-temp-file path (insert content))
    path))

(defun test-edit--read-file (name)
  (with-temp-buffer
    (insert-file-contents (expand-file-name name test-edit--temp-dir))
    (buffer-string)))

(defun test-edit--apply-patch-sync (file patch-text)
  "Apply PATCH-TEXT to FILE synchronously for testing."
  (let ((default-directory (file-name-directory file))
        (tmp-patch (make-temp-file "test-patch-")))
    (unwind-protect
        (progn
          (with-temp-file tmp-patch (insert patch-text))
          (call-process "patch" nil t t "-p1" "--forward" "--batch"
                        (file-name-nondirectory file) "-i" tmp-patch))
      (delete-file tmp-patch))))

;;; Tests for my/gptel--agent--strip-diff-fences

(ert-deftest edit/strip-diff-fences/plain-text-unchanged ()
  "Plain text without fences should pass through unchanged."
  (let ((text "just plain text"))
    (should (string= text (my/gptel--agent--strip-diff-fences text)))))

(ert-deftest edit/strip-diff-fences/strips-diff-fence ()
  "Should strip ```diff fence markers."
  (let ((text "```diff
--- a/foo.el
+++ b/foo.el
@@ -1 +1 @@
-old
+new
```"))
    (should (string= "--- a/foo.el
+++ b/foo.el
@@ -1 +1 @@
-old
+new"
                     (my/gptel--agent--strip-diff-fences text)))))

(ert-deftest edit/strip-diff-fences/strips-patch-fence ()
  "Should strip ```patch fence markers."
  (let ((text "```patch
--- a/test.txt
+++ b/test.txt
```"))
    (should (string= "--- a/test.txt
+++ b/test.txt"
                     (my/gptel--agent--strip-diff-fences text)))))

(ert-deftest edit/strip-diff-fences/strips-plain-code-fence ()
  "Should strip plain ``` fence markers."
  (let ((text "```
--- a/file
+++ b/file
```"))
    (should (string= "--- a/file
+++ b/file"
                     (my/gptel--agent--strip-diff-fences text)))))

(ert-deftest edit/strip-diff-fences/handles-whitespace ()
  "Should handle leading/trailing whitespace in fences."
  (let ((text "  ```diff  
--- a/x
+++ b/x
  ```  "))
    (should (string= "--- a/x
+++ b/x"
                     (my/gptel--agent--strip-diff-fences text)))))

(ert-deftest edit/strip-diff-fences/no-trailing-newline ()
  "Should handle text without trailing newline."
  (let ((text "```diff
--- a/x
```"))
    (should (string= "--- a/x"
                     (my/gptel--agent--strip-diff-fences text)))))

(ert-deftest edit/strip-diff-fences/empty-string ()
  "Should handle empty string."
  (should (string= "" (my/gptel--agent--strip-diff-fences ""))))

(ert-deftest edit/strip-diff-fences/only-fences ()
  "Should handle string with only fences."
  (let ((text "```diff
```"))
    (should (string= "" (my/gptel--agent--strip-diff-fences text)))))

;;; Tests for patch application (synchronous helper)

(ert-deftest edit/apply-patch/simple-addition ()
  "Should apply simple addition patch."
  (test-edit--with-temp
    (let ((file (test-edit--write-file "test.el" "(defun foo () 1)\n")))
      (let ((patch "--- a/test.el
+++ b/test.el
@@ -1 +1 @@
-(defun foo () 1)
+(defun foo () 2)
"))
        (should (= 0 (test-edit--apply-patch-sync file patch)))
        (should (string= "(defun foo () 2)\n" (test-edit--read-file "test.el")))))))

(ert-deftest edit/apply-patch/multi-line-change ()
  "Should apply multi-line patch."
  (test-edit--with-temp
    (let ((file (test-edit--write-file "test.el" "(defun foo ()
  1)\n")))
      (let ((patch "--- a/test.el
+++ b/test.el
@@ -1,2 +1,2 @@
 (defun foo ()
-  1)
+  2)
"))
        (should (= 0 (test-edit--apply-patch-sync file patch)))
        (should (string= "(defun foo ()
  2)\n" (test-edit--read-file "test.el")))))))

(ert-deftest edit/apply-patch/invalid-patch-fails ()
  "Should return error for invalid patch."
  (test-edit--with-temp
    (let ((file (test-edit--write-file "test.el" "original")))
      (let ((patch "this is not a valid patch"))
        (should-not (= 0 (test-edit--apply-patch-sync file patch)))))))

(ert-deftest edit/apply-patch/nonexistent-file-fails ()
  "Should return error for nonexistent file."
  (let ((tmpdir (make-temp-file "test-" t)))
    (unwind-protect
        (let* ((file (expand-file-name "nonexistent.el" tmpdir))
               ;; Don't create the file - test nonexistent case
               (patch "--- a/nonexistent.el
+++ b/nonexistent.el
@@ -1 +1 @@
-old
+new
"))
          (should-not (= 0 (test-edit--apply-patch-sync file patch))))
      (delete-directory tmpdir t))))

;;; Tests for gptel-tools-edit-register

(ert-deftest edit/register/creates-edit-tool ()
  "gptel-tools-edit-register should register Edit tool."
  (should (fboundp 'gptel-tools-edit-register))
  (should (functionp 'gptel-tools-edit-register)))

(provide 'test-gptel-tools-edit)

;;; test-gptel-tools-edit.el ends here
