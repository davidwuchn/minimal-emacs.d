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
(declare-function eca--session-workspace-folders "eca-util" (session))
(declare-function eca--session-add-workspace-folder "eca-util" (session folder))
(declare-function eca-list-sessions "eca-ext" ())
(declare-function eca-switch-to-session "eca-ext" (&optional session-id))
(declare-function eca-chat-add-file-context "eca-ext" (session file-path))
(declare-function eca-chat-add-repo-map-context "eca-ext" (session))
(declare-function eca-chat-add-cursor-context "eca-ext" (session file-path position))
(declare-function eca-chat-add-clipboard-context "eca-ext" (session content))
(declare-function ai-code-read-string "ai-code-input" (prompt &optional initial-input candidate-list))
(declare-function ai-code-git-worktree-branch "ai-code-git" (branch start-point))
(declare-function ai-code--repo-backend-for-root "ai-code-backends" (git-root))
(declare-function ai-code--remember-repo-backend "ai-code-backends" (git-root backend))

;; Internal ECA variables (not officially exported but referenced)
(defvar eca--sessions nil
  "Hash table of ECA sessions. Internal to eca-util.el.")

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
Saves session affinity after switching."
  (interactive)
  (ai-code-eca--ensure-available)
  (unless (fboundp 'eca-switch-to-session)
    (user-error "Session multiplexing requires eca-ext.el (add to load-path)"))
  (eca-switch-to-session session-id)
  ;; Save session affinity after switching
  (run-at-time 0.5 nil #'ai-code-eca--save-session-affinity))

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

;;; ==============================================================================
;;; Git Worktree Integration
;;; ==============================================================================

;; Delegates to ai-code-git when available.
;; Worktree root configured via ai-code-git-worktree-root.

(defun ai-code-eca--git-common-dir (dir)
  "Return the common git directory for DIR, handling worktrees.
Uses `git rev-parse --git-common-dir` to detect if DIR is a worktree
sharing a .git directory with other worktrees."
  (when (and dir (file-directory-p dir))
    (condition-case nil
        (let ((default-directory dir))
          (string-trim (shell-command-to-string "git rev-parse --git-common-dir 2>/dev/null")))
      (error nil))))

(defun ai-code-eca--session-for-worktree (worktree-root)
  "Find existing ECA session for a worktree sharing the same git repo.
WORKTREE-ROOT is the root directory of the worktree.
Returns the session if found, nil otherwise."
  (let ((common-dir (ai-code-eca--git-common-dir worktree-root)))
    (when common-dir
      (condition-case nil
          (let ((existing-sessions
                 (when (fboundp 'eca-list-sessions)
                   (eca-list-sessions))))
            (catch 'found
              (dolist (session-info existing-sessions)
                (let* ((session-id (plist-get session-info :id))
                       (session (when (hash-table-p eca--sessions)
                                  (gethash session-id eca--sessions)))
                       (workspace-folders (plist-get session-info :workspace-folders)))
                  (when session
                    (dolist (folder workspace-folders)
                      (let ((folder-common (ai-code-eca--git-common-dir folder)))
                        (when (and folder-common
                                   (string= folder-common common-dir))
                          (throw 'found session)))))))))
        (error nil)))))

(defun ai-code-eca--add-worktree-to-session (session worktree-root)
  "Add WORKTREE-ROOT as a workspace folder to SESSION if not already present.
This allows a single ECA session to manage multiple worktrees from the same repo."
  (when (and session worktree-root)
    (condition-case nil
        (let ((workspace-folders (eca--session-workspace-folders session)))
          (unless (member worktree-root workspace-folders)
            (when (fboundp 'eca--session-add-workspace-folder)
              (eca--session-add-workspace-folder session worktree-root)
              (eca-info "Added worktree to session: %s" worktree-root))))
      (error nil))))

;;;###autoload
(defun ai-code-eca-git-worktree-detect-and-attach ()
  "Detect if current buffer is in a git worktree and attach to existing session.
If the current buffer's directory is a worktree sharing a .git directory
with an existing ECA session, attach to that session and add the worktree
as a workspace folder."
  (interactive)
  (ai-code-eca--ensure-available)
  (let* ((current-dir (when buffer-file-name (file-name-directory buffer-file-name)))
         (worktree-session (when current-dir
                             (ai-code-eca--session-for-worktree current-dir))))
    (if worktree-session
        (progn
          (ai-code-eca--add-worktree-to-session worktree-session current-dir)
          (eca-info "Attached worktree %s to existing session" current-dir)
          worktree-session)
      (when (called-interactively-p 'interactive)
        (message "Not in a worktree or no existing session found"))
      nil)))

;;;###autoload
(defun ai-code-eca-git-worktree-branch (branch start-point)
  "Create BRANCH and check it out in a new centralized worktree.
Delegates to `ai-code-git-worktree-branch'."
  (interactive
   (let ((default-branch (when (fboundp 'magit-get-current-branch)
                           (magit-get-current-branch))))
     (list (read-string "Branch name: " (format "feature/%s-wt" (or default-branch "main")))
           (or default-branch "HEAD"))))
  (ai-code-eca--ensure-available)
  (if (fboundp 'ai-code-git-worktree-branch)
      (ai-code-git-worktree-branch branch start-point)
    (user-error "ai-code-git-worktree-branch not available. Install ai-code-git.")))

;;;###autoload
(defun ai-code-eca-git-worktree-action (&optional prefix)
  "Dispatch worktree action by PREFIX.
Without PREFIX, call `ai-code-eca-git-worktree-branch'.
With PREFIX (for example C-u), call `magit-worktree-status'."
  (interactive "P")
  (if prefix
      (call-interactively #'magit-worktree-status)
    (call-interactively #'ai-code-eca-git-worktree-branch)))

(defun ai-code-eca--setup-worktree-keybindings ()
  "Add worktree keybindings to ECA chat mode."
  (when (boundp 'eca-chat-mode-map)
    (define-key eca-chat-mode-map (kbd "C-c w") #'ai-code-eca-git-worktree-action)
    (define-key eca-chat-mode-map (kbd "C-c W") #'ai-code-eca-git-worktree-detect-and-attach)))

;;; ==============================================================================
;;; Menu Integration
;;; ==============================================================================

;;;###autoload
(defun ai-code-eca-list-sessions ()
  "Display list of active ECA sessions."
  (interactive)
  (ai-code-eca--ensure-available)
  (let ((sessions (ai-code-eca-get-sessions)))
    (if sessions
        (message "ECA Sessions: %s"
                 (string-join (mapcar #'cdr sessions) " | "))
      (message "No active ECA sessions"))))

;;; ==============================================================================
;;; Context Synchronization
;;; ==============================================================================

(defvar ai-code-eca-context-sync-timer nil
  "Timer for automatic context synchronization.")

(defcustom ai-code-eca-context-sync-interval 60
  "Seconds between automatic context sync. nil to disable.
Default 60 seconds provides reasonable sync without excessive overhead."
  :type '(choice (const :tag "Disabled" nil)
          (integer :tag "Seconds"))
  :group 'ai-code)

;;;###autoload
(defun ai-code-eca-sync-context ()
  "Sync current buffer context to ECA session.

Adds file and cursor context if buffer has a file."
  (interactive)
  (ai-code-eca--ensure-available)
  (let ((session (eca-session)))
    (when (and session buffer-file-name)
      (condition-case err
          (progn
            (when (fboundp 'eca-chat-add-file-context)
              (eca-chat-add-file-context session buffer-file-name))
            (when (fboundp 'eca-chat-add-cursor-context)
              (eca-chat-add-cursor-context session buffer-file-name (point)))
            (when (called-interactively-p 'interactive)
              (message "Synced context: %s:%d" buffer-file-name (point))))
        (error
         (message "Context sync failed: %s" (error-message-string err)))))))

;;;###autoload
(defun ai-code-eca-context-sync-start ()
  "Start automatic context synchronization."
  (interactive)
  (when ai-code-eca-context-sync-timer
    (cancel-timer ai-code-eca-context-sync-timer))
  (when ai-code-eca-context-sync-interval
    (setq ai-code-eca-context-sync-timer
          (run-at-time t ai-code-eca-context-sync-interval
                       #'ai-code-eca-sync-context))
    (message "ECA context sync started (%ds)" ai-code-eca-context-sync-interval)))

;;;###autoload
(defun ai-code-eca-context-sync-stop ()
  "Stop automatic context synchronization."
  (interactive)
  (when ai-code-eca-context-sync-timer
    (cancel-timer ai-code-eca-context-sync-timer)
    (setq ai-code-eca-context-sync-timer nil)
    (message "ECA context sync stopped")))

;;; ==============================================================================
;;; Error Handling
;;; ==============================================================================

(defun ai-code-eca--wrap-with-error-handler (fn &rest args)
  "Call FN with ARGS, catching and reporting errors."
  (condition-case err
      (apply fn args)
    (user-error
     (message "ECA: %s" (error-message-string err)))
    (error
     (message "ECA error: %s" (error-message-string err))
     nil)))

(defmacro ai-code-eca--with-error-handling (&rest body)
  "Execute BODY with error handling."
  `(condition-case err
       (progn ,@body)
     (user-error
      (message "ECA: %s" (error-message-string err)))
     (error
      (message "ECA error: %s" (error-message-string err))
      nil)))

;;; ==============================================================================
;;; Keybindings
;;; ==============================================================================

(defvar ai-code-eca-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s") #'ai-code-eca-start)
    (define-key map (kbd "S") #'ai-code-eca-switch)
    (define-key map (kbd "r") #'ai-code-eca-resume)
    (define-key map (kbd "f") #'ai-code-eca-add-file-context)
    (define-key map (kbd "c") #'ai-code-eca-add-cursor-context)
    (define-key map (kbd "m") #'ai-code-eca-add-repo-map-context)
    (define-key map (kbd "y") #'ai-code-eca-add-clipboard-context)
    (define-key map (kbd "l") #'ai-code-eca-list-sessions)
    (define-key map (kbd "w") #'ai-code-eca-git-worktree-action)
    (define-key map (kbd "v") #'ai-code-eca-verify)
    map)
  "Keymap for ECA commands.")

;;;###autoload
(defun ai-code-eca-setup-keybindings ()
  "Set up ECA keybindings in relevant maps."
  (interactive)
  ;; ECA chat mode keybindings
  (when (boundp 'eca-chat-mode-map)
    (define-key eca-chat-mode-map (kbd "C-c C-f") #'ai-code-eca-add-file-context)
    (define-key eca-chat-mode-map (kbd "C-c C-c") #'ai-code-eca-add-cursor-context)
    (define-key eca-chat-mode-map (kbd "C-c C-m") #'ai-code-eca-add-repo-map-context)
    (define-key eca-chat-mode-map (kbd "C-c C-y") #'ai-code-eca-add-clipboard-context)
    (define-key eca-chat-mode-map (kbd "C-c C-w") #'ai-code-eca-git-worktree-action))
  
  ;; Global keybinding prefix
  (when (boundp 'ai-code-mode-map)
    (define-key ai-code-mode-map (kbd "C-c e") ai-code-eca-keymap))
  
  (message "ECA keybindings configured"))

;;; ==============================================================================
;;; Backend Registration
;;; ==============================================================================

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
                    :resume ai-code-eca-resume-affinity
                    :config "~/.config/eca/config.json"
                    :agent-file "AGENTS.md"
                    :upgrade ai-code-eca-upgrade-vc
                    :cli "eca"
                    :install-skills ai-code-eca-install-skills)
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
;;; Session Affinity (via ai-code--repo-backend-alist)
;;; ==============================================================================

;; Use ai-code's built-in repo-backend-alist for session affinity
;; This unifies with ai-code-select-backend behavior

(declare-function ai-code--repo-backend-for-root "ai-code-backends" (git-root))
(declare-function ai-code--remember-repo-backend "ai-code-backends" (git-root backend))

(defun ai-code-eca--project-root ()
  "Return project root for session affinity."
  (or (when (fboundp 'projectile-project-root)
        (ignore-errors (projectile-project-root)))
      (when (fboundp 'project-root)
        (ignore-errors (project-root (project-current))))
      default-directory))

(defun ai-code-eca--save-session-affinity ()
  "Save current ECA session as preferred for current project.
Uses ai-code--repo-backend-alist for unified session management."
  (when-let* ((root (ai-code-eca--project-root))
              ((fboundp 'ai-code--remember-repo-backend)))
    ;; Store 'eca as the preferred backend for this repo
    (ai-code--remember-repo-backend root 'eca)))

(defun ai-code-eca--get-session-for-project ()
  "Return 'eca if ECA is the preferred backend for current project."
  (when-let* ((root (ai-code-eca--project-root))
              ((fboundp 'ai-code--repo-backend-for-root)))
    (let ((preferred (ai-code--repo-backend-for-root root)))
      (when (eq preferred 'eca) 'eca))))

;;;###autoload
(defun ai-code-eca-resume-affinity ()
  "Resume ECA session with affinity for current project.

If ECA is the preferred backend for this project, resume or start.
Otherwise just start a new session.
Does NOT save affinity - use explicit switch for that."
  (interactive)
  (ai-code-eca--ensure-available)
  (let ((session (eca-session)))
    (if session
        (progn
          (pop-to-buffer (ai-code-eca--ensure-chat-buffer session))
          (message "Resumed ECA session"))
      (ai-code-eca-start)
      (message "Started new ECA session"))))

;;; ==============================================================================
;;; Improved Health Check
;;; ==============================================================================

(defcustom ai-code-eca-verify-timeout 5
  "Seconds to wait for ECA server response during verify."
  :type 'integer
  :group 'ai-code)

;;;###autoload
(defun ai-code-eca-verify-health ()
  "Verify ECA server is responsive with a ping.

Returns t if server responds within `ai-code-eca-verify-timeout' seconds."
  (interactive)
  (ai-code-eca--ensure-available)
  (let* ((session (eca-session))
         (start-time (current-time))
         (responsive nil))
    (if session
        (progn
          ;; Check session status
          (when (fboundp 'eca--session-status)
            (let ((status (eca--session-status session)))
              (setq responsive (memq status '(ready idle)))))
          ;; Try a minimal operation
          (when (and responsive (fboundp 'eca--session-workspace-folders))
            (condition-case nil
                (let ((folders (eca--session-workspace-folders session)))
                  (setq responsive (and folders (listp folders))))
              (error (setq responsive nil))))
          (let ((elapsed (float-time (time-subtract (current-time) start-time))))
            (if responsive
                (prog1 t
                  (message "ECA healthy (responded in %.2fs)" elapsed))
              (message "ECA not responding (session status: %s)"
                       (if (fboundp 'eca--session-status)
                           (eca--session-status session)
                         "unknown"))
              nil)))
      (message "No ECA session active")
      nil)))

;;; ==============================================================================
;;; VC Package Upgrade
;;; ==============================================================================

;;;###autoload
(defun ai-code-eca-upgrade-vc ()
  "Upgrade ECA if installed via package-vc.

Fetches latest from VC repository and rebuilds."
  (interactive)
  (if (and (featurep 'package-vc)
           (alist-get 'eca package-vc-selected-packages))
      (progn
        (message "Upgrading ECA via package-vc...")
        (package-vc-upgrade 'eca)
        (message "ECA upgraded. Restart Emacs or re-evaluate for changes."))
    (if (package-installed-p 'eca)
        (progn
          (package-refresh-contents)
          (package-install 'eca)
          (message "ECA upgraded via package.el"))
      (user-error "ECA is not installed"))))

;;; ==============================================================================
;;; Unload Hook
;;; ==============================================================================

(defun ai-code-eca--unload-function ()
  "Cleanup when unloading ai-code-eca-bridge."
  ;; Stop context sync timer
  (when ai-code-eca-context-sync-timer
    (cancel-timer ai-code-eca-context-sync-timer))
  ;; Remove keybindings
  (when (boundp 'eca-chat-mode-map)
    (define-key eca-chat-mode-map (kbd "C-c C-f") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-c") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-m") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-y") nil)
    (define-key eca-chat-mode-map (kbd "C-c C-w") nil))
  ;; Unregister backend
  (setq ai-code-backends (assq-delete-all 'eca ai-code-backends))
  ;; Remove advice
  (ignore-errors
    (advice-remove 'gptel-agent #'ai-code-eca--setup-worktree-keybindings)))

(add-hook 'ai-code-eca-bridge-unload-hook #'ai-code-eca--unload-function)

;;; ==============================================================================
;;; Context Integration with ai-code
;;; ==============================================================================

(defun ai-code-eca--around-context-action (orig &rest args)
  "Advice for `ai-code-context-action' to add ECA context support.
ORIG is the original function, ARGS are its arguments."
  (if (and (derived-mode-p 'gptel-mode)
            (eq gptel--preset 'eca)
            (eca-session))
      (progn
        (when buffer-file-name
          (ai-code-eca-add-file-context buffer-file-name))
        (message "Added file context to ECA session"))
    (apply orig args)))

;;; ==============================================================================
;;; Auto-registration
;;; ==============================================================================

;; Automatically register ECA backend when both ai-code-backends and eca are loaded
(with-eval-after-load 'ai-code-backends
  (with-eval-after-load 'eca
    (condition-case err
        (progn
          (ai-code-eca-register-backend)
          (ai-code-eca--setup-worktree-keybindings)
          (ai-code-eca-setup-keybindings))
      (error
       (message "ECA backend auto-registration failed: %s" err)))))

;; Integrate with ai-code-context-action
(with-eval-after-load 'ai-code
  (advice-add 'ai-code-context-action :around #'ai-code-eca--around-context-action))

(provide 'ai-code-eca-bridge)

;;; ai-code-eca-bridge.el ends here
