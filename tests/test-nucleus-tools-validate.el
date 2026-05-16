;;; test-nucleus-tools-validate.el --- Tests for tool signature validation -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for nucleus-tools-validate.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-nucleus-tools-validate.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nucleus-tools-validate)

;;; Cache tests

(ert-deftest test-validate/cache-ttl-default ()
  "Cache TTL should be 60 seconds."
  (should (= nucleus--validation-cache-ttl 60)))

(ert-deftest test-validate/cache-nil-initially ()
  "Cache should be nil initially."
  (should-not nucleus--validation-cache))

(ert-deftest test-validate/get-cached-validation-empty ()
  "Get cached validation should return nil when empty."
  (should-not (nucleus--get-cached-validation)))

;;; Signature extraction tests

(ert-deftest test-validate/extract-prompt-signature-no-lambda ()
  "Extract signature should return nil without lambda."
  (should-not (nucleus--extract-prompt-signature 'Read "No lambda here")))

(ert-deftest test-validate/extract-prompt-signature-empty-lambda ()
  "Extract signature should handle empty lambda params."
  (should (equal (nucleus--extract-prompt-signature 'test "λ(). test") nil)))

(ert-deftest test-validate/extract-prompt-signature-single-param ()
  "Extract signature should extract single param."
  (let ((sig (nucleus--extract-prompt-signature 'test "λ(path). test")))
    (should (equal sig '(path)))))

(ert-deftest test-validate/extract-prompt-signature-multi-param ()
  "Extract signature should extract multiple params."
  (let ((sig (nucleus--extract-prompt-signature 'test "λ(path, content). test")))
    (should (equal sig '(path content)))))

(ert-deftest test-validate/extract-prompt-signature-optional-param ()
  "Extract signature should strip optional marker."
  (let ((sig (nucleus--extract-prompt-signature 'test "λ(path, offset?). test")))
    (should (member 'offset sig))))

(provide 'test-nucleus-tools-validate)
;;; test-nucleus-tools-validate.el ends here