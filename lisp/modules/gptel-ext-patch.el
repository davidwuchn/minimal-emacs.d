;;; -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'project)
(require 'url)
(require 'url-parse)
(require 'url-util)
(require 'json)
(require 'dom)
(require 'diff)
(require 'gptel)
(eval-when-compile
  (require 'gptel-openai)
  (require 'gptel-gemini)
  (require 'gptel-gh))
(require 'gptel-context)
(require 'gptel-request)
(require 'gptel-gh)
(require 'gptel-gemini)
(require 'gptel-openai)
;; (require 'gptel-openai-extras)

(defun my/gptel--extract-patch (text)
  "Extract all unified diff blocks from TEXT.
Collects content from blocks starting with '--- a/' or '--- b/'.
Strips surrounding markdown chatter."
  (let ((pos 0)
        (patches '()))
    (while (string-match "\\(?:^\\|\n\\)\\(--- [ab]/[^\n]+\n\\+\\+\\+ [ab]/[^\n]+\n\\(?:@@ -[0-9,]+ \\+[0-9,]+ @@.*\n\\(?:[ +\\-].*\n\\|\\\\.*\n\\)*\\)+\\)" text pos)
      (push (match-string 1 text) patches)
      (setq pos (match-end 1)))
    (if patches
        (string-join (nreverse patches) "\n")
      ;; Fallback: try the older, looser matching if the strict regex fails
      (cond
       ((string-match "^--- [ab]/" text)
        (let ((start (match-beginning 0)))
          (if (string-match "^```\\(?:diff\\|patch\\)?\n" (substring text 0 start))
              (let ((content (substring text start)))
                (if (string-match "\n```" content)
                    (substring content 0 (match-beginning 0))
                  content))
            (substring text start))))
       ((string-match "\n--- [ab]/" text)
        (let ((start (1+ (match-beginning 0))))
          (if (string-match "^```\\(?:diff\\|patch\\)?\n" (substring text 0 start))
              (let ((content (substring text start)))
                (if (string-match "\n```" content)
                    (substring content 0 (match-beginning 0))
                  content))
            (substring text start))))
       (t text)))))

(defun my/gptel--parse-git-apply-errors (output)
  "Parse OUTPUT from git apply to extract specific hunk failures and path issues."
  (let ((errors '()))
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      ;; Path not found
      (while (re-search-forward "error: \\([^:\n]+\\): No such file or directory" nil t)
        (push (list :path (match-string 1) :type :not-found) errors))
      ;; Hunk failure
      (goto-char (point-min))
      (while (re-search-forward "error: patch failed: \\([^:\n]+\\):\\([0-9]+\\)" nil t)
        (push (list :path (match-string 1) :line (match-string 2) :type :hunk-failed) errors))
      ;; Context failure
      (goto-char (point-min))
      (while (re-search-forward "error: \\([^:\n]+\\): patch does not apply" nil t)
        (push (list :path (match-string 1) :type :context-mismatch) errors)))
    (nreverse errors)))

(defun my/gptel--find-correct-path (wrong-path)
  "Try to find a correct path for WRONG-PATH in the current project."
  (let* ((proj (project-current))
         ;; Strip git prefixes a/ or b/
         (clean-path (if (string-match "\\`[ab]/" wrong-path)
                         (substring wrong-path 2)
                       wrong-path))
         (base (file-name-nondirectory clean-path))
         (files (and proj (project-files proj))))
    (when files
      (or (seq-find (lambda (f) (string-suffix-p clean-path f)) files)
          (seq-find (lambda (f) (string-suffix-p base f)) files)))))

(defun my/gptel--preview-patch-core (patch &optional displayp)
  "Populate *gptel-patch-preview* with PATCH in diff-mode.

When DISPLAYP is non-nil (default), display the preview buffer.
Always uses `diff-mode' — magit-diff-mode requires git-parsed output
and cannot render raw unified diff text properly."
  (let ((clean-patch (my/gptel--extract-patch patch))
        (buf (get-buffer-create "*gptel-patch-preview*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert clean-patch)
        (diff-mode)
        (setq-local buffer-read-only t)))
    (when (or (null displayp) displayp)
      (display-buffer buf))
    "Patch previewed in *gptel-patch-preview* buffer."))

(defun my/gptel--preview-patch-async (patch gptel-buf callback on-confirm on-abort header)
  "Show PATCH in *gptel-patch-preview*, install n/q stepper, wait for user.

GPTEL-BUF is the originating gptel buffer (for abort-generation guard).
CALLBACK is the gptel async tool callback — fired by ON-CONFIRM or ON-ABORT.
ON-CONFIRM is a unary function called with CALLBACK when user presses n.
ON-ABORT   is a unary function called with CALLBACK when user presses q or
           kills the preview buffer.
HEADER is the string shown in the preview buffer's header-line.

Unlike the file-change queue, patch preview is always a single step — no
queue, no step numbering.  The stepper state uses :on-confirm/:on-abort so
`my/gptel--preview-next' and `my/gptel--preview-quit' dispatch correctly."
  (my/gptel--preview-patch-core patch t)
  (when-let ((buf (get-buffer "*gptel-patch-preview*")))
    (with-current-buffer buf
      ;; Install state with custom confirm/abort thunks.
      (setq-local my/gptel--preview-stepper-state
                  (list :gptel-buf  gptel-buf
                        :path       "*gptel-patch-preview*"
                        :callback   callback
                        :on-confirm on-confirm
                        :on-abort   on-abort))
      (setq header-line-format header)
      (my/gptel--preview-stepper-mode 1)
      ;; Kill-buffer guard: closing the buffer without n/q treats it as q.
      (add-hook 'kill-buffer-hook
                (lambda ()
                  (when my/gptel--preview-stepper-mode
                    (my/gptel--preview-quit)))
                nil t))))



;; --- Step-through preview infrastructure ---
;; preview_file_change is async: each call enqueues a (path orig new
;; callback) entry on the gptel buffer.  A 0.15 s idle timer lets
;; parallel tool calls batch up before the first step fires.  The user
;; steps through with n / q in a transient minor mode installed on the
;; diff buffer; each n fires that entry's callback so the FSM advances.

;; Buffer-local vars live on the gptel agent buffer.
(defvar-local my/gptel--preview-queue nil
  "Pending preview steps (newest first).
Each entry: (path orig new callback).")

(defvar-local my/gptel--preview-active nil
  "Non-nil while step-through preview is running.")

(defvar-local my/gptel--preview-step-count 0
  "Number of steps shown in the current preview batch.")

(defvar-local my/gptel--preview-temp-files nil
  "Temp files for the current preview step; cleaned up on advance.")

;; State plist stored buffer-locally on the diff buffer.
(defvar-local my/gptel--preview-stepper-state nil
  "Plist: :gptel-buf :path :callback for the current diff buffer step.")

(defun my/gptel--preview-update-header (step total path)
  "Set header-line in current buffer to show step progress."
  (setq header-line-format
        (format "  Preview [%d/%d]: %s    n next    q abort all"
                step total (file-name-nondirectory path))))

(defun my/gptel--preview-cleanup-temp-files (gptel-buf)
  "Delete temp files recorded on GPTEL-BUF."
  (when (buffer-live-p gptel-buf)
    (with-current-buffer gptel-buf
      (dolist (f my/gptel--preview-temp-files)
        (ignore-errors (delete-file f)))
      (setq my/gptel--preview-temp-files nil))))

(defun my/gptel--preview-next ()
  "Advance to the next preview step (bound to n in diff buffer).

If the stepper state has an :on-confirm thunk, calls it with the callback
\(patch tools use this to run git apply on confirm).  Otherwise fires the
default file-change result message."
  (interactive)
  (when-let* ((state my/gptel--preview-stepper-state)
              (gptel-buf (plist-get state :gptel-buf))
              (callback  (plist-get state :callback))
              (path      (plist-get state :path)))
    (my/gptel--preview-stepper-mode -1)
    (if-let ((on-confirm (plist-get state :on-confirm)))
        ;; Patch tool path: on-confirm is responsible for calling callback.
        (funcall on-confirm callback)
      ;; File-change path: fire default result and advance queue.
      (funcall callback (format "Preview shown for %s" path))
      (my/gptel--preview-step gptel-buf))))

(defun my/gptel--preview-quit ()
  "Abort the current preview step and all queued ones (bound to q).

If the stepper state has an :on-abort thunk, calls it with the callback.
Otherwise fires the default abort messages for file-change tools."
  (interactive)
  (when-let* ((state my/gptel--preview-stepper-state)
              (gptel-buf (plist-get state :gptel-buf))
              (callback  (plist-get state :callback))
              (path      (plist-get state :path)))
    (my/gptel--preview-stepper-mode -1)
    (if-let ((on-abort (plist-get state :on-abort)))
        ;; Patch tool path: on-abort is responsible for calling callback.
        (funcall on-abort callback)
      ;; File-change path: drain queue and fire default abort messages.
      (when (buffer-live-p gptel-buf)
        (with-current-buffer gptel-buf
          (dolist (entry my/gptel--preview-queue)
            (ignore-errors (funcall (nth 3 entry) "Preview aborted by user")))
          (setq my/gptel--preview-queue   nil
                my/gptel--preview-active  nil
                my/gptel--preview-step-count 0)
          (my/gptel--preview-cleanup-temp-files gptel-buf)))
      (funcall callback
               (format "Preview shown for %s (remaining previews aborted)" path)))))

(define-minor-mode my/gptel--preview-stepper-mode
  "Transient minor mode for gptel step-through file preview.
Press n to advance to the next file, q to abort all remaining previews."
  :lighter " Preview"
  :keymap (let ((m (make-sparse-keymap)))
            (define-key m (kbd "n") #'my/gptel--preview-next)
            (define-key m (kbd "q") #'my/gptel--preview-quit)
            m))

(defun my/gptel--preview-install-stepper (diff-buf gptel-buf path callback step total)
  "Install stepper mode and kill-guard on DIFF-BUF for one preview step."
  (with-current-buffer diff-buf
    (setq-local my/gptel--preview-stepper-state
                (list :gptel-buf gptel-buf
                      :path      path
                      :callback  callback))
    (my/gptel--preview-update-header step total path)
    (my/gptel--preview-stepper-mode 1)
    ;; Guard: if the diff buffer is killed without n/q, treat as quit.
    (add-hook 'kill-buffer-hook
              (lambda ()
                (when my/gptel--preview-stepper-mode
                  (my/gptel--preview-quit)))
              nil t)))

(defun my/gptel--preview-show-step (gptel-buf path orig new callback step total)
  "Display one preview step, install stepper, then wait for user."
  ;; Clean up previous step's temp files.
  (my/gptel--preview-cleanup-temp-files gptel-buf)
  (if (and (featurep 'magit) (fboundp 'magit-diff-paths))
      ;; Magit path: named temp files so the header shows BASE.EXT.
      (let* ((base      (file-name-base path))
             (ext       (file-name-extension path t)) ; includes "."
             (orig-file (make-temp-file
                         (format "gptel-orig-%s" base) nil ext))
             (new-file  (make-temp-file
                         (format "gptel-new-%s"  base) nil ext)))
        (with-temp-file orig-file (insert (or orig "")))
        (with-temp-file new-file  (insert (or new  "")))
        (with-current-buffer gptel-buf
          (setq my/gptel--preview-temp-files
                (list orig-file new-file)))
        ;; Show magit diff without stealing focus.
        (let ((magit-display-buffer-noselect t))
          (magit-diff-paths orig-file new-file))
        (when-let ((diff-buf (magit-get-mode-buffer 'magit-diff-mode)))
          (my/gptel--preview-install-stepper
           diff-buf gptel-buf path callback step total)))
    ;; Fallback: Emacs built-in diff-mode.
    (let* ((orig-file (make-temp-file "gptel-orig-"))
           (new-file  (make-temp-file "gptel-new-")))
      (with-temp-file orig-file (insert (or orig "")))
      (with-temp-file new-file  (insert (or new  "")))
      (with-current-buffer gptel-buf
        (setq my/gptel--preview-temp-files
              (list orig-file new-file)))
      (let ((diff-buf (diff-no-select orig-file new-file "-u" 'no-async)))
        (my/gptel--preview-install-stepper
         diff-buf gptel-buf path callback step total)
        (display-buffer diff-buf)))))

(defun my/gptel--preview-step (gptel-buf)
  "Show the next queued preview step, or finish if queue is empty."
  (when (buffer-live-p gptel-buf)
    (with-current-buffer gptel-buf
      (if (null my/gptel--preview-queue)
          ;; Batch complete — reset state.
          (setq my/gptel--preview-active     nil
                my/gptel--preview-step-count 0)
        (setq my/gptel--preview-active t)
        ;; Queue is newest-first (push order); oldest = last element.
        (let* ((entry    (car (last my/gptel--preview-queue)))
               (rest     (butlast my/gptel--preview-queue))
               (path     (nth 0 entry))
               (orig     (nth 1 entry))
               (new      (nth 2 entry))
               (callback (nth 3 entry))
               (step     (cl-incf my/gptel--preview-step-count))
               ;; total = steps already shown + remaining (incl. this)
               (total    (+ my/gptel--preview-step-count
                            (length rest))))
          (setq my/gptel--preview-queue rest)
          (my/gptel--preview-show-step
           gptel-buf path orig new callback step total))))))

(defun my/gptel--preview-enqueue (gptel-buf path orig new callback)
  "Add a preview step to GPTEL-BUF's queue and start if idle."
  (when (buffer-live-p gptel-buf)
    (with-current-buffer gptel-buf
      (push (list path orig new callback) my/gptel--preview-queue))
    (unless (buffer-local-value 'my/gptel--preview-active gptel-buf)
      ;; 0.15 s delay lets parallel tool calls batch before first step.
      (run-with-idle-timer 0.15 nil #'my/gptel--preview-step gptel-buf))))

(provide 'gptel-ext-patch)
;;; gptel-ext-patch.el ends here
