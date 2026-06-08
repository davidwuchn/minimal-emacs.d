;;; test-self-audit.el --- Tests for self-audit module -*- lexical-binding: t; -*-
;;
;; Verifies that the self-audit module can detect:
;; 1. Backend cold-start (backends with 0 recent experiments)
;; 2. Strategy cold-start (strategies never evaluated)
;; 3. Staging-merge bottleneck (>50% of failures from staging-merge)
;; 4. Module byte-compile health (modules that can't compile)
;;
;; This is the META layer: the system auditing itself for the patterns
;; a human reviewer keeps finding manually.

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "lisp/modules/gptel-auto-workflow-self-audit.el"
                             default-directory))

;; ---- Test fixtures ----

(defvar test-self-audit--tmp-dir nil
  "Temporary directory for test data.")

(defun test-self-audit--setup ()
  "Create temp dir and mock experiment data."
  (setq test-self-audit--tmp-dir
        (expand-file-name
         (concat "test-self-audit-" (format-time-string "%s"))
         temporary-file-directory))
  (make-directory test-self-audit--tmp-dir t)
  ;; Create var/tmp/experiments/ with a TSV file
  (let ((exp-dir (expand-file-name "var/tmp/experiments"
                                    test-self-audit--tmp-dir)))
    (make-directory exp-dir t)
    (with-temp-file (expand-file-name "results.tsv" exp-dir)
      ;; TSV: 16 fields per row, backend at field 15, decision at field 7,
      ;; strategy at field 21
      ;; Row 1: backend=DeepSeek, decision=kept, strategy=strategy-v1
      (insert "0\t0\t0\t0\t0\t0\t0\tkept\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v1\t0\t0\n")
      ;; Row 2: backend=DeepSeek, decision=staging-merge-failed, strategy=strategy-v1
      (insert "0\t0\t0\t0\t0\t0\t0\tstaging-merge-failed\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v1\t0\t0\n")
      ;; Row 3: backend=MiniMax, decision=kept, strategy=strategy-v2
      (insert "0\t0\t0\t0\t0\t0\t0\tkept\t0\t0\t0\t0\t0\t0\t0\tMiniMax\t0\t0\t0\t0\t0\tstrategy-v2\t0\t0\n")))
  ;; Create mementum/memories/
  (make-directory (expand-file-name "mementum/memories"
                                    test-self-audit--tmp-dir) t))

(defun test-self-audit--teardown ()
  "Delete temp dir and restore defaults."
  (when (and test-self-audit--tmp-dir
             (file-exists-p test-self-audit--tmp-dir))
    (delete-directory test-self-audit--tmp-dir t))
  (setq test-self-audit--tmp-dir nil))

;; Override root to use temp dir
(defun test-self-audit--mock-root ()
  "Return test temp dir as workspace root."
  test-self-audit--tmp-dir)

;; ---- Tests ----

(ert-deftest test-self-audit/backend-cold-start ()
  "Backends not seen in TSV data should appear as cold."
  (test-self-audit--setup)
  (unwind-protect
      (let ((gptel-auto-workflow-self-audit-enabled t))
        ;; Override --root to return our temp dir
        (fset 'gptel-auto-workflow-self-audit--root
              #'test-self-audit--mock-root)
        ;; Override --all-backends to return a known list
        (fset 'gptel-auto-workflow-self-audit--all-backends
              (lambda () '("DeepSeek" "MiniMax" "ColdBackend1" "ColdBackend2")))
        (let* ((bca (gptel-auto-workflow-self-audit--run-backend-check))
               (cold (plist-get bca :cold)))
          (should (= 2 (length cold)))
          (should (member "ColdBackend1" cold))
          (should (member "ColdBackend2" cold))
          ;; DeepSeek and MiniMax should NOT be cold
          (should (not (member "DeepSeek" cold)))
          (should (not (member "MiniMax" cold)))))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/strategy-cold-start ()
  "Strategies not seen in TSV data should appear as unevaluated."
  (test-self-audit--setup)
  (unwind-protect
      (let ((gptel-auto-workflow-self-audit-enabled t))
        (fset 'gptel-auto-workflow-self-audit--root
              #'test-self-audit--mock-root)
        (fset 'gptel-auto-workflow-self-audit--all-strategies
              (lambda () '("strategy-v1" "strategy-v2" "strategy-cold1")))
        (let* ((sca (gptel-auto-workflow-self-audit--run-strategy-check))
               (unevaluated (plist-get sca :unevaluated))
               (unevaluated-names (plist-get sca :unevaluated-names)))
          (should (= 1 unevaluated))
          (should (member "strategy-cold1" unevaluated-names))
          ;; v1 and v2 should NOT be unevaluated
          (should (not (member "strategy-v1" unevaluated-names)))))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/merge-bottleneck ()
  "When staging-merge failures exceed threshold, bottleneck-p should be true."
  (test-self-audit--setup)
  (unwind-protect
      (let ((gptel-auto-workflow-self-audit-enabled t)
            (gptel-auto-workflow-self-audit-bottleneck-threshold 0.5))
        (fset 'gptel-auto-workflow-self-audit--root
              #'test-self-audit--mock-root)
        ;; Our TSV has 3 rows: 2 kept + 1 staging-merge-failed
        ;; staging-total=1, total=3, fraction=0.33 -> NOT bottleneck
        (let* ((sma (gptel-auto-workflow-self-audit--run-merge-check)))
          (should (not (plist-get sma :bottleneck-p)))
          (should (= 3 (plist-get sma :total)))
          (should (= 1 (plist-get sma :staging-merge-count))))
        ;; Now REPLACE the TSV with one where 4/5 are staging-merge-failed
        ;; (fraction 0.8 > 0.5 threshold -> IS bottleneck)
        (let ((exp-dir (expand-file-name "var/tmp/experiments"
                                          test-self-audit--tmp-dir)))
          ;; Remove the old file
          (delete-file (expand-file-name "results.tsv" exp-dir))
          (with-temp-file (expand-file-name "results.tsv" exp-dir)
            (insert "0\t0\t0\t0\t0\t0\t0\tstaging-merge-failed\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v1\t0\t0\n")
            (insert "0\t0\t0\t0\t0\t0\t0\tstaging-merge-failed\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v2\t0\t0\n")
            (insert "0\t0\t0\t0\t0\t0\t0\tstaging-merge-failed\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v3\t0\t0\n")
            (insert "0\t0\t0\t0\t0\t0\t0\tstaging-merge-failed\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v4\t0\t0\n")
            (insert "0\t0\t0\t0\t0\t0\t0\tkept\t0\t0\t0\t0\t0\t0\t0\tDeepSeek\t0\t0\t0\t0\t0\tstrategy-v5\t0\t0\n"))
          (let* ((sma (gptel-auto-workflow-self-audit--run-merge-check)))
            ;; 4/5 = 80% > 50% threshold -> IS bottleneck
            (should (plist-get sma :bottleneck-p))
            (should (= 5 (plist-get sma :total)))
            (should (= 4 (plist-get sma :staging-merge-count))))))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/byte-compile-health ()
  "Byte-compile check should detect broken modules."
  (test-self-audit--setup)
  (unwind-protect
      (let ((gptel-auto-workflow-self-audit-enabled t))
        (fset 'gptel-auto-workflow-self-audit--root
              #'test-self-audit--mock-root)
        ;; Create a broken .el file in the modules dir
        (let ((mod-dir (expand-file-name "lisp/modules"
                                          test-self-audit--tmp-dir)))
          (make-directory mod-dir t)
          ;; Write a broken module (missing close paren)
          (with-temp-file (expand-file-name
                           "gptel-auto-workflow-test-broken.el" mod-dir)
            (insert "(defun broken-test ()\n  \"broken\"\n  (let ((x 1))\n    x\n"))
          ;; Write a healthy module
          (with-temp-file (expand-file-name
                           "gptel-auto-workflow-test-healthy.el" mod-dir)
            (insert "(defun healthy-test ()\n  \"healthy\"\n  (let ((x 1))\n    x))\n"))
          ;; Add load-path for the healthy module's dependencies
          (let ((default-directory mod-dir))
            (add-to-list 'load-path mod-dir))
          (let* ((bcc (gptel-auto-workflow-self-audit--byte-compile-check))
                 (broken (plist-get bcc :broken)))
            ;; Should detect the broken module
            (should (>= (length broken) 1))
            ;; The healthy module should NOT be in broken list
            (should (not (assoc "gptel-auto-workflow-test-healthy.el"
                                broken)))
            ;; The broken module should be in broken list
            (should (assoc "gptel-auto-workflow-test-broken.el"
                           broken)))))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/full-run-and-report ()
  "Full audit run should produce a result plist and formatted report."
  (test-self-audit--setup)
  (unwind-protect
      (let ((gptel-auto-workflow-self-audit-enabled t))
        (fset 'gptel-auto-workflow-self-audit--root
              #'test-self-audit--mock-root)
        (fset 'gptel-auto-workflow-self-audit--all-backends
              (lambda () '("DeepSeek" "MiniMax" "ColdBackend1")))
        (fset 'gptel-auto-workflow-self-audit--all-strategies
              (lambda () '("strategy-v1" "strategy-v2" "strategy-cold1")))
        ;; Skip byte-compile check (would need real modules)
        (fset 'gptel-auto-workflow-self-audit--byte-compile-check
              (lambda () (list :broken nil :total 0 :healthy t)))
        (let* ((result (gptel-auto-workflow-self-audit-run))
               (report (gptel-auto-workflow-self-audit--format-report result)))
          ;; Result should be a plist with expected keys
          (should result)
          (should (plist-member result :issues))
          (should (> (plist-get result :issues) 0))
          ;; Report should be a non-empty string
          (should report)
          (should (string-match "Self-Audit" report))
          ;; Cold backends should appear somewhere in the result
           (should (member "ColdBackend1" (plist-get (plist-get result :backend-cold-start) :cold)))))
     (test-self-audit--teardown)))

;; ── Synthesis Tests ──

(ert-deftest test-self-audit/read-audit-memories-empty ()
  "Returns nil when no audit-fix memory files exist."
  (test-self-audit--setup)
  (unwind-protect
      (let ((memories (gptel-auto-workflow-self-audit--read-audit-memories)))
        (should (null memories)))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/read-audit-memories-parses-files ()
  "Parses audit-fix memory files and returns list of plists."
  (test-self-audit--setup)
  (unwind-protect
      (progn
        ;; Create 3 audit-fix memory files
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-1.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-01T10:00:00\nissues: 5\n---\n\nBackend cold-start: 3/8 backends\nStrategy cold-start: 12/15 strategies\nBOTTLENECK: staging-merge\n"))
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-2.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-02T10:00:00\nissues: 4\n---\n\nBackend cold-start: 2/8 backends\nStrategy cold-start: 10/15 strategies\n"))
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-3.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-03T10:00:00\nissues: 3\n---\n\nBackend cold-start: 4/8 backends\nBOTTLENECK: staging-merge\n"))
        (let ((memories (gptel-auto-workflow-self-audit--read-audit-memories)))
          (should (= (length memories) 3))
          ;; Check that at least one has cold backends
          (should (> (seq-count (lambda (m) (> (plist-get m :cold-backends) 0)) memories) 0))))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/synthesize-system-health-below-threshold ()
  "Returns nil when fewer than 3 audit-fix memories exist."
  (test-self-audit--setup)
  (unwind-protect
      (progn
        ;; Create only 2 audit-fix memory files
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-1.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-01T10:00:00\nissues: 5\n---\n\nBackend cold-start: 3/8 backends\n"))
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-2.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-02T10:00:00\nissues: 4\n---\n\nBackend cold-start: 2/8 backends\n"))
        (let ((result (gptel-auto-workflow-self-audit--synthesize-system-health)))
          (should (null result))
          ;; Knowledge page should NOT be created
          (should-not (file-exists-p
                       (expand-file-name "mementum/knowledge/system-health-patterns.md"
                                         test-self-audit--tmp-dir)))))
    (test-self-audit--teardown)))

(ert-deftest test-self-audit/synthesize-system-health-creates-knowledge-page ()
  "Creates system-health-patterns.md when >=3 audit-fix memories exist."
  (test-self-audit--setup)
  (unwind-protect
      (progn
        ;; Create 3 audit-fix memory files
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-1.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-01T10:00:00\nissues: 5\n---\n\nBackend cold-start: 3/8 backends\nStrategy cold-start: 12/15 strategies\nBOTTLENECK: staging-merge\n"))
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-2.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-02T10:00:00\nissues: 4\n---\n\nBackend cold-start: 2/8 backends\nStrategy cold-start: 10/15 strategies\nBOTTLENECK: staging-merge\n"))
        (with-temp-file (expand-file-name "mementum/memories/audit-fix-run-3.md" test-self-audit--tmp-dir)
          (insert "---\ntimestamp: 2026-06-03T10:00:00\nissues: 3\n---\n\nBackend cold-start: 4/8 backends\nBOTTLENECK: staging-merge\n"))
        (let ((result (gptel-auto-workflow-self-audit--synthesize-system-health)))
          (should (= result 3))
          ;; Knowledge page should be created
          (should (file-exists-p
                   (expand-file-name "mementum/knowledge/system-health-patterns.md"
                                     test-self-audit--tmp-dir)))
          ;; Content should contain key sections
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "mementum/knowledge/system-health-patterns.md"
                               test-self-audit--tmp-dir))
            (goto-char (point-min))
            (should (search-forward "System Health Patterns" nil t))
            (should (search-forward "Backend Cold-Start" nil t))
            (should (search-forward "Staging-Merge Bottleneck" nil t)))))
    (test-self-audit--teardown)))

(provide 'test-self-audit)
;;; test-self-audit.el ends here