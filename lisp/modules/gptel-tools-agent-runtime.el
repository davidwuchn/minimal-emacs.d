;;; gptel-tools-agent-runtime.el --- Runtime asset seeding for workflow worktrees -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)

(defun gptel-auto-workflow--path-exists-or-symlink-p (path)
  "Return non-nil when PATH exists or is a symlink, including broken links."
  (or (file-exists-p path)
      (file-symlink-p path)))

(defun gptel-auto-workflow--safe-truename (path)
  "Return PATH's truename, or nil when PATH cannot be resolved."
  (condition-case nil
      (file-truename path)
    (error nil)))

(defun gptel-auto-workflow--link-shared-runtime-path (source target)
  "Link SOURCE to TARGET when TARGET is absent or a stale symlink."
  (cond
   ((not (and (stringp source) (stringp target)
              (not (string-empty-p source)) (not (string-empty-p target))))
    nil)
   ((not (gptel-auto-workflow--path-exists-or-symlink-p source))
    nil)
   ((file-symlink-p target)
    (unless (equal (gptel-auto-workflow--safe-truename source)
                   (gptel-auto-workflow--safe-truename target))
      (delete-file target)
      (make-symbolic-link source target t))
    t)
   ((file-exists-p target)
    t)
   (t
    (make-directory (file-name-directory target) t)
    (make-symbolic-link source target t)
    t)))

(defun gptel-auto-workflow--seed-worktree-runtime-var (worktree)
  "Seed ignored runtime `var' assets into workflow-owned WORKTREE.

Staging verification runs repository scripts with WORKTREE as the init
directory, so ignored package/cache assets must be visible there even though
they are not tracked by Git."
  (let* ((base-root-raw (gptel-auto-workflow--worktree-base-root))
         (base-root (and (stringp base-root-raw)
                         (not (string-empty-p base-root-raw))
                         (file-name-as-directory (expand-file-name base-root-raw))))
         (canonical-root (and base-root
                              (not (file-directory-p (expand-file-name "var" base-root)))
                              (gptel-auto-workflow--worktree-base-repo-root)))
         (source-root (and base-root
                           (or (and (stringp canonical-root)
                                    (file-name-as-directory (expand-file-name canonical-root)))
                               base-root)))
         (source-var (expand-file-name "var" source-root))
         (target-var (and worktree (expand-file-name "var" worktree)))
         (linked 0))
    (when (and (stringp worktree)
               (file-directory-p worktree)
               (file-directory-p source-var)
               (not (equal (file-truename worktree)
                           (file-truename source-root))))
      (make-directory target-var t)
      (let ((source-elpa (expand-file-name "elpa" source-var))
            (target-elpa (expand-file-name "elpa" target-var)))
        (when (file-directory-p source-elpa)
          (make-directory target-elpa t)
          (dolist (source (directory-files source-elpa t directory-files-no-dot-files-regexp))
            (when (gptel-auto-workflow--link-shared-runtime-path
                   source
                   (expand-file-name (file-name-nondirectory source) target-elpa))
              (cl-incf linked)))))
      (dolist (rel '("package-quickstart.el" "tree-sitter"))
        (when (gptel-auto-workflow--link-shared-runtime-path
               (expand-file-name rel source-var)
               (expand-file-name rel target-var))
          (cl-incf linked)))
      (when (> linked 0)
        (message "[auto-workflow] Seeded runtime var for %s from %s"
                 worktree
                 source-root))
      t)))

(provide 'gptel-tools-agent-runtime)
;;; gptel-tools-agent-runtime.el ends here
