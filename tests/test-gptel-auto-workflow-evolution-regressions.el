;;; test-gptel-auto-workflow-evolution-regressions.el --- Evolution regressions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-evolution.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

(ert-deftest regression/auto-workflow-evolution/insufficient-data-returns-skip-message ()
  "Pipeline callers should see a textual skip reason, not bare nil."
  (cl-letf (((symbol-function 'gptel-auto-workflow--evolution-count-new)
             (lambda () 0)))
    (should (string-match-p "Insufficient new data"
                            (gptel-auto-workflow-evolution-run-cycle)))))

(ert-deftest regression/auto-workflow-evolution/record-score-accepts-legacy-alist-history ()
  "Score history written with alist JSON should not trip `plist-put'."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (let ((score-file (expand-file-name "var/tmp/evolution-scores.json" root)))
          (make-directory (file-name-directory score-file) t)
          (with-temp-file score-file
            (insert "{\"scores\":{\"timestamp\":[\"2026-05-15T00:37\",\"score\",0.1,\"total\",1]},\"best\":0.1,\"last-score\":0.1,\"last-total\":1}"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () root))
                    ((symbol-function 'gptel-auto-workflow--parse-all-results)
                     (lambda () (list '(:decision "kept") '(:decision "discarded")))))
            (should (= (gptel-auto-workflow--evolution-count-new) 1))
            (should (= (gptel-auto-workflow--evolution-record-score) 0.5))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-has-no-blank-eof ()
  "Synthesized research insight pages should satisfy `git diff --check'."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should
           (gptel-auto-workflow--synthesize-research-knowledge
            "test-strategy"
            (list '(:decision "kept" :target "a.el")
                  '(:decision "discarded" :target "b.el")
                  '(:decision "discarded" :target "c.el"))))
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "mementum/knowledge/research-insights-test-strategy.md" root))
            (should-not (string-match-p "\n\n\\'" (buffer-string)))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-skips-rejected-strategy-labels ()
  "Rejected strategy evolution diagnostics must not become active knowledge pages."
  (let ((root (make-temp-file "aw-evolution" t))
        (strategy "[strategy-evolution] REJECTED candidate: Proposed name 'failure-weighted-skills' is generic (must be descriptive)"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not
           (gptel-auto-workflow--synthesize-research-knowledge
            strategy
            (list '(:decision "kept" :target "a.el")
                  '(:decision "kept" :target "b.el")
                  '(:decision "discarded" :target "c.el"))))
          (should-not (file-directory-p (expand-file-name "mementum/knowledge" root))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-skips-zero-kept-strategies ()
  "A strategy with no kept experiments should not be promoted to knowledge."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not
           (gptel-auto-workflow--synthesize-research-knowledge
            "pattern-driven-skills"
            (list '(:decision "discarded" :target "a.el")
                  '(:decision "discarded" :target "b.el")
                  '(:decision "validation-failed" :target "c.el"))))
          (should-not (file-directory-p (expand-file-name "mementum/knowledge" root))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-skips-placeholder-strategies ()
  "Placeholder strategy labels should not be promoted to knowledge."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not
           (gptel-auto-workflow--synthesize-research-knowledge
            "Unknown"
            (list '(:decision "kept" :target "a.el")
                  '(:decision "kept" :target "b.el")
                  '(:decision "discarded" :target "c.el"))))
          (should-not (file-directory-p (expand-file-name "mementum/knowledge" root))))
      (delete-directory root t))))

(provide 'test-gptel-auto-workflow-evolution-regressions)

;;; test-gptel-auto-workflow-evolution-regressions.el ends here
