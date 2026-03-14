;;; ai-code-eca-bridge.el --- Extensions for ECA backend in ai-code -*- lexical-binding: t; -*-

;; Copyright (C) 2026
;; Author: minimal-emacs.d
;; Version: 0.2
;; Package-Requires: ((emacs "28.1"))
;; Keywords: ai, code, assistant, eca

;;; Commentary:
;; This file EXTENDS the upstream ai-code-eca.el with additional features:
;;   - Session management (list, switch, create)
;;   - Context commands (file, cursor, repo-map, clipboard)
;;   - Keybindings integration
;;   - Session affinity
;;   - Health verification
;;   - Context synchronization
;;
;; Upstream ai-code-eca.el provides:
;;   - ai-code-eca-start, ai-code-eca-switch, ai-code-eca-send, ai-code-eca-resume
;;
;; Upstream ECA provides:
;;   - eca-chat-add-workspace-root (interactive workspace folder)
;;   - eca--session-add-workspace-folder (internal)
;;   - eca--session-for-worktree (worktree detection)
;;
;; Usage:
;;   (require 'ai-code-eca-bridge)
;;   ;; Extensions are auto-loaded

;;; Code:

(require 'ai-code-backends)
(require 'eca-ext nil t)

(declare-function eca-session "eca-util" ())
(declare-function eca-chat-open "eca-chat" (session))
(declare-function eca-chat--get-last-buffer "eca-chat" (session))
(declare-function eca-info "eca-util" (format-string &rest args))
(declare-function eca--session-status "eca-util" (session))
(declare-function eca--session-workspace-folders "eca-util" (session))
(declare-function eca-chat-add-workspace-root "eca-chat" ())
(declare-function ai-code-read-string "ai-code-input" (prompt &optional initial-input candidate-list))
(declare-function ai-code--repo-backend-for-root "ai-code-backends" (git-root))
(declare-function ai-code--remember-repo-backend "ai-code-backends" (git-root backend))

(defvar eca--sessions nil)
(defvar ai-code-eca--config-warned nil)

;;; Helpers

(defun ai-code-eca--ensure-chat-buffer (session)
  "Ensure ECA chat buffer for SESSION exists and return it."
  (let ((buf (eca-chat--get-last-buffer session)))
    (unless (and buf (get-buffer-window buf))
      (eca-chat-open session))
    buf))

(defun ai-code-eca--ensure-available ()
  "Ensure ECA package is available."
  (unless (require 'eca nil t)
    (user-error "ECA not available. Install with: M-x package-install RET eca RET"))
  (dolist (fn '(eca eca-session eca-chat-open eca-chat--get-last-buffer))
    (unless (fboundp fn)
      (user-error "ECA missing function: %s" fn)))
  (let ((config-file (expand-file-name "~/.config/eca/config.json")))
    (when (and (not (file-exists-p config-file))
               (not ai-code-eca--config-warned))
      (setq ai-code-eca--config-warned t)
      (message "Note: ECA config not found at %s (optional)" config-file))))

;;; Session Management (via eca-ext)

(defun ai-code-eca-get-sessions ()
  "Return list of active ECA sessions for display."
  (require 'eca-ext nil t)
  (when (fboundp 'eca-list-sessions)
    (condition-case err
        (mapcar (lambda (info)
                  (cons (plist-get info :id)
                        (format "Session %d: %s (%d chats)"
                                (plist-get info :id)
                                (mapconcat #'identity (plist-get info :workspace-folders) ", ")
                                (plist-get info :chat-count))))
                (eca-list-sessions))
      (error nil))))

(defun ai-code-eca-switch-session (&optional session-id)
  "Switch to ECA session SESSION-ID or prompt for selection."
  (interactive)
  (require 'eca-ext nil t)
  (unless (fboundp 'eca-switch-to-session)
    (user-error "Session multiplexing requires eca-ext.el"))
  (eca-switch-to-session session-id)
  (run-at-time 0.5 nil #'ai-code-eca--save-session-affinity))

(defun ai-code-eca-list-sessions ()
  "Display list of active ECA sessions."
  (interactive)
  (let ((sessions (ai-code-eca-get-sessions)))
    (if sessions
        (message "ECA Sessions: %s" (string-join (mapcar #'cdr sessions) " | "))
      (message "No active ECA sessions"))))

;;; Context Commands (via eca-ext)

(defun ai-code-eca-add-file-context (file-path)
  "Add FILE-PATH as context to current ECA session."
  (interactive "fAdd file context: ")
  (require 'eca-ext nil t)
  (unless (fboundp 'eca-chat-add-file-context)
    (user-error "Context features require eca-ext.el"))
  (let ((session (eca-session)))
    (if session
        (progn
          (ai-code-eca--ensure-chat-buffer session)
          (eca-chat-add-file-context session file-path)
          (eca-info "Added file context: %s" file-path))
      (user-error "No ECA session"))))

(defun ai-code-eca-add-cursor-context ()
  "Add current cursor position as context to ECA session."
  (interactive)
  (require 'eca-ext nil t)
  (unless (fboundp 'eca-chat-add-cursor-context)
    (user-error "Context features require eca-ext.el"))
  (let ((session (eca-session)))
    (if session
        (if buffer-file-name
            (progn
              (ai-code-eca--ensure-chat-buffer session)
              (eca-chat-add-cursor-context session buffer-file-name (point))
              (eca-info "Added cursor context: %s:%d" buffer-file-name (point)))
          (message "No buffer file"))
      (user-error "No ECA session"))))

(defun ai-code-eca-add-repo-map-context ()
  "Add repository map context to ECA session."
  (interactive)
  (require 'eca-ext nil t)
  (unless (fboundp 'eca-chat-add-repo-map-context)
    (user-error "Context features require eca-ext.el"))
  (let ((session (eca-session)))
    (if session
        (progn
          (ai-code-eca--ensure-chat-buffer session)
          (eca-chat-add-repo-map-context session)
          (eca-info "Added repo map context"))
      (user-error "No ECA session"))))

(defun ai-code-eca-add-clipboard-context ()
  "Add clipboard contents as context to current ECA session."
  (interactive)
  (require 'eca-ext nil t)
  (unless (fboundp 'eca-chat-add-clipboard-context)
    (user-error "Context features require eca-ext.el"))
  (let ((session (eca-session)))
    (if session
        (let ((clip-content (current-kill 0 t)))
          (if (and clip-content (not (string-empty-p clip-content)))
              (progn
                (ai-code-eca--ensure-chat-buffer session)
                (eca-chat-add-clipboard-context session clip-content)
                (eca-info "Added clipboard context (%d chars)" (length clip-content)))
            (message "Clipboard is empty")))
      (user-error "No ECA session"))))

(defun ai-code-eca-add-workspace-folder ()
  "Add workspace folder using upstream eca-chat-add-workspace-root."
  (interactive)
  (unless (fboundp 'eca-chat-add-workspace-root)
    (user-error "ECA workspace features not available"))
  (eca-chat-add-workspace-root))

;;; Context Synchronization

(defvar ai-code-eca-context-sync-timer nil)

(defcustom ai-code-eca-context-sync-interval 60
  "Seconds between automatic context sync. nil to disable."
  :type '(choice (const :tag "Disabled" nil)
                 (integer :tag "Seconds"))
  :group 'ai-code)

(defun ai-code-eca-sync-context ()
  "Sync current buffer context to ECA session."
  (interactive)
  (require 'eca-ext nil t)
  (let ((session (eca-session)))
    (when (and session buffer-file-name (fboundp 'eca-chat-add-file-context))
      (condition-case err
          (progn
            (eca-chat-add-file-context session buffer-file-name)
            (when (fboundp 'eca-chat-add-cursor-context)
              (eca-chat-add-cursor-context session buffer-file-name (point)))
            (when (called-interactively-p 'interactive)
              (message "Synced context: %s:%d" buffer-file-name (point))))
        (error (message "Context sync failed: %s" (error-message-string err)))))))

(defun ai-code-eca-context-sync-start ()
  "Start automatic context synchronization."
  (interactive)
  (when ai-code-eca-context-sync-timer
    (cancel-timer ai-code-eca-context-sync-timer))
  (when ai-code-eca-context-sync-interval
    (setq ai-code-eca-context-sync-timer
          (run-at-time t ai-code-eca-context-sync-interval #'ai-code-eca-sync-context))
    (message "ECA context sync started (%ds)" ai-code-eca-context-sync-interval)))

(defun ai-code-eca-context-sync-stop ()
  "Stop automatic context synchronization."
  (interactive)
  (when ai-code-eca-context-sync-timer
    (cancel-timer ai-code-eca-context-sync-timer)
    (setq ai-code-eca-context-sync-timer nil)
    (message "ECA context sync stopped")))

;;; Session Affinity

(defun ai-code-eca--project-root ()
  "Return project root for session affinity."
  (or (when (fboundp 'projectile-project-root)
        (ignore-errors (projectile-project-root)))
      (when (fboundp 'project-root)
        (ignore-errors (project-root (project-current))))
      default-directory))

(defun ai-code-eca--save-session-affinity ()
  "Save current ECA session as preferred for current project."
  (when-let* ((root (ai-code-eca--project-root))
              ((fboundp 'ai-code--remember-repo-backend)))
    (ai-code--remember-repo-backend root 'eca)))

;;; Health Verification

(defcustom ai-code-eca-verify-timeout 5
  "Seconds to wait for ECA server response during verify."
  :type 'integer
  :group 'ai-code)

(defun ai-code-eca-verify ()
  "Verify ECA backend is functional."
  (condition-case nil
      (progn
        (ai-code-eca--ensure-available)
        (let ((session (eca-session)))
          (and session
               (or (not (fboundp 'eca--session-status))
                   (eq (eca--session-status session) 'ready))
               (eca-chat--get-last-buffer session)
               t)))
    (error nil)))

(defun ai-code-eca-verify-health ()
  "Verify ECA server is responsive."
  (interactive)
  (ai-code-eca--ensure-available)
  (let* ((session (eca-session))
         (start-time (current-time))
         (responsive nil))
    (if session
        (progn
          (when (fboundp 'eca--session-status)
            (let ((status (eca--session-status session)))
              (setq responsive (memq status '(ready idle)))))
          (when (and responsive (fboundp 'eca--session-workspace-folders))
            (condition-case nil
                (let ((folders (eca--session-workspace-folders session)))
                  (setq responsive (and folders (listp folders))))
              (error (setq responsive nil))))
          (let ((elapsed (float-time (time-subtract (current-time) start-time))))
            (if responsive
                (prog1 t
                  (message "ECA healthy (responded in %.2fs)" elapsed))
              (message "ECA not responding (status: %s)"
                       (if (fboundp 'eca--session-status)
                           (eca--session-status session)
                         "unknown"))
              nil)))
      (message "No ECA session active")
      nil)))

;;; Upgrade

(defun ai-code-eca-upgrade-vc ()
  "Upgrade ECA if installed via package-vc."
  (interactive)
  (if (and (featurep 'package-vc)
           (alist-get 'eca package-vc-selected-packages))
      (progn
        (message "Upgrading ECA via package-vc...")
        (package-vc-upgrade 'eca)
        (message "ECA upgraded. Restart Emacs or re-evaluate."))
    (if (package-installed-p 'eca)
        (progn
          (package-refresh-contents)
          (package-install 'eca)
          (message "ECA upgraded via package.el"))
      (user-error "ECA is not installed"))))

;;; Install Skills

(defun ai-code-eca-install-skills ()
  "Install skills for ECA by prompting for a skills repo URL."
  (interactive)
  (require 'ai-code-input nil t)
  (let* ((url (read-string
               "Skills repo URL for ECA: "
               nil nil "https://github.com/obra/superpowers"))
         (default-prompt
          (format
           "Install the skill from %s for this ECA session. Read the repository README to understand the installation instructions and follow them. Set up the skill files under the appropriate directory (e.g. ~/.eca/ or the project .eca/ directory) so they are available in future sessions."
           url))
         (prompt (if (and (called-interactively-p 'interactive)
                          (fboundp 'ai-code-read-string))
                     (ai-code-read-string "Edit install-skills prompt: " default-prompt)
                   default-prompt)))
    (require 'ai-code-eca nil t)
    (when (fboundp 'ai-code-eca-send)
      (ai-code-eca-send prompt))))

;;; Keybindings

(defvar ai-code-eca-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "l") #'ai-code-eca-list-sessions)
    (define-key map (kbd "s") #'ai-code-eca-switch-session)
    (define-key map (kbd "f") #'ai-code-eca-add-file-context)
    (define-key map (kbd "c") #'ai-code-eca-add-cursor-context)
    (define-key map (kbd "m") #'ai-code-eca-add-repo-map-context)
    (define-key map (kbd "y") #'ai-code-eca-add-clipboard-context)
    (define-key map (kbd "a") #'ai-code-eca-add-workspace-folder)
    (define-key map (kbd "v") #'ai-code-eca-verify-health)
    map)
  "Keymap for ECA extension commands.")

(defun ai-code-eca-setup-keybindings ()
  "Set up ECA keybindings in relevant maps."
  (interactive)
  (when (boundp 'eca-chat-mode-map)
    (define-key eca-chat-mode-map (kbd "C-c C-f") #'ai-code-eca-add-file-context)
    (define-key eca-chat-mode-map (kbd "C-c C-c") #'ai-code-eca-add-cursor-context)
    (define-key eca-chat-mode-map (kbd "C-c C-m") #'ai-code-eca-add-repo-map-context)
    (define-key eca-chat-mode-map (kbd "C-c C-y") #'ai-code-eca-add-clipboard-context)
    (define-key eca-chat-mode-map (kbd "C-c C-a") #'ai-code-eca-add-workspace-folder))
  (when (boundp 'ai-code-mode-map)
    (define-key ai-code-mode-map (kbd "C-c e") ai-code-eca-keymap))
  (message "ECA extension keybindings configured"))

;;; Unload

(defun ai-code-eca--unload-function ()
  "Cleanup when unloading ai-code-eca-bridge."
  (when ai-code-eca-context-sync-timer
    (cancel-timer ai-code-eca-context-sync-timer))
  (when (boundp 'eca-chat-mode-map)
    (define-key eca-chat-mode-map (kbd "C-c C-f") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-c") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-m") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-y") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-a") nil)))

(add-hook 'ai-code-eca-bridge-unload-hook #'ai-code-eca--unload-function)

;;; Auto-setup

(with-eval-after-load 'eca
  (ai-code-eca-setup-keybindings))

(provide 'ai-code-eca-bridge)

;;; ai-code-eca-bridge.el ends here