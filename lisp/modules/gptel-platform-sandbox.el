;;; gptel-platform-sandbox.el --- Platform sandbox: seatbelt(macOS) + bubblewrap(linux) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; Layer 4 defense-in-depth: OS-level process containment for Bash/Programmatic
;; tool execution.  Emacs-native sandbox (gptel-sandbox.el) protects Lisp code;
;; this module protects actual shell processes.
;;
;; Strategy:
;;   macOS  → seatbelt (sandbox-exec)   — built-in, kernel-level enforcement
;;   Linux  → bubblewrap (bwrap)        — user-namespace containers
;;
;; See: mementum/knowledge/platform-sandbox-strategy.md

;;; Code:

(require 'cl-lib)

;; ── Platform Detection ──

(defun gptel-platform-sandbox--available-p ()
  "Return t if platform sandbox is available on this system."
  (cond
   ((eq system-type 'darwin)
    (and (executable-find "sandbox-exec") t))
   ((eq system-type 'gnu/linux)
    (and (executable-find "bwrap") t))
   (t nil)))

(defun gptel-platform-sandbox--platform-name ()
  "Return a keyword for the current platform sandbox type."
  (cond
   ((eq system-type 'darwin) :seatbelt)
   ((eq system-type 'gnu/linux) :bubblewrap)
   (t :none)))

;; ── Profile Generation ──

(defvar gptel-platform-sandbox--workspace-root nil
  "Workspace root directory for sandbox allowlisting.
Defaults to `gptel-auto-workflow--worktree-base-root' or `default-directory'.")

(defun gptel-platform-sandbox--current-mode ()
  "Return :plan or :agent based on active gptel preset.
Plan mode gets tighter restrictions (no network outbound)."
  (if (and (boundp 'gptel--preset)
           (eq gptel--preset 'gptel-plan))
      :plan
    :agent))

(defun gptel-platform-sandbox--seatbelt-profile (&optional mode)
  "Generate a temporary seatbelt profile for the current workspace.
MODE is :plan or :agent — plan mode denies all network."
  (let* ((root (or gptel-platform-sandbox--workspace-root
                   (when (fboundp 'gptel-auto-workflow--worktree-base-root)
                     (gptel-auto-workflow--worktree-base-root))
                   (expand-file-name default-directory)))
         (tmpdir (or (getenv "TMPDIR") "/tmp"))
         (profile (make-temp-file "sb-" nil ".sb"))
         (ro-dirs '("/usr" "/bin" "/sbin" "/Library" "/System"
                    "/Applications" "/private/var" "/dev"))
         (rw-root (expand-file-name root))
         (plan-mode (eq mode :plan)))
    (with-temp-file profile
      (insert "(version 1)\n")
      (insert "(deny default)\n")
      ;; Read-only system access
      (dolist (d ro-dirs)
        (when (file-directory-p d)
          (insert (format "(allow file-read* (subpath \"%s\"))\n" d))))
      ;; Workspace read+write
      (insert (format "(allow file-read* file-write* (subpath \"%s\"))\n" rw-root))
      ;; Temp directory
      (insert (format "(allow file-read* file-write* (subpath \"%s\"))\n" tmpdir))
      ;; Process execution
      (insert "(allow process-fork)\n")
      (insert "(allow process-exec (subpath \"/usr\"))\n")
      (insert "(allow process-exec (subpath \"/bin\"))\n")
      ;; Network: plan mode denies, agent mode allows
      (if plan-mode
          (insert "(deny network*)\n")
        (insert "(allow network-outbound)\n"))
      ;; Sysctl for system info
      (insert "(allow sysctl-read)\n"))
    profile))

(defun gptel-platform-sandbox--bwrap-args (&optional mode)
  "Generate bubblewrap arguments for the current workspace.
MODE is :plan or :agent — plan mode isolates network."
  (let* ((root (or gptel-platform-sandbox--workspace-root
                   (when (fboundp 'gptel-auto-workflow--worktree-base-root)
                     (gptel-auto-workflow--worktree-base-root))
                   (expand-file-name default-directory)))
         (rw-root (expand-file-name root))
         (tmpdir (or (getenv "TMPDIR") "/tmp"))
         (plan-mode (eq mode :plan)))
    (mapconcat
     #'identity
     (append
      ;; Read-only bind system dirs
      (cl-loop for d in '("/usr" "/bin" "/sbin" "/lib" "/lib64" "/etc"
                          "/opt" "/var" "/dev" "/proc" "/sys")
               when (file-directory-p d)
               collect (format "--ro-bind %s %s" d d))
      ;; Read-write bind workspace and temp
      (list (format "--bind %s %s" rw-root rw-root)
            (format "--bind %s %s" tmpdir tmpdir))
      ;; Isolate — plan mode unshares network, agent mode shares it
      (list (if plan-mode
                "--unshare-all --new-session"
              "--unshare-all --share-net --new-session")))
      " ")))

;; ── Command Wrapping ──

(defun gptel-platform-sandbox--wrap-command (command)
  "Wrap COMMAND in platform-appropriate sandbox with mode-detection.
Plan mode gets tighter restrictions (no network). Agent mode allows
network for git, curl, etc.
Returns (WRAPPED-COMMAND . PROFILE-FILE) where PROFILE-FILE is nil for
bubblewrap (no temp file to clean up) and non-nil for seatbelt."
  (let ((mode (gptel-platform-sandbox--current-mode)))
    (cond
     ((eq (gptel-platform-sandbox--platform-name) :seatbelt)
      (let ((profile (gptel-platform-sandbox--seatbelt-profile mode)))
        (cons (format "sandbox-exec -f %s -- %s"
                      (shell-quote-argument profile)
                      command)
              profile)))
     ((eq (gptel-platform-sandbox--platform-name) :bubblewrap)
      (cons (format "bwrap %s -- %s"
                    (gptel-platform-sandbox--bwrap-args mode)
                    command)
            nil))
     (t (cons command nil)))))

(defun gptel-platform-sandbox--wrap-and-send (command proc marker)
  "Send sandbox-wrapped COMMAND to bash PROC with MARKER.
Returns the profile file (for cleanup) or nil."
  (let* ((wrapped (gptel-platform-sandbox--wrap-command command))
         (wrapped-cmd (car wrapped))
         (profile (cdr wrapped)))
    (process-send-string proc
                         (format "{ %s\n} 2>&1\necho %s:$?\n"
                                 wrapped-cmd marker))
    profile))

(provide 'gptel-platform-sandbox)
;;; gptel-platform-sandbox.el ends here
