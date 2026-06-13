;;; test-gptel-ext-prefix-cache.el --- Tests for gptel-ext-prefix-cache -*- lexical-binding: t; -*-

;; Tests for prefix-cache-stable prompt architecture.
;; Core invariant: stable prefix stays byte-stable across experiments.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load module under test
(require 'gptel-ext-prefix-cache)

;; ─── Regression: Initial Value Is Nil ───

(ert-deftest test-prefix-cache-run-id-starts-nil ()
  "Regression: run-id must start as nil, not a hash table."
  (should (null gptel-prefix-cache--run-id))
  (should-not (hash-table-p gptel-prefix-cache--run-id)))

;; ─── Test Helpers ───

(defvar test-prefix-cache--original-content nil)
(defvar test-prefix-cache--original-valid-p nil)
(defvar test-prefix-cache--original-run-id nil)

(defun test-prefix-cache--save-state ()
  "Save current prefix cache state."
  (setq test-prefix-cache--original-content gptel-prefix-cache--content
        test-prefix-cache--original-valid-p gptel-prefix-cache--valid-p
        test-prefix-cache--original-run-id gptel-prefix-cache--run-id))

(defun test-prefix-cache--restore-state ()
  "Restore saved prefix cache state."
  (setq gptel-prefix-cache--content test-prefix-cache--original-content
        gptel-prefix-cache--valid-p test-prefix-cache--original-valid-p
        gptel-prefix-cache--run-id test-prefix-cache--original-run-id))

;; ─── Tests ───

(ert-deftest test-prefix-cache-invalidate ()
  "Test that invalidate clears all cache state."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        ;; Set up fake cache
        (setq gptel-prefix-cache--content "test content"
              gptel-prefix-cache--valid-p t
              gptel-prefix-cache--run-id "run-123"
              gptel-prefix-cache--stats '(:size 100))
        ;; Invalidate
        (gptel-prefix-cache-invalidate)
        ;; Verify cleared
        (should (null gptel-prefix-cache--content))
        (should (null gptel-prefix-cache--valid-p))
        (should (null gptel-prefix-cache--run-id))
        (should (null gptel-prefix-cache--stats)))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-compute-creates-content ()
  "Test that compute creates cache content."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (let ((result (gptel-prefix-cache-compute "run-abc")))
          ;; Should return non-empty string
          (should (stringp result))
          (should (> (length result) 0))
          ;; Should contain marker
          (should (string-match-p "STABLE PREFIX" result))
          ;; Should contain dynamic marker
          (should (string-match-p "DYNAMIC CONTENT" result))
          ;; Cache should be valid
          (should gptel-prefix-cache--valid-p)
          (should (equal gptel-prefix-cache--run-id "run-abc"))
          ;; Stats should be populated
          (should gptel-prefix-cache--stats)
          (should (> (plist-get gptel-prefix-cache--stats :size) 0))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-compute-reuses-cache ()
  "Test that compute reuses cache for same run-id."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        ;; First compute
        (let ((result1 (gptel-prefix-cache-compute "run-xyz")))
          (should (stringp result1))
          ;; Second compute with same run-id — should reuse
          (let ((result2 (gptel-prefix-cache-compute "run-xyz")))
            (should (string= result1 result2))
            ;; Stats should still be from first compute
            (should gptel-prefix-cache--stats))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-compute-forces-recompute ()
  "Test that force-recompute creates new cache."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (let ((_result1 (gptel-prefix-cache-compute "run-123")))
          ;; Force recompute
          (let ((result2 (gptel-prefix-cache-compute "run-123" t)))
            ;; Content might be same but timestamp should update
            (should (stringp result2))
            (should gptel-prefix-cache--timestamp))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-prepend-disabled ()
  "Test that prepend returns dynamic prompt when disabled."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((gptel-prefix-cache-enabled nil)
            (dynamic "dynamic content"))
        (should (string= (gptel-prefix-cache-prepend dynamic) dynamic)))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-prepend-enabled ()
  "Test that prepend concatenates prefix + dynamic."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "run-test")
        (let* ((dynamic "DYNAMIC PART")
               (result (gptel-prefix-cache-prepend dynamic)))
          ;; Result should contain both prefix and dynamic
          (should (string-match-p "STABLE PREFIX" result))
          (should (string-match-p "DYNAMIC PART" result))
          ;; Dynamic part should be after the marker
          (should (> (string-match-p "DYNAMIC PART" result)
                       (string-match-p "DYNAMIC CONTENT" result)))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-context-usage ()
  "Test context usage estimation."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "run-test")
        (let* ((dynamic "short dynamic prompt")
               (usage (gptel-prefix-cache-context-usage dynamic)))
          ;; Should return plist with expected keys
          (should (plist-get usage :total))
          (should (plist-get usage :prefix))
          (should (plist-get usage :dynamic))
          (should (numberp (plist-get usage :ratio)))
          ;; Ratio should be between 0 and 1 for short prompt
          (should (>= (plist-get usage :ratio) 0.0))
          ;; Prefix should be larger than dynamic for our test
          (should (>= (plist-get usage :prefix) (plist-get usage :dynamic)))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-extract-dynamic ()
  "Test extracting dynamic portion from full prompt."
  (let* ((dynamic "THIS IS DYNAMIC")
         (full (concat "=== STABLE PREFIX ===\n\n"
                       "stable content\n\n"
                       "=== DYNAMIC CONTENT (changes per experiment) ===\n\n"
                       dynamic)))
    (should (string= (gptel-prefix-cache-extract-dynamic full) dynamic))))

(ert-deftest test-prefix-cache-extract-dynamic-no-marker ()
  "Test extract-dynamic returns full prompt when no marker."
  (let ((prompt "just a plain prompt"))
    (should (string= (gptel-prefix-cache-extract-dynamic prompt) prompt))))

(ert-deftest test-prefix-cache-stats ()
  "Test stats formatting."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (should (string-match-p "No cache" (gptel-prefix-cache-stats)))
        (gptel-prefix-cache-compute "run-stats")
        (let ((stats (gptel-prefix-cache-stats)))
          (should (string-match-p "[0-9]+ chars" stats))
          (should (string-match-p "[0-9]+ sections" stats))
          (should (string-match-p "run=run-stats" stats))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-truncate-content ()
  "Test content truncation helper."
  ;; Short content — unchanged
  (should (string= (gptel-prefix-cache--truncate-content "short" 100) "short"))
  ;; Long content — truncated
  (let ((long (make-string 200 ?x)))
    (should (< (length (gptel-prefix-cache--truncate-content long 100)) 200))
    (should (string-match-p "\\.\\.\\."
                            (gptel-prefix-cache--truncate-content long 100)))))

(ert-deftest test-prefix-cache-run-lifecycle ()
  "Test run start/end lifecycle hooks."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        ;; Start run
        (gptel-prefix-cache-on-run-start "lifecycle-run")
        (should gptel-prefix-cache--valid-p)
        (should (equal gptel-prefix-cache--run-id "lifecycle-run"))
        ;; End run
        (gptel-prefix-cache-on-run-end)
        (should (null gptel-prefix-cache--valid-p))
        (should (null gptel-prefix-cache--content)))
    (test-prefix-cache--restore-state)))

;;; Compaction Tests

(ert-deftest test-prefix-cache-compact-dynamic ()
  "Test dynamic prompt compaction with many previous results."
  (let ((results
         (list
          (list :id 1 :hypothesis "fix nil guard" :score-before 0.5 :score-after 0.7 :kept t)
          (list :id 2 :hypothesis "add error handling" :score-before 0.7 :score-after 0.6 :kept nil
                :comparator-reason "score dropped")
          (list :id 3 :hypothesis "refactor loop" :score-before 0.6 :score-after 0.8 :kept t)
          (list :id 4 :hypothesis "optimize map" :score-before 0.8 :score-after 0.75 :kept nil
                :comparator-reason "marginal improvement")
          (list :id 5 :hypothesis "add tests" :score-before 0.75 :score-after 0.9 :kept t))))
    (let ((compacted (gptel-prefix-cache-compact-dynamic "test prompt" results)))
      ;; Should contain summary section
      (should (string-match-p "Previous Experiment Summary" compacted))
      ;; Should contain verbatim recent section
      (should (string-match-p "Recent Experiments" compacted))
      ;; Should still contain the original prompt
      (should (string-match-p "test prompt" compacted)))))

(ert-deftest test-prefix-cache-compact-dynamic-few-results ()
  "Test that compaction is skipped with <=3 results."
  (let ((results
         (list
          (list :id 1 :hypothesis "fix nil guard" :score-before 0.5 :score-after 0.7 :kept t)
          (list :id 2 :hypothesis "add error handling" :score-before 0.7 :score-after 0.6 :kept nil))))
    (let ((compacted (gptel-prefix-cache-compact-dynamic "test prompt" results)))
      ;; Should return prompt unchanged
      (should (string= compacted "test prompt")))))

(ert-deftest test-prefix-cache-summarize-results ()
  "Test result summarization."
  (let ((results
         (list
          (list :id 1 :hypothesis "fix nil guard" :score-before 0.5 :score-after 0.7 :kept t)
          (list :id 2 :hypothesis "add error handling" :score-before 0.7 :score-after 0.6 :kept nil
                :comparator-reason "score dropped")
          (list :id 3 :hypothesis "refactor loop" :score-before 0.6 :score-after 0.8 :kept t)
          (list :id 4 :hypothesis "optimize map" :score-before 0.8 :score-after 0.75 :kept nil
                :comparator-reason "score dropped"))))
    (let ((summary (gptel-prefix-cache--summarize-results results)))
      ;; Should contain counts
      (should (string-match-p "Kept: 2" summary))
      (should (string-match-p "Discarded: 2" summary))
      ;; Should contain failure mode
      (should (string-match-p "score dropped" summary))
      ;; Should contain best hypothesis
      (should (string-match-p "refactor loop" summary)))))

(ert-deftest test-prefix-cache-compaction-on-run-start ()
  "Test that compaction archive is cleared on run start."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (setq gptel-prefix-cache--compaction-archive '("old summary"))
        (gptel-prefix-cache-on-run-start "run-1")
        (should (null gptel-prefix-cache--compaction-archive)))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-sync-from-backend ()
  "Test context window sync from backend registry."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        ;; Test with a known backend/model
        (when (fboundp 'gptel-backend-registry-context-window)
          (gptel-prefix-cache-sync-from-backend 'DeepSeek 'deepseek-v4-pro)
          (should (> gptel-prefix-cache--context-window-size 0))
          ;; Should be 1M for DeepSeek
          (should (or (= gptel-prefix-cache--context-window-size 1000000)
                      (= gptel-prefix-cache--context-window-size 128000)))))
    (test-prefix-cache--restore-state)))

;;; Session Separation Tests (Gap 4)

(ert-deftest test-prefix-cache-role-compute ()
  "Test per-role prefix cache computation."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "role-test-run")
        ;; Compute executor prefix
        (let ((executor-prefix (gptel-prefix-cache-compute-for-role 'executor)))
          (should (stringp executor-prefix))
          (should (> (length executor-prefix) 0))
          ;; Should contain role-specific context
          (should (string-match-p "Role: EXECUTOR" executor-prefix)))
        ;; Compute grader prefix
        (let ((grader-prefix (gptel-prefix-cache-compute-for-role 'grader)))
          (should (stringp grader-prefix))
          (should (> (length grader-prefix) 0))
          (should (string-match-p "Role: GRADER" grader-prefix)))
        ;; Should be cached
        (should (gptel-prefix-cache-role-get 'executor))
        (should (gptel-prefix-cache-role-get 'grader)))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-role-isolation ()
  "Test that role caches are isolated from each other."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "isolation-run")
        (let* ((exec-prefix (gptel-prefix-cache-compute-for-role 'executor))
               (grad-prefix (gptel-prefix-cache-compute-for-role 'grader)))
          ;; Different roles should have different prefixes
          (should (not (string= exec-prefix grad-prefix)))
          ;; Both should contain base content
          (should (string-match-p "STABLE PREFIX" exec-prefix))
          (should (string-match-p "STABLE PREFIX" grad-prefix))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-role-invalidate ()
  "Test role cache invalidation."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "invalidate-run")
        (gptel-prefix-cache-compute-for-role 'executor)
        (gptel-prefix-cache-compute-for-role 'grader)
        ;; Both should exist
        (should (gptel-prefix-cache-role-get 'executor))
        (should (gptel-prefix-cache-role-get 'grader))
        ;; Invalidate one
        (gptel-prefix-cache-role-invalidate 'executor)
        (should (not (gptel-prefix-cache-role-get 'executor)))
        (should (gptel-prefix-cache-role-get 'grader))
        ;; Invalidate all
        (gptel-prefix-cache-role-invalidate t)
        (should (not (gptel-prefix-cache-role-get 'grader))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-role-prepend ()
  "Test role-aware prompt prepending."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((gptel-prefix-cache-role-aware t)
            (dynamic "Fix the nil guard in this function."))
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "prepend-run")
        (let ((result (gptel-prefix-cache-prepend-for-role 'executor dynamic)))
          ;; Should contain role prefix + dynamic content
          (should (string-match-p "Role: EXECUTOR" result))
          (should (string-match-p "Fix the nil guard" result))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-role-stats ()
  "Test role cache statistics."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "stats-run")
        (gptel-prefix-cache-compute-for-role 'executor)
        (gptel-prefix-cache-compute-for-role 'grader)
        (let ((stats (gptel-prefix-cache-role-stats)))
          (should (string-match-p "executor" stats))
          (should (string-match-p "grader" stats))
          (should (string-match-p "chars" stats))))
    (test-prefix-cache--restore-state)))

;;; Token Budget Tests (Gap 5)

(ert-deftest test-prefix-cache-dynamic-budget ()
  "Test dynamic token budget computation."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "budget-run")
        ;; Set a known context window
        (setq gptel-prefix-cache--context-window-size 10000)
        (let ((budget (gptel-prefix-cache-compute-dynamic-budget)))
          ;; Should be positive and less than context window
          (should (numberp budget))
          (should (> budget 0))
          (should (< budget 10000))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-build-with-budget ()
  "Test budget-aware prompt building."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "build-run")
        ;; Set small budget to force exclusion
        (setq gptel-prefix-cache--context-window-size 500)
        (setq gptel-prefix-cache--output-reservation 100)
        (setq gptel-prefix-cache-dynamic-token-budget 100)
        (let* ((sections
                (list
                 (cons 1 (cons "essential" "This is essential content."))
                 (cons 5 (cons "optional" (make-string 500 ?x)))))
               (result (gptel-prefix-cache-build-with-budget sections)))
          ;; Essential should be included
          (should (string-match-p "essential" result))
          ;; Optional should be excluded (too long for budget)
          (should (not (string-match-p "optional" result)))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-build-all-when-no-budget ()
  "Test that all sections included when budget disabled."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((gptel-prefix-cache-dynamic-token-budget nil)
            (sections
             (list
              (cons 1 (cons "first" "Content one."))
              (cons 2 (cons "second" "Content two.")))))
        (let ((result (gptel-prefix-cache-build-with-budget sections)))
          (should (string-match-p "Content one" result))
          (should (string-match-p "Content two" result))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-priority-ordering ()
  "Test that sections are included in priority order."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        ;; Use large context window so prefix fits
        (setq gptel-prefix-cache--context-window-size 100000)
        (setq gptel-prefix-cache--output-reservation 1000)
        ;; Budget that fits only 1-2 sections
        (setq gptel-prefix-cache-dynamic-token-budget 5)
        (let* ((sections
                (list
                 (cons 3 (cons "medium" "Medium"))
                 (cons 1 (cons "high" "High"))
                 (cons 5 (cons "low" "Low"))))
               (result (gptel-prefix-cache-build-with-budget sections)))
          ;; With tiny budget, only highest priority should fit
          (should (string-match-p "High" result))
          ;; Result should not contain all three
          (should (< (length result) 20))))
    (test-prefix-cache--restore-state)))

;; ─── Relevance Scoring Tests (AttnRes Phase 2) ───

(ert-deftest test-prefix-cache-format-results-weighted ()
  "Test weighted result formatting with relevance scores."
  (let* ((results
          (list
           (cons 0.85
                 (list :id "exp1" :hypothesis "Fix memory leak" :score-before 0.5 :score-after 0.8 :kept t))
           (cons 0.42
                 (list :id "exp2" :hypothesis "Refactor parser" :score-before 0.6 :score-after 0.6 :kept nil))))
         (formatted (gptel-prefix-cache--format-results-weighted results)))
    (should (string-match-p "rel=85%" formatted))
    (should (string-match-p "rel=42%" formatted))
    (should (string-match-p "KEPT" formatted))
    (should (string-match-p "DISCARDED" formatted))))

(ert-deftest test-prefix-cache-sections-with-relevance ()
  "Test that sections-for-experiment includes relevance-weighted results."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let* ((target "lisp/modules/gptel-ext-prefix-cache.el")
             (previous
              (list
               (list :id "exp1" :target "lisp/modules/gptel-ext-prefix-cache.el"
                     :hypothesis "Add caching" :score-before 0.5 :score-after 0.9 :kept t)
               (list :id "exp2" :target "lisp/modules/other.el"
                     :hypothesis "Refactor" :score-before 0.6 :score-after 0.4 :kept nil)))
             (sections (gptel-prefix-cache-sections-for-experiment
                        target 1 10 nil previous))
             (recent-results (cdr (assoc "recent-results"
                                         (mapcar (lambda (s) (cons (cadr s) (cddr s))) sections)))))
        (should (string-match-p "Previous Results" recent-results))
        ;; When rank-relevant is available, should show relevance scores
        (when (fboundp 'gptel-auto-experiment--rank-relevant)
          (should (string-match-p "rel=" recent-results))))
    (test-prefix-cache--restore-state)))

;; ─── Persistence Tests (Gap 6) ───

(ert-deftest test-prefix-cache-save-and-load ()
  "Test that cache state can be saved and restored."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((test-file (make-temp-file "prefix-cache-test-"))
            (original-content nil))
        ;; Setup: compute cache and role cache
        (gptel-prefix-cache-invalidate)
        (setq gptel-prefix-cache-persist-file test-file
              gptel-prefix-cache-persist-enabled t
              gptel-prefix-cache-persist-max-age-hours 24)
        (gptel-prefix-cache-compute "test-run")
        (setq original-content gptel-prefix-cache--content)
        (gptel-prefix-cache-compute-for-role 'executor "test-run")
        ;; Save state
        (gptel-prefix-cache-save-to-file)
        (should (file-exists-p test-file))
        ;; Invalidate and load back
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-role-invalidate t)
        (should (null gptel-prefix-cache--content))
        (let ((result (gptel-prefix-cache-load-from-file)))
          (should result)
          (should (equal gptel-prefix-cache--content original-content))
          (should gptel-prefix-cache--valid-p)
          (should (equal gptel-prefix-cache--run-id "test-run"))
          ;; Role cache should be restored
          (should (gptel-prefix-cache-role-get 'executor)))
        ;; Cleanup
        (delete-file test-file))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-load-stale-state ()
  "Test that stale persisted state is rejected."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((test-file (make-temp-file "prefix-cache-test-")))
        (setq gptel-prefix-cache-persist-file test-file
              gptel-prefix-cache-persist-enabled t
              gptel-prefix-cache-persist-max-age-hours 1)
        ;; Create a fake stale state file (2 hours old)
        (with-temp-file test-file
          (prin1 (list :version 1
                       :timestamp (time-subtract (current-time) (seconds-to-time 7200))
                       :run-id "old-run"
                       :content "stale content"
                       :role-caches nil)
                 (current-buffer)))
        (should (null (gptel-prefix-cache-load-from-file)))
        (should (null gptel-prefix-cache--content))
        ;; File should be deleted
        (should (not (file-exists-p test-file)))
        (when (file-exists-p test-file)
          (delete-file test-file)))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-load-version-mismatch ()
  "Test that version mismatch is handled gracefully."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((test-file (make-temp-file "prefix-cache-test-")))
        (setq gptel-prefix-cache-persist-file test-file
              gptel-prefix-cache-persist-enabled t)
        (with-temp-file test-file
          (prin1 (list :version 99
                       :timestamp (current-time)
                       :run-id "bad-version"
                       :content "bad content")
                 (current-buffer)))
        (should (null (gptel-prefix-cache-load-from-file)))
        (should (null gptel-prefix-cache--content))
        (delete-file test-file))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-run-end-saves-state ()
  "Test that run-end hook saves state before invalidating."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((test-file (make-temp-file "prefix-cache-test-")))
        (setq gptel-prefix-cache-persist-file test-file
              gptel-prefix-cache-persist-enabled t)
        (gptel-prefix-cache-invalidate)
        (gptel-prefix-cache-compute "lifecycle-run")
        ;; Run end hook should save then invalidate
        (gptel-prefix-cache-on-run-end)
        (should (not gptel-prefix-cache--valid-p))
        (should (file-exists-p test-file))
        ;; Should be restorable
        (should (gptel-prefix-cache-load-from-file))
        (should (equal gptel-prefix-cache--run-id "lifecycle-run"))
        (delete-file test-file))
    (test-prefix-cache--restore-state)))

;; ─── Phase 3: Cross-Run Statistics Tests ───

(ert-deftest test-prefix-cache-stats-hit-miss-tracking ()
  "Test that hit/miss counters are tracked correctly."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (setq gptel-prefix-cache--hit-counter 0
              gptel-prefix-cache--miss-counter 0)
        ;; First get should be a miss (compute)
        (let ((content (gptel-prefix-cache-get)))
          (should content)
          (should (= gptel-prefix-cache--miss-counter 1))
          (should (= gptel-prefix-cache--hit-counter 0)))
        ;; Second get should be a hit
        (let ((content2 (gptel-prefix-cache-get)))
          (should content2)
          (should (= gptel-prefix-cache--miss-counter 1))
          (should (= gptel-prefix-cache--hit-counter 1))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-stats-current-run ()
  "Test that current run statistics are computed correctly."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (gptel-prefix-cache-invalidate)
        (setq gptel-prefix-cache--hit-counter 3
              gptel-prefix-cache--miss-counter 1
              gptel-prefix-cache--compaction-counter 2
              gptel-prefix-cache--stats '(:size 5000 :compute-time-ms 12))
        (let ((stats (gptel-prefix-cache-stats-current-run)))
          (should (= (plist-get stats :hits) 3))
          (should (= (plist-get stats :misses) 1))
          (should (= (plist-get stats :compactions) 2))
          (should (= (plist-get stats :hit-rate) 0.75))
          (should (= (plist-get stats :prefix-size) 5000))
          (should (= (plist-get stats :compute-time-ms) 12))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-auto-tune-low-hit-rate ()
  "Test that auto-tune lowers threshold when hit rate is low."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((original-ratio gptel-prefix-cache--context-compact-ratio))
        (setq gptel-prefix-cache--context-compact-ratio 0.8
              gptel-prefix-cache--cross-run-stats
              (list :runs 10 :total-hits 3 :total-compactions 5)
              gptel-prefix-cache--auto-tune-enabled t)
        (gptel-prefix-cache--auto-tune-threshold)
        ;; Low hit rate (0.3) should lower threshold
        (should (< gptel-prefix-cache--context-compact-ratio 0.8))
        (should (>= gptel-prefix-cache--context-compact-ratio 0.6))
        (setq gptel-prefix-cache--context-compact-ratio original-ratio))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-auto-tune-high-hit-rate ()
  "Test that auto-tune raises threshold when hit rate is high and compactions frequent."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((original-ratio gptel-prefix-cache--context-compact-ratio))
        (setq gptel-prefix-cache--context-compact-ratio 0.8
              gptel-prefix-cache--cross-run-stats
              (list :runs 10 :total-hits 9 :total-compactions 30)
              gptel-prefix-cache--auto-tune-enabled t)
        (gptel-prefix-cache--auto-tune-threshold)
        ;; High hit rate (0.9) with frequent compactions (3/run) should raise threshold
        (should (> gptel-prefix-cache--context-compact-ratio 0.8))
        (should (<= gptel-prefix-cache--context-compact-ratio 0.95))
        (setq gptel-prefix-cache--context-compact-ratio original-ratio))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-stats-persistence ()
  "Test that cross-run statistics are saved and loaded."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((test-file (make-temp-file "prefix-cache-test-")))
        (setq gptel-prefix-cache-persist-file test-file
              gptel-prefix-cache-persist-enabled t)
        (gptel-prefix-cache-invalidate)
        (setq gptel-prefix-cache--cross-run-stats
              (list :runs 5 :total-hits 20 :total-compactions 10))
        (gptel-prefix-cache-compute "stats-test")
        (gptel-prefix-cache-on-run-end)
        ;; Load and verify stats
        (gptel-prefix-cache-invalidate)
        (setq gptel-prefix-cache--cross-run-stats nil)
        (should (gptel-prefix-cache-load-from-file))
        ;; Runs should be incremented (5 + 1)
        (should (equal (plist-get gptel-prefix-cache--cross-run-stats :runs) 6))
        ;; Total hits should be >= original (may include hits from compute/get)
        (should (>= (plist-get gptel-prefix-cache--cross-run-stats :total-hits) 20))
        (delete-file test-file))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-stats-report-format ()
  "Test that statistics report is formatted correctly."
  (test-prefix-cache--save-state)
  (unwind-protect
      (progn
        (setq gptel-prefix-cache--hit-counter 10
              gptel-prefix-cache--miss-counter 2
              gptel-prefix-cache--compaction-counter 1
              gptel-prefix-cache--stats '(:size 4000 :compute-time-ms 5)
              gptel-prefix-cache--cross-run-stats
              (list :runs 3 :total-hits 25 :total-compactions 5)
              gptel-prefix-cache--context-compact-ratio 0.8)
        (let ((report (gptel-prefix-cache-stats-report)))
          (should (string-match-p "Prefix Cache Statistics" report))
          (should (string-match-p "hits=10" report))
          (should (string-match-p "misses=2" report))
          (should (string-match-p "hit-rate=83.3" report))
          (should (string-match-p "Cross-run (3 runs)" report))))
    (test-prefix-cache--restore-state)))

(ert-deftest test-prefix-cache-metrics-export ()
  "Test that metrics are exported to JSON file."
  (test-prefix-cache--save-state)
  (unwind-protect
      (let ((metrics-dir (make-temp-file "prefix-cache-metrics-" t))
            (original-worktree-root (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                         (gptel-auto-workflow--worktree-base-root))))
        ;; Override worktree root to temp dir
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () metrics-dir)))
          (setq gptel-prefix-cache--hit-counter 5
                gptel-prefix-cache--miss-counter 1
                gptel-prefix-cache--compaction-counter 2
                gptel-prefix-cache--stats '(:size 3000 :compute-time-ms 3)
                gptel-prefix-cache--cross-run-stats
                (list :runs 2 :total-hits 10 :total-compactions 4)
                gptel-prefix-cache--context-compact-ratio 0.75
                gptel-prefix-cache--run-id "metrics-test")
          (let ((file (gptel-prefix-cache-export-metrics)))
            (should (file-exists-p file))
            (let* ((json (with-temp-buffer
                           (insert-file-contents file)
                           (json-read)))
                   (entry (aref json 0)))
              (should (equal (cdr (assoc 'run-id entry)) "metrics-test"))
              (should (equal (cdr (assoc 'hits entry)) 5))
              (should (equal (cdr (assoc 'misses entry)) 1))
              (should (equal (cdr (assoc 'compactions entry)) 2))
              (should (equal (cdr (assoc 'prefix-size entry)) 3000))
              (should (equal (cdr (assoc 'compact-ratio entry)) 0.75))
              (should (equal (cdr (assoc 'cross-run-runs entry)) 2)))))
        ;; Cleanup
        (delete-directory metrics-dir t))
    (test-prefix-cache--restore-state)))

(provide 'test-gptel-ext-prefix-cache)
;;; test-gptel-ext-prefix-cache.el ends here
