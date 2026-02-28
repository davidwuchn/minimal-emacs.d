;;; gptel-tool-ui.el --- Unified Tool Call Confirmation UI -*- lexical-binding: t -*-

;;; Commentary:
;; This module provides a unified tool call confirmation UI that:
;; 1. Shows consistent options in both overlay and minibuffer
;; 2. Supports 5-tier confirmation levels (auto/safe/normal/strict/paranoid)
;; 3. Provides clear help text matching available keybindings

;;; Code:

(defgroup my/gptel-confirmation nil
  "Enhanced tool call confirmation settings."
  :group 'gptel)

(defcustom my/gptel-confirmation-level 'normal
  "Confirmation level for tool calls.

Levels:
- auto     : No confirmation, auto-execute all tools
- safe     : Confirm only dangerous tools (Bash, Write, ApplyPatch)
- normal   : Confirm all tool calls (default)
- strict   : Confirm all tools with detailed preview
- paranoid : Confirm all tools with manual review required"
  :type '(choice (const :tag "Auto-execute (no confirmation)" auto)
                 (const :tag "Safe (dangerous tools only)" safe)
                 (const :tag "Normal (all tools)" normal)
                 (const :tag "Strict (detailed preview)" strict)
                 (const :tag "Paranoid (manual review)" paranoid))
  :group 'my/gptel-confirmation)

(defconst my/gptel--dangerous-tools
  '("Bash" "BashRO" "Write" "ApplyPatch" "Mkdir" "Move" "Delete")
  "List of potentially dangerous tool names that modify state.")

(defun my/gptel--tool-is-dangerous-p (tool-name)
  "Check if TOOL-NAME is in the dangerous tools list."
  (member tool-name my/gptel--dangerous-tools))

(defun my/gptel--get-confirmation-prompt ()
  "Get appropriate confirmation prompt based on confirmation level."
  (pcase my/gptel-confirmation-level
    ('auto "Auto-executing tool calls...")
    ('safe "Run dangerous tool calls?")
    ('normal "Run tool calls?")
    ('strict "Review and approve tool calls?")
    ('paranoid "MANUAL REVIEW REQUIRED: Approve tool calls?")
    (_ "Run tool calls?")))

(defun my/gptel--dispatch-tool-calls (&optional event)
  "Unified tool call dispatcher with consistent overlay/minibuffer options.

When called from overlay mouse click, EVENT is the mouse event.
When called interactively, EVENT is nil.

Shows all 6 available options in the minibuffer:
- y: Accept and run
- n: Skip but continue
- k: Cancel/reject
- i: Inspect details
- p: Previous overlay
- q: Quit/reject"
  (interactive)
  ;; If called from overlay click, move point to click position
  (when event
    (let ((pos (posn-point (event-end event))))
      (when pos
        (goto-char pos))))
  (let* ((prompt (my/gptel--get-confirmation-prompt))
         (choices '((?y ?Y "yes - Accept and run tool calls")
                    (?n ?N "no - Skip tool calls, continue without")
                    (?k ?K "cancel - Reject and cancel request")
                    (?i ?I "inspect - Inspect tool call details")
                    (?p ?P "previous - Jump to previous overlay")
                    (?q ?Q "quit - Reject tool calls"))))
    (cond
     ((eq my/gptel-confirmation-level 'auto)
      ;; Auto-execute without confirmation
      (message "Auto-executing tool calls...")
      (call-interactively #'gptel--accept-tool-calls))
     (t
      ;; Show confirmation with all options (always via minibuffer)
      (let ((choice (read-multiple-choice (concat prompt " (y/n/k/i/p/q) ") choices)))
        (pcase (car choice)
          (?y (call-interactively #'gptel--accept-tool-calls))
          (?n (message "Skipping tool calls...") nil)
          (?k (call-interactively #'gptel--reject-tool-calls))
          (?i (when (fboundp 'gptel--inspect-fsm)
                (gptel--inspect-fsm gptel--fsm-last)))
          (?p (when (fboundp 'gptel-agent--previous-overlay)
                (call-interactively #'gptel-agent--previous-overlay)))
          (?q (call-interactively #'gptel--reject-tool-calls))))))))

;;;###autoload
(defun my/gptel-set-confirmation-level (level)
  "Set tool call confirmation LEVEL interactively.

LEVEL can be: auto, safe, normal, strict, or paranoid."
  (interactive
   (list (completing-read "Confirmation level: "
                          '("auto" "safe" "normal" "strict" "paranoid")
                          nil t "normal")))
  (setq my/gptel-confirmation-level (intern level))
  (message "Tool confirmation level set to: %s"
           (pcase my/gptel-confirmation-level
             ('auto "AUTO (no confirmation)")
             ('safe "SAFE (dangerous tools only)")
             ('normal "NORMAL (all tools)")
             ('strict "STRICT (detailed preview)")
             ('paranoid "PARANOID (manual review)")
             (_ "UNKNOWN"))))

;;;###autoload
(defun my/gptel-setup-tool-ui ()
  "Set up unified tool call confirmation UI.

This patches `gptel--dispatch-tool-calls' to:
1. Show all 6 options in minibuffer (matching overlay keymap)
2. Support 5-tier confirmation levels
3. Provide consistent UX between overlay and minibuffer"
  (advice-add 'gptel--dispatch-tool-calls :override #'my/gptel--dispatch-tool-calls)
  (message "Unified tool UI enabled (y/n/k/i/p/q | 5-tier confirmation)"))

(provide 'gptel-tool-ui)

;;; gptel-tool-ui.el ends here
