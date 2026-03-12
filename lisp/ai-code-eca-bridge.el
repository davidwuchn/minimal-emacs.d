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

(declare-function eca "eca" (&optional arg))
(declare-function eca-session "eca-util" ())
(declare-function eca-chat-open "eca-chat" (session))
(declare-function eca-chat-send-prompt "eca-chat" (session message))
(declare-function eca-chat--get-last-buffer "eca-chat" (session))
(declare-function ai-code-read-string "ai-code-input" (prompt &optional initial-input candidate-list))

;;;###autoload
(defun ai-code-eca-start (&optional arg)
  "Start a new ECA session.

With prefix ARG, prompt for additional ECA arguments.
This function satisfies ai-code's :start backend contract."
  (interactive "P")
  (ai-code-eca--ensure-available)
  (let ((current-prefix-arg arg))
    (call-interactively #'eca))
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
        (progn
          (eca-chat-open session)
          (pop-to-buffer (eca-chat--get-last-buffer session)))
      (user-error "No ECA session. Run M-x ai-code-eca-start first"))))

;;;###autoload
(defun ai-code-eca-send (line)
  "Send LINE to ECA chat.

This function satisfies ai-code's :send backend contract."
  (interactive "sECA> ")
  (ai-code-eca--ensure-available)
  (let ((session (eca-session)))
    (if session
        (progn
          (eca-chat-open session)  ; Ensure buffer exists
          (eca-chat-send-prompt session line))
      (user-error "No ECA session. Run M-x ai-code-eca-start first"))))

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
            (eca-chat-open session)
            (pop-to-buffer (eca-chat--get-last-buffer session))
            (message "Resumed ECA session"))
        ;; No existing session, start a new one
        (ai-code-eca-start)
        (message "Started new ECA session")))))

;;;###autoload
(defun ai-code-eca--ensure-available ()
  "Ensure `eca' package and required functions are available.

Signals user-error if ECA cannot be used."
  (unless (require 'eca nil t)
    (user-error "ECA backend not available. Please install eca package."))
  (dolist (fn '(eca eca-session eca-chat-open eca-chat-send-prompt eca-chat--get-last-buffer))
    (unless (fboundp fn)
      (user-error "ECA backend missing required function: %s" fn))))

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
This function satisfies ai-code's :verify backend contract."
  (condition-case nil
      (progn
        (ai-code-eca--ensure-available)
        (let ((session (eca-session)))
          (and session
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
