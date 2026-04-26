;;; init-system.el --- Core performance and system integration -*- no-byte-compile: t; lexical-binding: t; -*-

(provide 'init-system)

;; Load theme and visual customizations
(require 'theme-setting)

;; Load decoupled modules
(require 'init-files)
(require 'init-editor)

;; compile-angel: Byte-compile and native-compile Elisp code automatically
(use-package compile-angel
  :ensure t
  :init
  (setq package-native-compile nil)
  (setq compile-angel-verbose nil)
  :config
  (add-to-list 'compile-angel-excluded-files "/ai-code-behaviors.el")
  (push "/init.el" compile-angel-excluded-files)
  (push "/early-init.el" compile-angel-excluded-files)
  (push "/pre-init.el" compile-angel-excluded-files)
  (push "/post-init.el" compile-angel-excluded-files)
  (push "/pre-early-init.el" compile-angel-excluded-files)
  (push "/post-early-init.el" compile-angel-excluded-files)
  :hook (emacs-startup . (lambda ()
                           (unless (or noninteractive
                                       (and (fboundp 'my/workflow-daemon-p)
                                            (my/workflow-daemon-p)))
                              (compile-angel-on-load-mode 1)))))

;; Environment Variable Synchronization (Essential for macOS users)
(use-package exec-path-from-shell
  :if (or (display-graphic-p) (daemonp))
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

;; ============================================================
;; Built-in Enhancements (No external packages required)
;; ============================================================

;; Window configuration undo/redo (C-c <left>, C-c <right>)
(winner-mode 1)

;; Auto-pairing parentheses, quotes, brackets
(electric-pair-mode 1)

;;; init-system.el ends here
