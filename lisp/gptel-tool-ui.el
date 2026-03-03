;;; gptel-tool-ui.el --- Unified Tool Call Confirmation UI -*- lexical-binding: t -*-

;;; Commentary:
;; Enhanced tool call confirmation UI with 3 tiers that map directly to
;; upstream gptel-confirm-tool-calls:
;;
;;   auto        → nil   (no confirmation ever)
;;   normal      → 'auto (confirm tools with :confirm t — the default)
;;   confirm-all → t     (confirm every tool call)
;;
;; The dispatch replaces the overlay mouse-click handler with a 7-option
;; minibuffer menu: y/n/k/a/i/p/q.

;;; Code:

(defgroup my/gptel-confirmation nil
  "Enhanced tool call confirmation settings."
  :group 'gptel)

(defcustom my/gptel-confirmation-level 'normal
  "Confirmation level for tool calls.

Maps directly to upstream `gptel-confirm-tool-calls':
- auto        : No confirmation, auto-execute all tools  (→ nil)
- normal      : Confirm tools with :confirm t (default)  (→ \\='auto)
- confirm-all : Confirm every tool call                  (→ t)"
  :type '(choice (const :tag "Auto-execute (no confirmation)" auto)
                 (const :tag "Normal (tools with :confirm t)" normal)
                 (const :tag "Confirm all tool calls" confirm-all))
  :group 'my/gptel-confirmation)

(defun my/gptel--sync-confirmation-to-upstream ()
  "Sync `my/gptel-confirmation-level' to `gptel-confirm-tool-calls'."
  (let ((val (pcase my/gptel-confirmation-level
               ('auto nil)
               ('normal 'auto)
               ('confirm-all t)
               (_ 'auto))))
    (setq gptel-confirm-tool-calls val)
    (setq-default gptel-confirm-tool-calls val)
    (dolist (b (buffer-list))
      (with-current-buffer b
        (when (derived-mode-p 'gptel-mode)
          (setq-local gptel-confirm-tool-calls val))))))

(defun my/gptel--get-confirmation-prompt ()
  "Get appropriate confirmation prompt based on confirmation level."
  (pcase my/gptel-confirmation-level
    ('auto "Auto-executing tool calls...")
    ('normal "Run tool calls?")
    ('confirm-all "Confirm tool call?")
    (_ "Run tool calls?")))

(defun my/gptel--dispatch-tool-calls (&optional event)
  "Unified tool call dispatcher with consistent overlay/minibuffer options.

When called from overlay mouse click, EVENT is the mouse event.
When called interactively, EVENT is nil.

Options:
- y: Accept and run
- n: Defer (leave overlay, decide later)
- k: Cancel/reject request
- a: Switch to auto level for rest of session
- i: Inspect FSM details
- p: Jump to previous overlay
- q: Reject (same as k)"
  (interactive)
  (when (mouse-event-p last-nonmenu-event)
    (mouse-set-point last-nonmenu-event))
  (let* ((prompt (my/gptel--get-confirmation-prompt))
         (choices '((?y "yes - Accept and run tool calls")
                    (?n "no - Defer (decide later)")
                    (?k "cancel - Reject and cancel request")
                    (?a "auto - Auto-execute all (rest of session)")
                    (?i "inspect - Inspect tool call details")
                    (?p "previous - Jump to previous overlay")
                    (?q "quit - Reject tool calls"))))
    (cond
     ((eq my/gptel-confirmation-level 'auto)
      (message "Auto-executing tool calls...")
      (call-interactively #'gptel--accept-tool-calls))
     (t
      (let ((choice (read-multiple-choice (concat prompt " (y/n/k/a/i/p/q) ") choices)))
        (pcase (car choice)
          (?y (call-interactively #'gptel--accept-tool-calls))
          (?n (message "Deferred — click overlay or C-c C-c to accept.") nil)
          (?k (call-interactively #'gptel--reject-tool-calls))
          (?a (setq my/gptel-confirmation-level 'auto)
              (my/gptel--sync-confirmation-to-upstream)
              (message "Confirmation level → AUTO (rest of session)")
              (call-interactively #'gptel--accept-tool-calls))
          (?i (when (fboundp 'gptel--inspect-fsm)
                (gptel--inspect-fsm gptel--fsm-last)))
          (?p (when (fboundp 'gptel-agent--previous-overlay)
                (call-interactively #'gptel-agent--previous-overlay)))
          (?q (call-interactively #'gptel--reject-tool-calls))))))))

;;;###autoload
(defun my/gptel-set-confirmation-level (level)
  "Set tool call confirmation LEVEL interactively.

LEVEL can be: auto, normal, or confirm-all.
Syncs to upstream `gptel-confirm-tool-calls' immediately."
  (interactive
   (list (completing-read "Confirmation level: "
                          '("auto" "normal" "confirm-all")
                          nil t "normal")))
  (setq my/gptel-confirmation-level (intern level))
  (my/gptel--sync-confirmation-to-upstream)
  (message "Tool confirmation: %s"
           (pcase my/gptel-confirmation-level
             ('auto "AUTO — no confirmation")
             ('normal "NORMAL — confirm tools with :confirm t")
             ('confirm-all "CONFIRM-ALL — confirm every tool call")
             (_ "UNKNOWN"))))

;;;###autoload
(defun my/gptel-setup-tool-ui ()
  "Set up unified tool call confirmation UI.

Patches `gptel-tool-call-actions-map' mouse-1 to use our dispatch,
and syncs the current confirmation level to upstream."
  (define-key gptel-tool-call-actions-map [mouse-1] #'my/gptel--dispatch-tool-calls)
  (my/gptel--sync-confirmation-to-upstream)
  (message "Unified tool UI enabled (y/n/k/a/i/p/q | %s)"
           my/gptel-confirmation-level))

;; Setup AFTER gptel loads and creates the keymap
(with-eval-after-load 'gptel
  (my/gptel-setup-tool-ui))

(provide 'gptel-tool-ui)

;;; gptel-tool-ui.el ends here
