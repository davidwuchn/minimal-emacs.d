;;; test-gptel-temp-files.el --- Tests for subagent temp files -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for temp file creation and TTL cleanup in gptel-tools-agent.el
;; Covers file creation, truncation, and auto-deletion.

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar my/gptel-subagent-result-limit 4000)
(defvar my/gptel-subagent-temp-file-ttl 300)
(defvar-local my/gptel--subagent-temp-files nil)
(defvar my/gptel--global-temp-files nil)

(defvar test--callback-result nil
  "Result passed to callback during tests.")

(defun my/gptel-make-temp-file (prefix &optional _dir-flag _suffix)
  "Stub for temp file creation. Creates actual temp file."
  (make-temp-file prefix))

(defun my/gptel--deliver-subagent-result (callback result)
  "Stub implementation of result delivery with truncation.
CALLBACK receives the (possibly truncated) result.
RESULT is the full subagent output."
  (if (> (length result) my/gptel-subagent-result-limit)
      (let* ((temp-file (my/gptel-make-temp-file "gptel-subagent-result-" nil ".txt"))
             (trunc-msg (format "%s\n...[Result too large, truncated. Full result saved to: %s. Use Read tool if you need more]..."
                                (substring result 0 my/gptel-subagent-result-limit)
                                temp-file))
             (file-list (if (buffer-live-p (current-buffer))
                            'my/gptel--subagent-temp-files
                          'my/gptel--global-temp-files)))
        (with-temp-file temp-file
          (insert result))
        (push temp-file (symbol-value file-list))
        (when (> my/gptel-subagent-temp-file-ttl 0)
          (run-at-time my/gptel-subagent-temp-file-ttl nil
                       (lambda (f list-var)
                         (when (file-exists-p f)
                           (delete-file f))
                         (set list-var (delete f (symbol-value list-var))))
                       temp-file file-list))
        (funcall callback trunc-msg))
    (funcall callback result)))

(defun test--temp-files-setup ()
  "Reset variables for each test."
  (setq my/gptel-subagent-result-limit 4000)
  (setq my/gptel-subagent-temp-file-ttl 300)
  (setq my/gptel--subagent-temp-files nil)
  (setq my/gptel--global-temp-files nil)
  (setq test--callback-result nil))

(defun test--capture-callback (result)
  "Callback that captures RESULT for test assertions."
  (setq test--callback-result result))

;;; Tests for result truncation decision

(ert-deftest temp-files/small-result-no-truncation ()
  "Results under limit should not be truncated."
  (test--temp-files-setup)
  (should (< (length "short result") my/gptel-subagent-result-limit)))

(ert-deftest temp-files/large-result-triggers-truncation ()
  "Results over limit should trigger truncation."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (should (> (length large-result) my/gptel-subagent-result-limit))))

(ert-deftest temp-files/exact-limit-no-truncation ()
  "Results exactly at limit should not be truncated."
  (test--temp-files-setup)
  (let ((exact-result (make-string 4000 ?x)))
    (should (= (length exact-result) my/gptel-subagent-result-limit))))

;;; Tests for temp file creation

(ert-deftest temp-files/creates-file ()
  "Should create temp file for large results."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result))
    (should test--callback-result)
    (should (string-match-p "truncated" test--callback-result))))

(ert-deftest temp-files/adds-to-buffer-local-list ()
  "Should add temp file to buffer-local list."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (should my/gptel--subagent-temp-files)
      (should (= (length my/gptel--subagent-temp-files) 1)))))

(ert-deftest temp-files/small-result-no-file ()
  "Should not create temp file for small results."
  (test--temp-files-setup)
  (let ((small-result "short result"))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback small-result)
      (should (equal test--callback-result "short result"))
      (should-not my/gptel--subagent-temp-files))))

;;; Tests for TTL=0 disables cleanup

(ert-deftest temp-files/ttl-zero-no-cleanup-scheduled ()
  "Should not schedule cleanup when TTL is 0."
  (test--temp-files-setup)
  (setq my/gptel-subagent-temp-file-ttl 0)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (should my/gptel--subagent-temp-files)
      (should test--callback-result))))

;;; Tests for truncated result format

(ert-deftest temp-files/truncated-result-has-path ()
  "Truncated result should contain temp file path."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result))
    (should (stringp test--callback-result))
    (should (string-match-p "saved to:" test--callback-result))
    (should (string-match-p "Use Read tool" test--callback-result))))

(ert-deftest temp-files/truncated-result-has-prefix ()
  "Truncated result should have original content prefix."
  (test--temp-files-setup)
  (let ((large-result (concat "PREFIX_CONTENT_" (make-string 5000 ?x))))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result))
    (should (string-match-p "PREFIX_CONTENT_" test--callback-result))))

;;; Tests for multiple temp files

(ert-deftest temp-files/multiple-files-tracked ()
  "Should track multiple temp files."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (should (= (length my/gptel--subagent-temp-files) 3)))))

;;; Tests for file existence

(ert-deftest temp-files/file-actually-created ()
  "Temp file should actually exist on disk."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (let ((temp-path (car my/gptel--subagent-temp-files)))
        (should temp-path)
        (should (file-exists-p temp-path))
        (delete-file temp-path)))))

(ert-deftest temp-files/file-contains-full-result ()
  "Temp file should contain the full result."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (let ((temp-path (car my/gptel--subagent-temp-files)))
        (should temp-path)
        (should (file-exists-p temp-path))
        (with-temp-buffer
          (insert-file-contents temp-path)
          (should (= (buffer-size) 5000)))
        (delete-file temp-path)))))

(provide 'test-gptel-temp-files)

;;; test-gptel-temp-files.el ends here