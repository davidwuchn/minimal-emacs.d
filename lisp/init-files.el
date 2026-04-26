;;; init-files.el --- File management, history, backup & no-littering -*- no-byte-compile: t; lexical-binding: t; -*-

(provide 'init-files)

;; ==============================================================================
;; FILE MANAGEMENT, HISTORY & SAFETY
;; ==============================================================================

(use-package autorevert
  :ensure nil
  :hook (after-init . global-auto-revert-mode)
  :init
  (setq auto-revert-interval 3
        auto-revert-remote-files nil
        auto-revert-use-notify t
        auto-revert-avoid-polling nil
        auto-revert-verbose t))

(defun my/enable-recentf-mode-if-appropriate ()
  "Enable `recentf-mode' unless this is a dedicated workflow daemon."
  (unless (and (fboundp 'my/workflow-daemon-p)
               (my/workflow-daemon-p))
    (recentf-mode 1)))

(use-package recentf
  :ensure nil
  :hook (after-init . my/enable-recentf-mode-if-appropriate)
  :init
  (setq recentf-auto-cleanup (if (daemonp) 300 'never)
        recentf-exclude
        (list "\\.tar$" "\\.tbz2$" "\\.tbz$" "\\.tgz$" "\\.bz2$"
              "\\.bz$" "\\.gz$" "\\.gzip$" "\\.xz$" "\\.zip$"
              "\\.7z$" "\\.rar$"
              "COMMIT_EDITMSG\\'"
              "\\.\\(?:gz\\|gif\\|svg\\|png\\|jpe?g\\|bmp\\|xpm\\)$"
              "-autoloads\\.el$" "autoload\\.el$"))
  :config
  (unless (and (fboundp 'my/workflow-daemon-p)
               (my/workflow-daemon-p))
    (add-hook 'kill-emacs-hook #'recentf-cleanup -90)))

(use-package savehist
  :ensure nil
  :hook (after-init . savehist-mode)
  :init
  (setq history-length 300
        savehist-autosave-interval 600))

(use-package saveplace
  :ensure nil
  :hook (after-init . save-place-mode)
  :init
  (setq save-place-limit 400))

;; ==============================================================================
;; BACKUP, AUTO-SAVE & LOCK FILES
;; ==============================================================================

;; Backup configuration - versioned backups in var/backup/
(setq backup-directory-alist
      `(("." . ,(expand-file-name "backup/" user-emacs-directory))))
(setq tramp-backup-directory-alist backup-directory-alist)
(setq backup-by-copying t)            ; Backup by copying, not renaming
(setq backup-by-copying-when-linked t)
(setq version-control t)              ; Use version numbers (file.~1~, file.~2~, etc.)
(setq delete-old-versions t)          ; Delete excess backups silently
(setq kept-new-versions 10)           ; Keep 10 newest versions
(setq kept-old-versions 5)            ; Keep 5 oldest versions
(setq make-backup-files t)            ; Enable backups (overrides init.el)

;; Auto-save configuration (match upstream: autosave/)
(setq auto-save-default t)
(setq auto-save-interval 300)         ; Save every 300 keystrokes
(setq auto-save-timeout 30)           ; Or after 30 seconds of idle time
(setq auto-save-visited-interval 5)   ; auto-save-visited-mode interval
(setq auto-save-no-message t)         ; Don't show "Auto-saving..." messages
(setq auto-save-include-big-deletions t) ; Don't disable auto-save after big deletions
(setq kill-buffer-delete-auto-save-files t) ; Clean up auto-save files when killing buffer

;; Auto-save file locations (match upstream: autosave/)
(setq auto-save-list-file-prefix
      (expand-file-name "autosave/" user-emacs-directory))
(setq tramp-auto-save-directory
      (expand-file-name "tramp-autosave/" user-emacs-directory))
(setq auto-save-file-name-transforms
      `((".*" ,(file-name-concat auto-save-list-file-prefix "\\2-") sha1)))

;; Enable auto-save-visited-mode for automatic buffer saving
(auto-save-visited-mode 1)

;; Lock file configuration - prevent simultaneous edits
(setq create-lockfiles t)
(setq lock-file-name-transforms
      `((".*" ,(expand-file-name "lockfiles/" user-emacs-directory) t)))

;; Prevent world-readable backup files (security)
;; backup-file-modes does not exist in Emacs; backup permissions follow umask

;; ==============================================================================
;; NO-LITTERING: Keep var/ clean
;; ==============================================================================

;; Ensure var subdirectories exist
;; Upstream directories: backup, autosave, tramp-autosave
;; Local additions: cache, savefile, lockfiles, tmp
(let ((dirs '("backup" "autosave" "tramp-autosave" "cache" "savefile" "lockfiles" "tmp")))
  (dolist (dir dirs)
    (let ((path (expand-file-name dir user-emacs-directory)))
      (unless (file-directory-p path)
        (make-directory path t)))))

;; Package elpa directory already set in pre-early-init.el
;; Additional package-specific cleanup

(defun my/package-repair-autoloads (&optional regenerate-all)
  "Regenerate package autoload files under `package-user-dir'.

With prefix argument REGENERATE-ALL, rebuild autoloads for every installed
package.  Otherwise, only recreate missing `*-autoloads.el' files.  Refresh
`package-quickstart-file' after any changes."
  (interactive "P")
  (require 'package)
  (package-initialize)
  (let ((generated 0)
        (checked 0))
    (dolist (entry package-alist)
      (let* ((name (symbol-name (car entry)))
             (desc (car (cdr entry)))
             (dir (and desc (package-desc-dir desc)))
             (autoload-file (and dir
                                 (expand-file-name (format "%s-autoloads.el" name)
                                                   dir))))
        (when (and dir (file-directory-p dir))
          (setq checked (1+ checked))
          (when (or regenerate-all
                    (not (file-exists-p autoload-file)))
            (package-generate-autoloads name dir)
            (setq generated (1+ generated))))))
    (when (and (> generated 0)
               (fboundp 'package-quickstart-refresh))
      (package-quickstart-refresh))
    (message "Autoload repair checked %d packages, regenerated %d%s"
             checked
             generated
             (if regenerate-all " (full rebuild)" ""))))

;; Eshell history and directories
(setq eshell-directory-name
      (expand-file-name "eshell/" user-emacs-directory))

;; Projectile cache (if used)
(setq projectile-cache-file
      (expand-file-name "cache/projectile.cache" user-emacs-directory))
(setq projectile-known-projects-file
      (expand-file-name "cache/projectile-projects.cache" user-emacs-directory))

;; Recentf file
(setq recentf-save-file
      (expand-file-name "recentf" user-emacs-directory))

;; Saveplace file (match upstream: saveplace file in var/)
(setq save-place-file
      (expand-file-name "saveplace" user-emacs-directory))

;; Abbrev file (match upstream: abbrev_defs file in var/)
(setq abbrev-file-name
      (expand-file-name "abbrev_defs" user-emacs-directory))

;; Custom file (already using custom.el in root, but ensure path)
(setq custom-file
      (expand-file-name "custom.el" minimal-emacs-user-directory))

;; Gnus (if ever used)
(setq gnus-directory
      (expand-file-name "gnus/" user-emacs-directory))

;; Bookmark file
(setq bookmark-default-file
      (expand-file-name "bookmarks" user-emacs-directory))

;; Ido last file
(setq ido-last-file
      (expand-file-name "ido.last" user-emacs-directory))

;; Register file
(setq register-file
      (expand-file-name "registers" user-emacs-directory))

;; Dabbrev expansion cache
(setq dabbrev--last-buffer-file-name nil) ; Reset on session

;; Savehist file (command history)
(setq savehist-file
      (expand-file-name "history" user-emacs-directory))

;; Project list file
(setq project-list-file
      (expand-file-name "projects" user-emacs-directory))

;; Tramp persistence
(setq tramp-persistency-file-name
      (expand-file-name "tramp" user-emacs-directory))

;;; init-files.el ends here
