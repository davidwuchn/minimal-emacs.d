;;; post-init.el --- User configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Personal configuration and overrides. Add your customizations here.
;; This file is loaded after all modular configuration files.

;;; Code:

;; Add the local lisp directory to Emacs' load path using the true root directory
;; (not user-emacs-directory, since we changed that to var/)
(add-to-list 'load-path (expand-file-name "lisp" minimal-emacs-user-directory))

;; Load the modular configuration files
(require 'init-system)
(require 'init-completion)
(require 'init-evil)
(require 'init-dev)
(require 'init-tools)
(require 'init-org)      ; Org mode configuration
(require 'init-ai)

;; Backup and auto-save settings are configured in init-files.el

;; ==============================================================================
;; PERSONAL CUSTOMIZATIONS (Add your own below)
;; ==============================================================================

;; Example: Set your preferred theme
;; (load-theme 'doom-one t)

;; Example: Custom key bindings
;; (global-set-key (kbd "C-c w") #'whitespace-mode)

;; ==============================================================================
;; FIX: Mode-line restoration for buffers created during startup
;; ==============================================================================
;; Upstream early-init.el only restores mode-line for buffers that had
;; minimal-emacs--hidden-mode-line set. Buffers created during startup
;; with nil mode-line are skipped. This fixes that.

(defun my/fix-mode-line-for-all-buffers ()
  "Ensure all buffers have a proper mode-line-format.
Buffers created during startup may have nil mode-line if they
were created after the hiding but before restoration."
  (when (and (boundp 'minimal-emacs-disable-mode-line-during-startup)
             minimal-emacs-disable-mode-line-during-startup)
    (dolist (buf (buffer-list))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          ;; Buffer has nil mode-line as local var - restore to default
          (when (and (local-variable-p 'mode-line-format)
                     (eq mode-line-format nil))
            (kill-local-variable 'mode-line-format)))))))

;; Run after all init is complete
(add-hook 'emacs-startup-hook #'my/fix-mode-line-for-all-buffers 100)



;;; post-init.el ends here

;; ==============================================================================
;; RELOAD THEME-SETTING.EL FOR NEW GUI FRAMES
;; ==============================================================================
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings.
Only reloads for top-level frames (not Corfu child frames) and only once per frame."
  (when (and (display-graphic-p frame)
             (not (frame-parameter frame 'parent-frame))
             (not (frame-parameter frame 'theme-setting-loaded)))
    (set-frame-parameter frame 'theme-setting-loaded t)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")
    (message "✅ Reloaded theme-setting.el for new frame")))

;; Apply all settings from theme-setting.el to every new GUI frame
(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)

;; Load theme initially for non-daemon mode
(unless (daemonp)
  (load-file "~/.emacs.d/lisp/theme-setting.el"))

;; ─── Workflow Daemon: Use standalone research to avoid load-file corruption ───
;; load-file corrupts complex defuns with nested lambdas (specifically maphash).
;; We load a simple standalone research module and override run-research to use it.
;; An after-load-functions hook persists the override when strategic files are reloaded.
(when (string= (getenv "MINIMAL_EMACS_WORKFLOW_DAEMON") "1")
  (message "[daemon-fix] Setting up standalone research (avoids load-file corruption)")
  (let ((standalone-file (expand-file-name "lisp/modules/standalone-research.el"
                                           minimal-emacs-user-directory)))
    (when (file-exists-p standalone-file)
      (load-file standalone-file)
      (when (fboundp 'slr-run-research)
        (message "[daemon-fix] Loaded standalone research, overriding run-research")
        (defalias 'gptel-auto-workflow-run-research 'slr-run-research))))
  ;; Re-apply override after strategic files are (re)loaded by cron
  (defun my/daemon--reapply-run-research-override (loaded-file)
    (when (or (string-suffix-p "gptel-auto-workflow-strategic.el" loaded-file)
              (string-suffix-p "strategic-daemon-functions.el" loaded-file))
      (when (fboundp 'slr-run-research)
        (defalias 'gptel-auto-workflow-run-research 'slr-run-research)
        (message "[daemon-fix] Re-applied run-research override after %s" loaded-file))))
  (add-hook 'after-load-functions 'my/daemon--reapply-run-research-override)
  ;; Start periodic research timer once strategic module is loaded
  (defun my/daemon--start-periodic-research (loaded-file)
    (when (string-suffix-p "gptel-auto-workflow-strategic.el" loaded-file)
      (when (and (fboundp 'gptel-auto-workflow-start-periodic-research)
                 (not gptel-auto-workflow--research-timer))
        (gptel-auto-workflow-start-periodic-research)
        (message "[daemon] Auto-started periodic research timer (%ds)"
                 gptel-auto-workflow-research-interval))
      (remove-hook 'after-load-functions 'my/daemon--start-periodic-research)))
  (add-hook 'after-load-functions 'my/daemon--start-periodic-research))
