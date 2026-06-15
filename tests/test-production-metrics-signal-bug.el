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
