;;; test-gptel-ext-context-images.el --- Tests for image context management -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-ext-context-images.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-ext-context-images.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-ext-context-images)

;;; Customization tests

(ert-deftest test-images/auto-convert-default ()
  "Auto-convert should default to t."
  (should my/gptel-auto-convert-images))

(ert-deftest test-images/max-context-default ()
  "Max context images should default to 10."
  (should (= my/gptel-max-context-images 10)))

(ert-deftest test-images/token-estimate-default ()
  "Token estimate should default to 1000."
  (should (= my/gptel-image-token-estimate 1000)))

(ert-deftest test-images/convert-quality-default ()
  "Convert quality should default to 85."
  (should (= my/gptel-image-convert-quality 85)))

(ert-deftest test-images/max-dimensions-default ()
  "Max dimensions should default to 1024."
  (should (= my/gptel-image-max-dimensions 1024)))

;;; Image count tests

(ert-deftest test-images/context-image-count-zero-initially ()
  "Context image count should be 0 with no context."
  (let ((gptel-context nil))
    (should (= (my/gptel--context-image-count) 0))))

(provide 'test-gptel-ext-context-images)
;;; test-gptel-ext-context-images.el ends here