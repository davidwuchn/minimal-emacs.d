;;; test-eca-ext.el --- Tests for eca-ext.el -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

;; Stub ECA functions/variables
(defvar eca--sessions nil)
(defvar eca--session-id-cache nil)
(defvar eca-config-directory nil)
(defvar eca--context-temp-files nil)

(defun eca-session () nil)
(defun eca-get (alist key) (cdr (assoc key alist)))
(defun eca-info (fmt &rest args) (apply #'message fmt args))
(defun eca-assert-session-running (session) t)
(defun eca--session-id (session) session)
(defun eca--session-status (session) 'running)
(defun eca--session-workspace-folders (session) '("/test"))
(defun eca--session-chats (session) nil)
(defun eca-chat-open (session) nil)
(defun eca-chat--get-last-buffer (session) (current-buffer))
(defun eca-chat--add-context (ctx) nil)
(defmacro eca-chat--with-current-buffer (buf &rest body) `(progn ,@body))

;; Load the module
(load-file (expand-file-name "../lisp/eca-ext.el" (file-name-directory load-file-name)))

;;; Session listing tests

(ert-deftest eca-ext/list-sessions-returns-nil-when-empty ()
  "eca-list-sessions returns nil when no sessions exist."
  (let ((eca--sessions nil))
    (should (null (eca-list-sessions)))))

(ert-deftest eca-ext/list-sessions-returns-nil-when-unbound ()
  "eca-list-sessions returns nil when eca--sessions is unbound."
  (should (null (let ((eca--sessions (default-value 'eca--sessions)))
                  (makunbound 'eca--sessions)
                  (eca-list-sessions)))))

(ert-deftest eca-ext/list-sessions-returns-plist ()
  "eca-list-sessions returns list of plists with expected keys."
  (let ((eca--sessions '((1 . mock-session))))
    (cl-letf (((symbol-function 'eca--session-id) (lambda (_) 1))
              ((symbol-function 'eca--session-status) (lambda (_) 'running))
              ((symbol-function 'eca--session-workspace-folders) (lambda (_) '("/tmp")))
              ((symbol-function 'eca--session-chats) (lambda (_) nil)))
      (let ((sessions (eca-list-sessions)))
        (should (listp sessions))
        (should (= (length sessions) 1))
        (let ((s (car sessions)))
          (should (plist-get s :id))
          (should (plist-get s :status))
          (should (plist-get s :workspace-folders))
          (should (plist-get s :chat-count)))))))

;;; Session switching tests

(ert-deftest eca-ext/select-session-returns-nil-when-empty ()
  "eca-select-session returns nil when no sessions exist."
  (let ((eca--sessions nil))
    (should (null (eca-select-session)))))

(ert-deftest eca-ext/switch-to-session-returns-nil-when-empty ()
  "eca-switch-to-session returns nil when no sessions exist."
  (let ((eca--sessions nil))
    (should (null (eca-switch-to-session)))))

;;; Temp file management tests

(ert-deftest eca-ext/temp-file-tracking-per-session ()
  "Temp files are tracked per session."
  (let ((eca--context-temp-files nil)
        (tmp-dir (make-temp-file "eca-test" t)))
    (unwind-protect
        (let ((file1 (expand-file-name "file1.txt" tmp-dir))
              (file2 (expand-file-name "file2.txt" tmp-dir))
              (file3 (expand-file-name "file3.txt" tmp-dir)))
          (write-region "test" nil file1)
          (write-region "test" nil file2)
          (write-region "test" nil file3)
          
          (eca--register-temp-file file1 1)
          (eca--register-temp-file file2 1)
          (eca--register-temp-file file3 2)
          
          (should (listp eca--context-temp-files))
          (should (= (length eca--context-temp-files) 2))
          
          (let ((entry1 (assoc 1 eca--context-temp-files)))
            (should entry1)
            (should (= (length (cdr entry1)) 2)))
          
          (let ((entry2 (assoc 2 eca--context-temp-files)))
            (should entry2)
            (should (= (length (cdr entry2)) 1))))
      (when (file-directory-p tmp-dir)
        (delete-directory tmp-dir t)))))

(ert-deftest eca-ext/register-temp-file-skips-nonexistent ()
  "eca--register-temp-file returns nil for non-existent files."
  (let ((eca--context-temp-files nil))
    (should (null (eca--register-temp-file "/nonexistent/file.txt")))
    (should (null eca--context-temp-files))))

(ert-deftest eca-ext/register-temp-file-uses-current-session ()
  "eca--register-temp-file uses current session when not specified."
  (let ((eca--context-temp-files nil)
        (eca--session-id-cache 99))
    (let ((tmp-file (make-temp-file "eca-test")))
      (unwind-protect
          (progn
            (should (eca--register-temp-file tmp-file))
            (let ((entry (assoc 99 eca--context-temp-files)))
              (should entry)
              (should (member tmp-file (cdr entry)))))
        (when (file-exists-p tmp-file)
          (delete-file tmp-file))))))

(ert-deftest eca-ext/cleanup-session-temp-files ()
  "eca--cleanup-session-temp-files removes session's files."
  (let ((eca--context-temp-files nil)
        (tmp-dir (make-temp-file "eca-test-dir" t)))
    (unwind-protect
        (let ((file1 (expand-file-name "test1.txt" tmp-dir))
              (file2 (expand-file-name "test2.txt" tmp-dir))
              (file3 (expand-file-name "other.txt" tmp-dir)))
          (write-region "test" nil file1)
          (write-region "test" nil file2)
          (write-region "test" nil file3)
          
          (eca--register-temp-file file1 1)
          (eca--register-temp-file file2 1)
          (eca--register-temp-file file3 2)
          
          (eca--cleanup-session-temp-files 1)
          
          (should-not (file-exists-p file1))
          (should-not (file-exists-p file2))
          (should-not (assoc 1 eca--context-temp-files))
          (should (assoc 2 eca--context-temp-files)))
      (when (file-directory-p tmp-dir)
        (delete-directory tmp-dir t)))))

(ert-deftest eca-ext/cleanup-all-temp-files ()
  "eca--cleanup-temp-context-files removes all tracked files."
  (let ((eca--context-temp-files nil)
        (tmp-dir (make-temp-file "eca-test-dir" t)))
    (unwind-protect
        (let ((file1 (expand-file-name "test1.txt" tmp-dir))
              (file2 (expand-file-name "test2.txt" tmp-dir)))
          (write-region "test" nil file1)
          (write-region "test" nil file2)
          
          (eca--register-temp-file file1 1)
          (eca--register-temp-file file2 2)
          
          (should (file-exists-p file1))
          (should (file-exists-p file2))
          
          (eca--cleanup-temp-context-files)
          
          (should-not (file-exists-p file1))
          (should-not (file-exists-p file2))
          (should (null eca--context-temp-files)))
      (when (file-directory-p tmp-dir)
        (delete-directory tmp-dir t)))))

;;; Session creation validation tests

(ert-deftest eca-ext/create-session-validates-result ()
  "eca-create-session-for-workspace validates session creation."
  (cl-letf (((symbol-function 'eca-create-session)
             (lambda (roots) nil)))
    (condition-case err
        (eca-create-session-for-workspace '("/test"))
      (user-error
       (should (string-match-p "Failed to create" (error-message-string err)))))))

;;; Context function existence tests

(ert-deftest eca-ext/has-file-context-function ()
  "eca-ext.el should have eca-chat-add-file-context."
  (should (fboundp 'eca-chat-add-file-context)))

(ert-deftest eca-ext/has-cursor-context-function ()
  "eca-ext.el should have eca-chat-add-cursor-context."
  (should (fboundp 'eca-chat-add-cursor-context)))

(ert-deftest eca-ext/has-repo-map-context-function ()
  "eca-ext.el should have eca-chat-add-repo-map-context."
  (should (fboundp 'eca-chat-add-repo-map-context)))

;;; Workspace management tests

(ert-deftest eca-ext/has-list-workspace-folders ()
  "eca-ext.el should have eca-list-workspace-folders."
  (should (fboundp 'eca-list-workspace-folders)))

(ert-deftest eca-ext/has-add-workspace-folder ()
  "eca-ext.el should have eca-add-workspace-folder."
  (should (fboundp 'eca-add-workspace-folder)))

(ert-deftest eca-ext/has-remove-workspace-folder ()
  "eca-ext.el should have eca-remove-workspace-folder."
  (should (fboundp 'eca-remove-workspace-folder)))

(ert-deftest eca-ext/has-workspace-folder-for-file ()
  "eca-ext.el should have eca-workspace-folder-for-file."
  (should (fboundp 'eca-workspace-folder-for-file)))

(ert-deftest eca-ext/has-workspace-provenance ()
  "eca-ext.el should have eca-workspace-provenance."
  (should (fboundp 'eca-workspace-provenance)))

(ert-deftest eca-ext/workspace-provenance-returns-nil-outside-workspace ()
  "eca-workspace-provenance returns nil when file not in workspace."
  (let ((eca--sessions nil))
    (should (null (eca-workspace-provenance "/nonexistent/file.txt")))))

(ert-deftest eca-ext/workspace-folder-for-file-finds-match ()
  "eca-workspace-folder-for-file finds correct workspace."
  (let ((test-dir (make-temp-file "eca-test" t)))
    (unwind-protect
        (let ((subdir (expand-file-name "subdir/nested" test-dir)))
          (make-directory subdir t)
          (let ((eca--sessions nil)
                (session (list 'mock-session)))
            (cl-letf (((symbol-function 'eca-session) (lambda () session))
                      ((symbol-function 'eca--session-workspace-folders)
                       (lambda (_) (list test-dir))))
              (should (equal test-dir
                             (eca-workspace-folder-for-file (expand-file-name "file.txt" subdir)))))))
      (delete-directory test-dir t))))

(ert-deftest eca-ext/has-alias-workspace-folder ()
  "eca-ext.el should have alias eca-chat-add-workspace-folder."
  (should (fboundp 'eca-chat-add-workspace-folder)))

(ert-deftest eca-ext/has-add-workspace-folder-all-sessions ()
  "eca-ext.el should have eca-add-workspace-folder-all-sessions."
  (should (fboundp 'eca-add-workspace-folder-all-sessions)))

(ert-deftest eca-ext/auto-add-workspace-hook-defined ()
  "eca-ext.el should have auto-add hook."
  (should (fboundp 'eca--auto-add-workspace-hook)))

(ert-deftest eca-ext/auto-add-config-exists ()
  "eca-ext.el should have eca-auto-add-workspace-folder config."
  (should (boundp 'eca-auto-add-workspace-folder)))

(ert-deftest eca-ext/has-auto-switch-session-config ()
  "eca-ext.el should have eca-auto-switch-session config."
  (should (boundp 'eca-auto-switch-session)))

(ert-deftest eca-ext/has-session-for-project-root ()
  "eca-ext.el should have eca--session-for-project-root."
  (should (fboundp 'eca--session-for-project-root)))

(ert-deftest eca-ext/has-share-file-context ()
  "eca-ext.el should have eca-share-file-context."
  (should (fboundp 'eca-share-file-context)))

(ert-deftest eca-ext/has-share-repo-map-context ()
  "eca-ext.el should have eca-share-repo-map-context."
  (should (fboundp 'eca-share-repo-map-context)))

(ert-deftest eca-ext/has-session-dashboard ()
  "eca-ext.el should have eca-session-dashboard."
  (should (fboundp 'eca-session-dashboard)))

(ert-deftest eca-ext/has-clipboard-context-function ()
  "eca-ext.el should have eca-chat-add-clipboard-context."
  (should (fboundp 'eca-chat-add-clipboard-context)))

(provide 'test-eca-ext)

;;; test-eca-ext.el ends here