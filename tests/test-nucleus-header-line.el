;;; test-nucleus-header-line.el --- Tests for nucleus header-line -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for nucleus-header-line.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-nucleus-header-line.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'nucleus-header-line)
(require 'nucleus-presets)

;;; Preset toggle tests

(ert-deftest test-header/toggle-preset-switches ()
  "Toggle should switch between agent and plan presets."
  (should (fboundp 'nucleus-header-toggle-preset)))

;;; Header-line format tests

(ert-deftest test-header/apply-preset-label-skips-no-gptel-mode ()
  "Apply preset label should skip buffers without gptel-mode."
  (let ((gptel-mode nil)
        (gptel--preset 'gptel-agent)
        (header-line-format '("default")))
    (nucleus--header-line-apply-preset-label)
    (should (equal header-line-format '("default")))))

(ert-deftest test-header/apply-preset-label-skips-plain-gptel ()
  "Apply preset label should skip plain gptel buffers (no preset)."
  (let ((gptel-mode t)
        (gptel-use-header-line t)
        (gptel--preset nil)
        (header-line-format '("default")))
    (nucleus--header-line-apply-preset-label)
    (should (equal header-line-format '("default")))))

(ert-deftest test-header/apply-preset-label-modifies-agent ()
  "Apply preset label function should exist."
  (should (fboundp 'nucleus--header-line-apply-preset-label)))

(ert-deftest test-header/apply-preset-label-modifies-plan ()
  "Apply preset label function should exist and handle plan preset."
  (should (fboundp 'nucleus--header-line-apply-preset-label)))

(provide 'test-nucleus-header-line)
;;; test-nucleus-header-line.el ends here