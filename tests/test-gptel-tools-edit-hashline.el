;;; test-gptel-tools-edit-hashline.el --- Tests for hashline edit tool -*- no-byte-compile: t; lexical-binding: t; -*-

(require 'ert)
(require 'gptel-tools-edit-hashline)
;; Note: gptel-tools-edit requires gptel which may not be available in test env

(defvar test-hashline-temp-dir nil
  "Temporary directory for test files.")

(defun test-hashline-setup ()
  "Create temp directory and test file."
  (setq test-hashline-temp-dir (make-temp-file "hashline-test-" 'dir))
  (let ((test-file (expand-file-name "test.txt" test-hashline-temp-dir)))
    (with-temp-file test-file
      (insert "line one\nline two\nline three\nline four\n"))
    test-file))

(defun test-hashline-cleanup ()
  "Remove temp directory."
  (when test-hashline-temp-dir
    (delete-directory test-hashline-temp-dir 'recursive)
    (setq test-hashline-temp-dir nil)))

(ert-deftest hashline-hash-computation ()
  "Test hash computation."
  (let ((hash1 (gptel-tools-edit-hashline--hash "hello world"))
        (hash2 (gptel-tools-edit-hashline--hash "hello world"))
        (hash3 (gptel-tools-edit-hashline--hash "different")))
    (should (stringp hash1))
    (should (= (length hash1) gptel-tools-edit-hashline-length))
    (should (string= hash1 hash2))
    (should-not (string= hash1 hash3))))

(ert-deftest hashline-format-file ()
  "Test file formatting with hashlines."
  (let* ((test-file (test-hashline-setup))
         (formatted (gptel-tools-edit-hashline-format-file test-file)))
    (should (string-match-p "^1:[a-f0-9]+|line one$" formatted))
    (should (string-match-p "^2:[a-f0-9]+|line two$" formatted))
    (should (string-match-p "^3:[a-f0-9]+|line three$" formatted))
    (test-hashline-cleanup)))

(ert-deftest hashline-parse-tag ()
  "Test tag parsing."
  (let ((parsed (gptel-tools-edit-hashline--parse-tag "42:a3")))
    (should (consp parsed))
    (should (= (car parsed) 42))
    (should (string= (cdr parsed) "a3")))
  ;; Invalid tags
  (should-not (gptel-tools-edit-hashline--parse-tag "invalid"))
  (should-not (gptel-tools-edit-hashline--parse-tag "")))

(ert-deftest hashline-verify-match ()
  "Test hash verification."
  (let* ((test-file (test-hashline-setup))
         (hash (gptel-tools-edit-hashline--hash "line two")))
    ;; Correct hash
    (should (gptel-tools-edit-hashline--verify test-file 2 hash))
    ;; Wrong hash
    (should-not (gptel-tools-edit-hashline--verify test-file 2 "zz"))
    ;; Non-existent line
    (should-not (gptel-tools-edit-hashline--verify test-file 99 hash))
    (test-hashline-cleanup)))

(ert-deftest hashline-replace-line ()
  "Test single line replacement."
  (let* ((test-file (test-hashline-setup))
         (hash (gptel-tools-edit-hashline--hash "line two"))
         (tag (format "2:%s" hash))
         (result (gptel-tools-edit-hashline-replace test-file tag "replaced")))
    ;; Should succeed
    (should (string-match-p "Successfully replaced" result))
    ;; Verify content
    (with-temp-buffer
      (insert-file-contents test-file)
      (should (string-match-p "line one\nreplaced\nline three" (buffer-string))))
    (test-hashline-cleanup)))

(ert-deftest hashline-replace-hash-mismatch ()
  "Test replacement with wrong hash."
  (let* ((test-file (test-hashline-setup))
         ;; Use valid hex format but wrong hash value
         (result (gptel-tools-edit-hashline-replace test-file "2:aa" "replaced")))
    ;; Should fail with hash mismatch
    (should (string-match-p "Error: Hash mismatch" result))
    (test-hashline-cleanup)))

(ert-deftest hashline-insert-after ()
  "Test insertion after line."
  (let* ((test-file (test-hashline-setup))
         (hash (gptel-tools-edit-hashline--hash "line two"))
         (tag (format "2:%s" hash))
         (result (gptel-tools-edit-hashline-insert-after test-file tag "inserted")))
    ;; Should succeed
    (should (string-match-p "Successfully inserted" result))
    ;; Verify content
    (with-temp-buffer
      (insert-file-contents test-file)
      (should (string-match-p "line two\ninserted\nline three" (buffer-string))))
    (test-hashline-cleanup)))

(ert-deftest hashline-replace-range ()
  "Test range replacement."
  (let* ((test-file (test-hashline-setup))
         (hash1 (gptel-tools-edit-hashline--hash "line two"))
         (hash2 (gptel-tools-edit-hashline--hash "line three"))
         (start-tag (format "2:%s" hash1))
         (end-tag (format "3:%s" hash2))
         (result (gptel-tools-edit-hashline-replace-range
                  test-file start-tag end-tag "replaced range")))
    ;; Should succeed
    (should (string-match-p "Successfully replaced lines 2-3" result))
    ;; Verify content
    (with-temp-buffer
      (insert-file-contents test-file)
      (should (string-match-p "line one\nreplaced range\nline four" (buffer-string))))
    (test-hashline-cleanup)))

(ert-deftest hashline-edit-tool-integration ()
  "Test hashline mode in Edit tool."
  (let* ((test-file (test-hashline-setup))
         (hash (gptel-tools-edit-hashline--hash "line two"))
         (tag (format "2:%s" hash)))
    ;; Direct hashline replace (same logic as edit tool)
    (gptel-tools-edit-hashline-replace test-file tag "replaced via edit tool")
    ;; Verify
    (with-temp-buffer
      (insert-file-contents test-file)
      (should (string-match-p "replaced via edit tool" (buffer-string))))
    (test-hashline-cleanup)))

(provide 'test-gptel-tools-edit-hashline)
;;; test-gptel-tools-edit-hashline.el ends here
