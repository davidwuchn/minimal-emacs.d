;;; test-gptel-ext-abort.el --- Tests for abort and curl timeouts -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-abort.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-ext-abort.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-ext-abort)

;;; Test helpers

(defun test--make-gptel-buffer ()
  "Create a temp buffer with gptel-mode for abort tests."
  (let ((buf (generate-new-buffer "*test-gptel-abort*")))
    (with-current-buffer buf
      (setq-local my/gptel--abort-generation 0)
      buf)))

;;; Curl timeout tests

(ert-deftest test-abort/install-curl-timeouts-sets-args ()
  "Installing curl timeouts should set gptel-curl-extra-args."
  (let ((my/gptel-curl-connect-timeout 20)
        (my/gptel-curl-max-time 180))
    (my/gptel--install-fast-curl-timeouts)
    (should (member "--connect-timeout" gptel-curl-extra-args))
    (should (member "20" gptel-curl-extra-args))
    (should (member "--max-time" gptel-curl-extra-args))
    (should (member "--no-buffer" gptel-curl-extra-args))))

;;; Generation counter tests

(ert-deftest test-abort/generation-increments-on-abort ()
  "Aborting should increment the generation counter."
  (let ((buf (test--make-gptel-buffer)))
    (with-current-buffer buf
      (should (= my/gptel--abort-generation 0))
      (my/gptel-abort-here)
      (should (= my/gptel--abort-generation 1))
      (my/gptel-abort-here)
      (should (= my/gptel--abort-generation 2)))
    (kill-buffer buf)))

;;; Prompt marker tests

(ert-deftest test-abort/prompt-marker-not-present-initially ()
  "Buffer should not have prompt marker initially."
  (let ((buf (generate-new-buffer "*test-marker*")))
    (with-current-buffer buf
      (should-not (my/gptel--prompt-marker-present-at-eob-p)))
    (kill-buffer buf)))

(ert-deftest test-abort/insert-prompt-marker ()
  "Inserting prompt marker should add ### at EOB."
  (let ((buf (generate-new-buffer "*test-marker*"))
        (my/gptel-prompt-marker "### "))
    (with-current-buffer buf
      (my/gptel--insert-prompt-marker-at-eob)
      (should (my/gptel--prompt-marker-present-at-eob-p))
      (goto-char (point-max))
      (skip-chars-backward " \t\n")
      (beginning-of-line)
      (should (looking-at-p "^### ")))
    (kill-buffer buf)))

(ert-deftest test-abort/prompt-marker-idempotent ()
  "Inserting prompt marker twice should not duplicate."
  (let ((buf (generate-new-buffer "*test-marker*"))
        (my/gptel-prompt-marker "### "))
    (with-current-buffer buf
      (my/gptel--insert-prompt-marker-at-eob)
      (my/gptel--insert-prompt-marker-at-eob)
      (should (= (count-matches "^### " (point-min) (point-max)) 1)))
    (kill-buffer buf)))

(ert-deftest test-abort/goto-prompt-marker-end ()
  "Cursor should move to end of prompt marker."
  (let ((buf (generate-new-buffer "*test-marker*"))
        (my/gptel-prompt-marker "### "))
    (with-current-buffer buf
      (my/gptel--insert-prompt-marker-at-eob)
      (my/gptel--goto-prompt-marker-end)
      (should (<= (point) (point-max))))
    (kill-buffer buf)))

(provide 'test-gptel-ext-abort)
;;; test-gptel-ext-abort.el ends here
;;; Position validation tests

(ert-deftest test-abort/valid-position-p/positive-integer ()
  "Positive integers within buffer bounds should be valid."
  (let ((buf (generate-new-buffer "*test-valid*")))
    (with-current-buffer buf
      (insert "hello")
      (should (my/gptel--valid-position-p 1))
      (should (my/gptel--valid-position-p 5))
      (should (my/gptel--valid-position-p (point-max))))
    (kill-buffer buf)))

(ert-deftest test-abort/valid-position-p/invalid-values ()
  "Nil, zero, negative, and out-of-bounds values should be invalid."
  (let ((buf (generate-new-buffer "*test-valid*")))
    (with-current-buffer buf
      (insert "hello")
      (should-not (my/gptel--valid-position-p nil))
      (should-not (my/gptel--valid-position-p 0))
      (should-not (my/gptel--valid-position-p -1))
      (should-not (my/gptel--valid-position-p 100))
      (should-not (my/gptel--valid-position-p (1+ (point-max)))))
    (kill-buffer buf)))

(ert-deftest test-abort/valid-position-p/non-integers ()
  "Non-integer values should be invalid."
  (should-not (my/gptel--valid-position-p "5"))
  (should-not (my/gptel--valid-position-p 'foo))
  (should-not (my/gptel--valid-position-p 5.0)))

(ert-deftest test-abort/validate-end-for-goto/valid-end ()
  "Valid end should be returned as-is."
  (let ((buf (generate-new-buffer "*test-validate*")))
    (with-current-buffer buf
      (insert "hello")
      (should (= (my/gptel--validate-end-for-goto 5) 5))
      (should (= (my/gptel--validate-end-for-goto (point-max)) (point-max))))
    (kill-buffer buf)))

(ert-deftest test-abort/validate-end-for-goto/invalid-end-fallback ()
  "Invalid end should fallback to point-max."
  (let ((buf (generate-new-buffer "*test-validate*")))
    (with-current-buffer buf
      (insert "hello")
      (should (= (my/gptel--validate-end-for-goto nil) (point-max)))
      (should (= (my/gptel--validate-end-for-goto -1) (point-max)))
      (should (= (my/gptel--validate-end-for-goto 100) (point-max))))
    (kill-buffer buf)))

(ert-deftest test-abort/add-prompt-marker-ignores-nil-end ()
  "add-prompt-marker should not crash on nil end."
  (let ((buf (generate-new-buffer "*test-marker*")))
    (with-current-buffer buf
      (setq-local gptel-mode t)
      (my/gptel-add-prompt-marker 1 nil)  ; Should not error
      (should (= (point) 1)))  ; Point unchanged
    (kill-buffer buf)))

(ert-deftest test-abort/add-prompt-marker-ignores-out-of-bounds-end ()
  "add-prompt-marker should not crash on out-of-bounds end."
  (let ((buf (generate-new-buffer "*test-marker*")))
    (with-current-buffer buf
      (insert "hello")
      (setq-local gptel-mode t)
      (my/gptel-add-prompt-marker 1 9999)  ; Should not error
      (should (= (point) (1+ (length "hello")))))  ; Point at EOB
    (kill-buffer buf)))

