;;; test-gptel-tools-agent-main.el --- Tests for main workflow entry -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-main.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-main.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-main)

;;; Variable tests

(ert-deftest test-main/running-var-declared ()
  "Running variable should be declared."
  (should (intern-soft "gptel-auto-workflow--running")))

(ert-deftest test-main/cron-job-running-var-declared ()
  "Cron job running variable should be declared."
  (should (intern-soft "gptel-auto-workflow--cron-job-running")))

(ert-deftest test-main/watchdog-timer-var-declared ()
  "Watchdog timer variable should be declared."
  (should (intern-soft "gptel-auto-workflow--watchdog-timer")))

(ert-deftest test-main/status-refresh-timer-var-declared ()
  "Status refresh timer variable should be declared."
  (should (intern-soft "gptel-auto-workflow--status-refresh-timer")))

(ert-deftest test-main/run-id-var-declared ()
  "Run ID variable should be declared."
  (should (intern-soft "gptel-auto-workflow--run-id")))

;;; Timer tests

(ert-deftest test-main/stop-status-refresh-nil-timer ()
  "Stop status refresh should handle nil timer."
  (setq gptel-auto-workflow--status-refresh-timer nil)
  (gptel-auto-workflow--stop-status-refresh-timer)
  (should-not gptel-auto-workflow--status-refresh-timer))

;;; Function tests

(ert-deftest test-main/call-process-with-watchdog-exists ()
  "Call process with watchdog function should exist."
  (should (fboundp 'gptel-auto-workflow--call-process-with-watchdog)))

(provide 'test-gptel-tools-agent-main)
;;; test-gptel-tools-agent-main.el ends here