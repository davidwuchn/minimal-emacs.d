;;; gptel-ext-tool-sanitize.el --- Tool call sanitization and doom-loop detection -*- lexical-binding: t; -*-

;;; Commentary:
;; Sanitize malformed tool calls, detect doom-loops, and deduplicate tools.
;;
;; - nil/unknown tool calls: pre-mark with error result so FSM doesn't hang
;; - Doom-loop detection: abort when same tool+args repeats N times (OpenCode-style)
;; - Tool dedup: remove duplicate tool names before API serialization

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'gptel)

;; Handle nil/unknown tool calls gracefully instead of hanging the FSM.
;; When a model sends a tool call with a nil or unrecognized name, gptel's
;; `gptel--handle-tool-use' logs a message but doesn't advance the tool
;; counter, causing the FSM to hang forever.  This advice pre-marks any
;; malformed tool calls with an error result so they're skipped.
(defun my/gptel--nil-tool-call-p (tc)
  "Return non-nil when TC is a nil/null-named tool call spec."
  (let ((name (plist-get tc :name)))
    (or (null name) (eq name :null) (equal name "null"))))

(defun my/gptel--sanitize-tool-calls (fsm)
  "Remove nil/unknown-named tool calls from FSM before execution.

Two things are done for each offending entry:
1. Pre-set :result so gptel--handle-tool-use skips execution.
2. Remove the entry from :tool-use entirely so gptel--parse-tool-results
   does not emit an orphaned `tool' role message (tool_call_id=null with
   no matching tool_calls in the assistant message), which would cause a
   400 Bad Request from OpenRouter/Anthropic on the next turn.

Recovery: if a tool is not in info :tools but IS registered in
`gptel--known-tools' (i.e. a preset misconfiguration rather than
hallucination), it is injected into info :tools so it can execute.
This handles the case where the gptel-agent preset was applied before
RunAgent was registered, leaving it out of the buffer's tool list."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
              (tool-use (plist-get info :tool-use)))
    ;; Get the tools list; may be nil if preset had no tools set.
    (let ((tools (plist-get info :tools))
          pruned)
      (dolist (tc tool-use)
        (let* ((name (plist-get tc :name))
               (matched-tool (and (stringp name)
                                  (cl-find-if
                                   (lambda (ts) (string-equal-ignore-case
                                                 (gptel-tool-name ts) name))
                                   tools))))
          (cond
           ;; Case 1: found in info :tools (normal case)
           (matched-tool
            (let ((correct-name (gptel-tool-name matched-tool)))
              (unless (string= name correct-name)
                (message "gptel: repairing tool call casing %S -> %S" name correct-name)
                (plist-put tc :name correct-name))))
           ;; Case 2: not in info :tools but IS registered globally —
           ;; preset misconfiguration recovery (e.g. RunAgent missing from
           ;; buffer's gptel-tools due to load order issue at buffer creation).
           ((and (stringp name)
                 (fboundp 'gptel-get-tool)
                 (ignore-errors (gptel-get-tool name)))
            (let* ((global-tool (ignore-errors (gptel-get-tool name)))
                   (new-tools (append tools (list global-tool))))
              (message "gptel: recovering tool call %S not in FSM tools \
(preset misconfiguration); injecting from global registry" name)
              ;; Inject the tool into info :tools so gptel--handle-tool-use
              ;; can find it with its own cl-find-if lookup.
              ;; plist-put returns new list if :tools key is absent; store
              ;; it back into the FSM info to be sure.
              (setq info (plist-put info :tools new-tools))
              (setf (gptel-fsm-info fsm) info)
              ;; Update our local tools reference for subsequent loop iterations.
              (setq tools new-tools)))
           ;; Case 3: genuinely unknown / nil tool name — prune it
           (t
            (when (not (plist-get tc :result))
              (message "gptel: skipping malformed tool call \
(name=%S, known-tools=%S)"
                       name
                       (and (boundp 'gptel--known-tools)
                            (mapcar #'car gptel--known-tools)))
              (plist-put tc :result
                         (format "Error: unknown or nil tool %S called by model" name))
              (push tc pruned))))))
      ;; Prune offending entries so gptel--parse-tool-results never sees them.
      ;; This prevents orphaned tool role messages (tool_call_id=null) that
      ;; cause 400 errors when the assistant message has no matching tool_calls.
      (when pruned
        (plist-put info :tool-use
                   (cl-remove-if #'my/gptel--nil-tool-call-p
                                 tool-use))
        ;; Fix A: if all tool calls were malformed and :tool-use is now empty,
        ;; gptel--handle-tool-use's when-let* will short-circuit on (ntools 0)
        ;; and never call gptel--fsm-transition, leaving the FSM stuck in TOOL
        ;; state forever.  Force it to DONE so the turn ends cleanly.
        (when (= 0 (length (plist-get info :tool-use)))
          (message "gptel: all tool calls were malformed, advancing FSM to DONE")
          (when gptel-mode (gptel--update-status " Ready" 'success))
          (funcall (plist-get info :callback)
                   "gptel: turn skipped (all tool calls had nil/unknown names)" info)
          (gptel--fsm-transition fsm 'DONE))))))

;; --- Doom-loop detection (Fix C) ---
;; Mirrors OpenCode's doom_loop permission: if the same tool is called with the
;; same arguments 3 consecutive times, the agent is stuck.  We abort the turn
;; rather than ask (no interactive permission system in gptel), but the
;; threshold and fingerprint logic are taken directly from OpenCode's
;; packages/opencode/src/session/processor.ts (DOOM_LOOP_THRESHOLD = 3).

(defcustom my/gptel-doom-loop-threshold 3
  "Number of consecutive identical tool calls that trigger doom-loop abort.
Mirrors OpenCode's DOOM_LOOP_THRESHOLD.  Only calls with the same tool name
AND the same arguments count; different tools or different args do not."
  :type 'integer
  :group 'gptel)

(defun my/gptel--tool-call-fingerprint (tc)
  "Return a fingerprint string for tool call TC.
The fingerprint is \"NAME:MD5(ARGS)\" so two calls are considered identical
only when both the tool name and the serialized argument plist match."
  (let* ((name (or (plist-get tc :name) "nil"))
         (args (plist-get tc :args))
         (args-str (if args (format "%S" args) "nil")))
    (concat name ":" (md5 args-str))))

(cl-defun my/gptel--detect-doom-loop (fsm)
  "Abort FSM when the same tool call repeats `my/gptel-doom-loop-threshold' times.

Checks the fingerprint of each tool call in the current :tool-use list against
the rolling history stored in :doom-loop-fingerprints.  When the last N
fingerprints are identical, the turn is forcibly advanced to DONE.

This mirrors OpenCode's doom_loop detection (same tool + same args × N)."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
              (tool-use (plist-get info :tool-use)))
    ;; Append fingerprints for this cycle's tool calls.
    (let* ((fps (or (plist-get info :doom-loop-fingerprints) '()))
           (new-fps (mapcar #'my/gptel--tool-call-fingerprint tool-use))
           (fps (append fps new-fps)))
      (plist-put info :doom-loop-fingerprints fps)
      ;; Check whether every tool call in this cycle is a doom-loop repeat.
      (dolist (fp new-fps)
        (let* ((n my/gptel-doom-loop-threshold)
               ;; Count consecutive trailing occurrences of this fingerprint.
               (tail (reverse fps))
               (run (length (seq-take-while (lambda (f) (equal f fp)) tail))))
          (when (>= run n)
            (message "gptel: doom-loop detected — \"%s\" called %d times with identical args, aborting turn"
                     (car (split-string fp ":")) run)
            (funcall (plist-get info :callback)
                     (format "gptel: doom-loop aborted — tool \"%s\" called %d consecutive times \
with identical arguments.  Try a different approach or break the task into smaller steps."
                             (car (split-string fp ":")) run)
                     info)
            (gptel--fsm-transition fsm 'DONE)
            ;; Return immediately — transition already fired.
            (cl-return-from my/gptel--detect-doom-loop)))))))

;; --- Duplicate Tool Name Guard ---
;; gptel--parse-tools maps gptel-tools directly to JSON without deduplication.
;; When gptel-tools contains two structs with the same tool name (e.g. after a
;; config reload where both safe-get-tool and gptel-make-tool resolve the same
;; name), the API receives duplicate function entries and returns 400.
;; Guard against this at serialization time by deduplicating by name.
(defun my/gptel--dedup-tools-before-parse (orig backend tools)
  "Around-advice on `gptel--parse-tools': remove duplicate tool names before parsing.
Uses last-wins so the most recently registered struct takes precedence."
  (funcall orig backend
           (let ((seen (make-hash-table :test #'equal)))
             (nreverse
              (cl-loop for tool in (nreverse (copy-sequence tools))
                       for name = (ignore-errors (gptel-tool-name tool))
                       when (and name (not (gethash name seen)))
                       do (puthash name t seen)
                       and collect tool)))))

;; --- Advice Registration ---
;; Each function registers its own advice in the module that defines it.
(with-eval-after-load 'gptel-request
  ;; Tool-call guards
  (advice-add 'gptel--handle-tool-use :before #'my/gptel--sanitize-tool-calls)
  (advice-add 'gptel--handle-tool-use :before #'my/gptel--detect-doom-loop)
  ;; Dedup tools before serialization
  (advice-add 'gptel--parse-tools     :around #'my/gptel--dedup-tools-before-parse))

(provide 'gptel-ext-tool-sanitize)
;;; gptel-ext-tool-sanitize.el ends here
