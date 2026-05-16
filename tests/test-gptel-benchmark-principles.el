;;; test-gptel-benchmark-principles.el --- Tests for Eight Keys and Wu Xing -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-benchmark-principles.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-principles.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-principles)

;;; Eight Keys definitions tests

(ert-deftest test-principles/eight-keys-defined ()
  "Eight keys definitions should exist."
  (should (listp gptel-benchmark-eight-keys-definitions)))

(ert-deftest test-principles/eight-keys-has-8-keys ()
  "Eight keys should have 8 keys."
  (should (= (length gptel-benchmark-eight-keys-definitions) 8)))

;;; Weight tests

(ert-deftest test-principles/weights-defined ()
  "Eight keys weights should be defined."
  (should (listp gptel-benchmark-eight-keys-weights)))

(ert-deftest test-principles/weights-all-positive ()
  "All weights should be positive."
  (dolist (weight gptel-benchmark-eight-keys-weights)
    (should (> (cdr weight) 0))))

;;; Wu Xing tests

(ert-deftest test-principles/wu-xing-report-exists ()
  "Wu Xing report function should exist."
  (should (fboundp 'gptel-benchmark-wu-xing-report)))

(provide 'test-gptel-benchmark-principles)
;;; test-gptel-benchmark-principles.el ends here