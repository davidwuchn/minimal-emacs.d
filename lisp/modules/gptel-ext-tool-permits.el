;;; gptel-ext-tool-permits.el --- Tool confirmation modes -*- no-byte-compile: t; lexical-binding: t -*-

;;; Commentary:
;; Tool confirmation system with per-tool permit memory.
;;
;; Two modes:
;;   auto        → gptel-confirm-tool-calls nil   (no confirmation)
;;   confirm-all → gptel-confirm-tool-calls t     (confirm every call)
;;
;; Per-tool permit memory: once you approve a tool in confirm-all mode,
;; it's remembered for the Emacs session. Toggle clears permits.

;;; Code:

(require 'gptel)

;;; --- State ---

(defvar my/gptel-confirm-mode 'auto
  "Current confirmation mode: `auto' or `confirm-all'.")

(defvar my/gptel-permitted-tools (make-hash-table :test 'equal)
  "Session-scoped set of permitted tool names.
Keys are tool name strings, values are t.")

;;; --- Core API ---

(defun my/gptel-tool-permitted-p (tool-name)
  "Return non-nil if TOOL-NAME has been permitted this session."
  (and (hash-table-p my/gptel-permitted-tools)
       (stringp tool-name)
       (gethash tool-name my/gptel-permitted-tools)))

(defun my/gptel-permit-tool (tool-name)
  "Permit TOOL-NAME for the rest of this Emacs session.
TOOL-NAME must be a non-empty string."
  ;; ASSUMPTION: tool-name is a valid tool identifier string
  ;; EDGE CASE: nil or non-string inputs are silently ignored
  ;; EDGE CASE: uninitialized hash table is handled gracefully
  (when (and (hash-table-p my/gptel-permitted-tools)
             (stringp tool-name)
             (not (string-empty-p tool-name)))
    (puthash tool-name t my/gptel-permitted-tools)))

(defun my/gptel-clear-permits ()
  "Clear all per-tool permits."
  (when (hash-table-p my/gptel-permitted-tools)
    (clrhash my/gptel-permitted-tools)))

(defun my/gptel--sync-to-upstream ()
  "Sync `my/gptel-confirm-mode' to upstream `gptel-confirm-tool-calls'."
  ;; ASSUMPTION: gptel-confirm-tool-calls is a valid customizable variable
  ;; BEHAVIOR: Sets the variable globally and in all gptel-mode buffers
  ;; EDGE CASE: Buffers in inconsistent state are skipped, not fatal
  ;; TEST: Toggle mode with gptel buffers open and closed
  (let ((val (if (eq my/gptel-confirm-mode 'auto) nil t)))
    (setq gptel-confirm-tool-calls val)
    (setq-default gptel-confirm-tool-calls val)
    (dolist (b (buffer-list))
      (condition-case err
          (with-current-buffer b
            (when (derived-mode-p 'gptel-mode)
              (setq-local gptel-confirm-tool-calls val)))
        (error
         ;; Skip buffers that error during sync - don't break the loop
         (message "Warning: could not sync buffer %s: %s"
                  (buffer-name b) (error-message-string err)))))))

(defun my/gptel--mode-label ()
  "Return display label for current confirmation mode."
  (if (eq my/gptel-confirm-mode 'auto) "AUTO" "CONFIRM-ALL"))

;;; --- User Commands ---

;;;###autoload
(defun my/gptel-toggle-confirm ()
  "Toggle between auto and confirm-all modes.
Switching to confirm-all clears all per-tool permits."
  (interactive)
  (setq my/gptel-confirm-mode
        (if (eq my/gptel-confirm-mode 'auto) 'confirm-all 'auto))
  (when (eq my/gptel-confirm-mode 'confirm-all)
    (my/gptel-clear-permits))
  (my/gptel--sync-to-upstream)
  ;; ASSUMPTION: permit count is only meaningful in auto mode or before clear
  ;; BEHAVIOR: Shows count only when permits exist (auto mode), not after clear
  (let ((permit-count (hash-table-count my/gptel-permitted-tools)))
    (message "Tool confirmation: %s%s"
             (my/gptel--mode-label)
             (if (and (eq my/gptel-confirm-mode 'auto) (> permit-count 0))
                 (format " (%d tools permitted)" permit-count)
               ""))))

;;;###autoload
(defun my/gptel-show-permits ()
  "Show currently permitted tools."
  (interactive)
  ;; ASSUMPTION: Hash keys should be strings (tool names)
  ;; EDGE CASE: Non-string keys from corrupted state are filtered out
  ;; TEST: Call with normal permits and verify display
  (let ((tools (when (hash-table-p my/gptel-permitted-tools)
                 (cl-loop for k being the hash-keys of my/gptel-permitted-tools
                          when (stringp k) collect k))))
    (if (null tools)
        (message "No tools permitted (mode: %s)" my/gptel-confirm-mode)
      (message "Permitted tools: %s (mode: %s)"
               (string-join tools ", ")
               my/gptel-confirm-mode))))

;;;###autoload
(defun my/gptel-emergency-stop ()
  "Emergency stop: abort all requests, clear permits, switch to confirm-all.

Use this when the agent is misbehaving or you need immediate control back."
  (interactive)
  (my/gptel-clear-permits)
  (setq my/gptel-confirm-mode 'confirm-all)
  (my/gptel--sync-to-upstream)
  (when (fboundp 'my/gptel-abort-here)
    (my/gptel-abort-here))
  (message "EMERGENCY STOP - Permits cleared, confirm-all mode, requests aborted"))

;;;###autoload
(defun my/gptel-health-check ()
  "Show tool system status: mode, permits, preset, registered tools."
  (interactive)
  (let* ((permits (hash-table-count my/gptel-permitted-tools))
         (preset (and (boundp 'gptel--preset) gptel--preset))
         (tools (and (boundp 'gptel-tools)
                     (proper-list-p gptel-tools)
                     (length gptel-tools)))
         (active-procs
          (cl-count-if (lambda (p)
                         (and (processp p)
                              (process-live-p p)
                              (or (process-get p 'my/gptel-managed)
                                  (string-prefix-p "gptel-" (process-name p)))))
                       (process-list))))
    ;; ASSUMPTION: process-list returns valid process objects or nil
    ;; EDGE CASE: Non-process items in process-list are filtered by processp
    (message "Tool Health: %s | Permits: %d | Preset: %s | Tools: %s | Active: %d"
             (my/gptel--mode-label)
             permits
             (or preset "none")
             (or tools 0)
             active-procs)))

;;; --- Setup ---

(defun my/gptel-setup-tool-ui ()
  "Initialize tool confirmation system."
  (my/gptel--sync-to-upstream)
  (message "Tool UI: %s" my/gptel-confirm-mode))

(with-eval-after-load 'gptel
  (my/gptel-setup-tool-ui))

(provide 'gptel-ext-tool-permits)

;;; gptel-ext-tool-permits.el ends here
