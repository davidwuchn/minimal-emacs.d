;;; test-gptel-auto-workflow-strategic-regressions.el --- Regressions for strategic selection -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(require 'gptel-auto-workflow-strategic)

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
