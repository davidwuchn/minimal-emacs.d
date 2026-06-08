;;; test-pi5-recent-fixes.el --- TDD tests for Pi5's recent fixes

(require 'cl-lib)

(unless (fboundp 'gptel-auto-workflow--daemon-health)
  (load-file "lisp/modules/gptel-tools-agent-main.el"))
(unless (fboundp 'gptel-auto-workflow--auto-remediate-grader-timeout)
  (load-file "lisp/modules/gptel-auto-workflow-evolution.el"))
(unless (fboundp 'gptel-auto-experiment--effective-grade-timeout)
  (load-file "lisp/modules/gptel-tools-agent-benchmark.el"))

(ert-deftest tdd/pi5/daemon-health/returns-running-no-target-no-rate-limit ()
  "When all variables are nil, daemon-health string reports defaults."
  (let ((gptel-auto-workflow--running nil)
        (gptel-auto-workflow--current-target nil)
        (gptel-auto-workflow--rate-limited-backends nil)
        (gptel-auto-experiment-grade-timeout 900))
    (let ((result (gptel-auto-workflow--daemon-health)))
      (should (stringp result))
      (should (string-match-p "running=no" result))
      (should (string-match-p "target=none" result))
      (should (string-match-p "rate-limited=0" result))
      (should (string-match-p "grade-timeout=900s" result)))))

(ert-deftest tdd/pi5/daemon-health/returns-running-yes-with-target-and-rate-limit ()
  "When running with target and rate-limited backends, reports state."
  (let ((gptel-auto-workflow--running t)
        (gptel-auto-workflow--current-target "experiment-42")
        (gptel-auto-workflow--rate-limited-backends '(a b c))
        (gptel-auto-experiment-grade-timeout 1200))
    (let ((result (gptel-auto-workflow--daemon-health)))
      (should (string-match-p "running=yes" result))
      (should (string-match-p "target=experiment-42" result))
      (should (string-match-p "rate-limited=3" result))
      (should (string-match-p "grade-timeout=1200s" result)))))

(ert-deftest tdd/pi5/auto-remediate-grader-timeout/clamps-below-floor-to-900 ()
  "When budget < 900s, clamps to floor (900s default)."
  (let ((gptel-auto-experiment-grade-timeout 300)
        (gptel-auto-experiment-time-budget 300)
        (gptel-auto-workflow--grader-timeout-override nil))
    (let ((result (gptel-auto-workflow--auto-remediate-grader-timeout)))
      (should (= 900 result))
      (should (= 900 gptel-auto-experiment-grade-timeout)))))

(ert-deftest tdd/pi5/auto-remediate-grader-timeout/clamps-above-ceiling-to-1800 ()
  "When budget > 1800s, clamps to ceiling (1800s)."
  (let ((gptel-auto-experiment-grade-timeout 3000)
        (gptel-auto-experiment-time-budget 3000)
        (gptel-auto-workflow--grader-timeout-override nil))
    (let ((result (gptel-auto-workflow--auto-remediate-grader-timeout)))
      (should (= 1800 result)))))

(ert-deftest tdd/pi5/auto-remediate-grader-timeout/respects-pipeline-override ()
  "When pipeline-override is set, uses it (not the budget clamp)."
  (let ((gptel-auto-experiment-grade-timeout 300)
        (gptel-auto-experiment-time-budget 300)
        (gptel-auto-workflow--grader-timeout-override 1500))
    (let ((result (gptel-auto-workflow--auto-remediate-grader-timeout)))
      (should (= 1500 result)))))

(ert-deftest tdd/pi5/auto-remediate-grader-timeout/returns-nil-when-vars-unbound ()
  "When required variables are not bound, returns nil (no fix applied)."
  (let ((gptel-auto-experiment-grade-timeout 300)
        (gptel-auto-experiment-time-budget 300)
        (gptel-auto-workflow--grader-timeout-override nil)
        (gptel-auto-workflow--auto-remediate-grader-timeout-skip-check t))
    (makunbound 'gptel-auto-experiment-time-budget)
    (let ((result (gptel-auto-workflow--auto-remediate-grader-timeout)))
      (should (null result)))))

(ert-deftest tdd/pi5/effective-grade-timeout/uses-default-when-no-override ()
  "When no override, returns capped default."
  (let ((gptel-auto-experiment-grade-timeout 900)
        (gptel-auto-workflow--grader-timeout-override nil))
    (let ((result (gptel-auto-experiment--effective-grade-timeout)))
      ;; default=900, capped to [300, 1800] → 900
      (should (= 900 result)))))

(ert-deftest tdd/pi5/effective-grade-timeout/uses-override-when-set ()
  "When override is set, uses it (within cap)."
  (let ((gptel-auto-experiment-grade-timeout 900)
        (gptel-auto-workflow--grader-timeout-override 1500))
    (let ((result (gptel-auto-experiment--effective-grade-timeout)))
      (should (= 1500 result)))))

(ert-deftest tdd/pi5/effective-grade-timeout/floors-very-small-override ()
  "When override is below 300, floors to 300."
  (let ((gptel-auto-experiment-grade-timeout 900)
        (gptel-auto-workflow--grader-timeout-override 100))
    (let ((result (gptel-auto-experiment--effective-grade-timeout)))
      (should (= 300 result)))))

(ert-deftest tdd/pi5/effective-grade-timeout/caps-very-large-override ()
  "When override is above 2*default, caps to 2*default."
  (let ((gptel-auto-experiment-grade-timeout 900)
        (gptel-auto-workflow--grader-timeout-override 5000))
    (let ((result (gptel-auto-experiment--effective-grade-timeout)))
      (should (= 1800 result)))))

(provide 'test-pi5-recent-fixes)
;;; test-pi5-recent-fixes.el ends here
