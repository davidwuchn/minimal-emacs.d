;;; ai-code-eca-bridge.el --- Bridge ai-code to ECA backend -*- lexical-binding: t; -*-

;; Copyright (C) 2026
;; Author: minimal-emacs.d
;; Version: 0.1
;; Package-Requires: ((emacs "28.1"))
;; Keywords: ai, code, assistant, eca

;;; Commentary:
;; This file provides a bridge between ai-code's backend contract and ECA
;; (Editor Code Assistant).  It allows ai-code to use ECA as a backend
;; without modifying any upstream files in var/elpa/.
;;
;; Usage:
;;   (require 'ai-code-eca-bridge)
;;   (ai-code-set-backend 'eca)
;;
;; Requirements:
;;   - eca package installed and configured
;;   - ai-code package installed and configured

;;; Code:

(require 'ai-code-backends)
(require 'eca-ext nil t)

(declare-function eca "eca" (&optional arg))
(declare-function eca-session "eca-util" ())
(declare-function eca-chat-open "eca-chat" (session))
(declare-function eca-chat-send-prompt "eca-chat" (session message))
(declare-function eca-chat--get-last-buffer "eca-chat" (session))
(declare-function eca-info "eca-util" (format-string &rest args))
(declare-function eca--session-status "eca-util" (session))
(declare-function eca-list-sessions "eca-ext" ())
(declare-function eca-switch-to-session "eca-ext" (&optional session-id))
(declare-function eca-chat-add-file-context "eca-ext" (session file-path))
(declare-function eca-chat-add-repo-map-context "eca-ext" (session))
(declare-function eca-chat-add-cursor-context "eca-ext" (session file-path position))
(declare-function eca-chat-add-clipboard-context "eca-ext" (session content))
(declare-function ai-code-read-string "ai-code-input" (prompt &optional initial-input candidate-list))

(defvar ai-code-eca--config-warned nil
  "Non-nil if missing config warning has already been shown.")

(defun ai-code-eca--ensure-chat-buffer (session)
  "Ensure ECA chat buffer for SESSION exists and return it.
Only calls eca-chat-open if buffer doesn't exist or isn't visible."
  (let ((buf (eca-chat--get-last-buffer session)))
    (unless (and buf (get-buffer-window buf))
      (eca-chat-open session))
    buf))

;;;###autoload
(defun ai-code-eca-start (&optional arg)
  "Start a new ECA session.

With prefix ARG, prompt for additional ECA arguments.
This function satisfies ai-code's :start backend contract."
  (interactive "P")
  (ai-code-eca--ensure-available)
  (if arg
      (let ((current-prefix-arg arg))
        (funcall-interactively #'eca))
    (funcall #'eca))
  (message "ECA session started"))

;;;###autoload
(defun ai-code-eca-switch (&optional arg)
  "Switch to ECA chat buffer.

With prefix ARG, force new session before switching.
This function satisfies ai-code's :switch backend contract."
  (interactive "P")
  (ai-code-eca--ensure-available)
  (when arg
    (ai-code-eca-start arg)
    (message "Started new ECA session"))
  (let ((session (eca-session)))
    (if session
        (pop-to-buffer (ai-code-eca--ensure-chat-buffer session))
      (user-error "No ECA session (M-x ai-code-eca-start to create one)"))))

;;;###autoload
(defun ai-code-eca-send (line)
  "Send LINE to ECA chat.

This function satisfies ai-code's :send backend contract."
  (interactive "sECA> ")
  (ai-code-eca--ensure-available)
  (let ((session (eca-session)))
    (if session
        (progn
          (ai-code-eca--ensure-chat-buffer session)
          (eca-chat-send-prompt session line))
      (user-error "No ECA session (M-x ai-code-eca-start to create one)"))))

;;;###autoload
(defun ai-code-eca-add-file-context (file-path)
  "Add FILE-PATH as context to current ECA session."
  (interactive "fAdd file context: ")
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-chat-add-file-context)
    (user-error "Context features require eca-ext.el (add to load-path)"))
  (let ((session (eca-session)))
    (if session
        (progn
          (ai-code-eca--ensure-chat-buffer session)
          (eca-chat-add-file-context session file-path)
          (eca-info "Added file context: %s" file-path))
      (user-error "No ECA session. Start one with M-x ai-code-eca-start"))))

;;;###autoload
(defun ai-code-eca-add-clipboard-context ()
  "Add clipboard contents as context to current ECA session."
  (interactive)
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-chat-add-clipboard-context)
    (user-error "Context features require eca-ext.el (add to load-path)"))
  (let ((session (eca-session)))
    (if session
        (let ((clip-content (current-kill 0 t)))
          (if (and clip-content (not (string-empty-p clip-content)))
              (progn
                (ai-code-eca--ensure-chat-buffer session)
                (eca-chat-add-clipboard-context session clip-content)
                (eca-info "Added clipboard context (%d chars)" (length clip-content)))
            (message "Clipboard is empty")))
      (user-error "No ECA session. Start one with M-x ai-code-eca-start"))))

;;;###autoload
(defun ai-code-eca-add-cursor-context ()
  "Add current cursor position as context to ECA session."
  (interactive)
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-chat-add-cursor-context)
    (user-error "Context features require eca-ext.el (add to load-path)"))
  (let ((session (eca-session)))
    (if session
        (if buffer-file-name
            (progn
              (ai-code-eca--ensure-chat-buffer session)
              (eca-chat-add-cursor-context session buffer-file-name (point))
              (eca-info "Added cursor context: %s:%d" buffer-file-name (point)))
          (message "No buffer file"))
      (user-error "No ECA session. Start one with M-x ai-code-eca-start"))))

;;;###autoload
(defun ai-code-eca-add-repo-map-context ()
  "Add repository map context to ECA session."
  (interactive)
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-chat-add-repo-map-context)
    (user-error "Context features require eca-ext.el (add to load-path)"))
  (let ((session (eca-session)))
    (if session
        (progn
          (ai-code-eca--ensure-chat-buffer session)
          (eca-chat-add-repo-map-context session)
          (eca-info "Added repo map context"))
      (user-error "No ECA session. Start one with M-x ai-code-eca-start"))))

;;;###autoload
(defun ai-code-eca-get-sessions ()
  "Return list of active ECA sessions for ai-code menu display.
Returns an alist of (session-id . session-info) for integration with ai-code-menu."
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-list-sessions)
    (user-error "Session multiplexing requires eca-ext.el (add to load-path)"))
  (condition-case err
      (mapcar (lambda (session-info)
                (cons (plist-get session-info :id)
                      (format "Session %d: %s (%d chats)"
                              (plist-get session-info :id)
                              (mapconcat #'identity (plist-get session-info :workspace-folders) ", ")
                              (plist-get session-info :chat-count))))
              (eca-list-sessions))
    (error
     (message "[ai-code-eca] Warning: Failed to list sessions: %s" (error-message-string err))
     nil)))

;;;###autoload
(defun ai-code-eca-switch-session (&optional session-id)
  "Switch to ECA session SESSION-ID or prompt for selection.
Returns the selected session or nil if cancelled."
  (interactive)
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-switch-to-session)
    (user-error "Session multiplexing requires eca-ext.el (add to load-path)"))
  (eca-switch-to-session session-id))

;;;###autoload
(defun ai-code-eca-resume (&optional arg)
  "Resume an existing ECA session.

With prefix ARG, force new session instead of resuming.
This function satisfies ai-code's :resume backend contract."
  (interactive "P")
  (ai-code-eca--ensure-available)
  (if arg
      ;; Force new session with C-u prefix
      (ai-code-eca-start arg)
    ;; Resume existing session
    (let ((session (eca-session)))
      (if session
          (progn
            (pop-to-buffer (ai-code-eca--ensure-chat-buffer session))
            (message "Resumed ECA session"))
        ;; No existing session, start a new one
        (ai-code-eca-start)
        (message "Started new ECA session")))))

;;;###autoload
(defun ai-code-eca--ensure-available ()
  "Ensure `eca' package and required functions are available.

Signals user-error if ECA cannot be used.
Warns if ECA config file is missing (non-fatal)."
  (unless (require 'eca nil t)
    (user-error "ECA backend not available (package not loaded). Install with: M-x package-install RET eca RET"))
  (dolist (fn '(eca eca-session eca-chat-open eca-chat-send-prompt eca-chat--get-last-buffer))
    (unless (fboundp fn)
      (user-error "ECA backend incomplete: function '%s' missing. Reinstall eca package" fn)))
  (let ((config-file (expand-file-name "~/.config/eca/config.json")))
    (when (and (not (file-exists-p config-file))
               (not ai-code-eca--config-warned))
      (setq ai-code-eca--config-warned t)
      (message "Note: ECA config file not found at %s (optional)" config-file))))

;;;###autoload
(defun ai-code-eca-version ()
  "Return ECA version string."
  (interactive)
  (ai-code-eca--ensure-available)
  (let ((version (or (and (featurep 'eca)
                          (boundp 'eca-version)
                          eca-version)
                     "unknown")))
    (if (called-interactively-p 'interactive)
        (message "ECA version: %s" version)
      version)))

;;;###autoload
(defun ai-code-eca-upgrade ()
  "Upgrade ECA package via package.el.

Prompts for confirmation before refreshing package archives
and installing the latest version of ECA."
  (interactive)
  (ai-code-eca--ensure-available)
  (if (y-or-n-p "Refresh package archives and upgrade ECA? ")
      (progn
        (package-refresh-contents)
        (package-install 'eca)
        (message "ECA upgraded successfully"))
    (message "Upgrade cancelled")))

;;;###autoload
(defun ai-code-eca-verify ()
  "Verify ECA backend is functional.

Returns non-nil if ECA is available and responsive, nil otherwise.
Checks that session exists and is in a responsive state.
This function satisfies ai-code's :verify backend contract."
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

;;;###autoload
(defun ai-code-eca-install-skills ()
  "Install skills for ECA by prompting for a skills repo URL.
Ask the ECA session to clone and set up the skills from the given
repository.  ECA manages skills as files under ~/.eca/ or project
.eca/ directory, so the CLI itself handles the installation details."
  (interactive)
  (ai-code-eca--ensure-available)
  (let* ((url (read-string
               "Skills repo URL for ECA: "
               nil nil "https://github.com/obra/superpowers"))
         (default-prompt
          (format
           "Install the skill from %s for this ECA session. Read the repository README to understand the installation instructions and follow them. Set up the skill files under the appropriate directory (e.g. ~/.eca/ or the project .eca/ directory) so they are available in future sessions."
           url))
         (prompt (if (called-interactively-p 'interactive)
                     (ai-code-read-string
                      "Edit install-skills prompt for ECA: "
                      default-prompt)
                   default-prompt)))
    (ai-code-eca-send prompt)))

;;; ==============================================================================
;;; Backend Registration
;;; ==============================================================================

;;;###autoload
(defun ai-code-eca-register-backend ()
  "Register ECA as an ai-code backend.

This adds ECA to `ai-code-backends' alist and makes it available
via `ai-code-select-backend'."
  (interactive)
  (ai-code-eca--ensure-available)
  
  ;; Check if already registered
  (unless (assoc 'eca ai-code-backends)
    (add-to-list 'ai-code-backends
                 '(eca
                   :label "ECA (Editor Code Assistant)"
                   :require ai-code-eca-bridge
                   :start ai-code-eca-start
                   :switch ai-code-eca-switch
                   :send ai-code-eca-send
                   :resume ai-code-eca-resume
                   :verify ai-code-eca-verify           ; Health check
                   :config "~/.config/eca/config.json"  ; ECA global config
                   :agent-file "AGENTS.md"              ; Standard agent instructions
                   :upgrade ai-code-eca-upgrade         ; Upgrade via package.el
                   :cli nil                             ; ECA is an Emacs package, not a CLI binary
                   :install-skills ai-code-eca-install-skills)  ; Skills installation function
                 t)  ; Append to end of list
    (message "ECA backend registered with ai-code"))
  
  (when (called-interactively-p 'interactive)
    (message "Available backends: %s"
             (mapconcat (lambda (b) (symbol-name (car b))) ai-code-backends ", "))))

;;;###autoload
(defun ai-code-eca-unregister-backend ()
  "Unregister ECA from ai-code backends."
  (interactive)
  (setq ai-code-backends (assq-delete-all 'eca ai-code-backends))
  (message "ECA backend unregistered from ai-code"))

;;; ==============================================================================
;;; Auto-registration
;;; ==============================================================================

;; Automatically register ECA backend when both ai-code-backends and eca are loaded
(with-eval-after-load 'ai-code-backends
  (with-eval-after-load 'eca
    (condition-case err
        (ai-code-eca-register-backend)
      (error
       (message "ECA backend auto-registration failed: %s" err)))))

(provide 'ai-code-eca-bridge)

;;; ai-code-eca-bridge.el ends here
