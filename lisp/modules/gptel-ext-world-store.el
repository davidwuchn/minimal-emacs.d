;;; gptel-ext-world-store.el --- Elisp bridge to OV5 World Store -*- lexical-binding: t -*-

;; Copyright (C) 2026 David Wu

;; Author: David Wu
;; Keywords: data, database, datalog
;; Version: 0.1.0

;;; Commentary:

;; Bridge between Emacs and the OV5 World Store (Datahike via brepl).
;; Provides functions to connect, transact, query, and inspect entities.

;; Requires:
;; - babashka (bb) installed
;; - brepl (~/.local/bin/brepl) for nREPL communication
;; - Datahike pod (configured in bb.edn)

;;; Code:

;; Soft-require query module for cache-invalidation advice (no error if absent)
(require 'gptel-ext-world-store-query nil t)
(require 'gptel-ext-brepl nil t)

;; Soft-require nrepl-client from cider for persistent nREPL connection path.
;; Ensure cider and its dependencies are on load-path before requiring.
(eval-and-compile
  (dolist (dir '("var/elpa/cider-1.21.0"
                 "var/elpa/queue-0.2"
                 "var/elpa/sesman-0.3.2"
                 "var/elpa/clojure-mode-5.23.0"))
    (let ((full (expand-file-name dir user-emacs-directory)))
      (when (and (file-directory-p full)
                 (not (member full load-path)))
        (add-to-list 'load-path full)))))
(require 'nrepl-client nil t)

;; -----------------------------------------------------------------------------
;; Customization

(defgroup ov5-world-store nil
  "OV5 World Store configuration."
  :group 'gptel)

(defcustom ov5-world-store-directory
  (expand-file-name
   "var/world-store"
   ;; pre-early-init.el redirects user-emacs-directory to <root>/var/ so
   ;; Emacs's generated files stay out of the repo root.  Derive the actual
   ;; project root (parent of that var/ dir); appending "var/world-store"
   ;; directly onto user-emacs-directory would produce <root>/var/var/world-store
   ;; and mismatch the babashka pipeline's <root>/var/world-store path, causing
   ;; Datahike "Store identity mismatch" and zero recorded experiments.
   (file-name-directory (directory-file-name user-emacs-directory)))
  "Directory for the World Store database files."
  :type 'directory
  :group 'ov5-world-store)

(defcustom ov5-world-store-nrepl-port
  nil
  "Port of the running bb nREPL server.
If nil, auto-detect via .nrepl-port file."
  :type '(choice (const :tag "Auto-detect" nil)
                 (integer :tag "Port number"))
  :group 'ov5-world-store)

;; -----------------------------------------------------------------------------
;; State

(defvar ov5-world-store--nrepl-process nil
  "Process handle for the bb nREPL server.")

(defvar ov5-world-store--connected nil
  "Non-nil when connected to the World Store.")

(defvar ov5-world-store--nrepl-client-buffer nil
  "Buffer for the persistent nREPL client connection.
Set to nil when the client disconnects or initialization fails.")

(defvar ov5-world-store--persistent-nrepl-available nil
  "Non-nil when a persistent nREPL client is connected and can be used.
Falls back to CLI brepl when nil.")

;; -----------------------------------------------------------------------------
;; Helpers

(defun ov5-world-store--nrepl-port ()
  "Return the nREPL port, auto-detecting if necessary."
  (or ov5-world-store-nrepl-port
      (let ((port-file ".nrepl-port"))
        (when (file-exists-p port-file)
          (string-to-number (string-trim
                             (with-temp-buffer
                               (insert-file-contents port-file)
                               (buffer-string))))))
      7888))  ;; default bb nREPL port

(defvar ov5-world-store--datahike-pod-available nil
  "Cached result of Datahike pod availability check.")

(defun ov5-world-store--datahike-pod-available-p ()
  "Return non-nil if the Datahike pod can be loaded by bb.
Caches the result in `ov5-world-store--datahike-pod-available'.
Uses `bb -e' to load the pod declared in bb.edn."
  (unless (booleanp ov5-world-store--datahike-pod-available)
    (setq ov5-world-store--datahike-pod-available
          (condition-case nil
              (zerop (call-process "bb" nil nil nil
                                   "-e"
                                   "(require '[babashka.pods :as pods]) (pods/load-pod 'replikativ/datahike \"0.8.1697\")"))
            (error nil))))
  ov5-world-store--datahike-pod-available)

(defun ov5-world-store--ensure-nrepl ()
  "Ensure bb nREPL server is running. Start if not.
Also establish or reconnect the persistent nREPL client connection.
Returns non-nil if the nREPL server is live."
  (if (ov5-world-store--datahike-pod-available-p)
      (progn
        (unless (and ov5-world-store--nrepl-process
                     (process-live-p ov5-world-store--nrepl-process))
          (let ((port (ov5-world-store--nrepl-port)))
            (message "[world-store] Starting bb nREPL server on port %d..." port)
            ;; --init clj/ov5/world_store.clj ensures the query namespace is loaded
            ;; on the server side.  Without this, (ns ov5.world-store.query) in
            ;; eval forms fails because the server's classpath doesn't auto-load
            ;; source files when switching namespaces.
            ;;
            ;; IMPORTANT: --init must come BEFORE the nrepl-server subcommand
            ;; (it's a global bb flag, not a subcommand arg).
            (setq ov5-world-store--nrepl-process
                  (start-process "bb-nrepl" "*bb-nrepl*"
                                "bb" "--init" "clj/ov5/world_store.clj"
                                "nrepl-server" (format "%d" port)))
            ;; --init loads world_store.clj (~1.5k lines, ~5s on cold start).
            ;; Old value (2s) was enough for nrepl-server but not for --init.
            (sleep-for 8)  ;; Give server time to start AND load --init file
            (if (process-live-p ov5-world-store--nrepl-process)
                (message "[world-store] nREPL server started")
              (message "[world-store] nREPL server died (Datahike pod?)")
              (setq ov5-world-store--nrepl-process nil))))
        ;; Reconnect persistent nREPL client if server is live but client is not
        (when (and ov5-world-store--nrepl-process
                   (process-live-p ov5-world-store--nrepl-process)
                   (not (and ov5-world-store--persistent-nrepl-available
                             ov5-world-store--nrepl-client-buffer
                             (buffer-live-p ov5-world-store--nrepl-client-buffer))))
          (ov5-world-store--init-persistent-nrepl))
        (and ov5-world-store--nrepl-process
             (process-live-p ov5-world-store--nrepl-process)))
    (message "[world-store] Datahike pod unavailable; nREPL not started")
    nil))

;; ── Persistent nREPL Client ──

(defun ov5-world-store--init-persistent-nrepl ()
  "Establish a persistent nREPL client connection to the bb nREPL server.
Uses low-level `nrepl-connect' to avoid the `nrepl-start-client-process'
dependency chain (which requires `cider-version' and session-clone support).
On failure, leaves persistent state nil and logs a message — callers will
fall back to the CLI brepl path."
  (when (and (featurep 'nrepl-client)
             (fboundp 'nrepl-connect))
    (condition-case err
        (let* ((port (ov5-world-store--nrepl-port))
               (endpoint (nrepl-connect "localhost" port))
               (client-proc (plist-get endpoint :proc))
               (client-buf (generate-new-buffer " *ov5-nrepl-client*")))
          ;; Set up the process buffer
          (set-process-buffer client-proc client-buf)
          (set-process-filter client-proc #'nrepl-client-filter)
          (set-process-sentinel client-proc
            (lambda (proc _msg)
              (when (memq (process-status proc) '(exit signal closed failed))
                (setq ov5-world-store--nrepl-client-buffer nil
                      ov5-world-store--persistent-nrepl-available nil)
                (message "[world-store] Persistent nREPL client disconnected"))))
          (set-process-coding-system client-proc 'utf-8-unix 'utf-8-unix)
          ;; Process properties required by nrepl-client-filter / nrepl-bdecode
          (process-put client-proc :string-q (queue-create))
          (process-put client-proc :response-q (nrepl-response-queue))
          ;; Initialize buffer-local state needed by nrepl-send-request
          (with-current-buffer client-buf
            (setq nrepl-endpoint endpoint
                  nrepl-pending-requests (make-hash-table :test 'equal)
                  nrepl-completed-requests (make-hash-table :test 'equal)))
          (setq ov5-world-store--nrepl-client-buffer client-buf
                ov5-world-store--persistent-nrepl-available t)
          (message "[world-store] Persistent nREPL client connected on port %d" port))
      (error
       (when (and ov5-world-store--nrepl-client-buffer
                  (buffer-live-p ov5-world-store--nrepl-client-buffer))
         (kill-buffer ov5-world-store--nrepl-client-buffer))
       (setq ov5-world-store--nrepl-client-buffer nil
             ov5-world-store--persistent-nrepl-available nil)
       (message "[world-store] Persistent nREPL client unavailable: %s"
                (error-message-string err))))))

(define-error 'ov5-world-store--nrepl-eval-error
  "nREPL eval failed" 'error)

(defun ov5-world-store--persistent-nrepl-eval (code)
  "Evaluate Clojure CODE via the persistent nREPL client.
Returns the eval result as a trimmed string, consistent with the brepl CLI
output format.  Signals an error on any failure — the caller
(`ov5-world-store--brepl-eval') catches it and falls back to CLI brepl."
  (let* ((conn-buf ov5-world-store--nrepl-client-buffer)
         ;; Tight timeout for the hot path (CLI brepl takes ~265ms)
         (nrepl-sync-request-timeout 5)
         (response
          (condition-case inner-err
              (nrepl-send-sync-request
               `("op" "eval" "code" ,code)
               conn-buf)
            (error
             (signal 'ov5-world-store--nrepl-eval-error
                     (list (error-message-string inner-err)))))))
    ;; nil response means sync request timed out or was aborted
    (unless response
      (signal 'ov5-world-store--nrepl-eval-error
              (list "Sync request returned nil (connection lost or timed out)")))
    ;; Extract result from the nREPL response dict
    (let ((val (nrepl-dict-get response "value"))
          (out (nrepl-dict-get response "out"))
          (err (nrepl-dict-get response "err"))
          (ex  (nrepl-dict-get response "ex")))
      (cond
       (val
        ;; nREPL concatenates return values of all top-level forms.
        ;; Every world-store eval starts with (ns ov5.world-store) which
        ;; returns nil, so the value string begins with "nil".  Strip all
        ;; leading "nil" prefixes to get the actual result.
        (let ((v (string-trim val)))
          (while (string-prefix-p "nil" v)
            (setq v (substring v 3)))
          (let ((result (string-trim v)))
            ;; When the value is empty (only nil returns from ns/aborted
            ;; forms) AND an exception or error is present, the eval
            ;; actually failed — signal instead of returning "".
            (if (and (string-empty-p result)
                     (or ex err))
                (signal 'ov5-world-store--nrepl-eval-error
                        (list (format "nREPL eval error: %s"
                                      (or (and ex (string-trim ex))
                                          (and err (string-trim err))
                                          "unknown"))))
              result))))
       (out (let* ((s (string-trim out))
                   (lines (split-string s "\n" t)))
              (car (last lines))))
       (ex  (signal 'ov5-world-store--nrepl-eval-error
                    (list (format "nREPL eval exception: %s" (string-trim ex)))))
       (err (signal 'ov5-world-store--nrepl-eval-error
                    (list (format "nREPL eval error: %s" (string-trim err)))))
       (t   (signal 'ov5-world-store--nrepl-eval-error
                    (list "nREPL eval returned empty response")))))))

;; ── Primary eval dispatcher ──

(defun ov5-world-store--brepl-eval (code)
  "Evaluate Clojure CODE via the fastest available nREPL path.
Prefer the persistent nREPL client connection; fall back to CLI brepl
on failure.  Return the result string or nil if unavailable."
  (when (ov5-world-store--ensure-nrepl)
    (condition-case nil
        (if (and ov5-world-store--persistent-nrepl-available
                 ov5-world-store--nrepl-client-buffer
                 (buffer-live-p ov5-world-store--nrepl-client-buffer))
            (condition-case err
                (ov5-world-store--persistent-nrepl-eval code)
              (ov5-world-store--nrepl-eval-error
               (message "[world-store] Persistent nREPL eval failed, falling back: %s"
                        (error-message-string err))
               (setq ov5-world-store--persistent-nrepl-available nil)
               (ov5-world-store--brepl-eval-fallback code)))
          (ov5-world-store--brepl-eval-fallback code))
      (error nil))))

(defun ov5-world-store--brepl-eval-fallback (code)
  "Evaluate Clojure CODE via CLI brepl or shell-command.
This is the existing fallback path extracted from the original
`ov5-world-store--brepl-eval' (preserves behavior unchanged)."
  (cond
   ((fboundp 'gptel-brepl-eval)
    (let ((result (gptel-brepl-eval code)))
      (if (plist-get result :success)
          (let* ((stdout (string-trim (or (plist-get result :result) "")))
                 (lines (split-string stdout "\n" t)))
            (car (last lines)))
        (error "%s" (or (plist-get result :error) "brepl eval failed")))))
    (t
     (let* ((port (ov5-world-store--nrepl-port))
            (tmpfile (make-temp-file "ov5-brepl-"))
            (output nil))
       (with-temp-file tmpfile
         (insert code))
       (unwind-protect
           (setq output (shell-command-to-string
                         (format "BREPL_PORT=%d brepl < %s" port tmpfile)))
         (delete-file tmpfile))
       (let ((lines (split-string output "\n" t)))
         (car (last lines)))))))

;; -----------------------------------------------------------------------------
;; Connection

;;;###autoload
(defun ov5-world-store-connect ()
  "Connect to the World Store. Starts nREPL if needed."
  (interactive)
  (if (ov5-world-store--ensure-nrepl)
      (let ((result (ov5-world-store--brepl-eval
                     (format "(load-file \"clj/ov5/world_store.clj\") (ns ov5.world-store) (connect \"%s\")"
                             ov5-world-store-directory))))
        (setq ov5-world-store--connected t)
        (message "[world-store] Connected: %s" result)
        t)
    (setq ov5-world-store--connected 'unavailable)
    (message "[world-store] Cannot connect: nREPL server not available")
    nil))

;;;###autoload
(defun ov5-world-store-disconnect ()
  "Disconnect from the World Store."
  (interactive)
  (ov5-world-store--brepl-eval "(ns ov5.world-store) (disconnect)")
  (setq ov5-world-store--connected nil)
  (when ov5-world-store--nrepl-process
    (delete-process ov5-world-store--nrepl-process)
    (setq ov5-world-store--nrepl-process nil))
  (message "[world-store] Disconnected"))

(defun ov5-world-store-connected-p ()
  "Return non-nil if connected to the World Store."
  (eq ov5-world-store--connected t))

;; -----------------------------------------------------------------------------
;; CRUD

(defun ov5-world-store-transact (data)
  "Transact DATA into the store.
DATA is an Elisp list of plists, each representing an entity map.
Example: \='((:experiment/id \"exp-001\" :experiment/target \"foo.el\"))"
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (let* ((edn (ov5-world-store--plist-to-edn data))
         (code (format "(ns ov5.world-store) (transact %s)" edn)))
    (ov5-world-store--brepl-eval code)))

(defun ov5-world-store--invalidate-query-cache-after-transact (&rest _)
  "Invalidate the query cache after a successful transact."
  (when (fboundp 'world-store-query-invalidate-cache)
    (world-store-query-invalidate-cache)))

(advice-add 'ov5-world-store-transact :after
            #'ov5-world-store--invalidate-query-cache-after-transact)

(defun ov5-world-store--plist-to-edn (data)
  "Convert Elisp plist DATA to EDN string."
  (cond
   ((null data) "nil")
   ((stringp data) (format "%S" data))
   ((numberp data) (number-to-string data))
   ((symbolp data) (symbol-name data))
   ((listp data)
    (if (keywordp (car data))
        ;; It's a plist → convert to EDN map
        (let ((pairs '()))
          (while data
            (let ((key (car data))
                  (val (cadr data)))
              (push (format "%s %s" (ov5-world-store--plist-to-edn key)
                           (ov5-world-store--plist-to-edn val)) pairs)
              (setq data (cddr data))))
          (concat "{" (mapconcat #'identity (nreverse pairs) " ") "}"))
      ;; It's a list of things → convert each element
      (concat "[" (mapconcat #'ov5-world-store--plist-to-edn data " ") "]")))
   (t (format "%S" data))))

(defun ov5-world-store-query (q &rest args)
  "Execute Datalog query Q against the store.
Q is a string containing the Datalog query.
Example: \"[:find ?e :where [?e :name \\\"Alice\\\"]]\"
Optional ARGS are additional query inputs."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (let* ((args-edn (if args
                      (mapconcat (lambda (a) (format "%S" a)) args " ")
                      ""))
         (code (if args
                  (format "(ns ov5.world-store) (query '%s %s)" q args-edn)
                 (format "(ns ov5.world-store) (query '%s)" q))))
    (ov5-world-store--brepl-eval code)))

(defun ov5-world-store-entity (attr val)
  "Look up entity by ATTR and VAL.
Example: (ov5-world-store-entity :experiment/id \"exp-001\")"
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (let ((code (format "(ns ov5.world-store) (entity %S %S)" attr val)))
    (ov5-world-store--brepl-eval code)))

;; -----------------------------------------------------------------------------
;; Convenience

(defun ov5-world-store-experiment-count ()
  "Return the total number of experiments in the store."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (let ((result (ov5-world-store--brepl-eval
                 "(ns ov5.world-store) (experiment-count)")))
    (string-to-number result)))

(defun ov5-world-store-experiments-by-target (target)
  "Return all experiments for TARGET path."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store--brepl-eval
   (format "(ns ov5.world-store) (experiments-by-target %S)" target)))

(defun ov5-world-store-experiments-by-backend (backend)
  "Return all experiments for BACKEND name."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store--brepl-eval
   (format "(ns ov5.world-store) (experiments-by-backend %S)" backend)))

(defun ov5-world-store-backend-keep-rate (backend)
  "Return keep rate for BACKEND as a float."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (let ((result (ov5-world-store--brepl-eval
                 (format "(ns ov5.world-store) (backend-keep-rate %S)" backend))))
    (string-to-number result)))

;; -----------------------------------------------------------------------------
;; Cleanup

(defun ov5-world-store-cleanup ()
  "Clean up resources. Disconnect persistent nREPL client, store, and server."
  ;; Disconnect from the store first (uses remaining nREPL path)
  (condition-case nil (ov5-world-store-disconnect) (error nil))
  ;; Tear down persistent nREPL client
  (when (and ov5-world-store--nrepl-client-buffer
             (buffer-live-p ov5-world-store--nrepl-client-buffer))
    (let ((proc (get-buffer-process ov5-world-store--nrepl-client-buffer)))
      (when (and proc (process-live-p proc))
        (delete-process proc)))
    (kill-buffer ov5-world-store--nrepl-client-buffer))
  (setq ov5-world-store--nrepl-client-buffer nil
        ov5-world-store--persistent-nrepl-available nil))

(add-hook 'kill-emacs-hook #'ov5-world-store-cleanup)

(provide 'gptel-ext-world-store)

;;; gptel-ext-world-store.el ends here
