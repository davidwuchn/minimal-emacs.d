;;; test-gptel-temp-files.el --- Tests for subagent temp files -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for temp file creation and TTL cleanup in gptel-tools-agent.el
;; Covers file creation, truncation, and auto-deletion.

;;; Code:

(require 'ert)
(require 'cl-lib)

;;; Load real dependencies
(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-fsm)
(require 'gptel-ext-fsm-utils)
(require 'gptel-ext-core)
(require 'gptel-tools-agent)

(defvar test--callback-result nil
  "Result passed to callback during tests.")

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
      (setq-local my/gptel--subagent-temp-files nil)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (should my/gptel--subagent-temp-files)
      (should (= (length my/gptel--subagent-temp-files) 1)))))

(ert-deftest temp-files/small-result-no-file ()
  "Small results should not create a file."
  (test--temp-files-setup)
  (let ((small-result "short result"))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback small-result)
      (should test--callback-result)
      (should-not (string-match-p "truncated" test--callback-result))
      (should-not my/gptel--subagent-temp-files))))

(ert-deftest temp-files/truncated-result-has-prefix ()
  "Truncated result should contain the prefix."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result))
    (should (string-match-p "truncated" test--callback-result))
    (should (string-match-p "gptel-subagent-result" test--callback-result))))

(ert-deftest temp-files/truncated-result-has-path ()
  "Truncated result should contain the file path."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result))
    (should (string-match-p "/tmp/" test--callback-result))))

(ert-deftest temp-files/multiple-files-tracked ()
  "Multiple temp files should all be tracked."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (setq-local my/gptel--subagent-temp-files nil)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (should (= (length my/gptel--subagent-temp-files) 3)))))

(ert-deftest temp-files/file-actually-created ()
  "Temp file should actually exist on disk."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x))
        temp-path)
    (with-temp-buffer
      (setq-local my/gptel--subagent-temp-files nil)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (setq temp-path (car my/gptel--subagent-temp-files)))
    (should temp-path)
    (should (file-exists-p temp-path))
    (delete-file temp-path)))

(ert-deftest temp-files/file-contains-full-result ()
  "Temp file should contain the full result."
  (test--temp-files-setup)
  (let ((large-result (make-string 5000 ?x))
        temp-path)
    (with-temp-buffer
      (setq-local my/gptel--subagent-temp-files nil)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (setq temp-path (car my/gptel--subagent-temp-files)))
    (should temp-path)
    (should (file-exists-p temp-path))
    (let ((contents (with-temp-buffer
                      (insert-file-contents temp-path)
                      (buffer-string))))
      (should (equal contents large-result)))
    (delete-file temp-path)))

(ert-deftest temp-files/ttl-zero-no-cleanup-scheduled ()
  "TTL of 0 should not schedule cleanup."
  (test--temp-files-setup)
  (let ((my/gptel-subagent-temp-file-ttl 0)
        (large-result (make-string 5000 ?x)))
    (with-temp-buffer
      (setq-local my/gptel--subagent-temp-files nil)
      (my/gptel--deliver-subagent-result #'test--capture-callback large-result)
      (should my/gptel--subagent-temp-files)
      (should (file-exists-p (car my/gptel--subagent-temp-files)))
      (delete-file (car my/gptel--subagent-temp-files)))))

(provide 'test-gptel-temp-files)

;;; test-gptel-temp-files.el ends here