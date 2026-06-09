(ert-deftest tdd/evolution/condition-case-err-binding-survives-handler ()
  (condition-case err
      (signal 'error "test error")
    (error (should (stringp (error-message-string err))))))

(ert-deftest tdd/evolution/nested-condition-case-err-in-inner-handler ()
  (let ((captured nil))
    (condition-case nil
        (condition-case err
            (error "test")
          (error (setq captured err)))
      (error nil))
    (should captured)
    (should (string-match "test" (error-message-string captured)))))

(ert-deftest tdd/evolution/experiment-run-trigger-handler-references-err ()
  (let ((captured-message nil))
    (condition-case nil
        (let ((new-experiments 0))
          (when (<= new-experiments 0)
            (condition-case err
                (progn
                  (error "triggered error")
                  nil)
              (error (setq captured-message (format "Experiment run error: %s" err))))))
      (error nil))
    (should captured-message)
    (should (string-match "triggered error" captured-message))))

(ert-deftest tdd/evolution/exact-bug-pattern-with-require-and-async ()
  (let ((captured-message nil)
        (require-called nil))
    (condition-case nil
        (let ((new-experiments 0))
          (when (<= new-experiments 0)
            (condition-case err
                (progn
                  (setq require-called t)
                  (error "async failed")
                  nil)
              (error (setq captured-message (format "Experiment run error: %s" err))))))
      (error (princ (format "OUTER CAUGHT: %s\n" (error-message-string err)))))
    (should require-called)
    (should captured-message)
    (should (string-match "async failed" captured-message))))

(ert-deftest tdd/evolution/source-uses-unique-err-variable-name ()
  "Regression: the log showed 'void-variable err' repeatedly. The
fix renames the inner condition-case's err to 'trigger-err' to
avoid clashing with err variables in the call chain (e.g., from
gptel-auto-workflow-run-async which has multiple condition-case err
blocks). This test verifies the renamed variable is in use."
  (let ((source (with-temp-buffer
                  (insert-file-contents "lisp/modules/gptel-auto-workflow-evolution.el")
                  (buffer-string))))
    (with-temp-buffer
      (insert source)
      (goto-char (point-min))
      (let ((found-trigger nil)
            (found-handler nil)
            (found-old-err nil))
        (when (re-search-forward "No new experiments to analyze. Triggering experiment run" nil t)
          (setq found-trigger t)
          ;; After this point: find condition-case form
          (let ((block-start (point))
                (block-end (progn (re-search-forward "cl-return-from gptel-auto-workflow-evolution-run-cycle" nil t)
                                  (line-end-position))))
            (goto-char block-start)
            ;; The block now contains the trigger. Check for trigger-err
            ;; (renamed) and NOT plain err (would indicate bug not fixed).
            (when (re-search-forward "condition-case trigger-err" block-end t)
              (setq found-handler t))
            (goto-char block-start)
            (when (re-search-forward "condition-case err$\\|condition-case err[^a-z-]" block-end t)
              (setq found-old-err t))))
        (should found-trigger)
        (should found-handler)
        (should-not found-old-err)))))

(provide 'test-evolution-err-binding)
;;; test-evolution-err-binding.el ends here
