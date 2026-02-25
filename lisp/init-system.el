;;; init-system.el --- Core performance, UI, and file management -*- lexical-binding: t; -*-

(provide 'init-system)

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

;; Auto-save settings
(setq auto-save-default t)
(setq auto-save-interval 300)
(setq auto-save-timeout 30)

(setq auto-save-visited-interval 5)
(auto-save-visited-mode 1)
