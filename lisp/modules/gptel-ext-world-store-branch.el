;;; gptel-ext-world-store-branch.el --- Elisp bridge to OV5 World Store branching -*- lexical-binding: t -*-

;; Copyright (C) 2026 David Wu

;; Author: David Wu
;; Keywords: data, database, branch
;; Version: 0.1.0

;;; Commentary:

;; Elisp bridge wrapping Clojure branch functions from clj/ov5/world_store/branch.clj
;; via the brepl/nREPL dispatcher in gptel-ext-world-store.el.
;;
;; Branch layout:
;;   var/world-store/main/            — main store DB
;;   var/world-store/branches/<id>/   — branch DBs
;;   var/world-store/branch-registry.edn — branch metadata
;;
;; All functions are fboundp-guarded by consumers so the workflow continues
;; normally when the World Store is unavailable.

;;; Code:

;; Soft-require the parent bridge (no error if absent)
(require 'gptel-ext-world-store nil t)

;; -----------------------------------------------------------------------------
;; Internal helpers

(defun ov5-world-store-branch--set-directory ()
  "Set the JVM system property so Clojure branch functions find the store root.
   Must be called before any branch operation via nREPL."
  (ov5-world-store--brepl-eval
   (format "(System/setProperty \"ov5.world-store.directory\" \"%s\")"
           ov5-world-store-directory)))

(defun ov5-world-store-branch--call (fn-name &rest args)
  "Call a Clojure branch function FN-NAME with ARGS via brepl.
   Ensures the store directory property is set and the branch namespace loaded.
   Returns the result string or signals an error."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  ;; Set the directory property before calling branch functions
  (ov5-world-store-branch--set-directory)
  ;; Build the eval code: ensure namespace, call function
  (let* ((args-str (mapconcat
                    (lambda (a)
                      (cond
                       ((null a) "nil")
                       ((stringp a) (format "%S" a))
                       ((numberp a) (number-to-string a))
                       (t (format "%s" a))))
                    args " "))
         (code (format "(ns ov5.world-store.branch) (%s %s)" fn-name args-str)))
    (ov5-world-store--brepl-eval code)))

;; -----------------------------------------------------------------------------
;; Public API

;;;###autoload
(defun ov5-world-store-branch-create (branch-id &optional parent-branch metadata)
  "Create a new World Store branch named BRANCH-ID.
PARENT-BRANCH defaults to \"main\".
METADATA is an optional plist merged into the registry entry.
Returns t on success, signals error on failure."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (let* ((parent (or parent-branch "main"))
         (meta-edn (if metadata
                       (ov5-world-store--plist-to-edn metadata)
                     "nil"))
         (code (format
                "(ns ov5.world-store.branch)
                 (or (create-branch \"%s\" \"%s\" %s)
                     (throw (Exception. \"Branch creation failed\")))"
                branch-id parent meta-edn)))
    (ov5-world-store--brepl-eval code))
  t)

;;;###autoload
(defun ov5-world-store-branch-switch (branch-id)
  "Switch the active World Store connection to BRANCH-ID.
Returns BRANCH-ID on success."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (let ((code (format
               "(ns ov5.world-store.branch)
                (or (switch-branch \"%s\")
                    (throw (Exception. \"Branch switch failed\")))"
               branch-id)))
    (ov5-world-store--brepl-eval code))
  branch-id)

;;;###autoload
(defun ov5-world-store-branch-merge (source-branch target-branch)
  "Merge SOURCE-BRANCH experiment data into TARGET-BRANCH.
Returns the count of new entities transacted (number)."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (let* ((code (format
                "(ns ov5.world-store.branch)
                 (merge-branch \"%s\" \"%s\")"
                source-branch target-branch))
         (result (ov5-world-store--brepl-eval code)))
    (string-to-number (or result "0"))))

;;;###autoload
(defun ov5-world-store-branch-promote (branch-id)
  "Promote BRANCH-ID to become the new main branch.
Old main is archived as main-@<timestamp>.
Returns t on success."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (let ((code (format
               "(ns ov5.world-store.branch)
                (or (promote-branch \"%s\")
                    (throw (Exception. \"Branch promotion failed\")))"
               branch-id)))
    (ov5-world-store--brepl-eval code))
  t)

;;;###autoload
(defun ov5-world-store-branch-list ()
  "Return the branch registry as an EDN string (map of branch-id -> metadata)."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (ov5-world-store--brepl-eval
   "(ns ov5.world-store.branch) (list-branches)"))

;;;###autoload
(defun ov5-world-store-branch-delete (branch-id)
  "Delete BRANCH-ID. Refuses to delete \"main\".
Returns t on success."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (let ((code (format
               "(ns ov5.world-store.branch)
                (or (delete-branch \"%s\")
                    (throw (Exception. \"Branch delete failed\")))"
               branch-id)))
    (ov5-world-store--brepl-eval code))
  t)

;;;###autoload
(defun ov5-world-store-branch-current ()
  "Return the current branch-id string, or nil."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (let ((result (ov5-world-store--brepl-eval
                 "(ns ov5.world-store.branch) (current-branch)")))
    (when (and result (not (string= result "nil")))
      result)))

;;;###autoload
(defun ov5-world-store-branch-ensure-main ()
  "Idempotently ensure the main branch exists in the registry.
Handles auto-migration of old flat store into main/ subdirectory.
Returns t on success."
  (unless ov5-world-store--connected
    (ov5-world-store-connect))
  (ov5-world-store-branch--set-directory)
  (ov5-world-store--brepl-eval
   "(ns ov5.world-store.branch) (branch-ensure-main)")
  t)

(provide 'gptel-ext-world-store-branch)

;;; gptel-ext-world-store-branch.el ends here
