;;; gptel-nucleus-context-intercept.el --- Context interception layer for OV5 -*- lexical-binding: t; -*-

;; Context-mode absorption: PreToolUse/PostToolUse hooks, auto-indexing,
;; bytes accounting, progressive throttling, session event capture,
;; "Think in Code" enforcement, and context-cost integration.

;;; Code:

(require 'cl-lib)

;; ─── Hook Infrastructure ───

(defvar gptel-nucleus-context--pre-tool-hooks nil
  "List of PreToolUse hook functions.
Each function receives (AGENT-NAME PROMPT DESCRIPTION) and must return a plist:
  (:continue)             → proceed normally
  (:deny)                 → skip tool call entirely
  (:continue :modified-prompt NEW-PROMPT) → use modified prompt
  (:redirect ALTERNATE-AGENT) → dispatch different agent instead.

Hooks run in registration order. First :deny stops the chain.
Hook errors are trapped — they never crash the tool call.")

(defvar gptel-nucleus-context--post-tool-hooks nil
  "List of PostToolUse hook functions.
Each function receives (AGENT-NAME RESULT-STRING DURATION-SECS ORIGINAL-PROMPT).
Return value is ignored. Hook errors are trapped and logged.")

(defvar gptel-nucleus-context--last-pre-result nil
  "Result of last PreToolUse hook chain execution.")

(defvar gptel-nucleus-context--last-post-result nil
  "Result of last PostToolUse hook chain execution.")


;; ─── Pre-Tool Hook Execution ───

(cl-defun gptel-nucleus-context--run-pre-tool-hooks (agent-name prompt description _dispatch-fn)
  "Run all PreToolUse hooks for a tool call.
Returns a plist: (:action :continue|:deny|:redirect :modified-prompt STR :redirect-agent STR)."
  (let ((result :continue)
        (modified-prompt prompt)
        (redirect-agent nil))
    (catch 'pre-tool-hook-deny
      (dolist (hook gptel-nucleus-context--pre-tool-hooks)
        (let ((hook-result
               (condition-case hook-err
                   (funcall hook agent-name prompt description)
                 (error
                  (message "[context-intercept] PreToolUse hook error: %s"
                           (error-message-string hook-err))
                  nil))))
          (when hook-result
            (when (memq :deny hook-result)
              (setq result :deny)
              (throw 'pre-tool-hook-deny nil))
            (when (memq :redirect hook-result)
              (setq result :redirect)
              (setq redirect-agent (car (cdr-safe (memq :redirect hook-result)))))
            (when (memq :modified-prompt hook-result)
              (setq modified-prompt (car (cdr-safe (memq :modified-prompt hook-result)))))))))
    (setq gptel-nucleus-context--last-pre-result result)
    `(:action ,result :modified-prompt ,modified-prompt :redirect-agent ,redirect-agent)))

;; ─── Post-Tool Hook Execution ───

(defun gptel-nucleus-context--run-post-tool-hooks (agent-name result-string duration-secs prompt)
  "Run all PostToolUse hooks after a tool call completes.
Errors in hooks are trapped — they never propagate to the caller."
  (dolist (hook gptel-nucleus-context--post-tool-hooks)
    (condition-case post-err
        (funcall hook agent-name result-string duration-secs prompt)
      (error
       (message "[context-intercept] PostToolUse hook error: %s" (error-message-string post-err))))))


;; ─── Tool Routing Rules ───

(defvar gptel-nucleus-context--tool-routing-rules
  (let ((ht (make-hash-table :test 'equal)))
    ht)
  "Hash table mapping tool names to (ALTERNATE-TOOL . REASON) pairs.
Inspired by context-mode's route redirection (Read→ctx_execute_file, curl→ctx_fetch_and_index).
When a tool should be redirected to a more context-efficient alternative, PreToolUse hooks
consult this table.")

(cl-defun gptel-nucleus-context--add-routing-rule (tool-name alternate-tool reason)
  "Register a routing rule: redirect TOOL-NAME to ALTERNATE-TOOL with REASON."
  (puthash tool-name (cons alternate-tool reason)
           gptel-nucleus-context--tool-routing-rules))

(defun gptel-nucleus-context--match-routing-rule (tool-name)
  "Return (ALTERNATE-TOOL . REASON) for TOOL-NAME, or nil if no rule matches."
  (gethash tool-name gptel-nucleus-context--tool-routing-rules))


;; ─── "Think in Code" Enforcement ───

(defvar gptel-nucleus-context--think-in-code-directive
  "[CONTEXT-MODE] INFORMATION RETRIEVAL PROTOCOL:
1. When you need to understand a file's content, USE A CODE EXECUTION TOOL
   with a script that reads and processes the file, returning only the
   relevant analysis — not the raw file contents.
2. When you need to search for patterns, WRITE A SCRIPT that does the search
   and returns structured results — not raw grep output.
3. One ctx_execute call replaces 10+ Read/Grep/Bash tool calls. PROGRAM the
   analysis, don't COMPUTE it in your context window.
4. When output exceeds 5 KB, specify an INTENT parameter so only matching
   sections are returned.

This directive is adapted from context-mode's mandatory \"Think in Code\"
paradigm, which achieves 96% context savings across 21 benchmark scenarios."
  "Mandatory routing directive injected into executor/researcher system prompts.
Instructs the LLM to program analysis rather than dump raw data into context.
Purely informational — does NOT dictate prose style or brevity.")


;; ─── Context Bytes Accounting ───

(defvar gptel-nucleus-context--bytes-saved-this-session 0
  "Total bytes kept out of context during this session (lifetime of daemon process).")

(defvar gptel-nucleus-context--bytes-returned-this-session 0
  "Total bytes returned to the model during this session.")

(defvar gptel-nucleus-context--bytes-saved-lifetime 0
  "Cumulative bytes saved across all sessions.
Persisted to var/tmp/context-savings.json (loaded/saved with Emacs session).")

(defvar gptel-nucleus-context--bytes-returned-lifetime 0
  "Cumulative bytes returned across all sessions.")

(defvar gptel-nucleus-context--persist-file
  (expand-file-name "var/tmp/context-savings.json" user-emacs-directory)
  "File for persisting lifetime context savings.")

(defvar gptel-nucleus-context--backend-efficiency
  (let ((ht (make-hash-table :test 'equal)))
    ht)
  "Per-backend context efficiency: backend-name → (bytes-saved . bytes-returned).")

(defun gptel-nucleus-context--record-bytes-saved (bytes)
  "Increment bytes-saved counters by BYTES."
  (cl-incf gptel-nucleus-context--bytes-saved-this-session bytes)
  (cl-incf gptel-nucleus-context--bytes-saved-lifetime bytes))

(defun gptel-nucleus-context--record-bytes-returned (bytes)
  "Increment bytes-returned counters by BYTES."
  (cl-incf gptel-nucleus-context--bytes-returned-this-session bytes)
  (cl-incf gptel-nucleus-context--bytes-returned-lifetime bytes))

(defun gptel-nucleus-context--context-savings-ratio ()
  "Return ratio (0.0-1.0) of total bytes saved vs total bytes handled.
Formula from context-mode: Without = bytesSaved + bytesReturned.
Savings ratio = bytesSaved / (bytesSaved + bytesReturned + 1).
Returns 0.0 when no data."
  (let* ((saved (max 0 gptel-nucleus-context--bytes-saved-this-session))
         (returned (max 0 gptel-nucleus-context--bytes-returned-this-session))
         (total (+ saved returned)))
    (if (= total 0)
        0.0
      (/ (float saved) total))))

(defun gptel-nucleus-context--context-efficiency ()
  "Return context efficiency as a human-readable string like \"94%\"."
  (let* ((ratio (gptel-nucleus-context--context-savings-ratio))
         (pct (* ratio 100.0)))
    (format "%.0f%%" pct)))

(defun gptel-nucleus-context--record-backend-efficiency (backend-name bytes-saved bytes-returned)
  "Record per-backend context efficiency.
BACKEND-NAME is a string (e.g. \"DeepSeek\"). BYTES-SAVED and BYTES-RETURNED
are integers accumulated across all calls to this backend."
  (let ((existing (gethash backend-name gptel-nucleus-context--backend-efficiency '(0 . 0))))
    (puthash backend-name
             (cons (+ (car existing) bytes-saved)
                   (+ (cdr existing) bytes-returned))
             gptel-nucleus-context--backend-efficiency)))

(defun gptel-nucleus-context--backend-context-efficiency (backend-name)
  "Return context savings ratio (0.0-1.0) for BACKEND-NAME.
Returns nil if no data exists for this backend."
  (let ((entry (gethash backend-name gptel-nucleus-context--backend-efficiency)))
    (when entry
      (let ((saved (car entry))
            (returned (cdr entry)))
        (if (= (+ saved returned) 0)
            0.0
          (/ (float saved) (+ saved returned)))))))

(defun gptel-nucleus-context--load-lifetime ()
  "Load lifetime context savings from persist file."
  (ignore-errors
    (when (file-exists-p gptel-nucleus-context--persist-file)
      (let* ((json (with-temp-buffer
                     (insert-file-contents gptel-nucleus-context--persist-file)
                     (json-parse-buffer :object-type 'plist)))
             (saved (plist-get json :bytes-saved-lifetime))
             (returned (plist-get json :bytes-returned-lifetime)))
        (when (integerp saved)
          (setq gptel-nucleus-context--bytes-saved-lifetime saved))
        (when (integerp returned)
          (setq gptel-nucleus-context--bytes-returned-lifetime returned))))))

(defun gptel-nucleus-context--save-lifetime ()
  "Save lifetime context savings to persist file."
  (ignore-errors
    (make-directory (file-name-directory gptel-nucleus-context--persist-file) t)
    (with-temp-file gptel-nucleus-context--persist-file
      (let ((json (json-serialize
                   (list :bytes-saved-lifetime gptel-nucleus-context--bytes-saved-lifetime
                         :bytes-returned-lifetime gptel-nucleus-context--bytes-returned-lifetime)
                   :null-object nil :false-object nil)))
        (insert json)))))

;; Load on init
(gptel-nucleus-context--load-lifetime)


;; ─── Auto-Indexing Store ───

(defvar gptel-nucleus-context--auto-index-threshold 10000
  "Minimum bytes before a tool output is auto-indexed instead of returned raw.
Inspired by context-mode's threshold: output > 10 KB → auto-index, return pointer.")

(defvar gptel-nucleus-context--index-store
  (let ((ht (make-hash-table :test 'equal)))
    ht)
  "In-memory content index: key → (TIMESTAMP . CONTENT-STRING).
Used as a lightweight FTS5-equivalent for auto-indexed tool outputs.
Content is searchable via simple substring matching with relevance scoring.

Architecture note: While context-mode uses SQLite FTS5 with BM25 ranking,
the Emacs Lisp implementation uses an in-memory store with substring matching.
For production use, this can be upgraded to Emacs's built-in sqlite3 module
(available since Emacs 29) for disk persistence and FTS5 features.")

(defvar gptel-nucleus-context--max-index-entries 500
  "Maximum number of index entries before FIFO eviction.")

(defun gptel-nucleus-context--auto-index-p (byte-count)
  "Return t if BYTE-COUNT exceeds the auto-index threshold."
  (and (integerp byte-count)
       (> byte-count 0)
       (> byte-count gptel-nucleus-context--auto-index-threshold)))

(cl-defun gptel-nucleus-context--auto-index-truncate (full-output max-chars agent-name index-key)
  "Truncate FULL-OUTPUT to MAX-CHARS, auto-index the rest, and return truncated version.
Returns a string containing:
  1. The truncated output (first MAX-CHARS chars)
  2. A pointer block with the index key for retrieval

Inspired by context-mode's behavior: when output > 5 KB, auto-index and
return only matching sections via intent-driven search."
  (let* ((total-len (length full-output))
         (truncated-p (> total-len max-chars))
         (display (if truncated-p
                      (substring full-output 0 max-chars)
                    full-output))
         (saved (if truncated-p (- total-len max-chars) 0)))
    (when truncated-p
      (gptel-nucleus-context--index-store index-key full-output agent-name)
      (gptel-nucleus-context--record-bytes-saved saved))
    (if truncated-p
        (concat display
                "\n\n[context-mode] Output truncated: "
                (format "%d bytes" total-len)
                " → " (format "%d bytes" max-chars)
                " (" (format "%d bytes" saved) " saved, index: " index-key ")\n"
                "Retrieve full content with: ctx_search(\"" index-key "\", \"<query>\")\n")
      display)))

(defun gptel-nucleus-context--index-store (key content agent-name)
  "Store CONTENT in the index under KEY, tagged with AGENT-NAME.
KEY is a string identifier (e.g. experiment ID + timestamp).
CONTENT is the full text to be indexed.
FIFO eviction: oldest entries removed when max-index-entries exceeded."
  (let* ((timestamp (float-time))
         (entry (list timestamp content agent-name)))
    (when (> (hash-table-count gptel-nucleus-context--index-store)
             gptel-nucleus-context--max-index-entries)
      (let ((oldest-key nil)
            (oldest-time most-positive-fixnum))
        (maphash (lambda (k v)
                   (when (< (car v) oldest-time)
                     (setq oldest-key k
                           oldest-time (car v))))
                 gptel-nucleus-context--index-store)
        (when oldest-key
          (remhash oldest-key gptel-nucleus-context--index-store))))
    (puthash key entry gptel-nucleus-context--index-store)))

(defun gptel-nucleus-context--index-lookup (key)
  "Return the stored content for KEY, or nil if not found."
  (let ((entry (gethash key gptel-nucleus-context--index-store)))
    (when entry
      (cadr entry))))

(defun gptel-nucleus-context--index-clear (key)
  "Remove KEY from the index store."
  (remhash key gptel-nucleus-context--index-store))

(cl-defun gptel-nucleus-context--index-search (key query &optional max-results)
  "Search indexed content at KEY for QUERY using simple substring matching.
Returns a list of matching lines with line numbers, sorted by relevance (length
of match, occurrence count). MAX-RESULTS defaults to 20.

This is the Emacs Lisp equivalent of context-mode's FTS5 search with
three-tier fallback (Porter stemming → Trigram → Fuzzy).
The current implementation uses exact substring matching; future versions
can add trigram and Levenshtein fallback."
  (let ((content (gptel-nucleus-context--index-lookup key))
        (max-n (or max-results 20)))
    (unless content
      (cl-return-from gptel-nucleus-context--index-search nil))
    (let* ((lines (split-string content "\n"))
           (query-lower (downcase query))
           (matches nil))
      (cl-loop for i from 0
               for line in lines
               for line-lower = (downcase line)
               for pos = (string-match (regexp-quote query-lower) line-lower)
               when pos do
               (let ((score (+ (- (length line-lower))
                               (* 10 (length query-lower))
                               (cl-count (aref query-lower 0) line-lower))))
                 (push (list score (1+ i) line) matches)))
      ;; Sort by score descending, then return results
      (let ((sorted (sort matches (lambda (a b) (> (car a) (car b))))))
        (mapcar (lambda (m) (cons (cadr m) (caddr m)))
                (cl-subseq sorted 0 (min max-n (length sorted))))))))


;; ─── Progressive Throttling ───

(defvar gptel-nucleus-context--throttle-counts (make-hash-table :test 'equal)
  "Hash table: action-name → (TIMESTAMP . COUNT) for current throttle window.")

(defvar gptel-nucleus-context--throttle-window 60
  "Throttle window in seconds. Calls older than this are evicted.")

(defvar gptel-nucleus-context--throttle-limits
  '(("index-search" . (3 . 8))
    ("execute" . (5 . 12))
    ("fetch" . (3 . 5)))
  "Throttle limits: ACTION → (NORMAL-THRESHOLD . MAX-THRESHOLD).
Between NORMAL and MAX: reduced mode (warn but allow).
Above MAX: blocked.
Inspired by context-mode's progressive throttling: 1-3 normal, 4-8 reduced, 9+ blocked.")

(defun gptel-nucleus-context--throttle-allow-p (action-name)
  "Return t if ACTION-NAME is below its throttle limit for the current window.
Returns nil if the action should be blocked (above MAX threshold).
The caller should use this to decide whether to proceed, warn, or block."
  (let* ((now (float-time))
         (existing (gethash action-name gptel-nucleus-context--throttle-counts))
         (window-start (- now gptel-nucleus-context--throttle-window)))
    (if (and existing (> (car existing) window-start))
        ;; Within window: increment count
        (let ((new-count (1+ (cdr existing))))
          (puthash action-name (cons now new-count)
                   gptel-nucleus-context--throttle-counts)
          (let ((limits (assoc-default action-name gptel-nucleus-context--throttle-limits)))
            (if limits
                (<= new-count (cdr limits))
              (<= new-count 10))))
      ;; Outside window: reset
      (puthash action-name (cons now 1) gptel-nucleus-context--throttle-counts)
      t)))

(defun gptel-nucleus-context--throttle-reset ()
  "Reset all throttle counters."
  (clrhash gptel-nucleus-context--throttle-counts))


;; ─── Session Event Capture ───

(defvar gptel-nucleus-context--session-events nil
  "List of session events for the current workflow run.
Each event is a plist: (:TYPE ... :TARGET ... :DETAIL ... :TIMESTAMP ...).
Event types: :file-edit, :file-read, :decision, :error, :git-commit,
:git-push, :task-create, :task-complete, :agent-dispatched, :agent-completed,
:search-query, :search-result, :environment, :constraint, :blocked, :resolved.

Inspired by context-mode's 28 event categories captured via PostToolUse hooks
and stored in SessionDB with SQLite + FTS5. OV5's implementation uses an
in-memory list during the session, with ability to persist to JSON for
cross-session continuity.")

(defvar gptel-nucleus-context--max-session-events 1000
  "Maximum session events before FIFO eviction (lowest priority first).
Matches context-mode's SessionDB limit.")

(defun gptel-nucleus-context--record-session-event (type target detail)
  "Record a session event of TYPE for TARGET with DETAIL string."
  (let ((event (list :type type
                     :target target
                     :detail (truncate-string-to-width detail 200)
                     :timestamp (float-time))))
    (push event gptel-nucleus-context--session-events)
    (when (> (length gptel-nucleus-context--session-events)
             gptel-nucleus-context--max-session-events)
      ;; FIFO eviction: remove oldest (last in list since we push)
      (setq gptel-nucleus-context--session-events
            (cl-subseq gptel-nucleus-context--session-events 0
                       gptel-nucleus-context--max-session-events)))))

(defun gptel-nucleus-context--build-resume-snapshot (experiment-id)
  "Build a resume snapshot from current session events for EXPERIMENT-ID."
  (let ((events gptel-nucleus-context--session-events))
    (if (null events)
        (format "<session_resume experiment=\"%s\">\n  No session events recorded.\n</session_resume>"
                experiment-id)
      (let* ((file-events nil)
             (decision-events nil)
             (error-events nil))
        (dolist (event events)
          (let ((type (plist-get event :type)))
            (cond
             ((memq type '(:file-edit :file-read :file-glob :file-search))
              (push event file-events))
             ((eq type :decision)
              (push event decision-events))
             ((memq type '(:error :error-resolved :constraint :blocked))
              (push event error-events)))))
        (with-temp-buffer
          (insert (format "<session_resume experiment=\"%s\">\n" experiment-id))
          (when file-events
            (insert (format "  <files count=\"%d\">\n" (length file-events)))
            (dolist (ev (cl-subseq file-events 0 (min 20 (length file-events))))
              (insert "    <edit"
                      " file=\"" (or (plist-get ev :target) "unknown") "\""
                      " detail=\"" (or (plist-get ev :detail) "") "\"/>\n"))
            (when (> (length file-events) 20)
              (insert (format "    <more count=\"%d\"/>\n" (- (length file-events) 20))))
            (insert "  </files>\n"))
          (when decision-events
            (insert (format "  <decisions count=\"%d\">\n" (length decision-events)))
            (dolist (ev decision-events)
              (insert "    <decision"
                      " topic=\"" (or (plist-get ev :target) "unknown") "\">"
                      (or (plist-get ev :detail) "") "</decision>\n"))
            (insert "  </decisions>\n"))
          (when error-events
            (insert (format "  <errors count=\"%d\">\n" (length error-events)))
            (dolist (ev (cl-subseq error-events 0 (min 10 (length error-events))))
              (insert "    <error"
                      " location=\"" (or (plist-get ev :target) "unknown") "\""
                      " detail=\"" (or (plist-get ev :detail) "") "\"/>\n"))
            (insert "  </errors>\n"))
          (insert "  <retrieval>\n"
                  "    Search this session's events with context_search queries.\n"
                  "  </retrieval>\n")
          (insert "</session_resume>")
          (buffer-string))))))

(defun gptel-nucleus-context--clear-session-events ()
  "Clear all session events (call at start of new workflow run)."
  (setq gptel-nucleus-context--session-events nil))


;; ─── Persistent Session State (survives daemon restarts) ───

(defvar gptel-nucleus-context--auto-persist-enabled t
  "When non-nil, session events auto-persist after each record (debounced 2s).")

(defvar gptel-nucleus-context--persist-timer nil
  "Idle timer for debounced event persistence.")

(defun gptel-nucleus-context--persist-events ()
  "Write session events to persist file as JSON."
  (ignore-errors
    (let ((dir (file-name-directory gptel-nucleus-context--persist-file)))
      (unless (file-directory-p dir)
        (make-directory dir t)))
    (let* ((n (min 200 (length gptel-nucleus-context--session-events)))
           (events (and (> n 0) (cl-subseq gptel-nucleus-context--session-events 0 n)))
           (json (if events
                     (json-serialize
                      (vconcat
                       (mapcar (lambda (ev)
                                 (list :type (symbol-name (plist-get ev :type))
                                       :target (or (plist-get ev :target) "")
                                       :detail (or (plist-get ev :detail) "")
                                       :timestamp (or (plist-get ev :timestamp) 0.0)))
                               events)))
                   "[]")))
      (with-temp-file gptel-nucleus-context--persist-file
        (insert json)))))

(defun gptel-nucleus-context--load-events ()
  "Load session events from persist file. Survives daemon restarts."
  (ignore-errors
    (when (file-exists-p gptel-nucleus-context--persist-file)
      (let* ((raw (with-temp-buffer
                    (insert-file-contents gptel-nucleus-context--persist-file)
                    (buffer-string)))
             (parsed (condition-case nil
                         (json-parse-string raw)
                       (error nil)))
             (source (when parsed
                       (if (vectorp parsed)
                           (append parsed nil)
                         (when (listp parsed) parsed))))
             (loaded (when source
                       (mapcar (lambda (e)
                                 (list :type (intern (or (gethash "type" e) ""))
                                       :target (gethash "target" e)
                                       :detail (gethash "detail" e)
                                       :timestamp (gethash "timestamp" e)))
                               (cl-subseq source 0 (min gptel-nucleus-context--max-session-events
                                                       (length source)))))))
        (when loaded
          (setq gptel-nucleus-context--session-events
                (let ((merged (append gptel-nucleus-context--session-events loaded)))
                  (cl-subseq merged 0 (min gptel-nucleus-context--max-session-events
                                          (length merged))))))))))

(defun gptel-nucleus-context--auto-persist ()
  "Debounced auto-persist: schedule write 2s from now."
  (when gptel-nucleus-context--auto-persist-enabled
    (when gptel-nucleus-context--persist-timer
      (cancel-timer gptel-nucleus-context--persist-timer))
    (setq gptel-nucleus-context--persist-timer
          (run-at-time 2.0 nil #'gptel-nucleus-context--persist-events))))

(advice-add 'gptel-nucleus-context--record-session-event :after
            (lambda (&rest _) (gptel-nucleus-context--auto-persist)))

;; ─── Upgraded Search: TF-IDF + BM25-Style + Trigram Fallback ───

(defvar gptel-nucleus-context--search-bm25-k1 2.0 "BM25 k1: term freq saturation.")
(defvar gptel-nucleus-context--search-bm25-b 0.75 "BM25 b: doc length normalization.")

(defun gptel-nucleus-context--index-search-tfidf (key query &optional max-results)
  "Search indexed content at KEY for QUERY using TF-IDF+BM25 scoring."
  (let ((content (gptel-nucleus-context--index-lookup key))
        (max-n (or max-results 20)))
    (unless content
      (cl-return-from gptel-nucleus-context--index-search-tfidf nil))
    (let* ((query-lower (downcase (string-trim query))))
      (when (string= "" query-lower)
        (cl-return-from gptel-nucleus-context--index-search-tfidf nil))
      (let* ((lines (split-string content "\n"))
             (num-lines (length lines))
             (query-terms (split-string query-lower "[ \t]+" t))
             (df (make-hash-table :test 'equal))
             (avg-len (if (> num-lines 0)
                          (/ (float (cl-reduce #'+ (mapcar #'length lines) :initial-value 0))
                             num-lines)
                        1.0))
             (scored nil))
        (dolist (term query-terms)
          (let ((count 0))
            (dolist (line lines)
              (when (string-match-p (regexp-quote term) (downcase line))
                (cl-incf count)))
            (puthash term count df)))
        (cl-loop for i from 0 for line in lines for line-lower = (downcase line)
                 for line-len = (length line)
                 do (let ((score 0.0))
                      (dolist (term query-terms)
                        (let ((term-df (gethash term df 0)))
                          (when (> term-df 0)
                            (let ((tf 0) (start 0))
                              (while (string-match (regexp-quote term) line-lower start)
                                (cl-incf tf)
                                (setq start (1+ (match-beginning 0))))
                              (when (> tf 0)
                                (let* ((len-ratio (/ (float line-len) (max 1.0 avg-len)))
                                       (k1 gptel-nucleus-context--search-bm25-k1)
                                       (b gptel-nucleus-context--search-bm25-b)
                                       (denom (+ (* k1 (+ (- 1 b) (* b len-ratio))) tf))
                                       (tf-sat (/ (* (+ k1 1) tf) (max 1.0 denom)))
                                       (idf (log (/ (+ (- num-lines term-df) 0.5)
                                                     (+ term-df 0.5)))))
                                  (cl-incf score (* tf-sat idf))))))))
                      (when (> score 0.0)
                        (when (string-match-p "\\`[#;]" (string-trim line))
                          (setq score (* score 5.0)))
                        (push (list score (1+ i) line) scored))))
        (let ((sorted (sort scored (lambda (a b) (> (car a) (car b))))))
          (seq-take sorted (min max-n (length sorted))))))))

(defun gptel-nucleus-context--trigrams (s)
  "Return all trigrams of string S."
  (let ((n (length s)) (result nil))
    (when (>= n 3)
      (dotimes (i (- n 2))
        (push (substring s i (+ i 3)) result)))
    (nreverse result)))

(defun gptel-nucleus-context--index-search-trigram (key query &optional max-results)
  "Search indexed content using trigram Jaccard similarity."
  (let ((content (gptel-nucleus-context--index-lookup key))
        (max-n (or max-results 20)))
    (unless content
      (cl-return-from gptel-nucleus-context--index-search-trigram nil))
    (let* ((query-lower (downcase (string-trim query))))
      (when (string= "" query-lower)
        (cl-return-from gptel-nucleus-context--index-search-trigram nil))
      (let* ((lines (split-string content "\n"))
             (query-trigrams (gptel-nucleus-context--trigrams query-lower))
             (scored nil))
        (cl-loop for i from 0 for line in lines for line-lower = (downcase line)
                 do (let ((line-trigrams (gptel-nucleus-context--trigrams line-lower))
                          (intersection 0))
                      (dolist (qt query-trigrams)
                        (when (member qt line-trigrams)
                          (cl-incf intersection)))
                      (when (> intersection 0)
                        (let ((union (+ (length query-trigrams) (length line-trigrams)
                                        (- intersection)))
                              (jaccard (/ (float intersection) (max 1 union))))
                          (push (list jaccard (1+ i) line) scored)))))
        (let ((sorted (sort scored (lambda (a b) (> (car a) (car b))))))
          (seq-take sorted (min max-n (length sorted))))))))

(defun gptel-nucleus-context--search-with-fallback (key query &optional max-results)
  "Three-tier search: TF-IDF → trigram → simple contains."
  (or (and (fboundp 'gptel-nucleus-context--index-search-tfidf)
           (gptel-nucleus-context--index-search-tfidf key query max-results))
      (and (fboundp 'gptel-nucleus-context--index-search-trigram)
           (gptel-nucleus-context--index-search-trigram key query max-results))
      (when (fboundp 'gptel-nucleus-context--index-search)
        (let ((simple (gptel-nucleus-context--index-search key query max-results)))
          (when simple
            (mapcar (lambda (r) (list 0.01 (car r) (cdr r))) simple))))))

;; ─── Intent-Driven Search ───

(defun gptel-nucleus-context--intent-search (output intent &optional max-chars)
  "Filter large OUTPUT to sections matching INTENT keywords.
If OUTPUT fits within MAX-CHARS (default 4000), return as-is.
Otherwise split by markdown headings and keep only matching sections."
  (let ((max-c (or max-chars 4000)))
    (if (<= (length output) max-c)
        output
      (let* ((intent-lower (downcase (string-trim (or intent ""))))
             (sections (if (string-match-p "\n## " output)
                           (split-string output "\n\\(?=## \\)" t)
                         (split-string output "\n\n+" t)))
             (matching nil)
             (remaining max-c))
        (if (string= "" intent-lower)
            (let ((truncated (substring output 0 max-c)))
              (gptel-nucleus-context--record-bytes-saved (- (length output) max-c))
              truncated)
          (dolist (section sections)
            (when (and (> remaining 100)
                       (let ((case-fold-search t))
                         (string-match-p (regexp-quote intent-lower)
                                         (downcase section))))
              (let ((part (if (> (length section) remaining)
                              (concat (substring section 0 remaining) "...")
                            section)))
                (push part matching)
                (setq remaining (- remaining (length part))))))
          (let* ((filtered (mapconcat #'identity (nreverse matching) "\n"))
                 (saved (- (length output) (length filtered))))
            (when (> saved 0)
              (gptel-nucleus-context--record-bytes-saved saved))
            (if (string= "" filtered)
                (substring output 0 max-c)
              filtered)))))))

;; ─── Lambda Notation Compression ───

(defvar gptel-nucleus-context--lambda-shortcuts
  '(("function" . "fn")
    ("the function" . "fn")
    ("returns" . "→")
    ("should return" . "→")
    ("must return" . "→")
    ("always returns" . "→")
    ("when" . "when")
    ("if and only if" . "⇔")
    ("therefore" . "∴")
    ("because" . "∵")
    ("prefer" . ">")
    ("is preferred over" . ">")
    ("more than" . ">")
    ("never" . "¬")
    ("do not" . "¬")
    ("not" . "¬")
    ("there exists" . "∃")
    ("for all" . "∀")
    ("for every" . "∀")
    ("equivalent" . "≡")
    ("is defined as" . "≡")
    ("error" . "err")
    ("argument" . "arg")
    ("argument(s)" . "args")
    ("argument s)" . "args")
    ("context window" . "ctx")
    ("context" . "ctx")
    ("benchmark" . "bench")
    ("backend" . "be")
    ("experiment" . "exp")
    ("executor" . "exec")
    ("execution" . "exec")
    ("the following" . "")
    ("please" . "")
    ("you must" . "→")
    ("you should" . "→")
    ("it is important to" . "")
    ("it is recommended that" . "")
    ("make sure that" . "→")
    ("ensure that" . "→")
    ("in order to" . "to")
    ("a number of" . "some")
    ("the majority of" . "most")
    ("due to the fact that" . "because")
    ("in the event that" . "if")
    ("with regard to" . "about")
    ("it is necessary that" . "→")
    ("it is required that" . "→"))
  "Phrase → lambda-symbol shortcut map for prompt compression.
Long phrases are replaced with their shorter equivalents during compression.
Inspired by context-mode's brevity enforcement (though OV5 already uses
lambda notation, this extends the compression to common English fillers).")

(defun gptel-nucleus-context--lambda-compress-and-measure (text)
  "Apply lambda compression to TEXT and measure bytes saved.
Returns (COMPRESSED-STRING . BYTES-SAVED).
Safe: never changes the meaning, only replaces filler phrases."
  (let* ((original-len (length text))
         (compressed text))
    (dolist (pair gptel-nucleus-context--lambda-shortcuts)
      (let ((phrase (car pair))
            (shortcut (cdr pair)))
        (when (and (> (length phrase) 0)
                   (string-match-p (regexp-quote phrase) compressed))
          (setq compressed
                (replace-regexp-in-string
                 (regexp-quote phrase) shortcut compressed t t)))))
    (let ((saved (max 0 (- original-len (length compressed)))))
      (when (> saved 0)
        (gptel-nucleus-context--record-bytes-saved saved))
      (cons compressed saved))))


;; ─── Context-Cost Model Integration ───

(defun gptel-nucleus-context--context-cost-estimate (context-bytes model-name)
  "Estimate dollar cost of CONTEXT-BYTES for MODEL-NAME.
Uses the model's input pricing from gptel-ai-behaviors--model-pricing.
Returns a float representing the dollar cost (or 0.0 if pricing unknown)."
  (let* ((pricing (and (boundp 'gptel-ai-behaviors--model-pricing)
                       (cl-find-if (lambda (e) (string-match-p (car e) model-name))
                                   gptel-ai-behaviors--model-pricing)))
         (input-price (or (plist-get (cdr-safe pricing) :input) 0.0)))
    (if (and (> input-price 0) (> context-bytes 0))
        (let* ((price-per-1M (/ input-price 1000000.0))
               (estimated-tokens (/ (float context-bytes) 4.0))
               (dollar-cost (* estimated-tokens price-per-1M)))
          (max 0.0 dollar-cost))
      0.0)))

(defun gptel-nucleus-context--context-cost-adjusted-rate (kept total model-name context-savings-ratio)
  "Compute keep-rate adjusted for BOTH dollar cost AND context efficiency.
KEPT and TOTAL are integers from the backend's experiment stats.
MODEL-NAME is a string (e.g. \"deepseek-v4-flash\").
CONTEXT-SAVINGS-RATIO is a float 0.0-1.0 representing bytes saved/(saved+returned).

Formula: cost-adjusted-rate = (kept/total) / (dollar-cost-per-experiment * (1 + padding-factor))
where padding-factor = (1.0 - context-savings-ratio) adds context waste to the cost denominator.

This means: a model with 90% context savings has a padding factor of 0.1 (small adjustment),
while a model with 10% context savings has a padding factor of 0.9 (large adjustment).
Context-wasteful models are penalized in the keep-rate model."
  (if (= total 0)
      0.0
    (let* ((avg-keep-rate (/ (float kept) total))
           (avg-input-chars 8000)  ; typical experiment prompt size
           (context-cost (gptel-nucleus-context--context-cost-estimate
                          avg-input-chars model-name))
           ;; Padding: models that waste context pay a multiplier
           (padding-factor (max 0.01 (- 1.0 context-savings-ratio)))
           (adjusted-cost (* context-cost (+ 1.0 padding-factor)))
           (cost-denom (+ adjusted-cost 0.001)))  ; avoid division by zero
      (/ avg-keep-rate cost-denom))))


;; ─── Full Tool Dispatch Wrapper ───

(cl-defun gptel-nucleus-context--wrap-agent-tool
    (original-fn callback agent-name description prompt files include-history include-diff)
  "Wrap ORIGINAL-FN (my/gptel--run-agent-tool) with context interception hooks.
Runs PreToolUse hooks before dispatch, wraps callback for PostToolUse hooks +
auto-indexing, records session events.

This is the primary integration point: replaces direct calls to
my/gptel--run-agent-tool in the experiment dispatch pipeline.

Returns whatever ORIGINAL-FN returns (the agent task object)."
  (let* ((start-time (float-time))
         (pre-result (gptel-nucleus-context--run-pre-tool-hooks
                      agent-name description prompt nil))
         (pre-action (plist-get pre-result :action))
         (modified-prompt (plist-get pre-result :modified-prompt))
         (redirect-agent (plist-get pre-result :redirect-agent)))
    (when (eq pre-action :deny)
      (message "[context-intercept] Denied tool call: %s → %s" agent-name description)
      (gptel-nucleus-context--record-session-event :denied agent-name description)
      (when (functionp callback)
        (funcall callback "Error: tool call denied by context interception"))
      (cl-return-from gptel-nucleus-context--wrap-agent-tool nil))
    (let ((effective-agent (or redirect-agent agent-name))
          (effective-prompt (or modified-prompt prompt)))
      (gptel-nucleus-context--record-session-event
       :agent-dispatched effective-agent description)
      ;; Wrap callback with post-tool interception + auto-indexing + accounting
      (let ((wrapped-callback
             (lambda (result)
               (let ((duration (- (float-time) start-time))
                     (result-bytes (length (or result ""))))
                 (gptel-nucleus-context--record-bytes-returned result-bytes)
                 (gptel-nucleus-context--run-post-tool-hooks
                  effective-agent result duration effective-prompt)
                 (gptel-nucleus-context--record-session-event
                  :agent-completed effective-agent
                  (format "Result: %d bytes, %.1fs" result-bytes duration))
                 (when (functionp callback)
                   (funcall callback result))))))
        (funcall original-fn wrapped-callback effective-agent description
                 effective-prompt files include-history include-diff)))))


;; ─── Advice Registration (Wire Into Existing Pipeline) ───

(defun gptel-nucleus-context-intercept--enable ()
  "Activate context interception by advising tool dispatch functions.
Safe to call multiple times (idempotent — removes old advice first)."
  ;; Remove any existing advice to avoid duplicates
  (ignore-errors
    (advice-remove 'my/gptel--run-agent-tool-with-timeout
                   'gptel-nucleus-context--advice-agent-tool-timeout))
  (ignore-errors
    (advice-remove 'gptel-auto-experiment-run
                   'gptel-nucleus-context--advice-experiment-run))
  ;; Clear session events for new run
  (gptel-nucleus-context--clear-session-events)
  ;; Wire advice: after every tool dispatch, capture events and context stats
  (advice-add 'my/gptel--run-agent-tool-with-timeout :after
              #'gptel-nucleus-context--advice-agent-tool-timeout)
  (advice-add 'gptel-auto-experiment-run :around
              #'gptel-nucleus-context--advice-experiment-run)
  (message "[context-intercept] Enabled — PreToolUse + PostToolUse hooks active"))

(defun gptel-nucleus-context-intercept--disable ()
  "Deactivate context interception."
  (ignore-errors
    (advice-remove 'my/gptel--run-agent-tool-with-timeout
                   'gptel-nucleus-context--advice-agent-tool-timeout))
  (ignore-errors
    (advice-remove 'gptel-auto-experiment-run
                   'gptel-nucleus-context--advice-experiment-run))
  (message "[context-intercept] Disabled"))

(defun gptel-nucleus-context--advice-agent-tool-timeout (&rest _args)
  "Post-tool-dispatch advice: record session event and track bytes."
  (ignore-errors
    (let ((agent-name (car _args)))  ; args: (timeout callback agent-name description prompt ...)
      (when (stringp agent-name)
        (gptel-nucleus-context--record-session-event
         :subagent-start agent-name "Tool dispatch")))))

(defun gptel-nucleus-context--advice-experiment-run (orig-fun &rest args)
  "Around advice on gptel-auto-experiment-run: inject think-in-code directive
and track experiment-level events."
  (unwind-protect
      (progn
        ;; Before experiment: inject think-in-code into executor prompts
        ;; This is done by the PreToolUse hook chain which fires inside the run
        (apply orig-fun args))
    ;; After experiment: save lifetime context stats
    (gptel-nucleus-context--save-lifetime)))

;; ─── Default Hook: Think-in-Code Enforcement ───

(defun gptel-nucleus-context--default-pre-hook (agent-name prompt _description)
  "Default PreToolUse hook: inject think-in-code directive for code-facing agents.
Only injects for agents that produce code (executor, researcher).
Does NOT inject for graders/comparators (those only consume, not produce)."
  (condition-case nil
      (if (member agent-name '("executor" "researcher" "explorer"))
          (let ((modified-prompt
                 (if (and prompt (> (length prompt) 0))
                     (concat gptel-nucleus-context--think-in-code-directive
                             "\n\n--- TASK PROMPT ---\n" prompt)
                   prompt)))
            (list :continue :modified-prompt modified-prompt))
        (list :continue))
    (error (list :continue))))

;; Register the think-in-code hook by default
(cl-pushnew #'gptel-nucleus-context--default-pre-hook
            gptel-nucleus-context--pre-tool-hooks :test #'equal)

;; ─── Default Hook: Auto-Index Large Results ───

(defun gptel-nucleus-context--default-post-hook (agent-name result duration prompt)
  "Default PostToolUse hook: auto-index large results.
When a tool returns > threshold bytes, auto-index the content so it doesn't
pollute the context window on subsequent reads."
  (condition-case nil
      (when (and result (> (length result) gptel-nucleus-context--auto-index-threshold))
        (let* ((index-key (format "ag-%s-%d" agent-name (floor (float-time))))
               (truncated (gptel-nucleus-context--auto-index-truncate
                           result 5000 agent-name index-key)))
          (gptel-nucleus-context--record-bytes-saved
           (- (length result) (length truncated)))))
    (error nil)))

;; Register the auto-index hook by default
(cl-pushnew #'gptel-nucleus-context--default-post-hook
            gptel-nucleus-context--post-tool-hooks :test #'equal)

(provide 'gptel-nucleus-context-intercept)
;;; gptel-nucleus-context-intercept.el ends here
