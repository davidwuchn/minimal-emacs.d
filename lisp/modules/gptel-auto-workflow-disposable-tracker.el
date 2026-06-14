;;; gptel-auto-workflow-disposable-tracker.el --- Persistent disposable module tracking -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: disposable, regeneration, module-tracking

;;; Commentary:

;; Tracks which modules are candidates for code regeneration.
;; Persists to var/disposable/<module-slug>.edn sidecar files.
;; Survives daemon restarts.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'parseedn)
(require 'gptel-tools-agent-experiment-loop)

;; ============================================================================
;; Configuration
;; ============================================================================

(defcustom gptel-auto-workflow-disposable-dir "var/disposable"
  "Directory for disposable module tracking sidecars."
  :type 'string
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow-disposable-min-experiments 5
  "Minimum experiments before a module is considered for disposable tracking.")

(defvar gptel-auto-workflow-disposable-max-delta 0.05
  "Maximum score delta for a module to be marked disposable (stagnant improvement).")

;; ============================================================================
;; Helpers
;; ============================================================================

(defun gptel-auto-workflow-disposable--dir ()
  "Return the disposable tracking directory."
  (let ((root (if (fboundp 'gptel-auto-workflow--worktree-base-root)
                  (gptel-auto-workflow--worktree-base-root)
                user-emacs-directory)))
    (expand-file-name gptel-auto-workflow-disposable-dir root)))

(defun gptel-auto-workflow-disposable--slug (module)
  "Create filesystem-safe slug from MODULE path."
  (replace-regexp-in-string "[^a-zA-Z0-9_-]" "-"
                             (downcase (file-name-nondirectory module))))

(defun gptel-auto-workflow-disposable--file (module)
  "Return sidecar file path for MODULE."
  (expand-file-name (format "%s.edn" (gptel-auto-workflow-disposable--slug module))
                    (gptel-auto-workflow-disposable--dir)))

;; ============================================================================
;; CRUD
;; ============================================================================

(defun gptel-auto-workflow-disposable-mark (module &rest props)
  "Mark MODULE as disposable with optional PROPS.
Writes an EDN sidecar file with :module, :marked-at, and any PROPS."
  (let* ((file (gptel-auto-workflow-disposable--file module))
         (existing (gptel-auto-workflow-disposable-read module))
         (entry (append (list :module module
                              :marked-at (float-time)
                              :status "disposable")
                        props
                        (when existing
                          (list :history (plist-get existing :history))))))
    (make-directory (file-name-directory file) t)
    (gptel-auto-workflow--write-edn file entry)
    (message "[disposable] Marked: %s" (file-name-nondirectory module))
    entry))

(defun gptel-auto-workflow-disposable-unmark (module)
  "Unmark MODULE as disposable. Removes the sidecar file."
  (let ((file (gptel-auto-workflow-disposable--file module)))
    (when (file-exists-p file)
      (delete-file file)
      (message "[disposable] Unmarked: %s" (file-name-nondirectory module))
      t)))

(defun gptel-auto-workflow-disposable-read (module)
  "Read disposable tracking entry for MODULE. Returns plist or nil."
  (gptel-auto-workflow--read-edn (gptel-auto-workflow-disposable--file module)))

(defun gptel-auto-workflow-disposable-list ()
  "Return list of all tracked disposable modules."
  (let ((dir (gptel-auto-workflow-disposable--dir))
        (entries nil))
    (when (file-directory-p dir)
      (dolist (f (directory-files dir t "\\.edn$"))
        (let ((entry (gptel-auto-workflow--read-edn f)))
          (when (and entry (plist-get entry :module))
            (push entry entries)))))
    (nreverse entries)))

(defun gptel-auto-workflow-disposable-status (module)
  "Return status of MODULE: :disposable, :persistent, or :unknown."
  (let ((entry (gptel-auto-workflow-disposable-read module)))
    (if entry
        (intern (or (plist-get entry :status) "disposable"))
      :persistent)))

;; ============================================================================
;; Auto-detection from context database
;; ============================================================================

(defun gptel-auto-workflow-disposable-auto-detect ()
  "Scan context database for modules with stagnant improvement.
Marks modules as disposable if they have enough history but low score delta.
Returns list of newly marked modules."
  (let ((newly-marked nil))
    (when (fboundp 'gptel-auto-workflow-context-db-query)
      (condition-case nil
          (let* ((all-contexts (gptel-auto-workflow-context-db-query))
                 (by-target (make-hash-table :test 'equal)))
            ;; Group by target
            (dolist (ctx all-contexts)
              (let ((target (or (plist-get ctx :target) "")))
                (when (and target (not (string-empty-p target)))
                  (puthash target
                           (cons ctx (gethash target by-target))
                           by-target))))
            ;; Check each target
            (maphash
             (lambda (target contexts)
               (when (>= (length contexts) gptel-auto-workflow-disposable-min-experiments)
                 (let ((best-delta 0.0))
                   (dolist (ctx contexts)
                     (let* ((before (or (plist-get ctx :score-before) 0.0))
                            (after (or (plist-get ctx :score-after) 0.0))
                            (delta (- after before)))
                       (when (> delta best-delta)
                         (setq best-delta delta))))
                   ;; Mark if stagnant and not already tracked
                   (when (and (< best-delta gptel-auto-workflow-disposable-max-delta)
                              (not (gptel-auto-workflow-disposable-read target)))
                     (gptel-auto-workflow-disposable-mark
                      target
                      :best-delta best-delta
                      :experiment-count (length contexts))
                     (push target newly-marked)))))
             by-target))
        (error nil)))
    newly-marked))

(provide 'gptel-auto-workflow-disposable-tracker)
;;; gptel-auto-workflow-disposable-tracker.el ends here
