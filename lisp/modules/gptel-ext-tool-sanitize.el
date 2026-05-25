;;; gptel-ext-tool-sanitize.el --- Tool call sanitization and doom-loop detection -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Sanitize malformed tool calls, detect doom-loops, and deduplicate tools.
;;
;; - nil/unknown tool calls: pre-mark with error result so FSM doesn't hang
;; - Doom-loop detection: abort when same tool+args repeats N times (OpenCode-style)
;; - Tool dedup: remove duplicate tool names before API serialization
;; - Tool repair: fix case, underscore/hyphen, and common typos (OpenCode-style)

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'gptel)
(require 'nucleus-tools)
(require 'md5)

(defcustom my/gptel-tool-repair-enabled t
  "When non-nil, attempt to repair malformed tool names.
Repairs: case (read -> Read), underscores (code-map -> Code_Map)."
  :type 'boolean
  :group 'gptel)

(defun my/gptel--normalize-tool-name (name)
  "Normalize tool NAME for fuzzy matching.
Removes underscores, hyphens, and converts to lowercase."
  (when (stringp name)
    (downcase (replace-regexp-in-string "[-_]" "" name))))

(defun my/gptel--tool-spec (tool)
  "Return TOOL as a bare `gptel-tool' struct when possible.
Accepts already-normalized tool structs and registry entries of the form
\(NAME . TOOL)."
  (cond
   ((and (fboundp 'gptel-tool-p) (gptel-tool-p tool))
    tool)
   ((and (consp tool)
         (fboundp 'gptel-tool-p)
         (gptel-tool-p (cdr tool)))
    (cdr tool))
   (t nil)))

(defun my/gptel--tool-name-from-spec (ts &optional log-errors tool)
  "Extract tool name from TS, returning nil on error.
When LOG-ERRORS is non-nil and an error occurs, log a message using TOOL.
Avoids code duplication in functions that extract tool names."
  (when (and (fboundp 'gptel-tool-p)
             (gptel-tool-p ts))
    (condition-case err
        (gptel-tool-name ts)
      (error
       (when log-errors
         (message "gptel: tool-name extraction failed for %S: %s"
                  tool (error-message-string err)))
       nil))))

(defun my/gptel--normalize-tool-list (tools)
  "Return TOOLS as a list of bare `gptel-tool' structs."
  (delq nil (mapcar #'my/gptel--tool-spec tools)))

(defun my/gptel--find-tool-by-name (tools name &optional comparison-fn)
  "Find tool in TOOLS whose name matches NAME using COMPARISON-FN.
COMPARISON-FN should accept two strings and return non-nil if they match.
Defaults to `string='."
  (cl-find-if (lambda (ts)
                (let ((tool-name (my/gptel--tool-name-from-spec ts)))
                  (and tool-name
                       (funcall (or comparison-fn #'string=)
                                tool-name name))))
              tools))

(defun my/gptel--tool-name-candidates (name)
  "Return fuzzy-match candidates extracted from tool NAME.
This keeps the original NAME first, then any token-like substrings so
malformed parser output such as embedded XML can still recover the
underlying tool name."
  (when (stringp name)
    (let* ((tokens (split-string name "[^[:alnum:]_-]+" t))
           (candidates (cons name tokens)))
      (delete-dups (seq-filter (lambda (candidate)
                                 (> (length candidate) 0))
                               candidates)))))

(defun my/gptel--find-tool-fuzzy (name tools)
  "Find tool in TOOLS matching NAME using fuzzy matching.
Tries: exact, case-insensitive, underscore/hyphen normalization."
  (when (stringp name)
    (let ((tool-specs (my/gptel--normalize-tool-list tools)))
      (cl-loop
       for candidate in (my/gptel--tool-name-candidates name)
       for normalized = (my/gptel--normalize-tool-name candidate)
       thereis
       (or
        ;; 1. Exact match
        (my/gptel--find-tool-by-name tool-specs candidate)
        ;; 2. Case-insensitive match
        (my/gptel--find-tool-by-name tool-specs candidate #'string-equal-ignore-case)
        ;; 3. Normalized match (ignore underscores/hyphens)
        (when (and my/gptel-tool-repair-enabled normalized)
          (cl-find-if
           (lambda (ts)
             (let ((tool-name (my/gptel--tool-name-from-spec ts)))
               (and tool-name
                    (string= normalized
                             (my/gptel--normalize-tool-name tool-name)))))
           tool-specs)))))))

;; Handle nil/unknown tool calls gracefully instead of hanging the FSM.
;; When a model sends a tool call with a nil or unrecognized name, gptel's
;; `gptel--handle-tool-use' logs a message but doesn't advance the tool
;; counter, causing the FSM to hang forever.  This advice pre-marks any
;; malformed tool calls with an error result so they're skipped.
(defun my/gptel--nil-tool-call-p (tc)
  "Return non-nil when TC is a nil/null/empty-named tool call spec."
  (when (and (proper-list-p tc)
             (plist-member tc :name))
    (let ((name (plist-get tc :name))
          (args (plist-get tc :args)))
      (or (null name) (eq name :null) (equal name "null") (equal name "")
          (not (proper-list-p args))))))

(defun my/gptel--repair-tool-call (tc correct-name)
  "Repair tool call TC to use CORRECT-NAME.
Messages the repair and updates the :name property in place."
  (when (and (proper-list-p tc) (stringp correct-name) (> (length correct-name) 0))
    (let ((current-name (plist-get tc :name)))
      (when (and (stringp current-name) (not (string= current-name correct-name)))
        (message "gptel: repairing tool call %S -> %S" current-name correct-name)
        (plist-put tc :name correct-name)))))

(defun my/gptel--tool-dispatch-error-message (err)
  "Return a tool-result string for dispatch error ERR.
Uses `error-message-string' when ERR is a proper list, otherwise
returns a generic error description."
  (condition-case nil
      (if (proper-list-p err)
          (format "Error: %s" (error-message-string err))
        (format "Error: malformed error %S" err))
    (error
     (format "Error: %S" err))))

(defun my/gptel--complete-tool-dispatch-error (fsm err)
  "Record ERR as the current unresolved tool result for FSM.
Return non-nil when the error was converted into a tool result."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
              (tool-use (plist-get info :tool-use))
              (tool-call (cl-find-if-not (lambda (tc) (and (listp tc) (plist-get tc :result)))
                                         tool-use)))
    (let* ((name (plist-get tool-call :name))
           (tools (my/gptel--normalize-tool-list (plist-get info :tools)))
           (tool-spec (and (stringp name)
                           (my/gptel--find-tool-by-name tools name #'equal)))
           (message-text (my/gptel--tool-dispatch-error-message err)))
      (message "gptel: tool dispatch error for %s: %s"
               (or name "<unknown>") message-text)
      (if (fboundp 'gptel--process-tool-call)
          (gptel--process-tool-call fsm tool-spec tool-call message-text)
        (plist-put tool-call :result message-text))
      t)))

(defun my/gptel--handle-tool-use-with-error-result (orig fsm)
  "Run ORIG for FSM, turning dispatch errors into tool results.
This protects async tool dispatch, where gptel does not wrap the initial
`apply' in `condition-case'."
  (condition-case err
      (funcall orig fsm)
    (error
     (unless (my/gptel--complete-tool-dispatch-error fsm err)
       (let* ((err-is-proper (and (consp err) (symbolp (car err)) (listp (cdr err))))
              (err-sym (and err-is-proper (car err)))
              (err-data (and err-is-proper (cdr err))))
         (if err-sym
             (signal err-sym (if (proper-list-p err-data) err-data nil))
           (signal 'error (list "unhandled dispatch error"))))))))

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
    (let* ((tools (my/gptel--normalize-tool-list (plist-get info :tools)))
           (all-tools (when (boundp 'gptel--known-tools)
                        (cl-loop for (_ . entries) in gptel--known-tools
                                 append (my/gptel--normalize-tool-list entries))))
           pruned)
      (unless (equal tools (plist-get info :tools))
        (setq info (plist-put info :tools tools))
        (setf (gptel-fsm-info fsm) info))
      (dolist (tc tool-use)
        (when (proper-list-p tc)
          (let* ((name (plist-get tc :name))
               (matched-tool (and (stringp name)
                                  (my/gptel--find-tool-fuzzy name tools)))
               (direct-tool (and (stringp name)
                                 (fboundp 'gptel-get-tool)
                                 (ignore-errors (gptel-get-tool name))))
               (fuzzy-match (and (stringp name) my/gptel-tool-repair-enabled
                                 (my/gptel--find-tool-fuzzy name all-tools))))
          (cond
           (matched-tool
            (my/gptel--repair-tool-call tc (gptel-tool-name matched-tool)))
            ((or direct-tool fuzzy-match)
             (let* ((global-tool (or direct-tool fuzzy-match))
                    (correct-name (gptel-tool-name global-tool))
                    (new-tools (append tools (list global-tool))))
               (my/gptel--repair-tool-call tc correct-name)
               ;; Log only the first time a tool is injected (avoid noise
               ;; from repeated injections of the same tool in a session).
               (unless (my/gptel--find-tool-by-name tools correct-name)
                 (message "gptel: recovered tool %S (preset misconfiguration)" name))
               (setq info (plist-put info :tools new-tools))
               (setf (gptel-fsm-info fsm) info)
               (setq tools new-tools)))
           (t
            (when (not (plist-get tc :result))
              (message "gptel: skipping malformed tool call \
(name=%S, available-tools=%S)"
                       name
                       (mapcar (lambda (ts) (or (ignore-errors (gptel-tool-name ts)) "<unknown>")) tools))
              (plist-put tc :result
                         (format "Error: unknown or nil tool %S called by model" name))
              (push tc pruned)))))))
      (when pruned
        (setq info (plist-put info :tool-use
                              (cl-remove-if (lambda (tc) (memq tc pruned))
                                            tool-use)))
        (setf (gptel-fsm-info fsm) info)
        (when (null (plist-get info :tool-use))
          (message "gptel: all tool calls were malformed, advancing FSM to DONE")
          (when gptel-mode (gptel--update-status " Ready" 'success))
           (when-let ((cb (plist-get info :callback)))
             (funcall cb
                      "gptel: turn skipped (all tool calls had nil/unknown names)" info))
          (gptel--fsm-transition fsm 'DONE))))))

;; --- Doom-loop detection (Fix C) ---
;; Mirrors OpenCode's doom_loop permission: if the same tool is called with the
;; same arguments 3 consecutive times, the agent is stuck.  We abort the turn
;; rather than ask (no interactive permission system in gptel), but the
;; threshold and fingerprint logic are taken directly from OpenCode's
;; packages/opencode/src/session/processor.ts (DOOM_LOOP_THRESHOLD = 3).

(defcustom my/gptel-doom-loop-threshold 5
  "Number of consecutive identical tool calls that trigger doom-loop abort.
Mirrors OpenCode's DOOM_LOOP_THRESHOLD.  Only calls with the same tool name
AND the same arguments count; different tools or different args do not.
Raised from 3 to 5 because TodoWrite (progress tracking) and other
planning tools can legitimately repeat 3-4 times as the model iterates
on different approaches to the same task."
  :type 'integer
  :group 'gptel)

(defcustom my/gptel-inspection-thrash-threshold 40
  "Number of same-file read-only inspections allowed before aborting a turn.
This catches agents that keep exploring one file with `Code_Inspect', `Read',
or `Grep' but never switch to a write-capable tool."
  :type 'integer
  :group 'gptel)

(defcustom my/gptel-inspection-thrash-bytes-per-extra-step 8192
  "Bytes of readable file size that earn one extra inspection-thrash step.
Larger files need a bit more exploration headroom before a same-file read-only
streak should be treated as a stuck turn."
  :type 'integer
  :group 'gptel)

(defcustom my/gptel-inspection-thrash-max-extra 40
  "Maximum extra same-file inspection-thrash steps granted to large files."
  :type 'integer
  :group 'gptel)

(defsubst my/gptel--inspection-tools ()
  "Read-only tools that contribute to same-file inspection thrash.
Derived from nucleus-tool-markers :file-inspector."
  (nucleus-tools-with-marker :file-inspector))

(defsubst my/gptel--write-tools ()
  "Tools that reset inspection-thrash tracking because they can change files.
Derived from nucleus-tool-markers :can-edit."
  (nucleus-tools-with-marker :can-edit))

(defun my/gptel--safe-serialize-args (args)
  "Return a safe string representation of ARGS for fingerprinting.
Handles edge cases: circular references, objects without printers,
and other conditions that cause `format' to signal errors."
  (if args
      (or (ignore-errors (format "%S" args))
          "unserializable")
    "nil"))

(defun my/gptel--tool-call-fingerprint (tc)
  "Return a fingerprint string for tool call TC.
The fingerprint is \"NAME:MD5(ARGS)\" so two calls are considered identical
only when both the tool name and the serialized argument plist match.
When args cannot be serialized, uses a hash of the args format to ensure
each unserializable call gets a unique fingerprint."
  (when (proper-list-p tc)
    (let* ((raw-name (plist-get tc :name))
           (name (if (and raw-name (not (equal raw-name ""))) raw-name "nil"))
           (args (plist-get tc :args))
           (args-str (my/gptel--safe-serialize-args args))
           (args-hash (if (string= args-str "unserializable")
                          (or (ignore-errors (md5 (format "%S" args)))
                              (md5 "unserializable"))
                        (md5 args-str))))
      (concat name ":" args-hash))))

(defun my/gptel--inspection-tool-target (tc)
  "Return the inspected file path for tool call TC, or nil when unavailable."
  (when (proper-list-p tc)
    (let ((name (plist-get tc :name))
          (args (plist-get tc :args)))
      (when (and (member name (my/gptel--inspection-tools))
                 (proper-list-p args))
        (or (plist-get args :file_path)
            (plist-get args :path))))))

(defun my/gptel--inspection-thrash-threshold-for-file (file)
  "Return the same-file inspection-thrash threshold for FILE."
  (let* ((attrs (and (stringp file)
                     (file-readable-p file)
                     (not (file-directory-p file))
                     (ignore-errors (file-attributes file 'string))))
         (size (and attrs (file-attribute-size attrs)))
         (extra (if (and (integerp size) (> size 0))
                    (min my/gptel-inspection-thrash-max-extra
                         (/ size my/gptel-inspection-thrash-bytes-per-extra-step))
                  0)))
    (+ my/gptel-inspection-thrash-threshold extra)))

(defun my/gptel--abort-sanitized-turn (fsm info error-message)
  "Abort the live request behind FSM/INFO and stamp ERROR-MESSAGE on the FSM."
  (let ((updated-info (plist-put (plist-put info :error error-message)
                                 :stop-reason 'STOP)))
    (setf (gptel-fsm-info fsm) updated-info)
    (when-let* ((buffer (plist-get updated-info :buffer)))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (cond
           ((fboundp 'my/gptel-abort-here)
            (ignore-errors (my/gptel-abort-here)))
           ((fboundp 'gptel-abort)
            (ignore-errors (gptel-abort buffer)))))))
    updated-info))

(cl-defun my/gptel--detect-doom-loop (fsm)
  "Abort FSM when the same tool call repeats `my/gptel-doom-loop-threshold' times.

Checks the fingerprint of each tool call in the current :tool-use list against
the rolling history stored in :doom-loop-fingerprints.  When the last N
fingerprints are identical, the turn is forcibly advanced to DONE.

This mirrors OpenCode's doom_loop detection (same tool + same args × N)."
  (cl-block my/gptel--detect-doom-loop
    (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm))))
      (let ((tool-use (plist-get info :tool-use)))
        (when tool-use
          (let* ((fps (or (plist-get info :doom-loop-fingerprints) '()))
                 (run-counts (or (plist-get info :doom-loop-run-counts) '()))
                 (new-fps (mapcar #'my/gptel--tool-call-fingerprint tool-use))
                 (n my/gptel-doom-loop-threshold)
                 (fps-end (and (proper-list-p fps) (last fps)))
                 (prev-fp (car fps-end))
                 (aborted nil))
            (setq info (plist-put info :doom-loop-fingerprints (append fps new-fps)))
            (dolist (fp new-fps)
              (when fp
                (let* ((existing-count (alist-get fp run-counts nil nil #'string=))
                       (current-run
                        (if (and prev-fp (equal prev-fp fp))
                            (1+ (or existing-count 0))
                          1)))
                  (setf (alist-get fp run-counts nil t #'string=) current-run)
                  (when (>= current-run n)
                    (let ((error-message
                           (format "gptel: doom-loop aborted — tool \"%s\" called %d consecutive times \
 with identical arguments.  Try a different approach or break the task into smaller steps."
                                   (car (split-string fp ":" t)) current-run)))
                      (message "gptel: doom-loop detected — \"%s\" called %d times with identical args, aborting turn"
                               (car (split-string fp ":" t)) current-run)
                       (setq info (plist-put info :doom-loop-run-counts run-counts))
                       (setq info (my/gptel--abort-sanitized-turn fsm info error-message))
                       (when-let ((cb (plist-get info :callback)))
                         (funcall cb error-message info)))
                    (setq aborted t)
                    (gptel--fsm-transition fsm 'DONE)
                    (cl-return-from my/gptel--detect-doom-loop))
                  (setq prev-fp fp))))
            (unless aborted
              (setq info (plist-put info :doom-loop-run-counts run-counts))
              (setf (gptel-fsm-info fsm) info))))))))

(cl-defun my/gptel--detect-inspection-thrash (fsm)
  "Abort FSM when it stays in same-file read-only inspection for too long.

Unlike `my/gptel--detect-doom-loop', this catches varied `Code_Inspect',
`Read', or `Grep' calls that keep walking the same file without ever switching
to a write-capable tool."
  (cl-block my/gptel--detect-inspection-thrash
    (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
                (tool-use (plist-get info :tool-use)))
      (let* ((state (plist-get info :inspection-thrash-state))
              (current-file (plist-get state :file))
              (current-run (or (plist-get state :count) 0)))
        (dolist (tc tool-use)
          (let* ((name (plist-get tc :name))
                  (file (my/gptel--inspection-tool-target tc)))
            (cond
             ((member name (my/gptel--write-tools))
              (setq current-file nil
                    current-run 0)
              (setf (gptel-fsm-info fsm)
                    (plist-put info :inspection-thrash-state
                               (list :file current-file :count current-run))))
             (file
               (setq current-run (if (equal current-file file)
                                     (1+ current-run)
                                   1)
                     current-file file)
                (let* ((threshold (my/gptel--inspection-thrash-threshold-for-file file))
                       (abbrev-file (abbreviate-file-name file))
                       (warning-level
                        (cond
                         ((>= current-run threshold) :abort)
                         ((>= current-run (* threshold 0.75)) :urgent)
                         ((>= current-run (* threshold 0.5)) :warn)
                         (t nil))))
                  (cond
                   ((eq warning-level :abort)
                    (let ((error-message
                           (format "gptel: inspection-thrash aborted — %d consecutive read-only inspections on %s without a write-capable tool. Try editing sooner or narrow the task."
                                   current-run abbrev-file)))
                      (message "gptel: inspection-thrash detected — %d read-only inspections on %s without a write, aborting turn"
                               current-run abbrev-file)
                       (setq info (my/gptel--abort-sanitized-turn fsm info error-message))
                       (when-let ((cb (plist-get info :callback)))
                         (funcall cb error-message info)))
                    (gptel--fsm-transition fsm 'DONE)
                    (cl-return-from my/gptel--detect-inspection-thrash))
                   ((eq warning-level :urgent)
                    (message "gptel: inspection-thrash WARNING — %d/%d read-only inspections on %s. WRITE TO THE FILE NOW or this turn will be aborted."
                             current-run threshold abbrev-file))
                   ((eq warning-level :warn)
                    (message "gptel: inspection-thrash caution — %d/%d read-only inspections on %s. Consider writing to the file soon."
                             current-run threshold abbrev-file)))
                  (setf (gptel-fsm-info fsm)
                        (plist-put info :inspection-thrash-state
                                   (list :file current-file :count current-run)))))
             (t
             (setq current-file nil
                   current-run 0)
              (setf (gptel-fsm-info fsm)
                    (plist-put info :inspection-thrash-state
                               (list :file current-file :count current-run)))))))))))

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
           (if (null tools)
               tools
             (let ((seen (make-hash-table :test #'equal)))
               ;; Iterate reversed to capture last occurrence of each name.
               (dolist (tool (nreverse tools))
                 (let ((name (my/gptel--tool-name-from-spec tool 'log-errors tool)))
                   (when name (puthash name tool seen))))
               ;; Return values in original order (first occurrence wins).
               (nreverse (hash-table-values seen))))))

;; --- Advice Registration ---
;; Each function registers its own advice in the module that defines it.
(with-eval-after-load 'gptel-request
  ;; Tool-call guards
  (advice-add 'gptel--handle-tool-use :before #'my/gptel--sanitize-tool-calls)
  (advice-add 'gptel--handle-tool-use :before #'my/gptel--detect-doom-loop)
  (advice-add 'gptel--handle-tool-use :before #'my/gptel--detect-inspection-thrash)
  (advice-add 'gptel--handle-tool-use :around #'my/gptel--handle-tool-use-with-error-result)
  ;; Dedup tools before serialization
  (advice-add 'gptel--parse-tools     :around #'my/gptel--dedup-tools-before-parse))

(provide 'gptel-ext-tool-sanitize)
;;; gptel-ext-tool-sanitize.el ends here
