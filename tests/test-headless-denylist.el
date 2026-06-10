;;; test-headless-denylist.el --- TDD: headless target denylist -*- lexical-binding: t; -*-

;; Verifies that targets in `gptel-auto-workflow-headless-target-denylist'
;; are skipped during headless runs, and non-denylisted targets pass.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load strategic module (contains denylist and skip logic)
(unless (featurep 'gptel-auto-workflow-strategic)
  (load (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el"
                          default-directory)))

(ert-deftest tdd/headless-denylist/skips-denylisted-target ()
  "A target in the denylist is skipped during headless runs."
  (let ((gptel-auto-workflow--headless t)
        (gptel-auto-workflow-persistent-headless nil)
        (gptel-auto-workflow--cron-job-running nil)
        (gptel-auto-workflow-headless-target-denylist
         '("lisp/modules/gptel-auto-workflow-strategic.el")))
    (should (gptel-auto-workflow--skip-headless-target-p
             "lisp/modules/gptel-auto-workflow-strategic.el"))))

(ert-deftest tdd/headless-denylist/allows-non-denylisted-target ()
  "A target NOT in the denylist passes headless skip check."
  (let ((gptel-auto-workflow--headless t)
        (gptel-auto-workflow-persistent-headless nil)
        (gptel-auto-workflow--cron-job-running nil)
        (gptel-auto-workflow-headless-target-denylist
         '("lisp/modules/gptel-auto-workflow-strategic.el")))
    (should-not (gptel-auto-workflow--skip-headless-target-p
                 "lisp/modules/gptel-agent-loop.el"))))

(ert-deftest tdd/headless-denylist/allows-all-when-not-headless ()
  "When not in headless mode, no targets are skipped."
  (let ((gptel-auto-workflow--headless nil)
        (gptel-auto-workflow-persistent-headless nil)
        (gptel-auto-workflow--cron-job-running nil)
        (gptel-auto-workflow-headless-target-denylist
         '("lisp/modules/gptel-auto-workflow-strategic.el")))
    (should-not (gptel-auto-workflow--skip-headless-target-p
                 "lisp/modules/gptel-auto-workflow-strategic.el"))))

(ert-deftest tdd/dir-locals/no-denylisted-targets-configured ()
  ".dir-locals.el targets must not include any denylisted files."
  (let ((denylist (if (boundp 'gptel-auto-workflow-headless-target-denylist)
                      gptel-auto-workflow-headless-target-denylist
                    nil))
        ;; Simulate what .dir-locals.el sets
        (targets '("lisp/modules/gptel-auto-workflow-projects.el"
                   "lisp/modules/gptel-agent-loop.el"
                   "lisp/modules/gptel-tools-apply.el"
                   "lisp/modules/gptel-tools-agent-error.el"
                   "lisp/modules/gptel-benchmark-subagent.el")))
    ;; If denylist is not yet loaded, load it
    (when (null denylist)
      (let ((strat-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el"
                                          default-directory)))
        (when (file-readable-p strat-file)
          (load strat-file nil 'nomessage)
          (setq denylist gptel-auto-workflow-headless-target-denylist))))
    (dolist (target targets)
      (should (not (member target denylist))))))

(provide 'test-headless-denylist)
;;; test-headless-denylist.el ends here
