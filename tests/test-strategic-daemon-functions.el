;;; test-strategic-daemon-functions.el --- Tests for AutoTTS research controller -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for strategic-daemon-functions.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-strategic-daemon-functions.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'strategic-daemon-functions)

;;; Root/path tests

(ert-deftest test-daemon/autotts-root-returns-directory ()
  "AutoTTS root should return a directory path."
  (let ((root (gptel-auto-workflow--autotts-root)))
    (should (stringp root))
    (should (string-suffix-p "/" root))))

(ert-deftest test-daemon/autotts-file-expands-path ()
  "AutoTTS file should expand relative path."
  (let ((path (gptel-auto-workflow--autotts-file "var/tmp/test.json")))
    (should (stringp path))
    (should (string-match-p "var/tmp/test.json" path))))

;;; Branch pool tests

(ert-deftest test-daemon/branch-pool-init ()
  "Branch pool init should reset pool."
  (gptel-auto-workflow--branch-pool-init)
  (should (= (gptel-auto-workflow--branch-pool-active-count) 0)))

(ert-deftest test-daemon/branch-pool-active-count-zero-initially ()
  "Branch pool active count should be 0 initially."
  (gptel-auto-workflow--branch-pool-init)
  (should (= (gptel-auto-workflow--branch-pool-active-count) 0)))

;;; EMA tests

(ert-deftest test-daemon/reset-research-ema ()
  "Reset research EMA should clear state."
  (gptel-auto-workflow--reset-research-ema)
  (should (= (gptel-auto-workflow--research-ema-delta) 0.0)))

;;; Beta schedule tests

(ert-deftest test-daemon/beta-schedule-is-function ()
  "Beta schedule should be a function."
  (should (functionp 'gptel-auto-workflow--research-beta-schedule)))

(provide 'test-strategic-daemon-functions)
;;; test-strategic-daemon-functions.el ends here