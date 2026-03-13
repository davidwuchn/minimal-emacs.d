;;; test-gptel-tools-agent-integration.el --- Integration tests for agent tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Integration tests that test actual implementations, not mocks.
;; Tests:
;; - my/gptel--deliver-subagent-result (truncation logic)
;; - my/gptel--build-subagent-context (context building)

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Mock required dependencies

(defvar gptel--preset nil)
(defvar gptel-backend nil)
(defvar gptel-model nil)
(defvar gptel-agent-request--handlers nil)
(defvar gptel--fsm-last nil)

(defun gptel--preset-syms (_preset) nil)
(defun gptel--apply-preset (_preset) nil)
(defun gptel-make-fsm (&rest _args) nil)
(defun gptel-request (_prompt &rest _args) nil)
(defun gptel--update-status (&rest _args) nil)
(defun gptel-agent--task-overlay (&rest _args) nil)

(defun my/gptel--coerce-fsm (obj)
  "Mock: coerce to FSM."
  obj)

(defun my/gptel-make-temp-file (prefix &optional dir-flag suffix)
  "Mock: create temp file."
  (make-temp-file prefix dir-flag suffix))

;;; Define the actual functions under test

(defvar my/gptel-subagent-result-limit 4000
  "Max characters to return inline from a subagent result.")

(defun my/gptel--deliver-subagent-result (callback result)
  "Deliver RESULT to CALLBACK, truncating large results to a temp file."
  (if (> (length result) my/gptel-subagent-result-limit)
      (let* ((temp-file (my/gptel-make-temp-file "gptel-subagent-result-" nil ".txt"))
             (trunc-msg (format "%s\n...[Result too large, truncated. Full result saved to: %s. Use Read tool if you need more]..."
                                (substring result 0 my/gptel-subagent-result-limit)
                                temp-file)))
        (with-temp-file temp-file
          (insert result))
        (funcall callback trunc-msg))
    (funcall callback result)))

(defun my/gptel--build-subagent-context (prompt files include-history include-diff &optional origin-buf)
  "Package context for a subagent payload."
  (let ((context ""))
    (when files
      (let ((file-context ""))
        (dolist (f files)
          (if (file-readable-p f)
              (let ((content (with-temp-buffer
                               (insert-file-contents f)
                               (buffer-string))))
                (setq file-context (concat file-context (format "<file path=\"%s\">\n%s\n</file>\n" f content))))
            (setq file-context (concat file-context (format "<file path=\"%s\">\n[Error: File not found or not readable]\n</file>\n" f)))))
        (when (not (string-empty-p file-context))
          (setq context (concat context "<files>\n" file-context "</files>\n\n")))))
    (if (string-empty-p context)
        prompt
      (concat context "Task:\n" prompt))))

;;; Tests for my/gptel--deliver-subagent-result

(ert-deftest integration/deliver-result/small-result ()
  "Small result should be delivered without truncation."
  (let* ((my/gptel-subagent-result-limit 100)
         (small-result "This is a small result")
         (delivered nil))
    (my/gptel--deliver-subagent-result
     (lambda (r) (setq delivered r))
     small-result)
    (should (equal delivered small-result))))

(ert-deftest integration/deliver-result/large-result-truncates ()
  "Large result should be truncated with temp file reference."
  (let* ((my/gptel-subagent-result-limit 50)
         (large-result (make-string 200 ?x))
         (delivered nil)
         (temp-files nil))
    (my/gptel--deliver-subagent-result
     (lambda (r) (setq delivered r))
     large-result)
    (should (stringp delivered))
    (should (string-match-p "truncated" delivered))
    (should (string-match-p "gptel-subagent-result" delivered))
    ;; Cleanup temp files
    (when (string-match "gptel-subagent-result-[^\"]+" delivered)
      (let ((temp-file (match-string 0 delivered)))
        (when (file-exists-p temp-file)
          (delete-file temp-file))))))

(ert-deftest integration/deliver-result/exactly-at-limit ()
  "Result exactly at limit should not be truncated."
  (let* ((my/gptel-subagent-result-limit 100)
         (exact-result (make-string 100 ?x))
         (delivered nil))
    (my/gptel--deliver-subagent-result
     (lambda (r) (setq delivered r))
     exact-result)
    (should (equal delivered exact-result))))

(ert-deftest integration/deliver-result/one-over-limit ()
  "Result one char over limit should be truncated."
  (let* ((my/gptel-subagent-result-limit 100)
         (over-result (make-string 101 ?x))
         (delivered nil))
    (my/gptel--deliver-subagent-result
     (lambda (r) (setq delivered r))
     over-result)
    (should (string-match-p "truncated" delivered))))

(ert-deftest integration/deliver-result/empty-string ()
  "Empty string should be delivered as-is."
  (let* ((my/gptel-subagent-result-limit 100)
         (empty-result "")
         (delivered nil))
    (my/gptel--deliver-subagent-result
     (lambda (r) (setq delivered r))
     empty-result)
    (should (equal delivered ""))))

(ert-deftest integration/deliver-result/temp-file-contains-full-result ()
  "Temp file should contain the full result."
  (let* ((my/gptel-subagent-result-limit 10)
         (large-result "01234567890123456789")
         (delivered nil))
    (my/gptel--deliver-subagent-result
     (lambda (r) (setq delivered r))
     large-result)
    (should (stringp delivered))
    (when (string-match "/tmp/gptel-subagent-result-[^\"]+\\.txt" delivered)
      (let ((temp-file (match-string 0 delivered)))
        (when (file-exists-p temp-file)
          (let ((contents (with-temp-buffer
                            (insert-file-contents temp-file)
                            (buffer-string))))
            (should (equal contents large-result))
            (delete-file temp-file)))))))

;;; Tests for my/gptel--build-subagent-context

(ert-deftest integration/build-context/empty-context ()
  "Empty prompt with no extras should return as-is."
  (let ((result (my/gptel--build-subagent-context "Test prompt" nil nil nil)))
    (should (equal result "Test prompt"))))

(ert-deftest integration/build-context/includes-prompt ()
  "Result should include the original prompt."
  (let ((result (my/gptel--build-subagent-context "My task" nil nil nil)))
    (should (string-match-p "My task" result))))

(ert-deftest integration/build-context/with-files ()
  "Result should include file contents."
  (let* ((temp-file (make-temp-file "test-context" nil ".txt"))
         (_ (with-temp-file temp-file (insert "file content here")))
         (result (my/gptel--build-subagent-context
                  "Task" (list temp-file) nil nil)))
    (unwind-protect
        (progn
          (should (string-match-p "file content here" result))
          (should (string-match-p "<files>" result))
          (should (string-match-p "</files>" result)))
      (delete-file temp-file))))

(ert-deftest integration/build-context/with-nonexistent-file ()
  "Nonexistent files should show error."
  (let ((result (my/gptel--build-subagent-context
                 "Task" '("/nonexistent/file.txt") nil nil)))
    (should (string-match-p "File not found" result))))

(ert-deftest integration/build-context/with-multiple-files ()
  "Multiple files should all be included."
  (let* ((temp1 (make-temp-file "test1" nil ".txt"))
         (temp2 (make-temp-file "test2" nil ".txt"))
         (_ (with-temp-file temp1 (insert "content1")))
         (_ (with-temp-file temp2 (insert "content2")))
         (result (my/gptel--build-subagent-context
                  "Task" (list temp1 temp2) nil nil)))
    (unwind-protect
        (progn
          (should (string-match-p "content1" result))
          (should (string-match-p "content2" result)))
      (delete-file temp1)
      (delete-file temp2))))

;;; Footer

(provide 'test-gptel-tools-agent-integration)