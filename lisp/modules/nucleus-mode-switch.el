;;; nucleus-mode-switch.el --- Mode transition handler for nucleus -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 3.0.0
;;
;; Handles mode transitions (plan <-> agent) and injects appropriate
;; system reminders to break LLM context carryover.
;;
;; IMPORTANT: Captures last assistant response on both transitions
;; so context is preserved when switching modes.

(require 'cl-lib)

;;; Variables

(defvar nucleus--previous-preset nil
  "Tracks the previous preset for transition detection.
Values: nil (unset), 'gptel-plan, or 'gptel-agent.")

(defvar nucleus--last-response-content nil
  "Captured last assistant response before mode switch.
Used for both Plan→Agent and Agent→Plan transitions to preserve context.")

(make-variable-buffer-local 'nucleus--previous-preset)
(make-variable-buffer-local 'nucleus--last-response-content)

;;; Response Capture

(defun nucleus--capture-last-assistant-response ()
  "Capture the last assistant response content.
Returns text from last '###' heading to end of buffer, or nil if not found."
  (save-excursion
    (goto-char (point-max))
    (when (re-search-backward "^### " nil t)
      (let ((content (buffer-substring-no-properties (point) (point-max))))
        (when (> (length content) 50)
          (if (> (length content) 3000)
              (concat (substring content 0 3000) "\n...[truncated]")
            content))))))

;;; Mode Transition Detection

(defun nucleus--check-mode-transition (&rest _)
  "Advice to run after `gptel--apply-preset`.

Detects plan<->agent transitions and injects a system reminder in both
directions to break the LLM out of its prior mode mindset.
Captures last response content before transitioning.
Only fires on actual transitions (not initial setup)."
  (when (and (boundp 'gptel--preset)
             gptel--preset
             (memq gptel--preset '(gptel-plan gptel-agent)))
    (let ((previous nucleus--previous-preset)
          (current gptel--preset))
      ;; Only inject on actual transitions (not first-time setup)
      (when (and previous
                 (not (eq previous current)))
        ;; Capture response BEFORE switching
        (setq-local nucleus--last-response-content
                    (nucleus--capture-last-assistant-response))
        (cond
         ;; Plan → Agent: inject build reminder with plan
         ((and (eq previous 'gptel-plan)
               (eq current 'gptel-agent))
          (nucleus--inject-build-mode-reminder))
         ;; Agent → Plan: inject plan reminder with agent findings
         ((and (eq previous 'gptel-agent)
               (eq current 'gptel-plan))
          (nucleus--inject-plan-mode-reminder))))
      ;; Update tracked state
      (setq-local nucleus--previous-preset current))))

(defun nucleus--inject-build-mode-reminder ()
  "Inject a system reminder when switching from plan to build mode.

Includes captured plan content so agent knows what to execute.
Inserts after the last assistant exchange, before the current prompt.
Skips injection during active tool execution to avoid contaminating output."
  (when (and (derived-mode-p 'gptel-mode)
             (boundp 'gptel--tracking-marker)
             gptel--tracking-marker
             (not (nucleus--request-in-progress-p))
             (save-excursion
               (goto-char gptel--tracking-marker)
               (looking-back "```\n\\|</system-reminder>\n\\|\n\n"
                             (max 0 (- (point) 50)))))
    (save-excursion
      (let ((insert-pos (marker-position gptel--tracking-marker)))
        (when insert-pos
          (goto-char insert-pos)
          (let* ((plan-content nucleus--last-response-content)
                 (reminder
                  (concat "\n\n<system-reminder>\n"
                          "Your operational mode has changed from plan to build.\n"
                          "You are no longer in read-only mode.\n"
                          "EXECUTE THE PLAN BELOW NOW. Do not announce. Do not ask for clarification.\n"
                          "JUST CALL THE TOOLS. Permission is already granted.\n"
                          (if plan-content
                              (format "\n--- PLAN TO EXECUTE ---\n%s\n--- END PLAN ---\n"
                                      plan-content)
                            "\n(Execute the task you just planned.)\n")
                          "</system-reminder>\n")))
            (unless (looking-back (regexp-quote "<system-reminder>")
                                  (max 0 (- (point) 100)))
              (insert reminder))))))))

(defun nucleus--inject-plan-mode-reminder ()
  "Inject a system reminder when switching from build to plan mode.

Includes captured agent findings so planner knows current state.
Inserts after the last assistant exchange, before the current prompt.
Skips injection during active tool execution to avoid contaminating output."
  (when (and (derived-mode-p 'gptel-mode)
             (boundp 'gptel--tracking-marker)
             gptel--tracking-marker
             (not (nucleus--request-in-progress-p))
             (save-excursion
               (goto-char gptel--tracking-marker)
               (looking-back "```\n\\|</system-reminder>\n\\|\n\n"
                             (max 0 (- (point) 50)))))
    (save-excursion
      (let ((insert-pos (marker-position gptel--tracking-marker)))
        (when insert-pos
          (goto-char insert-pos)
          (let* ((agent-content nucleus--last-response-content)
                 (reminder
                  (concat "\n\n<system-reminder>\n"
                          "Your operational mode has changed from build to plan.\n"
                          "You are now in read-only mode.\n"
                          "Do not attempt file changes or shell commands.\n"
                          "Use only read-only tools: Glob, Grep, Read.\n"
                          (if agent-content
                              (format "\n--- AGENT FINDINGS ---\n%s\n--- END FINDINGS ---\n"
                                      agent-content)
                            "\n(Continue planning based on current state.)\n")
                          "CONTINUE YOUR ANALYSIS IMMEDIATELY. Do not pause.\n"
                          "</system-reminder>\n")))
            (unless (looking-back (regexp-quote "<system-reminder>")
                                  (max 0 (- (point) 100)))
              (insert reminder))))))))

(defun nucleus--request-in-progress-p ()
  "Check if there's an active gptel request in progress.
Returns non-nil if FSM is in WAIT, TYPE, TOOL, or TRET state."
  (when (and (boundp 'gptel--fsm-last)
             gptel--fsm-last)
    (let ((state (condition-case nil
                     (gptel-fsm-state gptel--fsm-last)
                   (error nil))))
      (and state
           (memq state '(WAIT TYPE TOOL TRET))))))

;;; Integration

;;;###autoload
(defun nucleus-mode-switch-setup ()
  "Setup mode transition tracking."
  (advice-add 'gptel--apply-preset :after #'nucleus--check-mode-transition))

(provide 'nucleus-mode-switch)

;;; nucleus-mode-switch.el ends here
