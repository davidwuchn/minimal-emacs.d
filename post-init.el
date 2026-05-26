;;; post-init.el --- User configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Personal configuration and overrides. Add your customizations here.
;; This file is loaded after all modular configuration files.

;;; Code:

;; Pre-emptively set persistent-headless for workflow daemons before any
;; gptel-mode buffers are created.  Without this the gptel-mode hook in
;; gptel-ext-core.el defaults every buffer's gptel-backend to MiniMax,
;; and the headless-provider-override never activates because it requires
;; this variable to be non-nil.
(when (string= (getenv "MINIMAL_EMACS_WORKFLOW_DAEMON") "1")
  (setq gptel-auto-workflow-persistent-headless t)
  ;; Clean stale daemon socket before server-start creates a new one.
  ;; On macOS, Emacs tries $TMPDIR/emacs$UID/$NAME first. If a stale
  ;; socket from a crashed daemon exists, the new daemon falls back to
  ;; /tmp/emacs$UID/$NAME, and emacsclient -s can't reach it because
  ;; it also checks TMPDIR first. Delete the stale socket here so the
  ;; new daemon always creates at the expected location.
  (condition-case nil
      (let ((socket-dir (expand-file-name (format "emacs%d" (user-uid))
                                          (or (getenv "TMPDIR") "/tmp")))
            (sock (concat server-name)))
        (let ((stale (expand-file-name server-name socket-dir)))
          (when (file-exists-p stale)
            (delete-file stale)
            (message "[post-init] Cleaned stale daemon socket: %s" stale))))
    (error nil)))

;; Add the local lisp directory to Emacs' load path using the true root directory
;; (not user-emacs-directory, since we changed that to var/)
(add-to-list 'load-path (expand-file-name "lisp" minimal-emacs-user-directory))

;; Set fringe width to match character size — scales with font, avoids fixed-width gap.
(fringe-mode (frame-char-width))

;; Typed text replaces active selection (standard behavior in every other editor).
(delete-selection-mode 1)

;; Visual column ruler at 80 characters — helps enforce line length discipline.
(global-display-fill-column-indicator-mode 1)

;; Smooth pixel-level scrolling (reduces jitter on macOS).
(when (fboundp 'pixel-scroll-precision-mode)
  (setq pixel-scroll-precision-use-momentum nil)
  (pixel-scroll-precision-mode 1))

;; Maximum tree-sitter syntax highlighting depth for richer colors.
(setq treesit-font-lock-level 4)

;; Load the modular configuration files
(require 'init-system)
(require 'init-completion)
(require 'init-evil)
(require 'init-dev)
(require 'init-tools)
(require 'init-org)      ; Org mode configuration
;; Defer AI module loading for workflow daemons to break C stack overflow.
;; run-with-timer 0 processes from event loop with clean stack.
(if (string= (getenv "MINIMAL_EMACS_WORKFLOW_DAEMON") "1")
    ;; Defer AI loading to break C stack overflow. Wrap in with-temp-message
    ;; to serialize all message writes — prevents *Messages* buffer corruption
    ;; from interleaved load/init messages during concurrent module initialization.
    (run-at-time 0.5 nil
      (lambda ()
        (condition-case err
            (let ((load-verbose nil)
                  (inhibit-message t))
              (require 'init-ai)
              ;; Force-reload key modules so chain-backend selection,
              ;; OR-condition override, and nil-backend failover are
              ;; available.  load-file always re-evaluates from source.
              (dolist (mod '("gptel-tools-agent-error"
                             "gptel-tools-agent-prompt-build"
                             "gptel-benchmark-subagent"))
                (load-file (expand-file-name
                            (format "lisp/modules/%s.el" mod)
                            minimal-emacs-user-directory)))
              (load (expand-file-name "lisp/modules/standalone-research.el"
                                       minimal-emacs-user-directory) nil 'nomessage)
              (when (fboundp 'slr-run-research)
                (defalias 'gptel-auto-workflow-run-research 'slr-run-research)))
          (error
           (message "[init-daemon] Deferred init-ai loading error: %s"
                    (error-message-string err)))))))
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

;; ─── Workflow Daemon: handled by deferred init-ai loading above ───

;; ─── Server socket self-healing ───
;; During long gptel-curl LLM calls, the emacs server socket can be lost
;; (network timeout, pipe break) while the Emacs process survives.  Instead
;; of requiring an external watchdog to SIGKILL and restart (losing all
;; in-progress experiment work), recreate the socket in-process every 30s.
(when (and (daemonp) server-process (process-live-p server-process))
  (run-at-time 30 30
               (lambda ()
                 (when (and (boundp 'server-name) (stringp server-name)
                            (boundp 'server-socket-dir) (stringp server-socket-dir))
                   (let ((sock (expand-file-name server-name server-socket-dir)))
                     (unless (file-exists-p sock)
                       (when server-process
                         (condition-case nil (delete-process server-process) (error nil))
                         (setq server-process nil))
                       (condition-case err
                           (progn (server-start)
                                  (message "[server] Self-healed socket %s" sock))
                         (error
                          (message "[server] Self-heal failed: %s"
                                    (error-message-string err))))))))))
