;;; test-world-store-migration.el --- Migration tests for World Store -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for TSV migration into the World Store.

;;; Code:

(require 'ert)

(condition-case err
    (require 'gptel-ext-world-store)
  (error
   (message "[world-store-test] Module load failed: %s" (error-message-string err))
   (defun ov5-world-store-connect () (error "brepl unavailable"))
   (defun ov5-world-store-disconnect () nil)
   (defun ov5-world-store-connected-p () nil)))

(defvar test-world-store--migration-counter 100)

(defun test-world-store--next-migration-id ()
  "Generate a unique test ID."
  (setq test-world-store--migration-counter (1+ test-world-store--migration-counter))
  test-world-store--migration-counter)

(defun test-world-store--with-migration-store (body)
  "Run BODY with a fresh World Store connection for migration tests."
  (let* ((id (test-world-store--next-migration-id))
         (db-path (format "/tmp/ov5-ws-migration-test-%d" id))
         (nrepl-port (+ 7900 id))
         (ov5-world-store-directory db-path)
         (ov5-world-store-nrepl-port nrepl-port))
    (when (file-exists-p db-path)
      (delete-directory db-path t))
    (unwind-protect
        (progn
          (ov5-world-store-connect)
          (funcall body))
      (ov5-world-store-disconnect)
      (when (file-exists-p db-path)
        (delete-directory db-path t)))))

;; -----------------------------------------------------------------------------
;; Migration Tests

(ert-deftest world-store/migrate-single-tsv ()
  "Test migrating a single TSV file."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-migration-store
   (lambda ()
     ;; Create a test TSV file
     (let* ((tsv-dir (make-temp-file "ov5-migration-" t))
            (tsv-file (expand-file-name "results.tsv" tsv-dir)))
       (with-temp-file tsv-file
         (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\toutput_chars\tbackend\tprompt_chars\tsections_included\texploration_axis\tcandidate_scores\tstrategy\tresearch_strategy\tresearch_hash\tresearch_quality\tcontroller_decision\tkibcm_axis\tmodel\teight_key_scores\tskills\tedit_mode\n")
         (insert "1\ttest.el\tfix bug\t0.5\t0.8\t0.7\t0.3\tkept\t120\t0.9\tgood\t:ok\tnil\toutput\t100\tMiniMax\t50\tall\t?\t\tdirect\tnone\thash123\thigh\tpersisted\t?\tmodel1\t\t\tnone\n")
         (insert "2\ttest2.el\trefactor\t0.4\t0.6\t0.6\t0.2\tdiscarded\t90\t0.7\tmeh\t:ok\tnil\toutput2\t80\tGemini\t40\tall\t?\t\tdirect\tnone\thash456\tlow\tpersisted\t?\tmodel2\t\t\tnone\n"))
       ;; Run migration via brepl, passing store path
       (let ((code (format "(load-file \"clj/ov5/world_store.clj\") (load-file \"clj/ov5/world_store/migration.clj\") (ns ov5.world-store.migration) (migrate-directory \"%s\" \"%s\")" tsv-dir ov5-world-store-directory)))
         (ov5-world-store--brepl-eval code))
       ;; Verify count
       (let ((count (ov5-world-store-experiment-count)))
         (should (>= count 2)))
       ;; Cleanup
       (delete-directory tsv-dir t)))))

(ert-deftest world-store/migrate-multi-schema ()
  "Test migrating TSVs with different schema versions."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-migration-store
   (lambda ()
     (let* ((base-dir (make-temp-file "ov5-multi-" t))
            (dir30 (expand-file-name "run-30" base-dir))
            (dir39 (expand-file-name "run-39" base-dir))
            (dir43 (expand-file-name "run-43" base-dir)))
       ;; Create 30-col TSV
       (make-directory dir30 t)
       (with-temp-file (expand-file-name "results.tsv" dir30)
         (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\toutput_chars\tbackend\tprompt_chars\tsections_included\texploration_axis\tcandidate_scores\tstrategy\tresearch_strategy\tresearch_hash\tresearch_quality\tcontroller_decision\tkibcm_axis\tmodel\teight_key_scores\tskills\tedit_mode\n")
         (insert "1\tfoo.el\th1\t0.5\t0.8\t0.7\t0.3\tkept\t100\t0.9\tg\t:ok\tnil\to\t50\tB1\t20\tall\t?\t\ts1\tnone\th1\thigh\tpersisted\t?\tm1\t\t\tnone\n"))
       ;; Create 39-col TSV
       (make-directory dir39 t)
       (with-temp-file (expand-file-name "results.tsv" dir39)
         (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\toutput_chars\tbackend\tprompt_chars\tsections_included\texploration_axis\tcandidate_scores\tstrategy\tresearch_strategy\tresearch_hash\tresearch_quality\tcontroller_decision\tkibcm_axis\tmodel\teight_key_scores\tskills\tedit_mode\tcost_usd\teffort_level\tprod_error_rate_before\tprod_error_rate_after\tprod_error_rate_delta\tuser_satisfaction_delta\tsupport_tickets_reduced\tbusiness_value_score\trisk_score\n")
         (insert "1\tbar.el\th2\t0.4\t0.7\t0.6\t0.3\tkept\t110\t0.8\tg\t:ok\tnil\to\t60\tB2\t25\tall\t?\t\ts2\tnone\th2\tmed\tpersisted\t?\tm2\t\t\tnone\t0.01\tlow\t0.1\t0.05\t-0.05\t0.2\t1\t50\t10\n"))
       ;; Create 43-col TSV
       (make-directory dir43 t)
       (with-temp-file (expand-file-name "results.tsv" dir43)
         (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\toutput_chars\tbackend\tprompt_chars\tsections_included\texploration_axis\tcandidate_scores\tstrategy\tresearch_strategy\tresearch_hash\tresearch_quality\tcontroller_decision\tkibcm_axis\tmodel\teight_key_scores\tskills\tedit_mode\tcost_usd\teffort_level\tprod_error_rate_before\tprod_error_rate_after\tprod_error_rate_delta\tuser_satisfaction_delta\tsupport_tickets_reduced\tbusiness_value_score\trisk_score\tcomplexity_before\tcomplexity_after\tlines_removed\tunderstanding_score\n")
         (insert "1\tbaz.el\th3\t0.6\t0.9\t0.8\t0.3\tkept\t120\t0.9\tg\t:ok\tnil\to\t70\tB3\t30\tall\t?\t\ts3\tnone\th3\thigh\tpersisted\t?\tm3\t\t\tnone\t0.02\tmed\t0.2\t0.1\t-0.1\t0.3\t2\t60\t15\t5\t3\t10\t0.8\n"))
       ;; Migrate all
       (let ((code (format "(load-file \"clj/ov5/world_store.clj\") (load-file \"clj/ov5/world_store/migration.clj\") (ns ov5.world-store.migration) (migrate-directory \"%s\" \"%s\")" base-dir ov5-world-store-directory)))
         (ov5-world-store--brepl-eval code))
       ;; Should have 3 experiments
       (let ((count (ov5-world-store-experiment-count)))
         (should (= count 3)))
       ;; Cleanup
       (delete-directory base-dir t)))))

(ert-deftest world-store/migrate-idempotent ()
  "Test that re-migrating is idempotent (upserts)."
  (skip-unless (executable-find "brepl"))
  (test-world-store--with-migration-store
   (lambda ()
     (let* ((tsv-dir (make-temp-file "ov5-idem-" t))
            (tsv-file (expand-file-name "results.tsv" tsv-dir)))
       (with-temp-file tsv-file
         (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\toutput_chars\tbackend\tprompt_chars\tsections_included\texploration_axis\tcandidate_scores\tstrategy\tresearch_strategy\tresearch_hash\tresearch_quality\tcontroller_decision\tkibcm_axis\tmodel\teight_key_scores\tskills\tedit_mode\n")
         (insert "1\tfoo.el\th1\t0.5\t0.8\t0.7\t0.3\tkept\t100\t0.9\tg\t:ok\tnil\to\t50\tB1\t20\tall\t?\t\ts1\tnone\th1\thigh\tpersisted\t?\tm1\t\t\tnone\n"))
       ;; First migration
       (let ((code (format "(load-file \"clj/ov5/world_store.clj\") (load-file \"clj/ov5/world_store/migration.clj\") (ns ov5.world-store.migration) (migrate-directory \"%s\" \"%s\")" tsv-dir ov5-world-store-directory)))
         (ov5-world-store--brepl-eval code))
       (let ((count1 (ov5-world-store-experiment-count)))
         ;; Second migration (same data)
         (let ((code (format "(load-file \"clj/ov5/world_store.clj\") (load-file \"clj/ov5/world_store/migration.clj\") (ns ov5.world-store.migration) (migrate-directory \"%s\" \"%s\")" tsv-dir ov5-world-store-directory)))
           (ov5-world-store--brepl-eval code))
         (let ((count2 (ov5-world-store-experiment-count)))
           ;; Count should be same (upsert)
           (should (= count1 count2))))
       ;; Cleanup
       (delete-directory tsv-dir t)))))

;;; test-world-store-migration.el ends here
