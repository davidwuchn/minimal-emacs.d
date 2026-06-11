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

;; -----------------------------------------------------------------------------
;; Customization

(defgroup ov5-world-store nil
  "OV5 World Store configuration."
  :group 'gptel)

(defcustom ov5-world-store-directory
  (expand-file-name "var/world-store" user-emacs-directory)
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

(defun ov5-world-store--ensure-nrepl ()
  "Ensure bb nREPL server is running. Start if not."
  (unless (and ov5-world-store--nrepl-process
               (process-live-p ov5-world-store--nrepl-process))
    (let ((port (ov5-world-store--nrepl-port)))
      (message "[world-store] Starting bb nREPL server on port %d..." port)
      (setq ov5-world-store--nrepl-process
            (start-process "bb-nrepl" "*bb-nrepl*"
                           "bb" "nrepl-server" (format "%d" port)))
      (sleep-for 2)  ;; Give server time to start
      (message "[world-store] nREPL server started"))))

(defun ov5-world-store--brepl-eval (code)
  "Evaluate Clojure CODE via brepl. Return parsed result or signal error."
  (ov5-world-store--ensure-nrepl)
  (let* ((port (ov5-world-store--nrepl-port))
         (tmpfile (make-temp-file "ov5-brepl-"))
         (output nil))
    (with-temp-file tmpfile
      (insert code))
    (setq output (shell-command-to-string
                  (format "BREPL_PORT=%d brepl < %s" port tmpfile)))
    (delete-file tmpfile)
    ;; brepl returns EDN; return the last non-empty line
    (let ((lines (split-string output "\n" t)))
      (car (last lines)))))

;; -----------------------------------------------------------------------------
;; Connection

;;;###autoload
(defun ov5-world-store-connect ()
  "Connect to the World Store. Starts nREPL if needed."
  (interactive)
  (ov5-world-store--ensure-nrepl)
  (let ((result (ov5-world-store--brepl-eval
                 (format "(load-file \"clj/ov5/world_store.clj\") (ns ov5.world-store) (connect \"%s\")"
                         ov5-world-store-directory))))
    (setq ov5-world-store--connected t)
    (message "[world-store] Connected: %s" result)
    t))

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
  ov5-world-store--connected)

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
  "Clean up resources. Disconnect and stop nREPL."
  (ov5-world-store-disconnect))

(add-hook 'kill-emacs-hook #'ov5-world-store-cleanup)

(provide 'gptel-ext-world-store)

;;; gptel-ext-world-store.el ends here
