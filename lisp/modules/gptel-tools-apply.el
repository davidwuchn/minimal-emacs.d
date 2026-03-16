;;; gptel-tools-apply.el --- ApplyPatch tool for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.1.0
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
    (when (string-match-p "^\\s-*```\\(diff\\|patch\\)?\\s-*" clean)
      (setq clean (replace-regexp-in-string "^\\s-*```\\(diff\\|patch\\)?\\s-*\\n?" "" clean)))
    (when (string-match-p "```\\s-*\\'" clean)
      (setq clean (replace-regexp-in-string "\\n?\\s-*```\\s-*\\'" "" clean)))
    (string-trim clean)))

;;; Envelope Format Parser

(cl-defstruct (gptel-envelope-hunk (:constructor gptel-envelope-hunk-create))
  type path contents chunks move-path)

(defun my/gptel--parse-envelope-patch (text)
  "Parse OpenCode envelope format patch TEXT into a list of hunks.

Returns a list of `gptel-envelope-hunk' structures.
Each hunk has :type (add, delete, or update), :path, and type-specific fields.

Envelope format:
  *** Begin Patch
  *** Add File: path/to/file
  +content lines...
  *** Delete File: path/to/file
  *** Update File: path/to/file
  *** Move to: new/path
  @@ context
   unchanged
  -removed
  +added
  *** End of File
  *** End Patch"
  (let ((lines (split-string text "\n"))
        (hunks nil)
        (i 0))
    (while (and (< i (length lines))
                (not (string-match-p "^\\*\\*\\* Begin Patch" (nth i lines))))
      (setq i (1+ i)))
    (setq i (1+ i))
    (while (and (< i (length lines))
                (not (string-match-p "^\\*\\*\\* End Patch" (nth i lines))))
      (let ((line (nth i lines)))
        (cond
         ((string-match "^\\*\\*\\* Add File: \\(.+\\)$" line)
          (let ((path (match-string 1 line))
                (contents nil)
                (j (1+ i)))
            (while (and (< j (length lines))
                        (not (string-match-p "^\\*\\*\\*" (nth j lines))))
              (let ((content-line (nth j lines)))
                (when (string-match "^\\+\\(.*\\)$" content-line)
                  (push (match-string 1 content-line) contents)))
              (setq j (1+ j)))
            (push (gptel-envelope-hunk-create
                   :type 'add
                   :path path
                   :contents (string-join (nreverse contents) "\n"))
                  hunks)
            (setq i j)))
         ((string-match "^\\*\\*\\* Delete File: \\(.+\\)$" line)
          (push (gptel-envelope-hunk-create
                 :type 'delete
                 :path (match-string 1 line))
                hunks)
          (setq i (1+ i)))
         ((string-match "^\\*\\*\\* Update File: \\(.+\\)$" line)
          (let ((path (match-string 1 line))
                (move-path nil)
                (chunks nil)
                (j (1+ i)))
            (when (and (< j (length lines))
                       (string-match "^\\*\\*\\* Move to: \\(.+\\)$" (nth j lines)))
              (setq move-path (match-string 1 (nth j lines)))
              (setq j (1+ j)))
            (while (and (< j (length lines))
                        (not (string-match-p "^\\*\\*\\* End Patch" (nth j lines)))
                        (not (string-match-p "^\\*\\*\\* \\(Add\\|Delete\\|Update\\) File:" (nth j lines))))
              (let ((chunk-line (nth j lines)))
                (cond
                 ((string-match "^@@" chunk-line)
                  (push (list :context (substring chunk-line 2)) chunks))
                 ((string-match-p "^\\*\\*\\* End of File" chunk-line)
                  nil)
                 ((string-match "^ " chunk-line)
                  (push (list 'keep (substring chunk-line 1))
                        (alist-get :lines (car chunks))))
                 ((string-match "^-" chunk-line)
                  (push (list 'remove (substring chunk-line 1))
                        (alist-get :lines (car chunks))))
                 ((string-match "^\\+" chunk-line)
                  (push (list 'add (substring chunk-line 1))
                        (alist-get :lines (car chunks))))))
              (setq j (1+ j)))
            (push (gptel-envelope-hunk-create
                   :type 'update
                   :path path
                   :chunks (nreverse chunks)
                   :move-path move-path)
                  hunks)
            (setq i j)))
         (t (setq i (1+ i))))))
    (nreverse hunks)))

(defun my/gptel--apply-envelope-hunks (hunks callback)
  "Apply envelope HUNKS to the filesystem asynchronously.
CALLBACK is called with the result string."
  (let ((added 0)
        (modified 0)
        (deleted 0)
        (errors nil)
        (root (or (when-let ((proj (project-current nil)))
                    (expand-file-name (project-root proj)))
                  default-directory))
        (idx 0))
    (while (< idx (length hunks))
      (let* ((hunk (nth idx hunks))
             (path (expand-file-name (gptel-envelope-hunk-path hunk) root)))
        (condition-case err
            (pcase (gptel-envelope-hunk-type hunk)
              ('add
               (make-directory (file-name-directory path) 'parents)
               (with-temp-file path
                 (insert (gptel-envelope-hunk-contents hunk)))
               (cl-incf added))
              ('delete
               (delete-file path)
               (cl-incf deleted))
              ('update
               (let* ((chunks (gptel-envelope-hunk-chunks hunk))
                      (move-path (gptel-envelope-hunk-move-path hunk))
                      (content (when (file-exists-p path)
                                 (with-temp-buffer
                                   (insert-file-contents path)
                                   (buffer-string)))))
                 (dolist (chunk chunks)
                   (let ((lines (alist-get :lines chunk)))
                     (when lines
                       (setq content (string-join
                                      (mapcar #'cadr (seq-filter
                                                      (lambda (l) (memq (car l) '(keep add)))
                                                      lines))
                                      "\n")))))
                 (let ((dest-path (if move-path
                                       (expand-file-name move-path root)
                                     path)))
                   (when move-path
                     (make-directory (file-name-directory dest-path) 'parents))
                   (with-temp-file dest-path
                     (insert (or content "")))
                   (when (and move-path (file-exists-p path))
                     (delete-file path))
                   (cl-incf modified)))))
          (error
           (push (format "Error processing %s: %s" path (error-message-string err)) errors))))
      (cl-incf idx))
    (if errors
        (funcall callback
                 (format "Envelope applied with errors.\nAdded: %d, Modified: %d, Deleted: %d\nErrors:\n%s"
                         added modified deleted (string-join errors "\n")))
      (funcall callback
               (format "Envelope applied successfully.\nAdded: %d, Modified: %d, Deleted: %d"
                       added modified deleted)))))

;;; ApplyPatch Implementation

(defun my/gptel--apply-patch-dispatch (callback patch)
  "Dispatch PATCH to either envelope or unified diff handler.
CALLBACK is called with the result string."
  (let ((clean (my/gptel--extract-patch patch)))
    (if (my/gptel--patch-looks-like-envelope-p clean)
        (condition-case err
            (let ((hunks (my/gptel--parse-envelope-patch clean)))
              (if (null hunks)
                  (funcall callback "Error: No valid hunks found in envelope patch.")
                (if my/gptel-applypatch-auto-preview
                    (my/gptel--preview-patch-async
                     clean (current-buffer) callback
                     (lambda (cb) (my/gptel--apply-envelope-hunks hunks cb))
                     (lambda (cb) (funcall cb "Error: Preview aborted by user."))
                     "ApplyPatch (envelope) preview" "ApplyPatch")
                  (my/gptel--apply-envelope-hunks hunks callback))))
          (error
           (funcall callback (format "Error parsing envelope: %s" (error-message-string err)))))
      (if my/gptel-applypatch-auto-preview
          (my/gptel--preview-patch-async
           clean (current-buffer) callback
           (lambda (cb) (my/gptel--apply-patch-core cb clean))
           (lambda (cb) (funcall cb "Error: Preview aborted by user."))
           "ApplyPatch preview" "ApplyPatch")
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
               (root (or (when-let ((proj (project-current nil)))
                           (expand-file-name (project-root proj)))
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