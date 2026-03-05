;;; gptel-ext-tool-confirm.el --- Enhanced tool call confirmation UI -*- lexical-binding: t; -*-

;;; Commentary:
;; Override `gptel--display-tool-calls' to include arguments in the minibuffer
;; prompt.  Integrates with gptel-tool-ui.el per-tool permit system.
;; Includes FSM lookup helper for the inspect action.

;;; Code:

(require 'cl-lib)
(require 'gptel)

(defvar gptel-tool-call-actions-map) ; defined in gptel
(defvar gptel--tool-preview-alist)   ; defined in gptel

;; Forward declarations for gptel-tool-ui.el functions
(declare-function my/gptel-permit-tool "gptel-tool-ui")
(declare-function my/gptel-tool-permitted-p "gptel-tool-ui")
(defvar my/gptel-permitted-tools)

;; --- FSM Lookup Helper ---
;; Upstream `gptel--inspect-fsm' has a bug: when called with nil FSM arg, it
;; falls back to `(cdr-safe (cl-find-if pred gptel--request-alist))' which
;; yields (FSM . CLEANUP-FN) — a cons cell, not a bare gptel-fsm struct.
;; This helper does the extraction correctly.

(defun my/gptel--current-fsm ()
  "Return the current gptel-fsm struct for the active request.

Looks up the FSM from `gptel--request-alist' using the correct
extraction: (car (cdr entry)) to unwrap the (FSM . CLEANUP-FN)
cons cell.  Falls back to `gptel--fsm-last' if no active request
is found."
  (or (and (bound-and-true-p gptel--request-alist)
           (car (cdr-safe
                 (cl-find-if
                  (lambda (entry)
                    (let ((buf (process-buffer (car entry))))
                      (eq buf (current-buffer))))
                  gptel--request-alist))))
      gptel--fsm-last))

;; --- Enhanced Tool Call Confirmation Context ---

(defun my/gptel--permit-and-accept-tool-calls ()
  "Permit all tools in the current overlay, then accept."
  (interactive)
  (when-let* ((ov (cdr-safe (get-char-property-and-overlay (point) 'gptel-tool)))
              (tool-calls (overlay-get ov 'gptel-tool)))
    (dolist (tc tool-calls)
      (my/gptel-permit-tool (gptel-tool-name (car tc)))))
  (call-interactively #'gptel--accept-tool-calls))

(defun my/gptel--display-tool-calls (tool-calls info &optional use-minibuffer)
  "Handle tool call confirmation with per-tool permit memory.

If all requested tools are already permitted (via `my/gptel-permitted-tools'),
auto-accepts without prompting.  Otherwise shows the standard confirmation
with an additional `p' option to permit and remember a tool."
  ;; Fast path: if all tools are already permitted, auto-accept
  (if (and (bound-and-true-p my/gptel-permitted-tools)
           (cl-every (lambda (tc) (my/gptel-tool-permitted-p (gptel-tool-name (car tc))))
                     tool-calls))
      (gptel--accept-tool-calls tool-calls nil)
    ;; Slow path: show confirmation UI
    (let* ((start-marker (plist-get info :position))
         (tracking-marker (plist-get info :tracking-marker)))
    (with-current-buffer (plist-get info :buffer)
      (if (or use-minibuffer        ;prompt for confirmation from the minibuffer
              buffer-read-only ;TEMP(tool-preview) Handle read-only buffers better
              (get-char-property
               (max (point-min) (1- (or tracking-marker start-marker)))
               'read-only))
          (let* ((minibuffer-allow-text-properties t)
                 (backend-name (gptel-backend-name (plist-get info :backend)))
                 (prompt (format "%s wants to run " backend-name)))
            (map-y-or-n-p
             (lambda (tool-call-spec)
               (let* ((tool-name (gptel-tool-name (car tool-call-spec)))
                      (args (cadr tool-call-spec))
                      (permitted (my/gptel-tool-permitted-p tool-name))
                      (formatted-args
                       (mapconcat (lambda (arg)
                                    (cond ((stringp arg)
                                           (truncate-string-to-width arg 60 nil nil "..."))
                                          (t (prin1-to-string arg))))
                                  args " ")))
                 (if permitted
                     ;; Already permitted — auto-accept this one
                     (progn (gptel--accept-tool-calls (list tool-call-spec) nil) nil)
                   (concat prompt
                           (propertize tool-name 'face 'font-lock-keyword-face)
                           (if (string-empty-p formatted-args) ""
                             (concat " " (propertize formatted-args 'face 'font-lock-constant-face)))
                           ": "))))
             (lambda (tcs) (gptel--accept-tool-calls (list tcs) nil))
             tool-calls '("tool call" "tool calls" "run")
             `((?i ,(lambda (_) (save-window-excursion
                             (with-selected-window
                                 (gptel--inspect-fsm (my/gptel--current-fsm))
                               (goto-char (point-min))
                               (when (search-forward-regexp "^:tool-use" nil t)
                                 (forward-line 0) (hl-line-highlight))
                               (use-local-map
                                (make-composed-keymap
                                 (define-keymap "q" (lambda () (interactive)
                                                      (quit-window)
                                                      (exit-recursive-edit)))
                                 (current-local-map)))
                               (recursive-edit) nil)))
                   "inspect call(s)")
               (?p ,(lambda (tool-call-spec)
                      (let ((name (gptel-tool-name (car tool-call-spec))))
                        (my/gptel-permit-tool name)
                        (message "Permitted %s for this session" name))
                      ;; Accept this tool call and continue
                      (gptel--accept-tool-calls (list tool-call-spec) nil)
                      nil)
                   "permit & run (remember)"))))
        ;; Prompt for confirmation from the chat buffer overlay
        (let* ((backend-name (gptel-backend-name (plist-get info :backend)))
               (actions-string
                (concat (propertize "Run: " 'face 'font-lock-string-face)
                        (propertize "C-c C-c" 'face 'help-key-binding)
                        (propertize ", Permit & run: " 'face 'font-lock-string-face)
                        (propertize "C-c C-p" 'face 'help-key-binding)
                        (propertize ", Cancel: " 'face 'font-lock-string-face)
                        (propertize "C-c C-k" 'face 'help-key-binding)
                        (propertize ", Inspect: " 'face 'font-lock-string-face)
                        (propertize "C-c C-i" 'face 'help-key-binding)))
               (confirm-strings)
               (ov-start (and start-marker
                               (save-excursion
                                 (goto-char start-marker)
                                 (when (text-property-search-backward 'gptel 'response)
                                   (point)))))
               (preview-handlers)
               (ov (and ov-start
                        (or (cdr-safe (get-char-property-and-overlay
                                       start-marker 'gptel-tool))
                            (make-overlay ov-start (or tracking-marker start-marker)
                                          nil nil nil))))
               (prompt-ov))
          ;; If the cursor is at the overlay-end, it ends up outside, so move it back
          (when (and start-marker (not tracking-marker))
            (when (= (point) start-marker) (ignore-errors (backward-char))))
          (when ov
            (save-excursion
              (goto-char (overlay-end ov))
              (pcase-dolist (`(,tool-spec ,arg-values _) tool-calls)
                ;; Call tool-specific confirmation prompt
                (if-let* ((funcs (cdr (assoc (gptel-tool-name tool-spec)
                                             gptel--tool-preview-alist)))
                          ((functionp (car-safe funcs))))
                    ;;preview-teardown func   preview-handle overlay/buffer
                    (push (list (cadr funcs) (funcall (car funcs) arg-values info))
                          preview-handlers)
                  (push (gptel--format-tool-call (gptel-tool-name tool-spec) arg-values)
                        confirm-strings)))
              (and confirm-strings (apply #'insert (nreverse confirm-strings)))
              ;; Only mark read-only if text was actually inserted (guard inverted range).
              (let ((insert-end (point)))
                (when (> insert-end (overlay-end ov))
                  (add-text-properties (overlay-end ov) (1- insert-end)
                                       '(read-only t font-lock-fontified t))))
              (setq prompt-ov (make-overlay (overlay-end ov) (point) nil t))
              (overlay-put
               prompt-ov 'before-string
               (concat "\n"
                       (propertize " " 'display `(space :align-to (- right ,(length actions-string) 2))
                                   'face '(:inherit font-lock-string-face :underline t :extend t))
                       actions-string
                       (format (propertize "\n%s wants to run:\n\n"
                                           'face 'font-lock-string-face)
                               backend-name)))
              (overlay-put
               prompt-ov 'after-string
               (concat (propertize "\n" 'face
                                   '(:inherit font-lock-string-face :underline t :extend t))))
              (overlay-put prompt-ov 'evaporate t)
              (overlay-put ov 'prompt prompt-ov)
              (move-overlay ov ov-start (point))
              ;; Add confirmation prompt to the overlay
              (when preview-handlers (overlay-put ov 'previews preview-handlers))
              (overlay-put ov 'mouse-face 'highlight)
              (overlay-put ov 'gptel-tool tool-calls)
              (overlay-put ov 'help-echo
                           (concat "Tool call(s) requested: " actions-string))
              (let ((map (make-sparse-keymap)))
                (set-keymap-parent map gptel-tool-call-actions-map)
                (define-key map (kbd "C-c C-p") #'my/gptel--permit-and-accept-tool-calls)
                (overlay-put ov 'keymap map))))))))))

(advice-add 'gptel--display-tool-calls :override #'my/gptel--display-tool-calls)

(provide 'gptel-ext-tool-confirm)
;;; gptel-ext-tool-confirm.el ends here
