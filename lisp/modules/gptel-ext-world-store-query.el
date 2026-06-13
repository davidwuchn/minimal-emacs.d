;;; gptel-ext-world-store-query.el --- OV5 World Store query bridge -*- lexical-binding: t -*-

;; Copyright (C) 2026 David Wu

;; Author: David Wu
;; Keywords: data, database, query, datalog
;; Version: 0.1.0

;;; Commentary:

;; Query bridge between Emacs and the OV5 World Store (Datahike via brepl).
;; Provides in-Emacs caching, a TSV-fallback wrapper, and convenience
;; query functions for the ontology-router and ontology-predict hot paths.
;;
;; Design: uses declare-function + fboundp guards instead of hard-requiring
;; gptel-ext-world-store, avoiding a load-cycle with the bridge's soft-require
;; of this module.  The bridge is always loaded before any caller.

;;; Code:

;; ── Compile-time bridge declarations (no hard require) ──
(eval-when-compile
  (declare-function ov5-world-store--brepl-eval "gptel-ext-world-store")
  (declare-function ov5-world-store-connected-p "gptel-ext-world-store")
  (declare-function ov5-world-store--ensure-nrepl "gptel-ext-world-store"))

;; ── Customization ──

(defgroup world-store-query nil
  "Query layer for the OV5 World Store."
  :group 'ov5-world-store)

(defcustom world-store-query--cache-ttl 30
  "TTL in seconds for query results cache.
Set to 0 to disable caching."
  :type 'integer
  :group 'world-store-query)

;; ── Cache ──

(defvar world-store-query--cache (make-hash-table :test 'equal)
  "Hash table mapping query keys to (timestamp . result) pairs.")

(defun world-store-query--cache-get (key)
  "Get cached result for KEY, or nil if expired/missing."
  (let ((entry (gethash key world-store-query--cache)))
    (when entry
      (let ((timestamp (car entry))
            (result    (cdr entry)))
        (if (> (- (float-time) timestamp) world-store-query--cache-ttl)
            (progn (remhash key world-store-query--cache) nil)
          result)))))

(defun world-store-query--cache-set (key result)
  "Store RESULT in cache under KEY with current timestamp."
  (puthash key (cons (float-time) result) world-store-query--cache))

(defun world-store-query-invalidate-cache ()
  "Clear the entire query cache."
  (clrhash world-store-query--cache))

;; ── EDN parsing ──

(defun world-store-query--parse-edn (edn-str)
  "Parse brepl EDN output (a Clojure vector of plist-vectors).
Strips cosmetic Clojure commas, then reads with Elisp `read'.
Returns list of plists (each entity as key-value pairs)."
  (when (and edn-str (stringp edn-str) (not (string-empty-p edn-str)))
    (condition-case nil
        (let* (;; Strip Clojure commas — cosmetic, not valid in Elisp
               (cleaned (replace-regexp-in-string ",\\( \\|\n\\)" " " edn-str t t))
               ;; Read the vector of plist-vectors
               (result (read cleaned)))
          ;; result is a vector of vectors: [[:id "t1" :backend "MiniMax" ...] ...]
          ;; Convert each inner vector to a proper plist
          (if (vectorp result)
              (mapcar (lambda (v) (append v nil)) (append result nil))
            result))
      (error nil))))

(defun world-store-query--clean-edn (s)
  "Preprocess EDN string for Elisp read compatibility.
If the result is a Clojure string (surrounded by quotes), strip the quotes
and unescape.  Otherwise, process as raw EDN."
  (let ((s s))
    ;; If the brepl returned a Clojure string (pr-str output), handle it
    (when (and (> (length s) 1)
               (string-prefix-p "\"" s)
               (string-suffix-p "\"" s))
      ;; It's a serialized string from pr-str. Unescape and strip quotes.
      (setq s (substring s 1 -1))
      (setq s (replace-regexp-in-string "\\\\\"" "\"" s t t))
      (setq s (replace-regexp-in-string "\\\\n" "\n" s t t)))
    ;; Strip namespace prefixes from Clojure keywords
    (setq s (replace-regexp-in-string ":experiment/" ":" s t t))
    (setq s (replace-regexp-in-string ":backend/" ":" s t t))
    (setq s (replace-regexp-in-string ":strategy/" ":" s t t))
    (setq s (replace-regexp-in-string ":target/" ":" s t t))
    s))

(defun world-store-query--convert-result (result)
  "Post-process Elisp read result: convert keyword values to strings
for :decision and :effort-level fields; ensure list of plists."
  (cond
   ;; A vector of maps: [[:decision :kept ...] ...]
   ((and (vectorp result) (listp (aref result 0)))
    (mapcar #'world-store-query--convert-plist (append result nil)))
   ;; A single map: [:decision :kept ...]
   ((and (listp result) (keywordp (car result)))
    (list (world-store-query--convert-plist result)))
   ;; Already a list of plists
   ((listp result)
    result)
   ;; Catch-all: wrap
   (t (list result))))

(defun world-store-query--convert-plist (plist)
  "Convert a plist: stringify :decision and :effort-level keyword values."
  (let ((result nil))
    (while plist
      (let ((key (car plist))
            (val (cadr plist)))
        (push key result)
        (push (if (and (member key '(:decision :effort-level))
                       (keywordp val))
                  (symbol-name val)
                val)
              result)
        (setq plist (cddr plist))))
    (nreverse result)))

;; ── Low-level brepl call ──

(defun world-store-query--call (code &optional cache-key)
  "Evaluate Clojure CODE via brepl and parse EDN result.
CODE should be a self-contained Clojure expression returning an EDN string
(via pr-str).  If CACHE-KEY is provided, check/set cache.
Returns Elisp data or nil."
  (or (when cache-key (world-store-query--cache-get cache-key))
      (when (and (fboundp 'ov5-world-store--brepl-eval)
                 (fboundp 'ov5-world-store-connected-p)
                 (ov5-world-store-connected-p))
        (let ((edn (condition-case nil
                       (ov5-world-store--brepl-eval code)
                     (error nil))))
          (let ((result (world-store-query--parse-edn edn)))
            (when (and cache-key result)
              (world-store-query--cache-set cache-key result))
            result)))))

;; ── Query convenience functions ──

(defun world-store-query-all-experiments ()
  "Return all experiments as a list of plists (matching parse-all-results shape).
Cached with key \"all-experiments\"."
  (world-store-query--call
   "(ns ov5.world-store) (entities-to-readable (all-experiments))"
   "all-experiments"))

(defun world-store-query--experiments-by-filter (filters)
  "Return experiments matching FILTERS plist.
FILTERS: (:backend \"MiniMax\" :strategy \"direct\").
Cached by filter serialization."
  (let* ((filter-key (format "filter-%S" filters))
         (edn-map (world-store-query--plist-to-filter-map filters))
         (code (format "(ns ov5.world-store.query) (entities-to-readable (experiments-by-filters %s))"
                       edn-map)))
    (world-store-query--call code filter-key)))

(defun world-store-query--plist-to-filter-map (filters)
  "Convert Elisp filter plist to EDN map string with namespace keys.
(:backend \"MiniMax\" :strategy \"direct\") -> \"{:experiment/backend
\\\"MiniMax\\\" :experiment/strategy \\\"direct\\\"}\""
  (let ((pairs nil))
    (while filters
      (let ((key (car filters))
            (val (cadr filters)))
        (let ((ns-key (cond ((eq key :backend)  ":experiment/backend")
                            ((eq key :strategy) ":experiment/strategy")
                            ((eq key :target)   ":experiment/target")
                            ((eq key :decision) ":experiment/decision")
                            (t (format ":%s" (symbol-name key))))))
          (push (format "%s %S" ns-key val) pairs))
        (setq filters (cddr filters))))
    (concat "{" (mapconcat #'identity (nreverse pairs) " ") "}")))

(defun world-store-query-backend-strategy-target-stats (backend &optional strategy target)
  "Return (:kept N :total M :keep-rate F) plist for experiments
matching BACKEND, optionally filtered by STRATEGY/TARGET."
  (let* ((code (format "(ns ov5.world-store.query) (backend-strategy-target-stats-readable %S %S %S)"
                       backend strategy target))
         (result (world-store-query--call code
                                          (format "stats-%s-%s-%s" backend strategy target))))
    (car result)))

(defun world-store-query-recent-experiments (n)
  "Return the most recent N experiments as a list of plists."
  (let ((cache-key (format "recent-%d" n))
         (code (format "(ns ov5.world-store.query) (entities-to-readable (recent-experiments %d))" n)))
    (world-store-query--call code cache-key)))

(defun world-store-query-experiments-by-strategy-and-target (strategy target)
  "Return experiments matching STRATEGY and TARGET."
  (let ((cache-key (format "st-%s-%s" strategy target))
         (code (format "(ns ov5.world-store.query) (entities-to-readable (experiments-by-strategy-and-target %S %S))"
                       strategy target)))
    (world-store-query--call code cache-key)))

;; ── Fallback macro ──

(defmacro world-store-query-with-fallback (ws-form &rest fallback-body)
  "Try WS-FORM; if nil (store unavailable, query failed, parse error),
evaluate FALLBACK-BODY.
Uses ignore-errors so any failure in the WS path triggers fallback."
  (declare (indent 1))
  `(let ((ws-result
          (when (and (fboundp 'ov5-world-store-connected-p)
                     (ov5-world-store-connected-p))
            (ignore-errors ,ws-form))))
     (or ws-result (progn ,@fallback-body))))

;; ── Provide ──

(provide 'gptel-ext-world-store-query)

;;; gptel-ext-world-store-query.el ends here
