;;; eca-ext.el --- ECA session multiplexing and context extensions -*- lexical-binding: t; -*-

;; This file extends ECA functionality without modifying upstream package files.
;; It provides session multiplexing and programmatic context management.

;;; Commentary:

;; Session Multiplexing (not in upstream):
;;   (eca-list-sessions)              → List all active sessions
;;   (eca-select-session)             → Interactively select a session
;;   (eca-switch-to-session)          → Switch to session and open chat buffer
;;   (eca-create-session-for-workspace) → Create new session for workspace
;;
;; Workspace Management (extends upstream):
;;   (eca-list-workspace-folders)     → List folders in current session
;;   (eca-add-workspace-folder)       → Add folder to session
;;   (eca-remove-workspace-folder)    → Remove folder from session
;;   (eca-workspace-folder-for-file)  → Find which workspace owns a file
;;
;; Context Management (programmatic API):
;;   (eca-chat-add-file-context session file-path)
;;   (eca-chat-add-repo-map-context session)
;;   (eca-chat-add-cursor-context session file-path position)
;;   (eca-chat-add-clipboard-context session content)
;;
;; Note: Upstream ECA now provides:
;;   - eca-chat-add-workspace-root (interactive)
;;   - eca--session-add-workspace-folder (internal)
;;   - eca--session-for-worktree (worktree detection)
;;   - Automatic worktree detection in eca-session

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
(declare-function eca--session-add-workspace-folder "eca-util" (session folder))
(declare-function eca--session-chats "eca-util" (session))
(declare-function eca-chat-open "eca-chat" (session))
(declare-function eca-chat--get-last-buffer "eca-chat" (session))
(declare-function eca-chat--add-context "eca-chat" (context-plist))
(declare-function eca-chat--with-current-buffer "eca-chat" (&rest body))
(declare-function eca-api-notify "eca-api" (session &rest args))

;;; Session Multiplexing

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

(defun eca-switch-to-session (&optional session-id)
  "Switch to ECA session SESSION-ID and open its last chat buffer.
When called interactively, prompts for session selection."
  (interactive)
  (let ((session (eca-select-session session-id)))
    (when session
      (eca-chat-open session)
      (pop-to-buffer (eca-chat--get-last-buffer session))
      session)))

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

;;; Workspace Management

(defun eca-list-workspace-folders (&optional session)
  "Return list of workspace folders for SESSION or current session.
Returns nil if no session is active."
  (let ((sess (or session (eca-session))))
    (when sess
      (eca--session-workspace-folders sess))))

(defun eca-add-workspace-folder (folder &optional session)
  "Add FOLDER to SESSION's workspace.
SESSION defaults to current session.  Returns the folder path on success.
Shows session ID in feedback for multi-session awareness."
  (interactive
   (let ((session (eca-session)))
     (unless session
       (user-error "No ECA session active"))
     (list (read-directory-name "Add workspace folder: ") session)))
  (let ((sess (or session (eca-session))))
    (unless sess
      (user-error "No ECA session active"))
    (let* ((folder (expand-file-name folder))
           (existing (eca--session-workspace-folders sess))
           (session-id (eca--session-id sess)))
      (unless (file-directory-p folder)
        (user-error "Directory does not exist: %s" folder))
      (when (member folder existing)
        (user-error "Folder already in workspace: %s" folder))
      (eca--session-add-workspace-folder sess folder)
      (eca-info "Added workspace folder to session %d: %s" session-id folder)
      folder)))

(defalias 'eca-chat-add-workspace-folder #'eca-add-workspace-folder
  "Alias for `eca-add-workspace-folder' for discoverability.")

(defun eca-add-workspace-folder-all-sessions (folder)
  "Add FOLDER to ALL active sessions' workspaces.
Useful for shared libraries across multiple projects."
  (interactive "DAdd to all sessions: ")
  (let* ((folder (expand-file-name folder))
         (sessions (eca-list-sessions))
         (added 0)
         (skipped 0))
    (unless sessions
      (user-error "No active ECA sessions"))
    (unless (file-directory-p folder)
      (user-error "Directory does not exist: %s" folder))
    (dolist (info sessions)
      (let* ((session-id (plist-get info :id))
             (session (condition-case nil
                            (eca-get eca--sessions session-id)
                          (error nil)))
             (existing (when session (eca--session-workspace-folders session))))
        (if (member folder existing)
            (cl-incf skipped)
          (when session
            (eca--session-add-workspace-folder session folder)
            (cl-incf added)))))
    (eca-info "Added %s to %d session(s), skipped %d (already present)"
              folder added skipped)))

(defun eca-remove-workspace-folder (folder &optional session)
  "Remove FOLDER from SESSION's workspace.
SESSION defaults to current session.  Returns the removed folder on success.
Shows session ID in feedback for multi-session awareness."
  (interactive
   (let* ((session (eca-session))
          (folders (when session (eca--session-workspace-folders session))))
     (unless session
       (user-error "No ECA session active"))
     (unless folders
       (user-error "No workspace folders in session"))
     (list (completing-read "Remove workspace folder: " folders nil t) session)))
  (let ((sess (or session (eca-session))))
    (unless sess
      (user-error "No ECA session active"))
    (let* ((folder (expand-file-name folder))
           (existing (eca--session-workspace-folders sess))
           (session-id (eca--session-id sess)))
      (unless (member folder existing)
        (user-error "Folder not in workspace: %s" folder))
      (setf (eca--session-workspace-folders sess)
            (remove folder existing))
      (when (fboundp 'eca-api-notify)
        (eca-api-notify
         sess
         :method "workspace/didChangeWorkspaceFolders"
         :params (list :event
                       (list :added []
                             :removed (vector
                                       (list :uri (concat "file://" folder)
                                             :name (file-name-nondirectory
                                                    (directory-file-name folder))))))))
      (eca-info "Removed workspace folder from session %d: %s" session-id folder)
      folder)))

(defun eca-workspace-folder-for-file (file-path &optional session)
  "Return the workspace folder that contains FILE-PATH in SESSION.
SESSION defaults to current session.  Returns nil if file is not
in any workspace folder."
  (let* ((sess (or session (eca-session)))
         (folders (when sess (eca--session-workspace-folders sess)))
         (file-path (expand-file-name file-path)))
    (when folders
      (seq-find (lambda (folder)
                   (string-prefix-p (file-name-as-directory folder)
                                    (file-name-as-directory file-path)))
                 folders))))

(defun eca-workspace-provenance (file-path &optional session)
  "Return plist with workspace provenance for FILE-PATH in SESSION.
Result contains :workspace, :relative-path, and :folder-name.
Returns nil if file is not in any workspace."
  (let* ((workspace (eca-workspace-folder-for-file file-path session)))
    (when workspace
      (list :workspace workspace
            :relative-path (file-relative-name file-path workspace)
            :folder-name (file-name-nondirectory
                          (directory-file-name workspace))))))

;;; Context Management Extensions (programmatic API)

(defun eca-chat-add-file-context (session file-path)
  "Add FILE-PATH as context to SESSION.
This is a programmatic interface for adding file context.
Includes workspace provenance when file is in a workspace folder."
  (eca-assert-session-running session)
  (let* ((file-path (expand-file-name file-path))
         (prov (eca-workspace-provenance file-path session))
         (context (list :type "file" :path file-path)))
    (when prov
      (setq context (append context (list :workspace prov))))
    (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
      (eca-chat--add-context context)
      (eca-chat-open session))))

(defun eca-chat-add-repo-map-context (session)
  "Add repository map context to SESSION.

This sends a :type \"repoMap\" context to ECA, requesting a
repository structure overview. ECA supports this context type
and will generate a summary of workspace files.

See also `eca-chat-auto-add-repomap' for automatic inclusion."
  (eca-assert-session-running session)
  (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
    (eca-chat--add-context (list :type "repoMap"))
    (eca-chat-open session)))

(defun eca-chat-add-cursor-context (session file-path position)
  "Add cursor context to SESSION at FILE-PATH and POSITION.
POSITION is a buffer position (integer).
Includes workspace provenance when file is in a workspace folder."
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
             (end-char (- end start))
             (file-path (expand-file-name file-path))
             (prov (eca-workspace-provenance file-path session))
             (context (list :type "cursor"
                            :path file-path
                            :position (list :start (list :line start-line :character start-char)
                                            :end (list :line end-line :character end-char)))))
        (when prov
          (setq context (append context (list :workspace prov))))
        (eca-chat--add-context context)))
    (eca-chat-open session)))

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
    (eca--register-temp-file temp-file session)
    (eca-chat--with-current-buffer (eca-chat--get-last-buffer session)
      (eca-chat--add-context (list :type "file" :path temp-file))
      (eca-chat-open session))
    (eca-info "Added clipboard context (%d chars)" (length content))))

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

;;; Temp File Management (for clipboard context)

(defvar eca--context-temp-files nil
  "List of temporary context files created by eca-ext.
Used for cleanup on session end or Emacs exit.

Format: ((session-id . (file-path1 file-path2 ...)) ...)")

(defvar eca--temp-file-max-age (* 24 3600)
  "Max age in seconds before temp files are considered stale.
Default: 24 hours.  Set to nil to disable age-based cleanup.")

(defun eca--cleanup-temp-context-files ()
  "Clean up all temporary context files created by eca-ext."
  (let ((count 0))
    (dolist (entry eca--context-temp-files)
      (dolist (file (cdr entry))
        (condition-case nil
            (when (and file (file-exists-p file))
              (delete-file file)
              (cl-incf count))
          (error nil))))
    (setq eca--context-temp-files nil)
    (when (and (fboundp 'eca-info) (> count 0))
      (eca-info "Cleaned up %d temporary context files" count))))

(defun eca--cleanup-stale-temp-files ()
  "Clean up temp files older than `eca--temp-file-max-age'."
  (when eca--temp-file-max-age
    (let ((now (float-time))
          (count 0))
      (dolist (entry eca--context-temp-files)
        (setcdr entry
                (cl-remove-if
                 (lambda (file)
                   (when (and file (file-exists-p file))
                     (let ((age (- now (float-time (nth 5 (file-attributes file))))))
                       (when (> age eca--temp-file-max-age)
                         (condition-case nil
                             (delete-file file)
                           (error nil))
                         (cl-incf count)
                         t))))
                 (cdr entry))))
      (when (and (fboundp 'eca-info) (> count 0))
        (eca-info "Cleaned up %d stale temp files (older than %d hours)"
                  count (/ eca--temp-file-max-age 3600))))))

(add-hook 'kill-emacs-hook #'eca--cleanup-temp-context-files)
(run-with-timer 3600 3600 #'eca--cleanup-stale-temp-files)

(defun eca--register-temp-file (file-path &optional session)
  "Register FILE-PATH for cleanup on Emacs exit or session end.
SESSION defaults to current session.  Only registers if file exists."
  (when (and file-path (file-exists-p file-path))
    (let* ((sid (if session
                    (if (numberp session) session (eca--session-id session))
                  (when (boundp 'eca--session-id-cache)
                    eca--session-id-cache)))
           (entry (assoc sid eca--context-temp-files)))
      (if entry
          (push file-path (cdr entry))
        (push (cons sid (list file-path)) eca--context-temp-files)))
    file-path))

(defun eca--cleanup-session-temp-files (session)
  "Clean up temp files associated with SESSION."
  (let* ((sid (if (numberp session) session (eca--session-id session)))
         (entry (assoc sid eca--context-temp-files))
         (files (cdr entry))
         (count 0))
    (when files
      (dolist (file files)
        (condition-case nil
            (when (and file (file-exists-p file))
              (delete-file file)
              (cl-incf count))
          (error nil)))
      (setq eca--context-temp-files (assq-delete-all sid eca--context-temp-files))
      (when (and (fboundp 'eca-info) (> count 0))
        (eca-info "Cleaned up %d temp files for session %s" count sid)))))

;;; Auto Session Detection (Gap 5 fix)

(defcustom eca-auto-add-workspace-folder t
  "If non-nil, automatically add file's project to current session's workspace.
When opening a file outside the current workspace, the project root
is added to the session's workspace folders automatically.

If 'prompt, ask before adding.
If nil, do nothing."
  :type '(choice (const :tag "Auto add" t)
                 (const :tag "Prompt before adding" prompt)
                 (const :tag "Disabled" nil))
  :group 'eca)

(defun eca--file-project-root (file-path)
  "Return project root for FILE-PATH using projectile or project.el."
  (when file-path
    (or (when (fboundp 'projectile-project-root)
          (ignore-errors
            (let ((projectile-project-root-cache (make-hash-table :test #'equal)))
              (projectile-project-root (file-name-directory file-path)))))
        (when (fboundp 'project-current)
          (ignore-errors
            (let ((proj (project-current nil (file-name-directory file-path))))
              (when proj (project-root proj)))))
        (file-name-directory file-path))))

(defun eca--auto-add-workspace-hook ()
  "Hook to auto-add file's project to current session's workspace.
Triggered when opening files outside current workspace."
  (when (and eca-auto-add-workspace-folder
             buffer-file-name
             (featurep 'eca)
             (eca-session))
    (let* ((file-path buffer-file-name)
           (project-root (eca--file-project-root file-path))
           (session (eca-session))
           (workspace-folders (eca--session-workspace-folders session))
           (in-workspace (and project-root
                              (member (directory-file-name (expand-file-name project-root))
                                      (mapcar (lambda (f) (directory-file-name (expand-file-name f)))
                                              workspace-folders)))))
      (when (and project-root (not in-workspace))
        (let ((root (directory-file-name (expand-file-name project-root))))
          (cond
           ((eq eca-auto-add-workspace-folder t)
            (eca--session-add-workspace-folder session root)
            (message "Auto-added project to ECA session %d: %s"
                     (eca--session-id session) root))
           ((eq eca-auto-add-workspace-folder 'prompt)
            (when (y-or-n-p (format "Add project to ECA workspace? (%s) " root))
              (eca--session-add-workspace-folder session root)))))))))

;; Add hook after ECA loads
(with-eval-after-load 'eca
  (add-hook 'find-file-hook #'eca--auto-add-workspace-hook))

(provide 'eca-ext)

;;; eca-ext.el ends here