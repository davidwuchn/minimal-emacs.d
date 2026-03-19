;;; nucleus-mode-switch.el --- Mode transition handler for nucleus -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 2.0.0
;;
;; Handles mode transitions (plan <-> agent) and injects appropriate
;; system reminders to break LLM context carryover.

(require 'cl-lib)

;;; Variables

(defvar nucleus--plan-mode-active nil
  "Tracks whether we were previously in plan mode.")

(make-variable-buffer-local 'nucleus--plan-mode-active)

;;; Mode Transition Detection

(defun nucleus--check-mode-transition (&rest _)
  "Advice to run after `gptel--apply-preset'.

Detects plan<->agent transitions and injects a system reminder in both
directions to break the LLM out of its prior mode mindset.
Dedup guard: only fires when the tracked state actually changes."
  (when (and (boundp 'gptel--preset)
             gptel--preset)
    (let ((was-plan nucleus--plan-mode-active)
          (is-plan (eq gptel--preset 'gptel-plan))
          (is-agent (eq gptel--preset 'gptel-agent)))
      ;; Only act when the state actually changes (dedup guard)
      (unless (eq was-plan is-plan)
        (setq-local nucleus--plan-mode-active is-plan)
        (cond
         ((and was-plan is-agent)
          (nucleus--inject-build-mode-reminder))
         ((and (not was-plan) is-plan)
          (nucleus--inject-plan-mode-reminder)))))))

(defun nucleus--inject-build-mode-reminder ()
  "Inject a system reminder when switching from plan to build mode.

Inserts after the last assistant exchange, before the current prompt."
  (when (and (derived-mode-p 'gptel-mode)
             (boundp 'gptel--tracking-marker)
             gptel--tracking-marker)
    (save-excursion
      (let ((insert-pos (marker-position gptel--tracking-marker)))
        (when insert-pos
          (goto-char insert-pos)
          (let ((reminder
                 (concat "\n\n<system-reminder>\n"
                         "Your operational mode has changed from plan to build.\n"
                         "You are no longer in read-only mode.\n"
                         "You are permitted to make file changes, run shell commands,\n"
                         "and utilize your full toolkit as needed.\n"
                         "CONTINUE EXECUTING YOUR TASK IMMEDIATELY. Do not pause.\n"
                         "</system-reminder>\n")))
            (unless (looking-back (regexp-quote "<system-reminder>")
                                  (max 0 (- (point) 100)))
              (insert reminder))))))))

(defun nucleus--inject-plan-mode-reminder ()
  "Inject a system reminder when switching from build to plan mode.

Inserts after the last assistant exchange, before the current prompt."
  (when (and (derived-mode-p 'gptel-mode)
             (boundp 'gptel--tracking-marker)
             gptel--tracking-marker)
    (save-excursion
      (let ((insert-pos (marker-position gptel--tracking-marker)))
        (when insert-pos
          (goto-char insert-pos)
          (let ((reminder
                 (concat "\n\n<system-reminder>\n"
                         "Your operational mode has changed from build to plan.\n"
                         "You are now in read-only mode.\n"
                         "Do not attempt file changes or shell commands.\n"
                         "Use only read-only tools: Glob, Grep, Read.\n"
                         "CONTINUE YOUR ANALYSIS IMMEDIATELY. Do not pause.\n"
                         "</system-reminder>\n")))
            (unless (looking-back (regexp-quote "<system-reminder>")
                                  (max 0 (- (point) 100)))
              (insert reminder))))))))

;;; Integration

;;;###autoload
(defun nucleus-mode-switch-setup ()
  "Setup mode transition tracking."
  (advice-add 'gptel--apply-preset :after #'nucleus--check-mode-transition))

(provide 'nucleus-mode-switch)

;;; nucleus-mode-switch.el ends here
