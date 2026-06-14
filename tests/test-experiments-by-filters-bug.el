;;; test-experiments-by-filters-bug.el --- TDD test for nil-result query bug -*- lexical-binding: t; -*-

;; gptel-auto-workflow--experiments-by-filter returns nil instead of
;; the matching experiments.  Root cause: experiments-by-filters
;; in clj/ov5/world_store/query.clj builds a Datalog form that
;; errors with "Cannot resolve any more clauses" — the pull
;; pattern is malformed.
;;
;; TDD red phase: this test fails on the current implementation.

(require 'ert)
(require 'cl-lib)

(unless (featurep 'gptel-ext-world-store)
  (load (expand-file-name "lisp/modules/gptel-ext-world-store.el"
                          default-directory)))
(unless (featurep 'gptel-ext-world-store-query)
  (load (expand-file-name "lisp/modules/gptel-ext-world-store-query.el"
                          default-directory)))

(defmacro tdd-qf--with-store (&rest body)
  "Run BODY with a fresh World Store."
  `(let* ((id (random 1000000))
          (db-path (format "/tmp/tdd-qf-test-%d" id))
          (nrepl-port (+ 7900 (mod id 100)))
          (ov5-world-store-directory db-path)
          (ov5-world-store-nrepl-port nrepl-port))
     (when (file-exists-p db-path)
       (delete-directory db-path t))
     (unwind-protect
         (progn
           (ov5-world-store-connect)
           ,@body)
       (condition-case nil (ov5-world-store-disconnect) (error nil))
       (when (file-exists-p db-path)
         (delete-directory db-path t)))))

(ert-deftest tdf-qf/compound-filter-returns-non-nil ()
  "experiments-by-filter should return matching experiments, not nil.
Bug: returns nil for valid input."
  (skip-unless (executable-find "brepl"))
  (skip-unless (and (fboundp 'ov5-world-store--datahike-pod-available-p)
                    (ov5-world-store--datahike-pod-available-p)))
  (tdd-qf--with-store
   (ov5-world-store-transact
    '((:experiment/id "e1" :experiment/backend "MiniMax" :experiment/decision "kept")))
   (let ((results (world-store-query--experiments-by-filter
                   (list :backend "MiniMax"))))
     (should results)
     (should (>= (length results) 1)))))
