;;; test-production-metrics-signal-bug.el --- TDD tests for Signal 1 cl-return bug -*- lexical-binding: t; -*-

(require 'gptel-auto-workflow-production-metrics)

(ert-deftest test-production-metrics/signal-1-detects-target-in-error-log ()
  "When the target basename appears in a recent error log, the
:support-tickets-reduced signal must be 1 (or :business-value-score
must include the +0.3 boost for fix-in-error-log).

Bug: `cl-block check-logs' uses (cl-return t) which targets the
innermost UNNAMED cl-block, but the block is named `check-logs'.
`cl-return' therefore signals `no-catch' — silently swallowed by the
surrounding `ignore-errors' — and Signal 1 is reported as nil
even when the target IS in the log."
  (let* ((test-root "/tmp/test-bv-signal-1-bug")
         (log-dir (expand-file-name "var/log/" test-root))
         (log-file (expand-file-name "test.log" log-dir))
         (old-default default-directory))
    (unwind-protect
        (progn
          ;; Stub the workspace-path expansion to point at our test dir.
          (fset 'gptel-auto-workflow--expand-workspace-path
                (lambda (&rest _) test-root))
          ;; Create the directory + a log mentioning the target basename
          ;; (the .el suffix matters — that's what target-basename is).
          (make-directory log-dir t)
          (with-temp-file log-file
            (insert "ERROR: something went wrong in my-target-basename.el\n"))
          ;; Call the function and assert Signal 1 fires.
          (let* ((result (gptel-auto-workflow--compute-local-business-value
                          "my-target-basename.el"))
                 (tickets (plist-get result :support-tickets-reduced))
                 (bv (plist-get result :business-value-score)))
            (should (= tickets 1))
            (should (>= bv 0.3))))
      (delete-directory test-root t)
      (fmakunbound 'gptel-auto-workflow--expand-workspace-path)
      (setq default-directory old-default))))

(ert-deftest test-production-metrics/signal-1-returns-nil-when-no-log-mentions-target ()
  "When the target basename does NOT appear in any error log,
:support-tickets-reduced should be 0 (not silently-fire from the
cl-return bug).  This is a complementary test: the bug caused the
function to ALWAYS return nil, so we need to verify it also returns
nil correctly in the negative case."
  (let* ((test-root "/tmp/test-bv-signal-1-neg")
         (log-dir (expand-file-name "var/log/" test-root))
         (log-file (expand-file-name "test.log" log-dir))
         (old-default default-directory))
    (unwind-protect
        (progn
          (fset 'gptel-auto-workflow--expand-workspace-path
                (lambda (&rest _) test-root))
          (make-directory log-dir t)
          (with-temp-file log-file
            (insert "ERROR: completely different file mentioned here\n"))
          (let* ((result (gptel-auto-workflow--compute-local-business-value
                          "my-target-basename.el"))
                 (tickets (plist-get result :support-tickets-reduced)))
            (should (= tickets 0))))
      (delete-directory test-root t)
      (fmakunbound 'gptel-auto-workflow--expand-workspace-path)
      (setq default-directory old-default))))

(ert-deftest test-production-metrics/signal-1-finds-target-in-second-log-file ()
  "When the target is mentioned in the SECOND log file (not the first),
Signal 1 should still fire.  This exercises the dolist's continuation
behavior — the original cl-return bug would have swallowed the throw
on the second log, but with cl-return-from the dolist continues."
  (let* ((test-root "/tmp/test-bv-signal-1-second")
         (log-dir (expand-file-name "var/log/" test-root))
         (old-default default-directory))
    (unwind-protect
        (progn
          (fset 'gptel-auto-workflow--expand-workspace-path
                (lambda (&rest _) test-root))
          (make-directory log-dir t)
          (with-temp-file (expand-file-name "01.log" log-dir)
            (insert "Unrelated error in some-other-file.el\n"))
          (with-temp-file (expand-file-name "02.log" log-dir)
            (insert "ERROR: target mentioned here: my-target-basename.el\n"))
          (let* ((result (gptel-auto-workflow--compute-local-business-value
                          "my-target-basename.el"))
                 (tickets (plist-get result :support-tickets-reduced)))
            (should (= tickets 1))))
      (delete-directory test-root t)
      (fmakunbound 'gptel-auto-workflow--expand-workspace-path)
      (setq default-directory old-default))))
