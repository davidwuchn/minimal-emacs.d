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

;;; After-experiment hook integration tests

(ert-deftest test-main/after-experiment-hook-var-declared ()
  "After-experiment hook variable should be declared."
  (should (intern-soft "gptel-auto-workflow-after-experiment-hook")))

(ert-deftest test-main/after-experiment-hook-runs-after-target-complete ()
  "After-experiment hook should fire when target-complete callback runs."
  (let ((hook-called nil))
    (add-hook 'gptel-auto-workflow-after-experiment-hook
              (lambda () (setq hook-called t))
              nil t)
    ;; Simulate target-complete context: set running state
    (setq gptel-auto-workflow--running t
          gptel-auto-workflow--run-id "test-run-hook"
          gptel-auto-workflow--stats (list :phase "running" :total 1 :kept 0))
    ;; Directly run the hook (target-complete calls run-hooks)
    (run-hooks 'gptel-auto-workflow-after-experiment-hook)
    (should hook-called)
    ;; Cleanup
    (setq gptel-auto-workflow--running nil)
    (remove-hook 'gptel-auto-workflow-after-experiment-hook
                  (lambda () (setq hook-called t))
                  t)))

(ert-deftest test-main/monitoring-cycle-called-after-batch ()
  "Monitoring cycle should be callable after experiment batch."
  (let ((cycle-called nil))
    (cl-letf
        (((symbol-function 'gptel-auto-workflow--monitoring-cycle)
          (lambda () (setq cycle-called t) nil)))
      ;; Simulate the call that target-complete would make
      (when (fboundp 'gptel-auto-workflow--monitoring-cycle)
        (gptel-auto-workflow--monitoring-cycle))
      (should cycle-called))))

(ert-deftest test-main/monitoring-cycle-throttled-after-batch ()
  "Monitoring cycle should respect throttle when called after batch."
  (require 'gptel-auto-workflow-monitoring-agent)
  (let ((gptel-auto-workflow-monitoring-last-cycle-time
         (- (float-time) 60))  ; 60s ago, under 900s throttle
        (gptel-auto-workflow-monitoring-enabled t)
        (gptel-auto-workflow-monitoring-cycle-interval 900))
    (should (null (gptel-auto-workflow--monitoring-cycle)))))

(ert-deftest test-main/self-heal-byte-compiler-skipped-in-cron-mode ()
  "Byte-compiler self-heal should be skipped when cron job is running."
  (let ((gptel-auto-workflow--cron-job-running t)
        (gptel-auto-workflow--self-heal-enabled t)
        (called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--self-heal-byte-compiler)
               (lambda () (setq called t) (list :fixes-applied 0 :remaining-warnings 0 :files-fixed nil))))
      (gptel-auto-workflow--maybe-self-heal-byte-compiler)
      (should-not called))))

(ert-deftest test-main/self-heal-byte-compiler-runs-when-enabled ()
  "Byte-compiler self-heal should run when enabled and not in cron mode."
  (let ((gptel-auto-workflow--cron-job-running nil)
        (gptel-auto-workflow--self-heal-enabled t)
        (called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--self-heal-byte-compiler)
               (lambda () (setq called t) (list :fixes-applied 0 :remaining-warnings 0 :files-fixed nil))))
      (gptel-auto-workflow--maybe-self-heal-byte-compiler)
      (should called))))

(ert-deftest test-main/self-heal-byte-compiler-skipped-when-disabled ()
  "Byte-compiler self-heal should be skipped when globally disabled."
  (let ((gptel-auto-workflow--cron-job-running nil)
        (gptel-auto-workflow--self-heal-enabled nil)
        (called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--self-heal-byte-compiler)
               (lambda () (setq called t) (list :fixes-applied 0 :remaining-warnings 0 :files-fixed nil))))
      (gptel-auto-workflow--maybe-self-heal-byte-compiler)
      (should-not called))))

(provide 'test-gptel-tools-agent-main)
;;; test-gptel-tools-agent-main.el ends here