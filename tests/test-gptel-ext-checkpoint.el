;;; test-gptel-ext-checkpoint.el --- Checkpoint EDN serialization tests -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'gptel-ext-checkpoint)

(ert-deftest test-gptel-checkpoint-serialize-edn ()
  "Serialize checkpoint to EDN and back, preserving data."
  (let* ((data (gptel-checkpoint-data-create
                :version 1
                :state 'running
                :run-id "test-run"
                :project-root "/tmp/project"
                :targets '("a.el" "b.el")
                :current-target "a.el"
                :targets-done '("done.el")
                :targets-failed '("fail.el")
                :current-exp-id 3
                :current-exp-count 2
                :current-best-score 0.75
                :no-improvement-count 1
                :results '((:id "exp-1" :target "a.el" :kept t :score-after 0.8))
                :total-experiments 5
                :started-at "2026-01-01T00:00:00Z"
                :checkpoint-at "2026-01-01T01:00:00Z"
                :last-target-at "2026-01-01T00:30:00Z"
                :experiment-loop-snapshot '(:exp-id 3 :best-score 0.75)
                :metadata '(:foo "bar")))
         (round (gptel-checkpoint--deserialize (gptel-checkpoint--serialize data))))
    (should (= 1 (gptel-checkpoint-data-version round)))
    (should (eq 'running (gptel-checkpoint-data-state round)))
    (should (string= "test-run" (gptel-checkpoint-data-run-id round)))
    (should (equal '("a.el" "b.el") (gptel-checkpoint-data-targets round)))
    (should (equal '("done.el") (gptel-checkpoint-data-targets-done round)))
    (should (equal '("fail.el") (gptel-checkpoint-data-targets-failed round)))
    (should (string= "a.el" (gptel-checkpoint-data-current-target round)))
    (should (= 3 (gptel-checkpoint-data-current-exp-id round)))
    (should (= 2 (gptel-checkpoint-data-current-exp-count round)))
    (should (= 0.75 (gptel-checkpoint-data-current-best-score round)))
    (should (= 1 (gptel-checkpoint-data-no-improvement-count round)))
    (should (= 5 (gptel-checkpoint-data-total-experiments round)))
    (should (= 1 (length (gptel-checkpoint-data-results round))))
    (let ((result (car (gptel-checkpoint-data-results round))))
      (should (string= "exp-1" (plist-get result :id)))
      (should (eq t (plist-get result :kept)))
      (should (= 0.8 (plist-get result :score-after))))
    (should (equal '(:foo "bar") (gptel-checkpoint-data-metadata round)))
    (should (equal '(:exp-id 3 :best-score 0.75)
                   (gptel-checkpoint-data-experiment-loop-snapshot round)))))

(ert-deftest test-gptel-checkpoint-save-and-load-edn ()
  "Save checkpoint to disk and load it back."
  (let* ((root (make-temp-file "ov5-checkpoint-" t))
         (base-dir (expand-file-name "checkpoints" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-checkpoint--base-dir)
                   (lambda () base-dir)))
          (setq gptel-checkpoint--current
                (gptel-checkpoint-data-create
                 :version 1
                 :state 'running
                 :run-id "disk-run"
                 :project-root root
                 :targets '("x.el")
                 :current-target "x.el"
                 :current-exp-id 1
                 :results nil
                 :total-experiments 0
                 :started-at "2026-01-01T00:00:00Z"
                 :checkpoint-at "2026-01-01T00:00:00Z"))
          (setq gptel-checkpoint--dirty t)
          (should (gptel-checkpoint--save))
          (should (file-exists-p (expand-file-name "active.edn" base-dir)))
          (let ((loaded (gptel-checkpoint--load)))
            (should loaded)
            (should (string= "disk-run" (gptel-checkpoint-data-run-id loaded)))
            (should (eq 'running (gptel-checkpoint-data-state loaded)))
            (should (equal '("x.el") (gptel-checkpoint-data-targets loaded)))))
      (setq gptel-checkpoint--current nil
            gptel-checkpoint--dirty nil)
      (delete-directory root t))))

(ert-deftest test-gptel-checkpoint-archive-uses-edn ()
  "Archiving must move active.edn to history/<run-id>.edn."
  (let* ((root (make-temp-file "ov5-checkpoint-" t))
         (base-dir (expand-file-name "checkpoints" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-checkpoint--base-dir)
                   (lambda () base-dir)))
          (setq gptel-checkpoint--current
                (gptel-checkpoint-data-create
                 :version 1
                 :state 'completed
                 :run-id "archive-run"
                 :project-root root
                 :targets '("y.el")
                 :started-at "2026-01-01T00:00:00Z"
                 :checkpoint-at "2026-01-01T00:00:00Z"))
          (setq gptel-checkpoint--dirty t)
          (gptel-checkpoint--save)
          (gptel-checkpoint--archive "archive-run")
          (should-not (file-exists-p (expand-file-name "active.edn" base-dir)))
          (should (file-exists-p (expand-file-name "history/archive-run.edn" base-dir))))
      (setq gptel-checkpoint--current nil
            gptel-checkpoint--dirty nil)
      (delete-directory root t))))

(ert-deftest test-gptel-checkpoint-legacy-json-migration ()
  "Legacy JSON .ckpt must be loaded and converted to EDN."
  (let* ((root (make-temp-file "ov5-checkpoint-" t))
         (base-dir (expand-file-name "checkpoints" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-checkpoint--base-dir)
                   (lambda () base-dir)))
          (make-directory base-dir t)
          (with-temp-file (expand-file-name "active.ckpt" base-dir)
            (insert "{\"version\":1,\"state\":\"running\",\"run-id\":\"legacy-run\",\"project-root\":\"" root "\",\"targets\":[\"z.el\"],\"current-target\":\"z.el\",\"targets-done\":[],\"targets-failed\":[],\"current-exp-id\":1,\"current-exp-count\":0,\"current-best-score\":0.0,\"no-improvement-count\":0,\"results\":[],\"total-experiments\":0,\"started-at\":\"2026-01-01T00:00:00Z\",\"checkpoint-at\":\"2026-01-01T00:00:00Z\",\"last-target-at\":null,\"experiment-loop-snapshot\":null,\"metadata\":null}"))
          (let ((loaded (gptel-checkpoint--load)))
            (should loaded)
            (should (string= "legacy-run" (gptel-checkpoint-data-run-id loaded)))
            (should (file-exists-p (expand-file-name "active.edn" base-dir)))
            (should (file-exists-p (expand-file-name "active.ckpt.migrated" base-dir)))))
      (setq gptel-checkpoint--current nil
            gptel-checkpoint--dirty nil)
      (delete-directory root t))))

(ert-deftest test-gptel-checkpoint-empty-results-roundtrip ()
  "Checkpoint with no results must round-trip."
  (let* ((data (gptel-checkpoint-data-create
                :version 1
                :state 'pending
                :run-id "empty-run"))
         (round (gptel-checkpoint--deserialize (gptel-checkpoint--serialize data))))
    (should (= 1 (gptel-checkpoint-data-version round)))
    (should (eq 'pending (gptel-checkpoint-data-state round)))
    (should (string= "empty-run" (gptel-checkpoint-data-run-id round)))
    (should (null (gptel-checkpoint-data-results round)))
    (should (= 1 (gptel-checkpoint-data-current-exp-id round)))
    (should (= 0 (gptel-checkpoint-data-current-exp-count round)))
    (should (= 0.0 (gptel-checkpoint-data-current-best-score round)))))

(provide 'test-gptel-ext-checkpoint)
;;; test-gptel-ext-checkpoint.el ends here
