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

(defun my/gptel--normalize-tool-list (tools)
  "Return TOOLS as a list of bare `gptel-tool' structs."
  (delq nil (mapcar #'my/gptel--tool-spec tools)))

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
        (cl-find-if (lambda (ts) (string= (gptel-tool-name ts) candidate)) tool-specs)
        ;; 2. Case-insensitive match
        (cl-find-if (lambda (ts) (string-equal-ignore-case (gptel-tool-name ts) candidate))
                    tool-specs)
        ;; 3. Normalized match (ignore underscores/hyphens)
        (when (and my/gptel-tool-repair-enabled normalized)
          (cl-find-if
           (lambda (ts)
             (string= normalized
                      (my/gptel--normalize-tool-name (gptel-tool-name ts))))
           tool-specs)))))))

;; Handle nil/unknown tool calls gracefully instead of hanging the FSM.
;; When a model sends a tool call with a nil or unrecognized name, gptel's
;; `gptel--handle-tool-use' logs a message but doesn't advance the tool
;; counter, causing the FSM to hang forever.  This advice pre-marks any
;; malformed tool calls with an error result so they're skipped.
(defun my/gptel--nil-tool-call-p (tc)
  "Return non-nil when TC is a nil/null/empty-named tool call spec."
  (when (listp tc)
    (let ((name (plist-get tc :name)))
      (or (null name) (eq name :null) (equal name "null") (equal name "")))))

(defun my/gptel--repair-tool-call (tc correct-name)
  "Repair tool call TC to use CORRECT-NAME.
Messages the repair and updates the :name property in place."
  (when (and (listp tc) (stringp correct-name) (> (length correct-name) 0))
    (let ((current-name (plist-get tc :name)))
      (when (and (stringp current-name) (not (string= current-name correct-name)))
        (message "gptel: repairing tool call %S -> %S" current-name correct-name)
        (plist-put tc :name correct-name)))))

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
        (let* ((name (plist-get tc :name))
               (matched-tool (and (stringp name)
                                  (my/gptel--find-tool-fuzzy name tools))))
          (cond
           (matched-tool
            (my/gptel--repair-tool-call tc (gptel-tool-name matched-tool)))
           ((and (stringp name)
                 (fboundp 'gptel-get-tool)
                 (or (ignore-errors (gptel-get-tool name))
                     (when my/gptel-tool-repair-enabled
                       (my/gptel--find-tool-fuzzy name all-tools))))
            (let* ((global-tool (or (ignore-errors (gptel-get-tool name))
                                    (my/gptel--find-tool-fuzzy name all-tools)))
                   (correct-name (gptel-tool-name global-tool))
                   (new-tools (append tools (list global-tool))))
              (my/gptel--repair-tool-call tc correct-name)
              (message "gptel: recovering tool call %S not in FSM tools \
(preset misconfiguration); injecting from global registry" name)
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
              (push tc pruned))))))
      (when pruned
        (plist-put info :tool-use
                   (cl-remove-if (lambda (tc) (memq tc pruned))
                                 tool-use))
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

(defcustom my/gptel-inspection-thrash-threshold 25
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

(defcustom my/gptel-inspection-thrash-max-extra 25
  "Maximum extra same-file inspection-thrash steps granted to large files."
  :type 'integer
  :group 'gptel)

(defconst my/gptel--inspection-tools
  '("Code_Inspect" "Code_Map" "Code_Usages" "Read" "Grep")
  "Read-only tools that contribute to same-file inspection thrash.")

(defconst my/gptel--write-tools
  '("ApplyPatch" "Edit" "Insert" "Mkdir" "Move" "Write")
  "Tools that reset inspection-thrash tracking because they can change files.")

(defun my/gptel--tool-call-fingerprint (tc)
  "Return a fingerprint string for tool call TC.
The fingerprint is \"NAME:MD5(ARGS)\" so two calls are considered identical
only when both the tool name and the serialized argument plist match."
  (when (listp tc)
    (let* ((raw-name (plist-get tc :name))
           (name (if (and raw-name (not (equal raw-name ""))) raw-name "nil"))
           (args (plist-get tc :args))
           (args-str (if args (format "%S" args) "nil")))
       (concat name ":" (md5 args-str)))))

(defun my/gptel--inspection-tool-target (tc)
  "Return the inspected file path for tool call TC, or nil when unavailable."
  (when (listp tc)
    (let ((name (plist-get tc :name))
          (args (plist-get tc :args)))
      (when (member name my/gptel--inspection-tools)
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
                 (run-counts (or (plist-get info :doom-loop-run-counts) nil))
                 (new-fps (mapcar #'my/gptel--tool-call-fingerprint tool-use))
                 (n my/gptel-doom-loop-threshold)
                 prev-fp)
            (setq info (plist-put info :doom-loop-fingerprints (append fps new-fps)))
            (dolist (fp new-fps run-counts)
              (let* ((prev-run (or (alist-get fp run-counts nil nil #'string=) 0))
                     (current-run (if (and prev-fp (equal prev-fp fp))
                                      (1+ prev-run)
                                    1)))
                (setq run-counts (cons (cons fp current-run) run-counts))))
            (setq info (plist-put info :doom-loop-run-counts run-counts))
            (setf (gptel-fsm-info fsm) info)
            (when-let* ((worst (cl-loop for (fp . count) in run-counts
                                        maximize count into max-count
                                        finally return (when (>= max-count n)
                                                         (cons (caar run-counts) max-count))))
                        (aborting-fp (car worst))
                        (run-count (cdr worst))
                        (tool-name (car (split-string aborting-fp ":" t)))
                        (error-message
                         (format "gptel: doom-loop aborted — tool \"%s\" called %d consecutive times \
 with identical arguments.  Try a different approach or break the task into smaller steps."
                                 tool-name run-count)))
              (message "gptel: doom-loop detected — \"%s\" called %d times with identical args, aborting turn"
                       tool-name run-count)
              (setq info (my/gptel--abort-sanitized-turn fsm info error-message))
              (funcall (plist-get info :callback) error-message info)
              (gptel--fsm-transition fsm 'DONE)
              (cl-return-from my/gptel--detect-doom-loop))))))))

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
             ((member name my/gptel--write-tools)
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
               (let ((threshold (my/gptel--inspection-thrash-threshold-for-file file)))
                 (when (>= current-run threshold)
                 (let ((abbrev-file (abbreviate-file-name file)))
                   (let ((error-message
                          (format "gptel: inspection-thrash aborted — %d consecutive read-only inspections on %s without a write-capable tool. Try editing sooner or narrow the task."
                                  current-run abbrev-file)))
                     (message "gptel: inspection-thrash detected — %d read-only inspections on %s without a write, aborting turn"
                              current-run abbrev-file)
                     (setq info (my/gptel--abort-sanitized-turn fsm info error-message))
                     (funcall (plist-get info :callback) error-message info))
                   (gptel--fsm-transition fsm 'DONE)
                   (cl-return-from my/gptel--detect-inspection-thrash))))
               (setf (gptel-fsm-info fsm)
                     (plist-put info :inspection-thrash-state
                                (list :file current-file :count current-run))))
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
                 (let ((name (ignore-errors (gptel-tool-name tool))))
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
  ;; Dedup tools before serialization
  (advice-add 'gptel--parse-tools     :around #'my/gptel--dedup-tools-before-parse))

(provide 'gptel-ext-tool-sanitize)
;;; gptel-ext-tool-sanitize.el ends here
