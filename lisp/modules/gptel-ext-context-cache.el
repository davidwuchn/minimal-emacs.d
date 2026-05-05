;;; gptel-ext-context-cache.el --- Context-window caching for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Caches model context-window sizes from gptel model tables and OpenRouter.
;; Provides `my/gptel--context-window' for other modules to query the current
;; model's context window in tokens.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'json)

;;; Customization

(defgroup my/gptel-context-cache nil
  "Context-window caching for gptel models."
  :group 'gptel)

(defcustom my/gptel-default-context-window 128000
  "Fallback context window (tokens) when model metadata is unavailable.

gptel does not always know the model's true context window (especially via
OpenRouter). Auto-compaction uses this value to estimate when to compact.

Default is 128k tokens, which is common for modern models (GPT-4, Claude 3, etc).
Set lower if you use models with smaller context windows."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-cache-file
  (expand-file-name "savefile/gptel-context-window-cache.el" user-emacs-directory)
  "Path to a cache file storing detected model context windows.

The cache is used when `gptel' does not provide model metadata (common with
OpenRouter-hosted model ids)."
  :type 'file
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-auto-refresh-enabled t
  "When non-nil, refresh context-window metadata in the background."
  :type 'boolean
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-auto-refresh-interval-days 7
  "Minimum number of days between background refreshes."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-context-window-auto-refresh-idle-seconds 20
  "Seconds of idle time before attempting a background refresh."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-openrouter-models-connect-timeout 10
  "Seconds to wait for OpenRouter model-metadata connection."
  :type 'integer
  :group 'my/gptel-context-cache)

(defcustom my/gptel-openrouter-models-max-time 60
  "Maximum seconds for the OpenRouter model-metadata request."
  :type 'integer
  :group 'my/gptel-context-cache)

;;; Internal Variables

(defvar my/gptel--context-window-cache (make-hash-table :test 'equal)
  "Hash table mapping model id string to context window tokens.
Legacy cache - use `my/gptel--model-metadata-cache' for full metadata.")

(defvar my/gptel--model-metadata-cache (make-hash-table :test 'equal)
  "Hash table mapping model id string to metadata plist.
Keys include: :context-window, :pricing-input, :pricing-output,
:max-output, :provider, :description.")

(defvar my/gptel--gptel-tables-cw-cache (make-hash-table :test 'equal)
  "Hash table caching context-window lookups from gptel model tables.
Reduces repeated iterations through model tables.")

(defconst my/gptel--token-estimate-cache-max-size 1000
  "Maximum entries in `my/gptel--token-estimate-cache'.
Prevents unbounded memory growth from repeated token estimates.")

(defvar my/gptel--token-estimate-cache (make-hash-table :test 'equal)
  "Hash table caching token estimates for (chars . extension) pairs.")

(defvar my/gptel--token-estimate-cache-size 0
  "Atomic counter tracking `my/gptel--token-estimate-cache' entry count.
Used to prevent cache from exceeding max-size by checking count before insertion.")

(defvar my/gptel--context-window-cache-last-refresh nil
  "Time (as a float) when the cache was last refreshed.")

(defvar my/gptel--openrouter-context-window-fetch-inflight nil)

(defvar my/gptel--context-window-cache-data nil
  "Temporary holder for data loaded from the context-window cache file.
Must be `defvar' (not `let') so the `setq' in the cache file reaches it
under `lexical-binding: t'.")

(defvar my/gptel--gptel-model-tables-cache nil
  "Cached result of gptel model table symbols lookup.
Avoids repeated filtering of the same symbol list.")

(defvar my/gptel--known-model-context-windows
  '(;; Qwen (Alibaba) - NOTE: Qwen3.5-Plus and Qwen3-Max have 1M context!
    ("qwen3-coder-next" . 131072)
    ("qwen3-coder-plus" . 1000000)
    ("qwen3.5-plus" . 1000000)
    ("qwen3.5-flash" . 1000000)
    ("qwen3-max-2026-01-23" . 262144)
    ("qwen3-coder" . 131072)
    ("qwen-plus" . 1000000)
    ("qwen-flash" . 1000000)
    ("qwen-max" . 131072)
    ("qwen2.5-max" . 131072)
    ("qwen2.5-72b" . 131072)
    ("qwen2.5-32b" . 131072)
    ("qwen2.5-14b" . 131072)
    ("qwen2.5-7b" . 131072)
    ;; Gemini (Google)
    ("gemini-3" . 1048576)
    ("gemini-2.5" . 1048576)
    ("gemini-1.5" . 1048576)
    ("gemini-pro" . 32760)
    ;; Anthropic Claude
    ("claude-4" . 200000)
    ("claude-sonnet-4" . 200000)
    ("claude-3.5" . 200000)
    ("claude-3" . 200000)
    ("claude-2.1" . 200000)
    ("claude-2" . 100000)
    ;; OpenAI GPT
    ("gpt-5" . 128000)
    ("gpt-4o" . 128000)
    ("gpt-4-turbo" . 128000)
    ("gpt-4" . 8192)
    ("gpt-4-32k" . 32768)
    ("gpt-3.5" . 16385)
    ;; DeepSeek
    ("deepseek-v4-flash" . 1000000)
    ("deepseek-v4-pro" . 1000000)
    ;; MiniMax
    ("minimax-m2.7-highspeed" . 196608)
    ("minimax-m2.7" . 196608)
    ("MiniMax-M2.5" . 196608)
    ;; Kimi/Moonshot
    ("kimi-k2.6" . 262144)
    ("kimi-k2.5" . 262144)
    ("kimi-for-coding" . 131072)
    ;; GLM (Zhipu AI)
    ("glm-5" . 131072)
    ("glm-4.7" . 131072)
    ;; Meta Llama
    ("llama-3.1" . 131072)
    ("llama-3-70b" . 8192)
    ("llama-3-8b" . 8192)
    ;; Mistral
    ("mistral-large" . 128000)
    ("mistral-medium" . 32000)
    ("mistral-small" . 32000)
    ("mixtral-8x7b" . 32768)
    ("mixtral-8x22b" . 65536))
  "Known model context windows (tokens) for popular models.
Used as fallback when provider metadata is unavailable.

IMPORTANT: Keep this updated! If you don't know a model's context window,
check the provider's documentation first before assuming defaults.

Sources:
- Qwen: https://help.aliyun.com/zh/model-studio/getting-started/models
- Gemini: https://openrouter.ai/models/google/gemini-2.5-pro-preview
- Claude: https://openrouter.ai/models/anthropic/claude-sonnet-4
- DeepSeek: https://api-docs.deepseek.com/zh-cn/quick_start/pricing
- MiniMax: https://openrouter.ai/models/minimax/minimax-m2.7-highspeed")

(defvar my/gptel--known-model-metadata
  '(;; Qwen (Alibaba via DashScope) - VISION ENABLED
    ("qwen3-coder-next"
     :context-window 131072
     :pricing-input 0.3 :pricing-output 1.2
     :max-output 16384
     :features (streaming tools vision)
     :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf")
     :description "Qwen3 Coder Next - fast coding model, 131k context, VISION")
    ("qwen3-coder-plus"
     :context-window 1000000
     :pricing-input 0.6 :pricing-output 2.4
     :max-output 65536
     :features (streaming tools vision)
     :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf")
     :description "Qwen3 Coder Plus - advanced coding, 1M context, VISION")
    ("qwen3.5-plus"
     :context-window 1000000
     :pricing-input 0.8 :pricing-output 4.8
     :max-output 65536
     :features (streaming tools vision)
     :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "image/tiff" "image/heic" "application/pdf")
     :description "Qwen3.5 Plus - 1M context, thinking mode, VISION ENABLED")
    ("qwen3.5-flash"
     :context-window 1000000
     :pricing-input 0.2 :pricing-output 2.0
     :max-output 65536
     :features (streaming tools vision)
     :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf")
     :description "Qwen3.5 Flash - fast, 1M context, VISION ENABLED")
    ("qwen3-max-2026-01-23"
     :context-window 262144
     :pricing-input 2.5 :pricing-output 10.0
     :max-output 32768
     :features (streaming tools vision)
     :mime-types ("image/jpeg" "image/png" "image/webp" "image/gif" "image/bmp" "application/pdf")
     :description "Qwen3 Max - best quality, 256k context, VISION ENABLED")
    ;; Gemini
    ("gemini-2.5-pro"
     :context-window 1048576
     :pricing-input 1.25 :pricing-output 5.0
     :max-output 65536
     :description "Gemini 2.5 Pro - 1M context, thinking")
    ("gemini-2.5-flash"
     :context-window 1048576
     :pricing-input 0.075 :pricing-output 0.3
     :max-output 65536
     :description "Gemini 2.5 Flash - fast, 1M context")
    ;; Claude
    ("claude-sonnet-4"
     :context-window 200000
     :pricing-input 3.0 :pricing-output 15.0
     :max-output 16384
     :description "Claude Sonnet 4 - balanced, 200k context")
    ("claude-opus-4"
     :context-window 200000
     :pricing-input 15.0 :pricing-output 75.0
     :max-output 16384
     :description "Claude Opus 4 - best, 200k context")
    ;; DeepSeek
    ("deepseek-v4-flash"
     :context-window 1000000
     :pricing-input 1.0 :pricing-output 2.0
     :max-output 384000
     :description "DeepSeek V4 Flash - 1M context, fast path with thinking disabled")
    ("deepseek-v4-pro"
     :context-window 1000000
     :pricing-input 12.0 :pricing-output 24.0
     :max-output 384000
     :description "DeepSeek V4 Pro - 1M context, thinking-enabled reasoning model")
    ;; MiniMax
    ("minimax-m2.7-highspeed"
     :context-window 196608
     :pricing-input 0.60 :pricing-output 2.40
     :max-output 131072
     :description "MiniMax M2.7 Highspeed - 196k context, lower-latency agent workflows")
    ("minimax-m2.7"
     :context-window 196608
     :pricing-input 0.27 :pricing-output 0.95
     :max-output 16384
     :description "MiniMax M2.7 - 196k context, advanced agent workflows")
    ("MiniMax-M2.5"
     :context-window 196608
     :pricing-input 0.27 :pricing-output 0.95
     :max-output 16384
     :description "MiniMax M2.5 - 196k context, SWE-bench 80.2%, agent workflows")
     ;; GPT
    ("gpt-4o"
     :context-window 128000
     :pricing-input 2.5 :pricing-output 10.0
     :max-output 16384
     :description "GPT-4o - 128k context, multimodal")
    ("gpt-4o-mini"
     :context-window 128000
     :pricing-input 0.15 :pricing-output 0.6
     :max-output 16384
     :description "GPT-4o Mini - fast, cheap")
    ;; Kimi
    ("kimi-k2.5"
     :context-window 262144
     :pricing-input 0.45 :pricing-output 2.20
     :max-output 16384
     :description "Kimi K2.5 - Moonshot AI multimodal, 256k context, visual coding")
    ;; GLM (Zhipu AI)
    ("glm-5"
     :context-window 131072
     :pricing-input 0.5 :pricing-output 0.5
     :max-output 16384
     :description "GLM-5 - Zhipu AI flagship, 131k context")
    ("glm-4.7"
     :context-window 131072
     :pricing-input 0.3 :pricing-output 0.3
     :max-output 16384
     :description "GLM-4.7 - Zhipu AI, 131k context"))
  "Pre-seeded model metadata with context window, pricing, and descriptions.
Pricing is in USD per million tokens (input/output).")

;;; Helpers

(defconst my/gptel--cache-sentinel (make-symbol "gptel-cache-sentinel")
  "Sentinel value for cache lookups.
Single constant avoids allocating a new symbol on every lookup call.")

(defconst my/gptel--alist-match-sentinel (make-symbol "alist-partial-match-sentinel")
  "Sentinel value for alist partial-match searches.
Single constant avoids allocating a new symbol on every search call.")

(defun my/gptel--cache-or-alist-lookup (hash-table alist key)
  "Look up KEY in HASH-TABLE, falling back to ALIST partial match.
Returns the value from hash table if found, otherwise searches ALIST
for a partial match (case-insensitive).  Returns nil if not found.
Handles negative cache hits when KEY maps to a miss sentinel."
  (when (and (stringp key) (not (string-empty-p key)))
    (if (hash-table-p hash-table)
        (let ((hash-value (gethash key hash-table my/gptel--cache-sentinel)))
          (cond
           ((eq hash-value my/gptel--cache-sentinel)
            (and (listp alist)
                 (my/gptel--alist-partial-match alist key)))
           ((eq hash-value my/gptel--context-window-miss-sentinel)
            nil)
           (t hash-value)))
      (and (listp alist)
           (my/gptel--alist-partial-match alist key)))))


(defvar my/gptel--alist-partial-match-cache (make-hash-table :test 'equal)
  "Cache for `my/gptel--alist-partial-match' results.
Maps (alist-hash . search-str) to match result for O(1) repeated lookups.")

(defun my/gptel--alist-partial-match (alist search-str)
  "Find best matching entry in ALIST where key partially matches SEARCH-STR (case-insensitive).
Returns the cdr (value) of the matching entry, or nil if no match.
Matches if the alist key is a prefix of SEARCH-STR.
When multiple entries match, returns the one with the longest key for most specific match.
Results are cached in `my/gptel--alist-partial-match-cache' for performance."
  (when (and alist (listp alist) (stringp search-str) (not (string-empty-p search-str)))
    (let* ((alist-id (sxhash alist))
           (cache-key (cons alist-id search-str)))
      (or (gethash cache-key my/gptel--alist-partial-match-cache)
          (let ((best-match my/gptel--alist-match-sentinel)
                (best-key-len 0))
            (dolist (entry alist)
              (when (consp entry)
                (let ((entry-key (car entry)))
                  (when (stringp entry-key)
                    (when (string-prefix-p entry-key search-str t)
                      (let ((key-len (length entry-key)))
                        (when (> key-len best-key-len)
                          (setq best-key-len key-len)
                          (setq best-match (cdr entry)))))))))
            (let ((result (unless (eq best-match my/gptel--alist-match-sentinel)
                            best-match)))
              (puthash cache-key result my/gptel--alist-partial-match-cache)
              result))))))

(defun my/gptel--plist-get (plist key &optional default)
  "Get value from PLIST for KEY, returning DEFAULT if not found.
Reduces duplication of `(or (plist-get ...) default-value)` patterns."
  (if (plist-member plist key)
      (plist-get plist key)
    default))


(defconst my/gptel--gptel-tables-miss-sentinel (make-symbol "gptel-tables-miss")
  "Sentinel for negative cache hits in gptel table lookups.
Avoids re-iterating tables for models that are not present.")

(defconst my/gptel--context-window-miss-sentinel (make-symbol "context-window-miss")
  "Sentinel for negative cache hits in main context-window cache.
Avoids redundant lookups when model is known to be absent from gptel tables.")

(defun my/gptel--lookup-context-window-in-gptel-tables (model)
  "Look up context window for MODEL in gptel's built-in model tables.
Returns the context window in tokens, or nil if not found.
Handles both symbol and string model identifiers with case-insensitive fallback.
Caches results in `my/gptel--gptel-tables-cw-cache' and `my/gptel--context-window-cache'
to avoid repeated table scans and redundant lookups."
  (when (or (stringp model) (symbolp model))
    (let ((model-str (if (stringp model) model (symbol-name model))))
      (when (and (stringp model-str) (not (string-empty-p model-str)))
      (let ((cached (gethash model-str my/gptel--gptel-tables-cw-cache)))
        (if (eq cached my/gptel--gptel-tables-miss-sentinel)
            nil
          (or cached
              (let ((result (catch 'found
                              (dolist (var (my/gptel--gptel-model-tables))
                                (let ((table (symbol-value var)))
                                  (when (listp table)
                                    (let ((entry (assoc-string model-str table t)))
                                      (when (and (consp entry) (listp (cdr entry))
                                                 (plist-member (cdr entry) :context-window))
                                        (let ((cw (my/gptel--normalize-context-window
                                                    (plist-get (cdr entry) :context-window))))
                                          (when (and (integerp cw) (> cw 0))
                                            (throw 'found cw))))))))
                              nil)))
                (if result
                    (puthash model-str result my/gptel--gptel-tables-cw-cache)
                  (puthash model-str my/gptel--gptel-tables-miss-sentinel my/gptel--gptel-tables-cw-cache))
                result))))))))
(defun my/gptel--model-id-string (&optional model)
  "Return MODEL as a stable string id."
  (let ((m (or model gptel-model)))
    (cond
     ((stringp m) m)
     ((symbolp m) (symbol-name m))
     (t (format "%S" m)))))

(defun my/gptel--normalize-context-window (n)
  "Normalize gptel context-window value N to tokens.

Some gptel model tables encode context windows in *thousands* of tokens as floats
(e.g. 8.192 for 8192 tokens). OpenRouter's `context_length' is in raw tokens."
  (cond
   ((not (numberp n)) nil)
   ((<= n 0) nil)
   ((floatp n) (round (* n 1000)))
   ((< n 1000) (round (* n 1000)))
   ((> n 2000000) nil)
   (t (round n))))

(defun my/gptel--positive-integer-p (n)
  "Return N if it is a positive integer, otherwise nil."
  (and (integerp n) (> n 0) n))

(defun my/gptel--cache-context-window (model-id cw)
  "Cache CW for MODEL-ID if positive integer. Return CW."
  (when (and (stringp model-id) (not (string-empty-p model-id))
             (my/gptel--positive-integer-p cw))
    (puthash model-id cw my/gptel--context-window-cache))
  cw)

(defun my/gptel--openrouter-entry-context-window (entry)
  "Extract valid context_window from an OpenRouter model ENTRY alist.
Returns (id . context_length) if ENTRY is a plist/alist with a string id
and a positive integer context_length; otherwise returns nil."
  (when (consp entry)
    (let ((id (alist-get 'id entry))
          (cw (alist-get 'context_length entry)))
      (and (stringp id) (not (string-empty-p id)) (integerp cw) (> cw 0)
           (cons id cw)))))

(defun my/gptel--estimate-text-tokens (chars)
  "Estimate text token count from CHARS."
  (if (not (and (numberp chars) (> chars 0)))
      0.0
    (let* ((buf (current-buffer))
           (ext (when (buffer-live-p buf)
                  (let ((fname (buffer-file-name buf)))
                    (and fname (file-name-extension fname)))))
           (cache-key (cons chars ext)))
      (or (gethash cache-key my/gptel--token-estimate-cache)
          (let* ((ratio (cond
                         ((member ext '("el" "clj" "cljs" "py" "js" "ts" "rs" "go" "java" "c" "cpp" "h"))
                          3.0)
                         ((member ext '("md" "txt" "org" "rst" "adoc"))
                          4.0)
                         ((member ext '("json" "yaml" "yml" "toml" "ini"))
                          2.5)
                         (t 3.5)))
                 (result (/ (float chars) ratio)))
            (when (< my/gptel--token-estimate-cache-size
                     my/gptel--token-estimate-cache-max-size)
              (puthash cache-key result my/gptel--token-estimate-cache)
              (cl-incf my/gptel--token-estimate-cache-size))
            result)))))

(defun my/gptel--estimate-tokens (chars)
  "Estimate total token count: text (CHARS) + images in context.

Text estimation uses language-aware heuristics.
Image tokens are counted from `gptel-context' if available.
Returns 0.0 if CHARS is not a positive number."
  (if (not (and (numberp chars) (> chars 0)))
      0.0
    (let ((text-tokens (my/gptel--estimate-text-tokens chars))
          (image-tokens (if (fboundp 'my/gptel--count-context-image-tokens)
                            (my/gptel--count-context-image-tokens)
                          0)))
      (+ text-tokens image-tokens))))

;;; Cache Persistence

(defun my/gptel--cache-save-context-windows ()
  "Save the context-window cache to disk."
  (make-directory (file-name-directory my/gptel-context-window-cache-file) t)
  (condition-case err
      (when (hash-table-p my/gptel--context-window-cache)
        (with-temp-file my/gptel-context-window-cache-file
          (insert ";; Auto-generated; model context windows cache\n")
          (insert (format ";; Updated: %s\n\n" (format-time-string "%Y-%m-%d %H:%M:%S")))
          (insert "(setq my/gptel--context-window-cache-data\n      '")
          (let (alist)
            (maphash (lambda (k v) (push (cons k v) alist)) my/gptel--context-window-cache)
            (prin1 alist (current-buffer)))
          (insert ")\n")
          (insert (format "(setq my/gptel--context-window-cache-last-refresh %S)\n"
                          (float-time (current-time))))))
    (error
     (message "gptel context-window cache: failed to write %s (%s)"
              my/gptel-context-window-cache-file
              (error-message-string err)))))

(defun my/gptel--cache-put-context-window (model-id window)
  "Persist WINDOW for MODEL-ID in the cache."
  (when (and (stringp model-id) (integerp window) (> window 0))
    (puthash model-id window my/gptel--context-window-cache)
    (clrhash my/gptel--alist-partial-match-cache)
    (my/gptel--cache-save-context-windows)))

(defun my/gptel--cache-load-context-windows ()
  "Load cached context windows from `my/gptel-context-window-cache-file'.

Uses transactional loading: loads into a temporary hash table first,
then atomically replaces the main cache. If loading fails, the
existing cache is preserved."
  (when (file-readable-p my/gptel-context-window-cache-file)
    (condition-case err
        (let* ((temp-cache (make-hash-table :test 'equal))
               (temp-data nil)
               (temp-refresh nil)
               (load-file my/gptel-context-window-cache-file))
          (load load-file nil t)
          (when (listp my/gptel--context-window-cache-data)
            (dolist (kv my/gptel--context-window-cache-data)
              (when (consp kv)
                (let ((key (car kv)) (val (cdr kv)))
                  (when (and (stringp key) (my/gptel--positive-integer-p val))
                    (puthash key val temp-cache)))))
            (let ((old-cache my/gptel--context-window-cache)
                  (new-refresh (or my/gptel--context-window-cache-last-refresh
                                   (float-time (current-time)))))
              (setq my/gptel--context-window-cache temp-cache
                    my/gptel--context-window-cache-last-refresh new-refresh
                    my/gptel--context-window-cache-data nil)
              (clrhash my/gptel--alist-partial-match-cache)
              (clrhash old-cache))))
      (error
       (message "gptel context-window cache: failed to load %s (%s)"
                my/gptel-context-window-cache-file
                (error-message-string err))))))

;; Load cache at require time
(my/gptel--cache-load-context-windows)

;;; Seeding and Refresh

(defun my/gptel--gptel-model-tables ()
  "Return list of gptel model table symbols to search.
Filters to only bound variables. Result is cached for performance."
  (or my/gptel--gptel-model-tables-cache
      (setq my/gptel--gptel-model-tables-cache
            (seq-filter #'boundp '(gptel--openai-models gptel--gemini-models gptel--gh-models gptel--anthropic-models)))))

(defun my/gptel--seed-cache-from-gptel-model-tables ()
  "Seed context-window cache from gptel's built-in model tables."
  (dolist (var (my/gptel--gptel-model-tables))
    (let ((table (symbol-value var)))
      (when (listp table)
        (dolist (entry table)
          (when (and (consp entry) (symbolp (car entry)) (plist-member (cdr entry) :context-window))
            (let* ((model (car entry))
                   (plist (cdr entry))
                   (cw (plist-get plist :context-window))
                   (tokens (my/gptel--normalize-context-window cw))
                   (id (my/gptel--model-id-string model)))
              (when (and (stringp id) (integerp tokens) (> tokens 0))
                (puthash id tokens my/gptel--context-window-cache)
                (puthash id plist my/gptel--model-metadata-cache))))))))
  (clrhash my/gptel--alist-partial-match-cache))

(defun my/gptel--openrouter-curl-command (url connect-timeout max-time key)
  "Build curl command list for OpenRouter API request.
URL is the API endpoint, CONNECT-TIMEOUT and MAX-TIME are in seconds,
KEY is the API key for authorization."
  (list "curl"
        "--silent" "--show-error" "--fail"
        "--connect-timeout" (number-to-string (if (numberp connect-timeout) connect-timeout 10))
        "--max-time" (number-to-string (if (numberp max-time) max-time 120))
        "--http1.1"
        "-H" (concat "Authorization: Bearer " key)
        "-H" "Accept: application/json"
        url))

(defun my/gptel--openrouter-fetch-with-callback (url callback &optional process-name connect-timeout max-time)
  "Fetch from OpenRouter API URL and call CALLBACK with parsed JSON data.

URL is the API endpoint.
CALLBACK is a function called with (data) where data is the parsed 'data field.
PROCESS-NAME defaults to \"gptel-openrouter-fetch\".
CONNECT-TIMEOUT and MAX-TIME default to 10 and 120 seconds.

Handles API key lookup, process creation, JSON parsing, and error handling.
Returns nil if curl is unavailable or a fetch is already in flight."
  (condition-case err
      (require 'gptel)
    (error
     (message "OpenRouter: gptel not available (%s)" (error-message-string err))
     nil))
  (let ((process-name (or process-name "gptel-openrouter-fetch"))
        (connect-timeout (or connect-timeout 10))
        (max-time (or max-time 120)))
    (cond
     ((not (stringp url))
      (message "OpenRouter: invalid URL (not a string)")
      nil)
     ((not (executable-find "curl"))
      (message "OpenRouter: curl not found")
      nil)
     (my/gptel--openrouter-context-window-fetch-inflight
      (message "OpenRouter: fetch already in flight, skipping")
      nil)
     (t
      (let* ((key (condition-case err
                      (gptel-api-key-from-auth-source "api.openrouter.com" "api")
                    (error
                     (message "OpenRouter: failed to get API key: %s" (error-message-string err))
                     nil)))
             (buf (generate-new-buffer (format " *%s*" process-name))))
        (if (not (and (stringp key) (not (string-empty-p key))))
            (prog1 nil
              (when (buffer-live-p buf) (kill-buffer buf))
              (message "OpenRouter: no API key found"))
          (setq my/gptel--openrouter-context-window-fetch-inflight t)
          (let* ((cmd (my/gptel--openrouter-curl-command url connect-timeout max-time key))
                 (proc
                  (make-process
                   :name process-name
                   :buffer buf
                   :command cmd
                   :noquery t
                   :connection-type 'pipe
                   :sentinel
                   (lambda (p _event)
                     (setq my/gptel--openrouter-context-window-fetch-inflight nil)
                     (unwind-protect
                         (let ((status (process-exit-status p)))
                           (cond
                            ((and status (= status 0))
                             (with-current-buffer buf
                               (goto-char (point-min))
                               (condition-case err
                                   (let ((obj (json-parse-buffer :object-type 'alist :array-type 'list :null-object nil :false-object nil))
                                         (data (alist-get 'data obj)))
                                     (funcall callback data))
                                 (error
                                  (message "OpenRouter: parse failed (%s)" (error-message-string err))))))
                            ((and status (not (= status 0)))
                             (message "OpenRouter: request failed (exit %d)" status))
                            (t
                             (message "OpenRouter: request terminated abnormally"))))
                       (when (buffer-live-p buf) (kill-buffer buf)))))))
            (process-put proc 'my/gptel-managed t)
            proc)))))))

(cl-defun my/gptel--openrouter-fetch-context-window (&optional model)
  "Fetch context window for MODEL from OpenRouter and cache it.

Runs asynchronously; returns nil immediately."
  (let* ((model-id (my/gptel--model-id-string model))
         (url "https://openrouter.ai/api/v1/models"))
    (cond
     ((or (not (stringp model-id)) (string= model-id "nil"))
      (message "OpenRouter context-window: model not set (gptel-model is nil)")
      nil)
     (t
      (my/gptel--openrouter-fetch-with-callback
       url
       (lambda (data)
         (let* ((valid-data (and (listp data) data))
                (entry (and valid-data
                            (seq-find (lambda (e)
                                        (let ((id (alist-get 'id e)))
                                          (and (stringp id) (string-equal id model-id))))
                                      valid-data)))
                (cw (and entry (alist-get 'context_length entry))))
           (if (and (integerp cw) (> cw 0))
               (progn
                 (my/gptel--cache-put-context-window model-id cw)
                 (message "OpenRouter context-window cached: %s -> %d" model-id cw))
             (message "OpenRouter context-window: model not found or missing context_length: %s" model-id))))
       "gptel-openrouter-models"
       my/gptel-openrouter-models-connect-timeout
       my/gptel-openrouter-models-max-time)
      nil))))

(defun my/gptel--auto-refresh-context-window-cache-maybe ()
  "Refresh context window cache if stale (non-blocking)."
  (when my/gptel-context-window-auto-refresh-enabled
    (let* ((last my/gptel--context-window-cache-last-refresh)
           (age-days (and (numberp last)
                          (/ (- (float-time (current-time)) last) 86400.0)))
           (stale (or (not (numberp age-days))
                      (>= age-days (max 1 my/gptel-context-window-auto-refresh-interval-days)))))
      (when stale
        ;; Seed from built-in tables (Gemini + Copilot) without network.
        (my/gptel--seed-cache-from-gptel-model-tables)
        ;; Fetch OpenRouter in the background when applicable.
        ;; NOTE: Cache persistence happens in the async callback, not here.
        (if (and (boundp 'gptel--openrouter)
                 (eq gptel-backend gptel--openrouter))
            (my/gptel--openrouter-fetch-context-window gptel-model)
          (my/gptel--cache-save-context-windows))))))

(defun my/gptel-refresh-context-window-cache ()
  "Refresh (fetch) the current model's context window into the cache."
  (interactive)
  (require 'gptel)
  (when (boundp 'gptel--openrouter)
    (my/gptel--openrouter-fetch-context-window gptel-model)))

(defun my/gptel-fetch-all-model-metadata ()
  "Fetch ALL model metadata from OpenRouter and cache it.
Run asynchronously. Use for bulk cache warming."
  (interactive)
  (let ((url "https://openrouter.ai/api/v1/models"))
    (when (my/gptel--openrouter-fetch-with-callback
           url
           (lambda (data)
             (let* ((valid-data (and (listp data) data))
                    (results (cl-loop for entry in valid-data
                                      for res = (my/gptel--openrouter-entry-context-window entry)
                                      when res collect res))
                    (count (length results)))
               (dolist (r results)
                 (puthash (car r) (cdr r) my/gptel--context-window-cache))
               (when (> count 0)
                 (my/gptel--cache-save-context-windows))
               (message "OpenRouter: cached %d models" count)))
           "gptel-openrouter-all-models"
           10
           120)
      (message "OpenRouter: fetching all models..."))))

(defun my/gptel-get-model-metadata (model-id)
  "Get metadata for MODEL-ID from cache.
Returns plist with :context-window, :pricing-input, :pricing-output, etc."
  (when model-id
    (require 'gptel)
    (let* ((model-id-str (cond
                          ((stringp model-id) model-id)
                          ((symbolp model-id) (symbol-name model-id))
                          (t (format "%S" model-id))))
           (model-id-str (string-trim model-id-str)))
      (when (and (stringp model-id-str) (not (string-empty-p model-id-str)))
        (my/gptel--cache-or-alist-lookup my/gptel--model-metadata-cache
                                         my/gptel--known-model-metadata
                                         model-id-str)))))

(defun my/gptel-show-model-info (model-id)
  "Show detailed info for MODEL-ID."
  (interactive
   (list (completing-read "Model: "
                          (hash-table-keys my/gptel--model-metadata-cache)
                          nil nil
                          (my/gptel--model-id-string gptel-model))))
  (let* ((meta (my/gptel-get-model-metadata model-id))
         (ctx (my/gptel--plist-get meta :context-window "unknown"))
         (pi (my/gptel--plist-get meta :pricing-input 0))
         (po (my/gptel--plist-get meta :pricing-output 0))
         (max-out (my/gptel--plist-get meta :max-output "unknown"))
         (desc (my/gptel--plist-get meta :description "N/A")))
    (message "Model: %s
Context: %s tokens
Pricing: $%.4f/$%.4f per 1M (in/out)
Max Output: %s
Description: %s"
             model-id
             ctx
             pi po
             max-out
             desc)))

;;; Provider Usage Contracts
;; Documentation of rate limits, pricing tiers, and feature constraints per provider

(defvar my/gptel-provider-contracts
  '((openrouter
     :description "OpenRouter - unified API for 300+ models"
     :rate-limit "Varies by provider, generally 200-500 req/min"
     :pricing-model "Per-model, passthrough pricing"
     :features (streaming tools reasoning)
     :notes "Use --http1.1 for curl, some models support reasoning tokens")

    (dashscope
     :description "Alibaba DashScope - Qwen, GLM models"
     :rate-limit "60 req/min (free tier), higher for paid"
     :pricing-model "Per-model, tiered by context length"
     :features (streaming tools reasoning)
     :notes "Qwen3.5-Plus has 1M context. Reasoning models need streaming or fast response."
     :context-windows
     ((qwen3-coder-next . 131072)
      (qwen3-coder-plus . 1000000)
      (qwen3.5-plus . 1000000)
      (qwen3.5-flash . 1000000)
      (qwen3-max-2026-01-23 . 262144)
      (glm-5 . 131072)
      (glm-4.7 . 131072)))

    (deepseek
     :description "DeepSeek - V4 Flash and V4 Pro models"
     :rate-limit "Varies, check dashboard"
     :pricing-model "Per-token, Flash low-cost and Pro premium"
     :features (streaming tools reasoning)
     :notes "Both V4 models support 1M context, 384K output, and thinking mode"
     :context-windows
     ((deepseek-v4-flash . 1000000)
      (deepseek-v4-pro . 1000000)))

    (moonshot
     :description "Moonshot AI - Kimi models"
     :rate-limit "Varies by tier"
     :pricing-model "Per-token, K2.5 competitive"
     :features (streaming tools reasoning)
     :notes "K2.5 supports high reasoning effort. Use :thinking enabled."
     :context-windows
     ((kimi-k2.5 . 131072)))

    (openai
     :description "OpenAI - GPT series"
     :rate-limit "Tier-based: Free 3/min, Tier1 500/min, Tier2 5000/min"
     :pricing-model "Per-token, GPT-4o cheaper than GPT-4"
     :features (streaming tools vision)
     :notes "GPT-4o: 128k context. GPT-4: 8k or 32k."
     :context-windows
     ((gpt-4o . 128000)
      (gpt-4o-mini . 128000)
      (gpt-4 . 8192)))

    (anthropic
     :description "Anthropic - Claude series"
     :rate-limit "Tier-based, see console"
     :pricing-model "Per-token, Sonnet cheaper than Opus"
     :features (streaming tools vision)
     :notes "Claude 4: 200k context. Use prompt caching for long context."
     :context-windows
     ((claude-4 . 200000)
      (claude-sonnet-4 . 200000)))

    (google
     :description "Google AI - Gemini series"
     :rate-limit "15 RPM (free), 2000 RPM (paid)"
     :pricing-model "Per-token, Flash much cheaper than Pro"
     :features (streaming tools vision)
     :notes "Gemini 1.5/2.5: 1M context! Flash is fastest/cheapest."
     :context-windows
     ((gemini-2.5-pro . 1048576)
      (gemini-2.5-flash . 1048576)))

    (minimax
     :description "MiniMax - M2.x models"
     :rate-limit "Check console"
     :pricing-model "Per-token, competitive pricing"
     :features (streaming tools)
     :notes "M2.5/M2.7/M2.7-highspeed: 196k context. Highspeed favors lower-latency agent workflows."
     :context-windows
     ((minimax-m2.7-highspeed . 196608)
      (minimax-m2.7 . 196608))))

  "Provider usage contracts: rate limits, pricing models, features, and notes.
Use `my/gptel-show-provider-contract' to query.")

(defun my/gptel-show-provider-contract (provider)
  "Show usage contract for PROVIDER."
  (interactive
   (list (completing-read "Provider: "
                          (mapcar #'car my/gptel-provider-contracts)
                          nil t)))
  (let* ((contract (alist-get (if (stringp provider) (intern provider) provider)
                              my/gptel-provider-contracts))
         (desc (my/gptel--plist-get contract :description "N/A"))
         (rate (my/gptel--plist-get contract :rate-limit "Unknown"))
         (pricing (my/gptel--plist-get contract :pricing-model "Unknown"))
         (features (my/gptel--plist-get contract :features nil))
         (notes (my/gptel--plist-get contract :notes "None"))
         (ctx-windows (my/gptel--plist-get contract :context-windows nil)))
    (with-output-to-temp-buffer "*gptel-provider-contract*"
      (princ (format "Provider: %s\n\n" provider))
      (princ (format "Description: %s\n" desc))
      (princ (format "Rate Limit: %s\n" rate))
      (princ (format "Pricing: %s\n" pricing))
      (princ (format "Features: %s\n" (or (and features (mapconcat #'symbol-name features " ")) "Unknown")))
      (princ (format "\nNotes:\n%s\n" notes))
      (when ctx-windows
        (princ "\nKnown Context Windows:\n")
        (dolist (cw ctx-windows)
          (princ (format "  %s: %d tokens\n" (car cw) (cdr cw))))))))

;;; Public Query API

(defun my/gptel--context-window ()
  "Return model context window if available, else fall back to defaults.

Fallback order:
1. Cached context window for model-id (with known-model alist fallback)
2. gptel model tables (OpenAI, Gemini, etc.) - cached for future lookups
3. Known model metadata (from cache or known list)
4. my/gptel-default-context-window (128k default)

Note: We do NOT use gptel-max-tokens as it's for response length, not context window.
Note: OpenRouter fetch is NOT triggered here - use `my/gptel-refresh-context-window-cache'."
  (require 'gptel)
  (let ((model-id (my/gptel--model-id-string gptel-model)))
    (cond
     ((or (string= model-id "nil") (string-empty-p model-id)) my/gptel-default-context-window)
     ((my/gptel--cache-or-alist-lookup my/gptel--context-window-cache
                                       my/gptel--known-model-context-windows
                                       model-id))
     ((let ((cw (my/gptel--lookup-context-window-in-gptel-tables gptel-model)))
        (when (my/gptel--positive-integer-p cw)
          (my/gptel--cache-context-window model-id cw))))
     ((let* ((meta (my/gptel-get-model-metadata model-id))
             (cw (my/gptel--plist-get meta :context-window)))
        (when (my/gptel--positive-integer-p cw)
          (my/gptel--cache-context-window model-id cw))))
     (t my/gptel-default-context-window))))

;;; Auto-refresh Timer

;; Schedule the background context-window cache refresh after gptel loads.
(with-eval-after-load 'gptel
  (run-with-idle-timer my/gptel-context-window-auto-refresh-idle-seconds nil
                       #'my/gptel--auto-refresh-context-window-cache-maybe))

;;; Footer

(provide 'gptel-ext-context-cache)
;;; gptel-ext-context-cache.el ends here
