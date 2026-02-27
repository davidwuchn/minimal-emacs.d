;;; init-system.el --- Core performance, UI, and file management -*- lexical-binding: t; -*-

(provide 'init-system)

;; Load theme and visual customizations
(require 'theme-setting)

;; compile-angel: Byte-compile and native-compile Elisp code automatically
(use-package compile-angel
  :ensure t
  :demand t
  :config
  (setq package-native-compile nil)
  (setq compile-angel-verbose nil)
  (push "/init.el" compile-angel-excluded-files)
  (push "/early-init.el" compile-angel-excluded-files)
  (push "/pre-init.el" compile-angel-excluded-files)
  (push "/post-init.el" compile-angel-excluded-files)
  (push "/pre-early-init.el" compile-angel-excluded-files)
  (push "/post-early-init.el" compile-angel-excluded-files)
  (compile-angel-on-load-mode 1))

;; Environment Variable Synchronization (Essential for macOS users)
(use-package exec-path-from-shell
  :if (and (or (display-graphic-p) (daemonp))
           (eq system-type 'darwin))
  :ensure t
  :demand t
  :functions exec-path-from-shell-initialize
  :config
  (dolist (var '("TMPDIR"
                 "SSH_AUTH_SOCK" "SSH_AGENT_PID"
                 "GPG_AGENT_INFO"
                 "LANG" "LC_CTYPE"))
    (add-to-list 'exec-path-from-shell-variables var))
  (exec-path-from-shell-initialize))


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

(use-package recentf
  :ensure nil
  :hook (after-init . recentf-mode)
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
  (add-hook 'kill-emacs-hook #'recentf-cleanup -90))

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

;; Auto-save configuration - files saved to var/auto-save/
(setq auto-save-default t)
(setq auto-save-interval 300)         ; Save every 300 keystrokes
(setq auto-save-timeout 30)           ; Or after 30 seconds of idle time
(setq auto-save-visited-interval 5)   ; auto-save-visited-mode interval
(setq auto-save-no-message t)         ; Don't show "Auto-saving..." messages
(setq auto-save-include-big-deletions t) ; Don't disable auto-save after big deletions
(setq kill-buffer-delete-auto-save-files t) ; Clean up auto-save files when killing buffer

;; Auto-save file locations
(setq auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" user-emacs-directory) t)))
(setq auto-save-list-file-prefix
      (expand-file-name "auto-save/saves-" user-emacs-directory))
(setq tramp-auto-save-directory
      (expand-file-name "tramp-autosave/" user-emacs-directory))

;; Enable auto-save-visited-mode for automatic buffer saving
(auto-save-visited-mode 1)

;; Lock file configuration - prevent simultaneous edits
(setq create-lockfiles t)
(setq lock-file-name-transforms
      `((".*" ,(expand-file-name "lockfiles/" user-emacs-directory) t)))

;; Prevent world-readable backup files (security)
(setq backup-file-modes '(#o600 #o400))

;; ==============================================================================
;; NO-LITTERING: Keep var/ clean
;; ==============================================================================

;; Ensure var subdirectories exist
(let ((dirs '("backup" "auto-save" "lockfiles" "cache" "tmp")))
  (dolist (dir dirs)
    (let ((path (expand-file-name dir user-emacs-directory)))
      (unless (file-directory-p path)
        (make-directory path t)))))

;; Package elpa directory already set in pre-early-init.el
;; Additional package-specific cleanup

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
      (expand-file-name "savefile/recentf" user-emacs-directory))

;; Saveplace file (already set in init.el, ensure consistency)
(setq save-place-file
      (expand-file-name "savefile/saveplace" user-emacs-directory))

;; Abbrev file
(setq abbrev-file-name
      (expand-file-name "savefile/abbrev_defs" user-emacs-directory))

;; Custom file (already using custom.el in root, but ensure path)
(setq custom-file
      (expand-file-name "custom.el" minimal-emacs-user-directory))

;; Gnus (if ever used)
(setq gnus-directory
      (expand-file-name "gnus/" user-emacs-directory))

;; Bookmark file
(setq bookmark-default-file
      (expand-file-name "savefile/bookmarks" user-emacs-directory))

;; Ido last file
(setq ido-last-file
      (expand-file-name "savefile/ido.last" user-emacs-directory))

;; Register file
(setq register-file
      (expand-file-name "savefile/registers" user-emacs-directory))

;; Dabbrev expansion cache
(setq dabbrev--last-buffer-file-name nil) ; Reset on session

;; ==============================================================================
;; HELP & INTROSPECTION
;; ==============================================================================

(use-package simple
  :ensure nil
  :hook ((text-mode . visual-line-mode)))

(use-package helpful
  :ensure t
  :bind
  ([remap describe-command] . helpful-command)
  ([remap describe-function] . helpful-callable)
  ([remap describe-key] . helpful-key)
  ([remap describe-variable] . helpful-variable)
  ([remap describe-symbol] . helpful-symbol))

;; ==============================================================================
;; QUALITY OF LIFE
;; ==============================================================================

;; which-key: Show available keybindings after prefix keys
(use-package which-key
  :ensure nil  ; built-in Emacs 29+
  :hook (after-init . which-key-mode)
  :custom
  (which-key-idle-delay 1.0)
  (which-key-idle-secondary-delay 0.25))

;; winner-mode: Undo/redo window configurations (C-c <left>/<right>)
(use-package winner
  :ensure nil
  :hook (after-init . winner-mode)
  :custom
  (winner-boring-buffers '("*Completions*"
                           "*Minibuf-0*" "*Minibuf-1*"
                           "*Compile-Log*"
                           "*Help*" "*Apropos*")))
