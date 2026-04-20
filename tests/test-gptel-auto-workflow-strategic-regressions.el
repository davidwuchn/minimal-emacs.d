;;; test-gptel-auto-workflow-strategic-regressions.el --- Regressions for strategic selection -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'gptel-auto-workflow-strategic)

(ert-deftest regression/auto-workflow-strategic/parse-targets-keeps-analyzer-quota-separate-from-executor-quota ()
  "Analyzer quota errors should not trip the executor quota flag."
  (let ((gptel-auto-experiment--quota-exhausted nil)
        (gptel-auto-workflow--analyzer-transient-failure nil)
        (gptel-auto-workflow--analyzer-quota-exhausted nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
               (lambda () "/tmp/project"))
              ((symbol-function 'message)
               (lambda (&rest _args) nil)))
      (should-not
       (gptel-auto-workflow--parse-targets
        "Error: Task analyzer could not finish task. Error details: (:type \"rate_limit_error\" :message \"usage limit exceeded (2056)\" :http_code \"429\")"))
       (should gptel-auto-workflow--analyzer-quota-exhausted)
       (should-not gptel-auto-workflow--analyzer-transient-failure)
       (should-not gptel-auto-experiment--quota-exhausted))))

(ert-deftest regression/auto-workflow-strategic/ask-analyzer-uses-dedicated-time-budget ()
  "Target selection should use the dedicated analyzer timeout budget."
  (let ((gptel-auto-experiment-use-subagents t)
        (gptel-auto-workflow-analyzer-time-budget 120)
        (my/gptel-agent-task-timeout 60)
        captured-timeout
        parsed-targets)
    (cl-letf (((symbol-function 'gptel-auto-workflow--gather-context)
               (lambda () '(:git-history "" :file-sizes "" :file-list "" :todos "")))
              ((symbol-function 'gptel-auto-workflow--build-analyzer-prompt)
               (lambda (&rest _) "Prompt body"))
              ((symbol-function 'gptel-auto-workflow--parse-targets)
               (lambda (_response) '("lisp/modules/target.el")))
              ((symbol-function 'gptel-benchmark-call-subagent)
               (lambda (_type _description _prompt callback &optional timeout)
                 (setq captured-timeout timeout)
                 (funcall callback "[]"))))
      (gptel-auto-workflow--ask-analyzer-with-findings
       nil
       (lambda (targets)
         (setq parsed-targets targets)))
      (should (= captured-timeout 120))
      (should (equal parsed-targets '("lisp/modules/target.el"))))))

(ert-deftest regression/auto-workflow-strategic/ask-analyzer-keeps-higher-global-timeout ()
  "Analyzer target selection should not shorten a larger global timeout."
  (let ((gptel-auto-experiment-use-subagents t)
        (gptel-auto-workflow-analyzer-time-budget 120)
        (my/gptel-agent-task-timeout 300)
        captured-timeout)
    (cl-letf (((symbol-function 'gptel-auto-workflow--gather-context)
               (lambda () '(:git-history "" :file-sizes "" :file-list "" :todos "")))
              ((symbol-function 'gptel-auto-workflow--build-analyzer-prompt)
               (lambda (&rest _) "Prompt body"))
              ((symbol-function 'gptel-auto-workflow--parse-targets)
               (lambda (_response) nil))
              ((symbol-function 'gptel-benchmark-call-subagent)
               (lambda (_type _description _prompt callback &optional timeout)
                 (setq captured-timeout timeout)
                 (funcall callback "[]"))))
      (gptel-auto-workflow--ask-analyzer-with-findings nil #'ignore)
      (should (= captured-timeout 300)))))

(ert-deftest regression/auto-workflow-strategic/ask-analyzer-retries-on-provider-failover ()
  "Analyzer target selection should rerun once on the promoted failover provider."
  (let ((gptel-auto-experiment-use-subagents t)
        (gptel-auto-workflow-analyzer-time-budget 120)
        (my/gptel-agent-task-timeout 60)
        (call-count 0)
        (selected nil)
        (messages nil)
        (gptel-auto-workflow--analyzer-transient-failure nil)
        (gptel-auto-workflow--analyzer-quota-exhausted nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--gather-context)
               (lambda () '(:git-history "" :file-sizes "" :file-list "" :todos "")))
              ((symbol-function 'gptel-auto-workflow--build-analyzer-prompt)
               (lambda (&rest _) "Prompt body"))
              ((symbol-function 'gptel-auto-workflow--analyzer-failover-candidate)
               (lambda ()
                 (and (= call-count 1)
                      '("DashScope" . "qwen3.6-plus"))))
              ((symbol-function 'gptel-auto-workflow--parse-targets)
               (lambda (_response)
                 (if (= call-count 1)
                     (progn
                       (setq gptel-auto-workflow--analyzer-quota-exhausted t)
                       nil)
                   '("lisp/modules/fallback-target.el"))))
              ((symbol-function 'gptel-benchmark-call-subagent)
               (lambda (_type _description _prompt callback &optional _timeout)
                 (cl-incf call-count)
                 (funcall callback "[]")))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (gptel-auto-workflow--ask-analyzer-with-findings
       nil
       (lambda (targets)
         (setq selected targets)))
      (should (= call-count 2))
      (should (equal selected '("lisp/modules/fallback-target.el")))
      (should-not gptel-auto-workflow--analyzer-quota-exhausted)
      (should
       (member
        "[auto-workflow] Retrying analyzer target selection with DashScope/qwen3.6-plus"
        messages)))))

(ert-deftest regression/auto-workflow-strategic/select-targets-falls-back-on-analyzer-transient-failure ()
  "Transient analyzer failures should use static targets."
  (let ((gptel-auto-workflow-strategic-selection t)
        (gptel-auto-workflow-targets '("ignored.el"))
        (selected nil)
        (messages nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
               (lambda () "/tmp/project"))
              ((symbol-function 'gptel-auto-workflow--filter-valid-targets)
               (lambda (&rest _args) '("lisp/modules/static-target.el")))
              ((symbol-function 'gptel-auto-workflow--ask-analyzer-for-targets)
               (lambda (callback)
                 (setq gptel-auto-workflow--analyzer-transient-failure t)
                 (funcall callback nil)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (gptel-auto-workflow-select-targets
       (lambda (targets)
         (setq selected targets)))
      (should (equal selected '("lisp/modules/static-target.el")))
      (should (member "[auto-workflow] Analyzer transient failure; using static targets"
                      messages)))))

(ert-deftest regression/auto-workflow-strategic/select-targets-falls-back-on-analyzer-quota ()
  "Analyzer quota exhaustion should use static targets without tripping executor quota."
  (let ((gptel-auto-workflow-strategic-selection t)
        (gptel-auto-workflow-targets '("ignored.el"))
        (gptel-auto-experiment--quota-exhausted nil)
        (selected nil)
        (messages nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
               (lambda () "/tmp/project"))
              ((symbol-function 'gptel-auto-workflow--filter-valid-targets)
               (lambda (&rest _args) '("lisp/modules/static-target.el")))
              ((symbol-function 'gptel-auto-workflow--ask-analyzer-for-targets)
               (lambda (callback)
                 (setq gptel-auto-workflow--analyzer-quota-exhausted t)
                 (funcall callback nil)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (gptel-auto-workflow-select-targets
       (lambda (targets)
         (setq selected targets)))
      (should (equal selected '("lisp/modules/static-target.el")))
       (should-not gptel-auto-experiment--quota-exhausted)
       (should (member "[auto-workflow] Analyzer quota exhausted; using static targets"
                       messages)))))

(ert-deftest regression/auto-workflow-strategic/select-targets-falls-back-after-analyzer-failover-retry ()
  "Analyzer target selection should use static targets if the failover retry also fails."
  (let ((gptel-auto-workflow-strategic-selection t)
        (gptel-auto-experiment-use-subagents t)
        (gptel-auto-workflow-targets '("ignored.el"))
        (selected nil)
        (call-count 0)
        (messages nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
               (lambda () "/tmp/project"))
              ((symbol-function 'gptel-auto-workflow--gather-context)
               (lambda () '(:git-history "" :file-sizes "" :file-list "" :todos "")))
              ((symbol-function 'gptel-auto-workflow--build-analyzer-prompt)
               (lambda (&rest _) "Prompt body"))
              ((symbol-function 'gptel-auto-workflow--filter-valid-targets)
               (lambda (&rest _args) '("lisp/modules/static-target.el")))
              ((symbol-function 'gptel-auto-workflow--analyzer-failover-candidate)
               (lambda ()
                 (and (= call-count 1)
                      '("DashScope" . "qwen3.6-plus"))))
              ((symbol-function 'gptel-auto-workflow--parse-targets)
               (lambda (_response)
                 (setq gptel-auto-workflow--analyzer-quota-exhausted t)
                 nil))
              ((symbol-function 'gptel-benchmark-call-subagent)
               (lambda (_type _description _prompt callback &optional _timeout)
                 (cl-incf call-count)
                 (funcall callback "[]")))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) messages))))
      (gptel-auto-workflow-select-targets
       (lambda (targets)
         (setq selected targets)))
      (should (= call-count 2))
      (should (equal selected '("lisp/modules/static-target.el")))
      (should
       (member
        "[auto-workflow] Retrying analyzer target selection with DashScope/qwen3.6-plus"
        messages))
      (should (member "[auto-workflow] Analyzer quota exhausted; using static targets"
                      messages)))))

(ert-deftest regression/auto-workflow-strategic/filter-valid-targets-rejects-nested-repos ()
  "Nested git repos should not be selected by the root workflow."
  (let* ((proj-root (make-temp-file "aw-strategic" t))
         (root-git (expand-file-name ".git" proj-root))
         (root-file (expand-file-name "lisp/modules/foo.el" proj-root))
         (nested-root (expand-file-name "packages/gptel" proj-root))
         (nested-git (expand-file-name ".git" nested-root))
         (nested-file (expand-file-name "packages/gptel/gptel.el" proj-root)))
    (unwind-protect
        (progn
          (make-directory root-git t)
          (make-directory (file-name-directory root-file) t)
          (with-temp-file root-file (insert ";; root\n"))
          (make-directory nested-git t)
          (with-temp-file nested-file (insert ";; nested\n"))
          (should (equal (gptel-auto-workflow--filter-valid-targets
                          '("lisp/modules/foo.el" "packages/gptel/gptel.el")
                          proj-root
                          5)
                         '("lisp/modules/foo.el"))))
      (delete-directory proj-root t))))

(ert-deftest regression/auto-workflow-strategic/filter-valid-targets-skips-self-hosting-tools-in-headless-runs ()
  "Headless runs should skip tool modules that can destabilize the live daemon."
  (let* ((proj-root (make-temp-file "aw-strategic" t))
         (root-git (expand-file-name ".git" proj-root))
         (safe-file (expand-file-name "lisp/modules/foo.el" proj-root))
         (tool-file (expand-file-name "lisp/modules/gptel-tools-code.el" proj-root))
         (messages nil)
         (gptel-auto-workflow--headless t))
    (unwind-protect
        (progn
          (make-directory root-git t)
          (make-directory (file-name-directory safe-file) t)
          (with-temp-file safe-file (insert ";; safe\n"))
          (with-temp-file tool-file (insert ";; tool\n"))
          (cl-letf (((symbol-function 'message)
                     (lambda (format-string &rest args)
                       (push (apply #'format format-string args) messages))))
            (should (equal (gptel-auto-workflow--filter-valid-targets
                            '("lisp/modules/gptel-tools-code.el" "lisp/modules/foo.el")
                            proj-root
                            5)
                           '("lisp/modules/foo.el")))
            (should (member
                     "[auto-workflow] Skipping self-hosting target in headless run: lisp/modules/gptel-tools-code.el"
                     messages))))
      (delete-directory proj-root t))))

(ert-deftest regression/auto-workflow-strategic/filter-valid-targets-keeps-self-hosting-tools-interactively ()
  "Interactive runs should still allow explicit tool-module targets."
  (let* ((proj-root (make-temp-file "aw-strategic" t))
         (root-git (expand-file-name ".git" proj-root))
         (tool-file (expand-file-name "lisp/modules/gptel-tools-code.el" proj-root))
         (gptel-auto-workflow--headless nil))
    (unwind-protect
        (progn
          (make-directory root-git t)
          (make-directory (file-name-directory tool-file) t)
          (with-temp-file tool-file (insert ";; tool\n"))
          (should (equal (gptel-auto-workflow--filter-valid-targets
                          '("lisp/modules/gptel-tools-code.el")
                          proj-root
                          5)
                         '("lisp/modules/gptel-tools-code.el"))))
      (delete-directory proj-root t))))

(ert-deftest regression/auto-workflow-strategic/static-fallback-filters-nested-repos ()
  "Static fallback targets should also exclude nested git repos."
  (let* ((proj-root (make-temp-file "aw-strategic" t))
         (root-git (expand-file-name ".git" proj-root))
         (root-file (expand-file-name "lisp/modules/foo.el" proj-root))
         (nested-root (expand-file-name "packages/gptel" proj-root))
         (nested-git (expand-file-name ".git" nested-root))
         (nested-file (expand-file-name "packages/gptel/gptel.el" proj-root))
         (gptel-auto-workflow-strategic-selection nil)
         (gptel-auto-workflow-targets '("lisp/modules/foo.el" "packages/gptel/gptel.el"))
         (selected nil))
    (unwind-protect
        (progn
          (make-directory root-git t)
          (make-directory (file-name-directory root-file) t)
          (with-temp-file root-file (insert ";; root\n"))
          (make-directory nested-git t)
          (with-temp-file nested-file (insert ";; nested\n"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
                     (lambda () proj-root)))
            (gptel-auto-workflow-select-targets
             (lambda (targets)
               (setq selected targets))))
          (should (equal selected '("lisp/modules/foo.el"))))
      (delete-directory proj-root t))))

(provide 'test-gptel-auto-workflow-strategic-regressions)

;;; test-gptel-auto-workflow-strategic-regressions.el ends here
