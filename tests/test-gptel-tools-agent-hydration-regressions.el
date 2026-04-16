;;; test-gptel-tools-agent-hydration-regressions.el --- Hydration regressions -*- lexical-binding: t; -*-

;;; Commentary:
;; Focused regressions for workflow submodule hydration edge cases.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent)

(ert-deftest regression/auto-workflow/hydrate-staging-submodules-removes-stale-target-before-add ()
  "Hydration should remove a stale target dir before adding the submodule worktree."
  (let* ((root (make-temp-file "staging-root" t))
         (shared-git-dir (make-temp-file "shared-gptel" t))
         (target (expand-file-name "packages/gptel" root))
         saw-add)
    (unwind-protect
        (progn
          (make-directory target t)
          (with-temp-file (expand-file-name "stale.txt" target)
            (insert "stale"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--staging-submodule-paths)
                     (lambda (&optional _worktree)
                       '("packages/gptel")))
                    ((symbol-function 'gptel-auto-workflow--staging-submodule-gitlink-revision)
                     (lambda (_worktree _path)
                       "abc123"))
                    ((symbol-function 'gptel-auto-workflow--shared-submodule-git-dir)
                     (lambda (_path &optional _commit)
                       shared-git-dir))
                    ((symbol-function 'gptel-auto-workflow--truncate-hash)
                     (lambda (commit)
                       commit))
                    ((symbol-function 'gptel-auto-workflow--git-result)
                     (lambda (command &optional _timeout)
                       (when (string-match-p "worktree add --detach --force" command)
                         (setq saw-add t)
                         (should-not (file-exists-p target)))
                       (cons "" 0))))
            (let ((delete-by-moving-to-trash t))
              (should (equal (gptel-auto-workflow--hydrate-staging-submodules root)
                             '("Hydrated submodules: packages/gptel=abc123" . 0))))
            (should saw-add)))
      (delete-directory root t)
      (delete-directory shared-git-dir t))))

;;; test-gptel-tools-agent-hydration-regressions.el ends here
