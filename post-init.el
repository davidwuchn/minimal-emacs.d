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
  (when (boundp 'server-socket-dir)
    (condition-case nil
        (let* ((socket-dir server-socket-dir)
               (stale (expand-file-name server-name socket-dir)))
          (when (file-exists-p stale)
            (delete-file stale)
            (message "[post-init] Cleaned stale daemon socket: %s" stale)))
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

;; Ensure config-verified flag even if init.el errors before its line 641.
;; Must be set after all module loads but before any post-init code that
;; might error and abort loading (which prevents init.el:641 from running).
(setq minimal-emacs--success t)

;; Backup and auto-save settings are configured in init-files.el

;; ==============================================================================
;; DEBUG: Auto-capture backtrace for mode-line errors
;; ==============================================================================
;; "Wrong type argument: stringp, nil" occurs during mode-line updates.
;; Catch it in format-mode-line and log a full backtrace.
(defvar my/backtrace-log
  (expand-file-name "var/log/backtrace-mode-line.log" user-emacs-directory))
(defun my/format-mode-line-backtrace (orig-fn format &optional face window buffer)
  (condition-case err
      (funcall orig-fn format face window buffer)
    (wrong-type-argument
     (when (string-match-p "stringp, nil" (error-message-string err))
       (with-temp-file my/backtrace-log
         (prin1 (format-time-string "%Y-%m-%dT%T ") (current-buffer))
         (prin1 err (current-buffer))
         (terpri (current-buffer))
         (let ((standard-output (current-buffer))
               (debug-on-error nil))
           (backtrace))))
     (signal (car err) (cdr err)))))
(advice-add 'format-mode-line :around #'my/format-mode-line-backtrace)

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

;; --- Auto-workflow: register external projects ---
(let ((projects-f (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el"
                                    user-emacs-directory))
      (base-f (expand-file-name "lisp/modules/gptel-tools-agent-base.el"
                                user-emacs-directory))
      (creatoros-dir (expand-file-name "~/workspace/creatoros/")))
  (when (file-directory-p creatoros-dir)
    ;; Step 1: register as project (lightweight — no deps needed)
    (condition-case nil
        (when (and (file-exists-p projects-f) (load-file projects-f))
          (add-to-list 'gptel-auto-workflow-projects
                       (directory-file-name creatoros-dir))
          (message "[post-init] CreatorOS: project registered"))
      (error (message "[post-init] CreatorOS project registration deferred")))
    ;; Step 2: allow workspace boundary (heavier deps — may fail)
    (condition-case nil
        (when (and (file-exists-p base-f) (load-file base-f))
          (add-to-list 'gptel-auto-workflow--allowed-workspace-roots creatoros-dir)
          (message "[post-init] CreatorOS: workspace boundary allowed"))
      (error (message "[post-init] CreatorOS boundary deferred — will retry on first workflow run")))))

;; Run after all init is complete
(add-hook 'emacs-startup-hook #'my/fix-mode-line-for-all-buffers 100)

;; Retry workspace boundary registration after full init (deps now loaded)
(add-hook 'emacs-startup-hook
          (lambda ()
            (let* ((base-f (expand-file-name "lisp/modules/gptel-tools-agent-base.el"
                                             user-emacs-directory))
                   (creatoros-dir (expand-file-name "~/workspace/creatoros/")))
              (when (and (file-directory-p creatoros-dir)
                         (file-exists-p base-f)
                         (not (member creatoros-dir gptel-auto-workflow--allowed-workspace-roots)))
                (condition-case nil
                    (progn
                      (load-file base-f)
                      (add-to-list 'gptel-auto-workflow--allowed-workspace-roots creatoros-dir)
                      (message "[post-init] CreatorOS boundary: now allowed"))
                  (error (message "[post-init] CreatorOS boundary still unavailable"))))))
          90)



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
;; Also ensure server-start is called initially if not already done.
(when (daemonp)
  ;; Ensure server is started (daemon should do this automatically, but be explicit)
  (unless (and (boundp 'server-process) server-process (process-live-p server-process))
    (condition-case err
        (progn
          (server-start)
          (message "[server] Explicitly started server: %s" server-name))
      (error
       (message "[server] Failed to start server: %s" (error-message-string err)))))
  
  ;; Hard curl timeout prevents orphaned subprocesses from hanging the daemon.
  ;; Without --max-time, curl blocks indefinitely when server closes connection
  ;; without FIN, filling the 64KB pipe buffer on macOS and never exiting.
  ;; Must use with-eval-after-load because gptel is loaded lazily; boundp
  ;; returns nil during post-init startup.
  (with-eval-after-load 'gptel-request
    (add-to-list 'gptel-curl-extra-args "--max-time" t)
    (add-to-list 'gptel-curl-extra-args "900" t)
    (message "[post-init] Set gptel curl --max-time 900s for daemon"))
  
  ;; Self-heal: check every 30s and recreate socket if lost
  (run-at-time 30 30
               (lambda ()
                 (when (and (boundp 'server-name) (stringp server-name)
                            (boundp 'server-socket-dir) (stringp server-socket-dir))
                   (let ((sock (expand-file-name server-name server-socket-dir)))
                     (unless (file-exists-p sock)
                       (message "[server] Socket missing: %s, attempting self-heal" sock)
                       (when server-process
                         (condition-case nil (delete-process server-process) (error nil))
                         (setq server-process nil))
                       (condition-case err
                           (progn (server-start)
                                  (message "[server] Self-healed socket %s" sock))
                         (error
                          (message "[server] Self-heal failed: %s"
                                    (error-message-string err))))))))))

;; ─── Critical function corruption guard ───
;; Self-heal: if pending-decisions-p returns a symbol instead of t/nil,
;; the entire pipeline is blocked. Redefine from source if corrupted.
;; This can happen when auto-evolution introduces subtle paren imbalance
;; that shifts function definitions.
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (and (fboundp 'gptel-auto-workflow--pending-decisions-p)
                       (not (daemonp)))
              ;; Skip check in daemon — daemon loads this before production.el
              t)
            (when (and (fboundp 'gptel-auto-workflow--pending-decisions-p)
                       (daemonp))
              (let ((result (condition-case nil
                                (gptel-auto-workflow--pending-decisions-p)
                              (error 'ERR))))
                (when (and (not (eq result t)) (not (eq result nil))
                           (not (eq result 'ERR)))
                  (message "[CRITICAL] pending-decisions-p corrupted (returns %s), reloading production.el" result)
                  (load "lisp/modules/gptel-auto-workflow-production.el" t t)
                  (let ((result2 (condition-case nil
                                     (gptel-auto-workflow--pending-decisions-p)
                                   (error 'ERR))))
                    (if (or (eq result2 t) (eq result2 nil))
                        (message "[CRITICAL] Fixed pending-decisions-p after reload")
                      (message "[CRITICAL] FAILED to fix pending-decisions-p (still returns %s)" result2))))))))
