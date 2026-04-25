;;; gptel-ext-tool-confirm.el --- Enhanced tool call confirmation UI -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Override `gptel--display-tool-calls' to include arguments in the minibuffer
;; prompt.  Integrates with gptel-ext-tool-permits.el per-tool permit system.
;; Includes FSM lookup helper for the inspect action.

;;; Code:

(require 'cl-lib)
(require 'gptel)
(require 'gptel-ext-fsm-utils)

(defvar gptel-tool-call-actions-map) ; defined in gptel
(defvar gptel--tool-preview-alist)   ; defined in gptel
(defvar gptel--request-alist)        ; defined in gptel-request
(defvar gptel--fsm-last)             ; defined in gptel
(defvar gptel-sandbox-confirm-function)
(defvar gptel-sandbox-aggregate-confirm-function)

;; Forward declarations for gptel-ext-tool-permits.el functions
(declare-function my/gptel-permit-tool "gptel-ext-tool-permits")
(declare-function my/gptel-tool-permitted-p "gptel-ext-tool-permits")
(defvar my/gptel-permitted-tools)

;; --- FSM Lookup Helper ---
;; Upstream `gptel--inspect-fsm' has two bugs in the unreleased FSM build used
;; here: the default lookup returns a wrapped request entry instead of a bare
;; struct, and the type check validates `gptel--fsm-last' instead of the FSM
;; argument that was actually resolved.

(defun my/gptel--current-fsm ()
  "Return the current gptel-fsm struct for the active request.

Looks up the FSM from `gptel--request-alist' and unwraps any request-entry
container shape used by the running gptel build.  Falls back to
`gptel--fsm-last' if no active request is found."
  (or (and (bound-and-true-p gptel--request-alist)
           (my/gptel--coerce-fsm
            (cl-find-if
             (lambda (entry)
               (let ((buf (ignore-errors (process-buffer (car entry)))))
                 (eq buf (current-buffer))))
             gptel--request-alist)))
      (my/gptel--coerce-fsm gptel--fsm-last)))

(defun my/gptel--inspect-fsm (&optional fsm)
  "Inspect gptel request state FSM.

FSM defaults to the active request in the current buffer.  Unlike upstream,
this accepts wrapped request entries and validates the resolved FSM itself."
  (setq fsm (or (my/gptel--coerce-fsm fsm)
                (my/gptel--current-fsm)))
  (unless (my/gptel--fsm-p fsm)
    (user-error "No gptel request log in this buffer yet!"))
  (require 'tabulated-list)
  (with-current-buffer (get-buffer-create "*gptel-diagnostic*")
    (setq tabulated-list-format [("Request attribute" 30 t)
                                 ("Value" 30)])
    (let* ((pb (lambda (s) (propertize s 'face 'font-lock-builtin-face)))
           (ps (lambda (s) (propertize s 'face 'font-lock-string-face)))
           (fmt (lambda (s)
                  (cond ((memq (car-safe s) '(closure lambda))
                         (format "#<lambda %#x>" (sxhash s)))
                        ((byte-code-function-p s)
                         (format "#<compiled %#x>" (sxhash s)))
                        ((stringp s) (string-replace "\n" "? " s))
                        (t (prin1-to-string s)))))
           (inhibit-read-only t)
           (info (gptel-fsm-info fsm))
           (entries-info
            (cl-loop
             for idx upfrom 3
             for (key val) on info by #'cddr
             unless (memq key '(:data :history :tools :partial_text :partial_json))
             collect
             (list idx `[,(funcall pb (symbol-name key))
                         ,(funcall ps (funcall fmt val))])))
           (entries-data
            (cl-loop
             for idx upfrom 50
             for (key val) on (plist-get info :data) by #'cddr
             unless (memq key '(:messages :stream :contents :query))
             collect
             (list idx `[,(funcall pb (symbol-name key))
                         ,(funcall ps (funcall fmt val))]))))
      (setq tabulated-list-entries
            (nconc (list `(2 [,(funcall pb ":state")
                              ,(funcall ps
                                        (mapconcat
                                         fmt
                                         (reverse (cons (gptel-fsm-state fsm)
                                                        (plist-get info :history)))
                                         " -> "))]))
                   entries-info
                   entries-data))
      (tabulated-list-print)
      (tabulated-list-mode)
      (tabulated-list-init-header)
      (hl-line-mode 1)
      (display-buffer
       (current-buffer)
       '((display-buffer-in-side-window)
         (side . bottom)
         (window-height . fit-window-to-buffer)
         (slot . 10)
         (body-function . select-window))))))

(advice-add 'gptel--inspect-fsm :override #'my/gptel--inspect-fsm)

(defun my/gptel--tool-spec-name (tool-spec)
  "Return a displayable tool name for TOOL-SPEC.
Supports normal gptel tool structs and lightweight plist specs used for
aggregate Programmatic previews."
  (or (let ((name (ignore-errors (gptel-tool-name tool-spec))))
        (and (stringp name) (not (string-empty-p name)) name))
      (let ((name (plist-get tool-spec :name)))
        (and (stringp name) (not (string-empty-p name)) name))
      (format "%s" tool-spec)))

;; --- Enhanced Tool Call Confirmation Context ---

(defun my/gptel--permit-and-accept-tool-calls ()
  "Permit all tools in the current overlay, then accept."
  (interactive)
  (when-let* ((ov (cdr-safe (get-char-property-and-overlay (point) 'gptel-tool)))
              (tool-calls (overlay-get ov 'gptel-tool)))
    (dolist (tc tool-calls)
      (my/gptel-permit-tool (my/gptel--tool-spec-name (car tc)))))
  (call-interactively #'gptel--accept-tool-calls))

(defun my/gptel--programmatic-confirm-tool (tool-spec arg-values callback)
  "Confirm nested Programmatic TOOL-SPEC with ARG-VALUES, then run CALLBACK.
CALLBACK receives non-nil for approval and nil for rejection."
  (let* ((tool-name (my/gptel--tool-spec-name tool-spec))
         (tool-call (list tool-spec arg-values callback))
         (info (list :buffer (current-buffer)
                     :backend gptel-backend
                     :position (point-marker)
                     :tracking-marker (copy-marker (point) t)
                     :programmatic-confirm t)))
    (if (and (stringp tool-name)
             (not (string-empty-p tool-name))
             (bound-and-true-p my/gptel-permitted-tools)
             (my/gptel-tool-permitted-p tool-name))
        (funcall callback t)
      (if (or buffer-read-only
              (get-char-property (point) 'read-only))
          (my/gptel--confirm-tool-calls-minibuffer (list tool-call) info)
        (my/gptel--confirm-tool-calls-overlay
         (list tool-call) info
         (plist-get info :position)
         (plist-get info :tracking-marker))))))

(defun my/gptel--programmatic-aggregate-confirm (plan callback)
  "Show aggregate confirmation UI for multi-step mutating Programmatic PLAN.
CALLBACK receives non-nil for approval and nil for rejection."
  (let* ((summary (mapconcat (lambda (step)
                               (concat "- " (plist-get step :summary)))
                             plan "\n"))
         (tool-calls
          (list (list (list :name "Programmatic Plan")
                      (list summary)
                      callback)))
         (info (list :buffer (current-buffer)
                     :backend gptel-backend
                     :position (point-marker)
                     :tracking-marker (copy-marker (point) t)
                     :programmatic-confirm t
                     :programmatic-aggregate t)))
    (if (or buffer-read-only
            (get-char-property (point) 'read-only))
        (my/gptel--confirm-tool-calls-minibuffer tool-calls info)
      (my/gptel--confirm-tool-calls-overlay
       tool-calls info
       (plist-get info :position)
       (plist-get info :tracking-marker)))))

(defun my/gptel--confirm-tool-calls-minibuffer (tool-calls info)
  "Confirm TOOL-CALLS via minibuffer with per-tool permit support.
Shows each tool call with arguments, offering inspect (i) and permit (p) actions."
  (let* ((minibuffer-allow-text-properties t)
         (backend-name (gptel-backend-name (plist-get info :backend)))
         (programmaticp (plist-get info :programmatic-confirm))
         (aggregatep (plist-get info :programmatic-aggregate))
         (prompt (format "%s wants to run " backend-name)))
    (map-y-or-n-p
     (lambda (tool-call-spec)
       (let* ((tool-name (my/gptel--tool-spec-name (car tool-call-spec)))
              (args (cadr tool-call-spec))
              (done-cb (nth 2 tool-call-spec))
              (permitted (my/gptel-tool-permitted-p tool-name))
              (formatted-args
               (mapconcat (lambda (arg)
                            (cond ((stringp arg)
                                   (truncate-string-to-width arg 60 nil nil "..."))
                                  (t (prin1-to-string arg))))
                          args " ")))
         (if permitted
             ;; Already permitted — auto-accept this one
             (progn
               (if programmaticp
                   (when (functionp done-cb)
                     (funcall done-cb t))
                 (gptel--accept-tool-calls (list tool-call-spec) nil))
               nil)
           (concat (if aggregatep
                       (format "%s wants to run this Programmatic plan step " backend-name)
                     prompt)
                   (propertize tool-name 'face 'font-lock-keyword-face)
                   (if (string-empty-p formatted-args) ""
                     (concat " " (propertize formatted-args 'face 'font-lock-constant-face)))
                   ": "))))
     (lambda (tcs)
       (let ((cb (nth 2 tcs)))
         (if programmaticp
             (when (functionp cb)
               (funcall cb t))
           (gptel--accept-tool-calls (list tcs) nil))))
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
              (let ((name (my/gptel--tool-spec-name (car tool-call-spec))))
                (my/gptel-permit-tool name)
                (message "Permitted %s for this session" name))
              ;; Accept this tool call and continue
              (let ((cb (nth 2 tool-call-spec)))
                (if programmaticp
                    (when (functionp cb)
                      (funcall cb t))
                  (gptel--accept-tool-calls (list tool-call-spec) nil)))
              nil)
           "permit & run (remember)")))))

(defun my/gptel--confirm-tool-calls-overlay (tool-calls info start-marker tracking-marker)
  "Confirm TOOL-CALLS via chat buffer overlay with previews and keybindings.
START-MARKER and TRACKING-MARKER delimit the response region."
  (let* ((backend-name (gptel-backend-name (plist-get info :backend)))
         (programmaticp (plist-get info :programmatic-confirm))
         (aggregatep (plist-get info :programmatic-aggregate))
         (actions-string
          (concat (propertize "Run: " 'face 'font-lock-string-face)
                  (propertize "C-c C-c" 'face 'help-key-binding)
                  (propertize ", Permit & run: " 'face 'font-lock-string-face)
                  (propertize "C-c C-." 'face 'help-key-binding)
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
        (pcase-dolist (`(,tool-spec ,arg-values ,_) tool-calls)
          ;; Call tool-specific confirmation prompt
          (if-let* ((funcs (and (not programmaticp)
                                (cdr (assoc (gptel-tool-name tool-spec)
                                            gptel--tool-preview-alist))))
                    ((functionp (car-safe funcs))))
              ;;preview-teardown func   preview-handle overlay/buffer
              (push (list (cadr funcs) (funcall (car funcs) arg-values info))
                    preview-handlers)
            (push (if aggregatep
                      (car arg-values)
                    (gptel--format-tool-call (my/gptel--tool-spec-name tool-spec) arg-values))
                  confirm-strings)))
        (and confirm-strings (apply #'insert (nreverse confirm-strings)))
        ;; Only mark read-only if text was actually inserted (guard inverted range).
        (let ((insert-end (point))
              (ov-end (overlay-end ov)))
          (when (and (> insert-end ov-end)
                     (> insert-end (1+ (point-min))))
            (add-text-properties ov-end (1- insert-end)
                                 '(read-only t font-lock-fontified t))))
        (setq prompt-ov (make-overlay (overlay-end ov) (point) nil t))
        (overlay-put
         prompt-ov 'before-string
         (concat "\n"
                 (propertize " " 'display `(space :align-to (- right ,(length actions-string) 2))
                             'face '(:inherit font-lock-string-face :underline t :extend t))
                 actions-string
                 (format (propertize "\n%s wants to run%s:\n\n"
                                     'face 'font-lock-string-face)
                         backend-name
                         (if aggregatep " this Programmatic plan" ""))))
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
        (overlay-put ov 'gptel-programmatic-confirm programmaticp)
        (overlay-put ov 'help-echo
                     (concat "Tool call(s) requested: " actions-string))
        (let ((map (make-sparse-keymap)))
          (set-keymap-parent map gptel-tool-call-actions-map)
          (define-key map (kbd "C-c C-.") #'my/gptel--permit-and-accept-tool-calls)
          (overlay-put ov 'keymap map))))))

(defun my/gptel--display-tool-calls (tool-calls info &optional use-minibuffer)
  "Handle tool call confirmation with per-tool permit memory.

If all requested tools are already permitted (via `my/gptel-permitted-tools'),
auto-accepts without prompting.  Otherwise shows the standard confirmation
with an additional `p' option to permit and remember a tool."
  ;; Fast path: if all tools are already permitted, auto-accept
  (if (and (bound-and-true-p my/gptel-permitted-tools)
           (cl-every (lambda (tc) (my/gptel-tool-permitted-p (my/gptel--tool-spec-name (car tc))))
                     tool-calls))
      (gptel--accept-tool-calls tool-calls nil)
    ;; Slow path: show confirmation UI
    (let* ((start-marker (plist-get info :position))
           (tracking-marker (plist-get info :tracking-marker))
           (buf (or (plist-get info :buffer) (current-buffer)))
           (fallback-pos (with-current-buffer buf (point-marker))))
      (unless (and start-marker (markerp start-marker) (marker-position start-marker))
        (setq start-marker fallback-pos))
      (unless (and tracking-marker (markerp tracking-marker) (marker-position tracking-marker))
        (setq tracking-marker start-marker))
      (with-current-buffer buf
        (if (or use-minibuffer
                buffer-read-only
                (get-char-property
                 (max (point-min) (1- (or tracking-marker start-marker)))
                 'read-only))
            (my/gptel--confirm-tool-calls-minibuffer tool-calls info)
          (my/gptel--confirm-tool-calls-overlay
           tool-calls info start-marker tracking-marker))))))

(defun my/gptel--programmatic-confirm-cleanup-overlay (ov)
  "Remove confirmation UI for nested Programmatic overlay OV."
  (when (and (overlayp ov) (overlay-buffer ov))
    (with-current-buffer (overlay-buffer ov)
      (when-let* ((prompt-ov (overlay-get ov 'prompt))
                  (buf (overlay-buffer prompt-ov))
                  (inhibit-read-only t))
        (delete-region (overlay-start prompt-ov)
                       (overlay-end prompt-ov))))
    (delete-overlay ov)))

(defun my/gptel--extract-programmatic-callback (response ov)
  "Extract callback from PROGRAMMATIC RESPONSE if valid.
Returns (callback . is-programmatic) where callback is the function or nil."
  (if (and (listp response)
           (= (length response) 1)
           (listp (car-safe response)))
      (let* ((first (car response))
             (cb (nth 2 first)))
        (if (or (and (overlayp ov) (overlay-get ov 'gptel-programmatic-confirm))
                (functionp cb))
            (cons cb t)
          (cons nil nil)))
    (cons nil nil)))

(defun my/gptel--around-accept-tool-calls (orig &optional response ov)
  "Handle nested Programmatic tool confirmations before normal acceptance."
  (pcase-let ((`(,cb . ,programmaticp) (my/gptel--extract-programmatic-callback response ov)))
    (if programmaticp
        (progn
          (when (functionp cb)
            (funcall cb t))
          (my/gptel--programmatic-confirm-cleanup-overlay ov))
      (funcall orig response ov))))

(defun my/gptel--around-reject-tool-calls (orig &optional response ov)
  "Handle nested Programmatic tool rejections before normal cancellation."
  (pcase-let ((`(,cb . ,programmaticp) (my/gptel--extract-programmatic-callback response ov)))
    (if programmaticp
        (progn
          (when (functionp cb)
            (funcall cb nil))
          (my/gptel--programmatic-confirm-cleanup-overlay ov))
      (funcall orig response ov))))

(advice-add 'gptel--display-tool-calls :override #'my/gptel--display-tool-calls)
(advice-add 'gptel--accept-tool-calls :around #'my/gptel--around-accept-tool-calls)
(advice-add 'gptel--reject-tool-calls :around #'my/gptel--around-reject-tool-calls)

(with-eval-after-load 'gptel-sandbox
  (setq gptel-sandbox-confirm-function #'my/gptel--programmatic-confirm-tool)
  (setq gptel-sandbox-aggregate-confirm-function #'my/gptel--programmatic-aggregate-confirm))

(provide 'gptel-ext-tool-confirm)
;;; gptel-ext-tool-confirm.el ends here
