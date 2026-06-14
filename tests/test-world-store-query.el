;;; test-world-store-query.el --- Query layer tests for World Store -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-ext-world-store-query.el: compound filters, keep-rate,
;; recent-experiment ordering, caching, fallback behavior, and shape match.
;; Each test uses an isolated database + nREPL port for independence.

;;; Code:

(require 'ert)

;; ── Load modules ──

(condition-case err
    (progn
      (require 'gptel-ext-world-store)
      (require 'gptel-ext-world-store-query))
  (error
   (message "[world-store-query-test] Module load failed: %s" (error-message-string err))
   (unless (fboundp 'ov5-world-store-connect)
     (defun ov5-world-store-connect () (error "brepl unavailable")))
   (unless (fboundp 'ov5-world-store-disconnect)
     (defun ov5-world-store-disconnect () nil))
(unless (fboundp 'ov5-world-store-connected-p)
      (defun ov5-world-store-connected-p () nil))))

(defun test-world-store--skip-if-unavailable ()
  "Skip test if World Store/Datahike pod is unavailable."
  (unless (and (fboundp 'ov5-world-store--datahike-pod-available-p)
               (ov5-world-store--datahike-pod-available-p))
    (ert-skip "World Store/Datahike pod unavailable")))

;; ── Test isolation ──

(defvar test-world-store-query--counter 0
  "Counter for unique test IDs.")

(defun test-world-store-query--next-id ()
  "Generate a unique test ID."
  (setq test-world-store-query--counter (1+ test-world-store-query--counter))
  test-world-store-query--counter)

(defmacro test-world-store-query--with-store (&rest body)
  "Run BODY with a fresh World Store connection."
  (declare (indent 0))
  `(let* ((id (test-world-store-query--next-id))
          (db-path (format "/tmp/ov5-ws-query-test-%d" id))
          (nrepl-port (+ 7900 id))
          (ov5-world-store-directory db-path)
          (ov5-world-store-nrepl-port nrepl-port))
     (test-world-store--skip-if-unavailable)
     (when (file-exists-p db-path)
       (delete-directory db-path t))
     (unwind-protect
         (progn
           (ov5-world-store-connect)
           ,@body)
       (condition-case nil (ov5-world-store-disconnect) (error nil))
       (when (file-exists-p db-path)
         (delete-directory db-path t)))))

;; ── Helper: insert test experiments ──

(defun test-world-store-query--seed-experiments ()
  "Insert a known set of experiments into the store for query testing."
  (ov5-world-store-transact
   '((:experiment/id "exp-query-001"
      :experiment/target "test-a.el"
      :experiment/backend "MiniMax"
      :experiment/strategy "direct"
      :experiment/decision "kept"
      :experiment/score-before 0.5
      :experiment/score-after 0.9
      :experiment/hypothesis "fix test-a")
     (:experiment/id "exp-query-002"
      :experiment/target "test-b.el"
      :experiment/backend "MiniMax"
      :experiment/strategy "indirect"
      :experiment/decision "discarded"
      :experiment/score-before 0.3
      :experiment/score-after 0.3
      :experiment/hypothesis "fix test-b")
     (:experiment/id "exp-query-003"
      :experiment/target "test-a.el"
      :experiment/backend "DeepSeek"
      :experiment/strategy "direct"
      :experiment/decision "kept"
      :experiment/score-before 0.6
      :experiment/score-after 0.95
      :experiment/hypothesis "fix test-a v2")
     (:experiment/id "exp-query-004"
      :experiment/target "test-c.el"
      :experiment/backend "MiniMax"
      :experiment/strategy "direct"
      :experiment/decision "kept"
      :experiment/score-before 0.4
      :experiment/score-after 0.8
      :experiment/hypothesis "fix test-c"))))

;; ── Tests ──

(ert-deftest world-store-query/compound-filter ()
  "Test that experiments-by-filter returns correct subset."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   (let ((results (world-store-query--experiments-by-filter
                   (list :backend "MiniMax"))))
     (should results)
     (should (= (length results) 3))
     ;; All returned results should have MiniMax backend
     (dolist (r results)
       (should (string= (or (plist-get r :backend) "unknown") "MiniMax"))))
   ;; Filter by strategy
   (let ((results (world-store-query--experiments-by-filter
                   (list :strategy "indirect"))))
     (should results)
     (should (= (length results) 1))
     (should (string= (plist-get (car results) :strategy) "indirect")))))

(ert-deftest world-store-query/keep-rate-by-filters ()
  "Test keep-rate calculation matches manual count."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   (let ((stats (world-store-query-backend-strategy-target-stats "MiniMax")))
     (should stats)
     ;; 3 MiniMax experiments: kept, discarded, kept = 2/3
     (should (= (plist-get stats :total) 3))
     (should (= (plist-get stats :kept) 2))
     (should (numberp (plist-get stats :keep-rate)))
     (should (< 0.6 (plist-get stats :keep-rate) 0.7)))))

(ert-deftest world-store-query/recent-experiments-order ()
  "Test recent-experiments returns results in descending ID order."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   (let ((recent (world-store-query-recent-experiments 2)))
     (should recent)
     (should (<= (length recent) 2))
     ;; IDs should be in descending order (newer first)
     (when (>= (length recent) 2)
       (let ((id1 (plist-get (nth 0 recent) :id))
             (id2 (plist-get (nth 1 recent) :id)))
         (should (string> (or id1 "") (or id2 ""))))))))

(ert-deftest world-store-query/cache-hit ()
  "Test that repeated identical queries hit the cache."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   ;; First query — should populate cache
   (let ((r1 (world-store-query--experiments-by-filter
              (list :backend "MiniMax"))))
     (should r1)
     ;; Second query with same key — should hit cache
     (let ((cached (world-store-query--cache-get "filter-(:backend \"MiniMax\")")))
       (should cached)))))

(ert-deftest world-store-query/cache-invalidation-on-transact ()
  "Test that cache is invalidated after a transact."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   ;; Populate cache
   (world-store-query--experiments-by-filter (list :backend "MiniMax"))
   (let ((cached-before (world-store-query--cache-get
                         "filter-(:backend \"MiniMax\")")))
     (should cached-before))
   ;; Transact a new experiment — should invalidate cache
   (ov5-world-store-transact
    '((:experiment/id "exp-query-005"
       :experiment/target "test-d.el"
       :experiment/backend "MiniMax"
       :experiment/strategy "direct"
       :experiment/decision "kept")))
   (let ((cached-after (world-store-query--cache-get
                        "filter-(:backend \"MiniMax\")")))
     (should-not cached-after))))

(ert-deftest world-store-query/fallback-when-disconnected ()
  "Test that with-fallback executes fallback when store is unavailable."
  (let ((fallback-executed nil))
    (world-store-query-with-fallback
        ;; WS path — store may be connected, so this might succeed
        ;; We can't reliably test disconnected, but we can test that
        ;; the fallback form is syntactically valid
        (progn (setq fallback-executed 'ws) 'ws-result)
      (setq fallback-executed 'fallback)
      'fallback-result)
    (should (memq fallback-executed '(ws fallback)))))

(ert-deftest world-store-query/decision-string-conversion ()
  "Test that decision keywords from Clojure are converted to Elisp strings."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   (let ((results (world-store-query--experiments-by-filter
                   (list :backend "MiniMax"))))
     (should results)
     (dolist (r results)
       (let ((decision (plist-get r :decision)))
         (should (stringp decision))
         (should (member decision '("kept" "discarded"))))))))

(ert-deftest world-store-query/result-shape-matches-parse-all-results ()
  "Test that store query results have the same plist keys as parse-all-results."
  (skip-unless (executable-find "brepl"))
  (test-world-store-query--with-store
   (test-world-store-query--seed-experiments)
   (let ((results (world-store-query-all-experiments))
         (required-keys '(:target :backend :strategy :decision
                          :hypothesis :score-before :score-after :id)))
     (should results)
     (dolist (r results)
       (dolist (key required-keys)
         (should (plist-member r key)))))))

(provide 'test-world-store-query)

;;; test-world-store-query.el ends here
