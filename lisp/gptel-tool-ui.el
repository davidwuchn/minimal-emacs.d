;;; gptel-tool-ui.el --- Enhanced tool call confirmation UI -*- lexical-binding: t -*-

;;; Commentary:
;; This module patches gptel's tool call confirmation to provide
;; consistent options between overlay and minibuffer prompts.

;;; Code:

(defun my/gptel--dispatch-tool-calls (&optional _event)
  "Enhanced version of `gptel--dispatch-tool-calls' with better help text.

Shows all available options in the minibuffer prompt to match overlay keymap."
  (interactive)
  (let* ((choices '((?y "yes - Accept and run tool calls")
                    (?n "no - Skip tool calls, continue without")
                    (?k "cancel - Reject and cancel request")
                    (?i "inspect - Inspect tool call details")
                    (?p "previous - Jump to previous overlay")
                    (?q "quit - Reject tool calls")))
         (choice (read-multiple-choice "Tool calls: " choices)))
    (pcase (car choice)
      (?y (call-interactively #'gptel--accept-tool-calls))
      (?n (message "Skipping tool calls...") nil)
      (?k (call-interactively #'gptel--reject-tool-calls))
      (?i (when (fboundp 'gptel--inspect-fsm)
            (gptel--inspect-fsm gptel--fsm-last)))
      (?p (when (fboundp 'gptel-agent--previous-overlay)
            (call-interactively #'gptel-agent--previous-overlay)))
      (?q (call-interactively #'gptel--reject-tool-calls)))))

;;;###autoload
(defun my/gptel-setup-tool-ui ()
  "Set up enhanced tool call confirmation UI.

This patches `gptel--dispatch-tool-calls' to show all available options
in the minibuffer, matching the overlay keymap options."
  (advice-add 'gptel--dispatch-tool-calls :override #'my/gptel--dispatch-tool-calls)
  (message "Enhanced tool call UI enabled (y/n/k/i/p/q)"))

(provide 'gptel-tool-ui)

;;; gptel-tool-ui.el ends here
