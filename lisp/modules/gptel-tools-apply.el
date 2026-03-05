;;; gptel-tools-apply.el --- ApplyPatch tool for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; ApplyPatch tool with support for unified diff and OpenCode envelope formats.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'project)
(require 'gptel-tools-preview)

;;; Customization

(defgroup gptel-tools-apply nil
  "ApplyPatch tool for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-applypatch-timeout 30
  "Seconds before ApplyPatch is force-stopped."
  :type 'integer
  :group 'gptel-tools-apply)

(defcustom my/gptel-applypatch-auto-preview t
  "When non-nil, show preview and wait for confirmation before applying."
  :type 'boolean
  :group 'gptel-tools-apply)

;;; Helper Functions

(defun my/gptel--patch-looks-like-unified-diff-p (text)
  "Return non-nil when TEXT looks like a unified diff."
  (and (stringp text)
       (or (string-match-p "^diff --git " text)
           (and (string-match-p "^--- " text)
                (string-match-p "^\\+\\+\\+ " text)))))

(defun my/gptel--patch-looks-like-envelope-p (text)
  "Return non-nil when TEXT looks like an OpenCode apply_patch envelope."
  (and (stringp text) (string-match-p "^\\*\\*\\* Begin Patch" text)))

(defun my/gptel--patch-has-absolute-paths-p (text)
  "Return non-nil when TEXT contains absolute paths."
  (and (stringp text)
       (or (string-match-p "^--- /" text)
           (string-match-p "^\\+\\+\\+ /" text)
           (string-match-p "^diff --git /" text)
           (string-match-p "/Users/" text))))

(defun my/gptel--extract-patch (text)
  "Extract patch content from TEXT, stripping markdown fences if present."
  (let ((clean text))
    (when (string-match "^```\\(?:diff\\|patch\\)?\n\\(.*\n\\)```$" text)
      (setq clean (match-string 1 text)))
    (string-trim clean)))

;;; ApplyPatch Implementation

(defun my/gptel--apply-patch-dispatch (callback patch)
  "Dispatch PATCH to either envelope or unified diff handler.

CALLBACK is called with the result string."
  (let* ((clean (my/gptel--extract-patch patch)))
    (if (my/gptel--patch-looks-like-envelope-p clean)
        (funcall callback "Error: Envelope format not yet implemented in split module.")
      ;; Unified diff: preview if requested, otherwise apply directly
      (if my/gptel-applypatch-auto-preview
          (my/gptel--preview-patch-async
           clean
           (current-buffer)
           callback
           ;; on-confirm
           (lambda (cb)
             (my/gptel--apply-patch-core cb clean))
           ;; on-abort
           (lambda (cb)
             (funcall cb "Error: Preview aborted by user."))
           "ApplyPatch preview — n apply patch    q abort")
        (my/gptel--apply-patch-core callback clean)))))

(defun my/gptel--apply-patch-core (callback patch)
  "Apply PATCH (unified diff) at the Emacs project root asynchronously.

Prefers `git apply` if in a git repository; otherwise uses `patch`."
  (condition-case err
      (progn
        (unless (or (executable-find "git") (executable-find "patch"))
          (error "neither 'git' nor 'patch' executable found"))
        (unless (and (stringp patch) (not (string-empty-p (string-trim patch))))
          (error "patch text is empty"))

        (let* ((clean-patch (my/gptel--extract-patch patch))
               (patch-file (my/gptel-make-temp-file "gptel-patch-"))
               (root (if-let ((proj (project-current nil)))
                         (expand-file-name (project-root proj))
                       (expand-file-name default-directory)))
               (default-directory (file-name-as-directory root))
               (is-git (and (executable-find "git")
                            (file-exists-p (expand-file-name ".git" root))))
               (backend (if is-git "git" "patch"))
               (buf (generate-new-buffer (format " *gptel-patch-%s*" backend)))
               (done nil)
               (timer nil)
               (finish
                (lambda (msg)
                  (unless done
                    (setq done t)
                    (when (timerp timer) (cancel-timer timer))
                    (when (buffer-live-p buf) (kill-buffer buf))
                    (when (file-exists-p patch-file) (delete-file patch-file))
                    (funcall callback msg)))))

          ;; Validation
          (when (string-match-p "^\\*\\*\\* Begin Patch" clean-patch)
            (error "patch expects unified diff, not envelope format"))
          (unless (my/gptel--patch-looks-like-unified-diff-p clean-patch)
            (error "patch does not look like a unified diff"))
          (when (my/gptel--patch-has-absolute-paths-p clean-patch)
            (error "patch contains absolute paths"))

          (with-temp-file patch-file (insert clean-patch))

          (let ((apply-args (if is-git
                                (list "apply" "--verbose" "--whitespace=fix" patch-file)
                              (list "--batch" "-p1" "-N" "-i" patch-file))))
            ;; Apply the patch
            (let ((proc
                   (make-process
                    :name (format "gptel-%s-apply" backend)
                    :buffer buf
                    :command (cons backend apply-args)
                    :connection-type 'pipe
                    :noquery t
                    :sentinel
                    (lambda (p _event)
                      (when (memq (process-status p) '(exit signal))
                        (let* ((status (process-exit-status p))
                               (out (with-current-buffer buf (string-trim (buffer-string)))))
                          (if (= status 0)
                              (funcall finish
                                       (format "Patch applied successfully using %s.\n\n%s"
                                               backend (if (string-empty-p out) "(no output)" out)))
                            (funcall finish
                                     (format "Patch application failed (status %d) using %s.\n\n%s"
                                             status backend out)))))))))
              (process-put proc 'my/gptel-managed t)
              (setq timer
                    (run-at-time
                     my/gptel-applypatch-timeout nil
                     (lambda ()
                       (when (process-live-p proc)
                         (delete-process proc))
                       (funcall finish (format "Error: ApplyPatch timed out after %ss"
                                               my/gptel-applypatch-timeout)))))))))
    (error (funcall callback (format "Error: %s" (error-message-string err))))))

;;; Tool Registration

(defun gptel-tools-apply-register ()
  "Register the ApplyPatch tool with gptel."
  (if (not (or (executable-find "git") (executable-find "patch")))
      (when (fboundp 'display-warning)
        (display-warning 'gptel-tools "Executables `git' and `patch' not found. ApplyPatch tool will not be registered." :warning))
    (when (fboundp 'gptel-make-tool)
      (gptel-make-tool
       :name "ApplyPatch"
       :description "Apply a unified diff or OpenCode envelope patch."
       :function #'my/gptel--apply-patch-dispatch
       :async t
       :args '((:name "patch"
                :type string
                :description "Unified diff content"))
       :category "gptel-agent"
       :confirm t
       :include t))))

;;; Footer

(provide 'gptel-tools-apply)

;;; gptel-tools-apply.el ends here
