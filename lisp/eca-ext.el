;;; eca-ext.el --- ECA session multiplexing and context extensions -*- lexical-binding: t; -*-

;; This file extends ECA functionality without modifying upstream package files.
;; It provides session multiplexing and programmatic context management.

;;; Commentary:

;; Session Multiplexing:
;;   (eca-list-sessions)              → List all active sessions
;;   (eca-select-session)             → Interactively select a session
;;   (eca-switch-to-session)          → Switch to session and open chat buffer
;;   (eca-create-session-for-workspace) → Create new session for workspace
;;
;; Context Management:
;;   (eca-chat-add-file-context session file-path)
;;   (eca-chat-add-repo-map-context session)
;;   (eca-chat-add-cursor-context session file-path position)
;;   (eca-chat-add-clipboard-context session content)

;;; Code:

(require 'eca nil t)
(require 'eca-util nil t)
(require 'eca-chat nil t)

(defvar eca--sessions nil)
(defvar eca--session-id-cache nil)
(defvar eca-config-directory nil)

(declare-function eca-session "eca-util" ())
(declare-function eca-get "eca-util" (alist key))
(declare-function eca-info "eca-util" (format-string &rest args))
(declare-function eca-create-session "eca-util" (workspace-folders))
(declare-function eca-assert-session-running "eca-util" (session))
(declare-function eca--session-id "eca-util" (session))
(declare-function eca--session-status "eca-util" (session))
(declare-function eca--session-workspace-folders "eca-util" (session))
(declare-function eca--session-chats "eca-util" (session))
(declare-function eca-chat-open "eca-chat" (session))
(declare-function eca-chat--get-last-buffer "eca-chat" (session))
(declare-function eca-chat--add-context "eca-chat" (context-plist))
(declare-function eca-chat--with-current-buffer "eca-chat" (&rest body))

;;; Session Multiplexing

;;;###autoload
(defun eca-list-sessions ()
  "Return a list of all active ECA sessions.
Each element is a plist with :id, :status, :workspace-folders, :chat-count.
Returns nil if ECA is not initialized or has no sessions."
  (and (boundp 'eca--sessions)
       eca--sessions
       (mapcar (lambda (pair)
                 (let ((session (cdr pair)))
                   (list :id (eca--session-id session)
                         :status (eca--session-status session)
                         :workspace-folders (eca--session-workspace-folders session)
                         :chat-count (length (eca--session-chats session)))))
               eca--sessions)))

;;;###autoload
(defun eca-select-session (&optional session-id)
  "Select an ECA session by SESSION-ID or interactively.
Returns the selected session or nil if cancelled.
When called interactively, prompts for session selection."
  (interactive)
  (let* ((sessions (eca-list-sessions))
         (choices (and sessions
                       (> (length sessions) 1)
                       (mapcar (lambda (s)
                                 (cons (format "Session %d: %s (%s) - %d chats"
                                               (plist-get s :id)
                                               (mapconcat #'identity (plist-get s :workspace-folders) ", ")
                                               (plist-get s :status)
                                               (plist-get s :chat-count))
                                       (plist-get s :id)))
                               sessions)))
         (session-id
          (or session-id
              (if (null sessions)
                  (progn
                    (message "No active ECA sessions")
                    nil)
                (if (= (length sessions) 1)
                    (plist-get (car sessions) :id)
                  (cdr (assoc (completing-read "Select ECA session: " choices nil t)
                              choices)))))))
    (when session-id
      (let ((session (condition-case nil
                           (eca-get eca--sessions session-id)
                         (error nil))))
        (if session
            (progn
              (setq eca--session-id-cache session-id)
              (when (called-interactively-p 'interactive)
                (eca-info "Switched to session %d" session-id))
              session)
          (user-error "Session %s not found (may have been deleted)" session-id))))))

;;;###autoload
(defun eca-switch-to-session (&optional session-id)
  "Switch to ECA session SESSION-ID and open its last chat buffer.
When called interactively, prompts for session selection."
  (interactive)
  (let ((session (eca-select-session session-id)))
    (when session
      (eca-chat-open session)
      (pop-to-buffer (eca-chat--get-last-buffer session))
      session)))

;;;###autoload
(defun eca-create-session-for-workspace (workspace-roots)
  "Create a new ECA session for WORKSPACE-ROOTS and switch to it.
Returns the new session."
  (interactive (list (list (read-directory-name "Workspace root: "))))
  (let ((session (eca-create-session workspace-roots)))
    (unless session
      (user-error "Failed to create ECA session for %s"
                  (mapconcat #'identity workspace-roots ", ")))
    (eca-info "Created session %d for %s"
              (eca--session-id session)
              (mapconcat #'identity workspace-roots ", "))
    (when (called-interactively-p 'interactive)
      (eca-switch-to-session (eca--session-id session)))
    session))

;;; Context Management Extensions

;;;###autoload
(defun eca-chat-add-file-context (session file-path)
  "Add FILE-PATH as context to SESSION.
This is a programmatic interface for adding file context."
  (eca-assert-session-running session)
  (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
    (eca-chat--add-context (list :type "file" :path (expand-file-name file-path)))
    (eca-chat-open session)))

;;;###autoload
(defun eca-chat-add-repo-map-context (session)
  "Add repository map context to SESSION."
  (eca-assert-session-running session)
  (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
    (eca-chat--add-context (list :type "repoMap"))
    (eca-chat-open session)))

;;;###autoload
(defun eca-chat-add-cursor-context (session file-path position)
  "Add cursor context to SESSION at FILE-PATH and POSITION.
POSITION is a buffer position (integer)."
  (eca-assert-session-running session)
  (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
    (save-restriction
      (widen)
      (goto-char position)
      (let* ((start (line-beginning-position))
             (end (line-end-position))
             (start-line (line-number-at-pos start))
             (end-line (line-number-at-pos end))
             (start-char (- position start))
             (end-char (- end start)))
        (eca-chat--add-context
         (list :type "cursor"
               :path (expand-file-name file-path)
               :position (list :start (list :line start-line :character start-char)
                               :end (list :line end-line :character end-char))))))
    (eca-chat-open session)))

;;;###autoload
(defun eca-chat-add-clipboard-context (session content)
  "Add CLIPBOARD CONTENT as a temporary file context to SESSION.
The content is saved to a temporary file and added as context."
  (eca-assert-session-running session)
  (let* ((temp-dir (file-name-as-directory
                    (or (bound-and-true-p eca-config-directory)
                        (expand-file-name "~/.eca"))))
         (tmp-subdir (expand-file-name "tmp" temp-dir))
         (temp-file (expand-file-name
                     (format "clipboard-%d-%d-%d.txt" (emacs-pid) (floor (float-time)) (random 1000000))
                     tmp-subdir)))
    (unless (file-directory-p tmp-subdir)
      (make-directory tmp-subdir t))
    (with-temp-file temp-file
      (insert content))
    (eca--register-temp-file temp-file)
    (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
      (eca-chat--add-context (list :type "file" :path temp-file))
      (eca-chat-open session))
    (eca-info "Added clipboard context (%d chars)" (length content))))

;;;###autoload
(defun eca-chat-add-clipboard-context-now ()
  "Add current clipboard contents as context to the current ECA session."
  (interactive)
  (let ((session (eca-session)))
    (if session
        (let ((clip-content (current-kill 0 t)))
          (if (and clip-content (not (string-empty-p clip-content)))
              (eca-chat-add-clipboard-context session clip-content)
            (message "Clipboard is empty")))
      (user-error "No ECA session active"))))

;;; Temp File Management

(defvar eca--context-temp-files nil
  "List of temporary context files created by eca-ext.
Used for cleanup on session end or Emacs exit.")

(defun eca--cleanup-temp-context-files ()
  "Clean up all temporary context files created by eca-ext."
  (let ((count (length eca--context-temp-files)))
    (dolist (file eca--context-temp-files)
      (condition-case nil
          (when (and file (file-exists-p file))
            (delete-file file))
        (error nil)))
    (setq eca--context-temp-files nil)
    (when (and (fboundp 'eca-info) (> count 0))
      (eca-info "Cleaned up %d temporary context files" count))))

(add-hook 'kill-emacs-hook #'eca--cleanup-temp-context-files)

;;;###autoload
(defun eca--register-temp-file (file-path)
  "Register FILE-PATH for cleanup on Emacs exit.
Returns FILE-PATH.  Only registers if file exists."
  (when (and file-path (file-exists-p file-path))
    (push file-path eca--context-temp-files)
    file-path))

;;;###autoload
(defun eca--cleanup-session-temp-files (_session)
  "Clean up temp files associated with SESSION.
Currently a no-op; future enhancement: track files per-session."
  nil)

(provide 'eca-ext)

;;; eca-ext.el ends here
