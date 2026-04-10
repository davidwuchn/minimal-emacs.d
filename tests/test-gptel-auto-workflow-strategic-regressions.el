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
