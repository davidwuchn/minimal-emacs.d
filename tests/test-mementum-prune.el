;;; test-mementum-prune.el --- Tests for memory pruning -*- lexical-binding: t; -*-
;;
;; Verifies the mementum prune logic correctly caps memories per topic
;; and removes ones older than max-age-days. Prevents memory bank
;; unbounded growth (YC: feed-forward ≠ unbounded).

;;; Code:

(require 'ert)

;; Load the module under test
(load-file (expand-file-name "lisp/modules/gptel-auto-workflow-mementum.el"
                             default-directory))

;; Override expand-workspace-path for tests via fset
(defvar test-prune--tmp-dir nil)
(defvar test-prune--orig-expand-fn nil)

(defun test-prune--setup-memories (memories)
  "Create MEMORIES (list of plists: (:name NAME :content TEXT :mtime MTIME))
under `test-prune--tmp-dir/mementum/memories/."
  (setq test-prune--tmp-dir (make-temp-file "ov5-prune-" t))
  (let ((mem-dir (expand-file-name "mementum/memories/" test-prune--tmp-dir)))
    (make-directory mem-dir t)
    (dolist (mem memories)
      (let* ((name (plist-get mem :name))
             (content (plist-get mem :content))
             (mtime (or (plist-get mem :mtime) (current-time)))
             (file (expand-file-name name mem-dir)))
        (with-temp-file file
          (insert content))
        (set-file-times file mtime)))
    ;; Override gptel-auto-workflow--expand-workspace-path using fset
    (setq test-prune--orig-expand-fn
          (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
               (symbol-function 'gptel-auto-workflow--expand-workspace-path)))
    (fset 'gptel-auto-workflow--expand-workspace-path
          (lambda (&optional _path) test-prune--tmp-dir))))

(defun test-prune--teardown ()
  (when (and test-prune--tmp-dir (file-directory-p test-prune--tmp-dir))
    (delete-directory test-prune--tmp-dir t))
  (setq test-prune--tmp-dir nil)
  ;; Restore the original function
  (if test-prune--orig-expand-fn
      (fset 'gptel-auto-workflow--expand-workspace-path test-prune--orig-expand-fn)
    (fmakunbound 'gptel-auto-workflow--expand-workspace-path)))

(ert-deftest test-prune/keeps-recent-prunes-old ()
  "Memories within max-age kept; older ones removed."
  (unwind-protect
      (progn
        (test-prune--setup-memories
         (list
          ;; Recent (within 30 days) — should be kept
          (list :name "insight-topic1.md" :content "old insight"
                :mtime (time-subtract (current-time) (days-to-time 5)))
          ;; Old (60 days) — should be pruned
          (list :name "insight-topic1-old.md" :content "ancient insight"
                :mtime (time-subtract (current-time) (days-to-time 60)))))
        (let* ((gptel-auto-workflow-mementum-prune-max-age-days 30)
               (gptel-auto-workflow-mementum-prune-max-per-topic 10)
               (result (gptel-auto-workflow--mementum-prune-stale))
               (pruned (plist-get result :pruned-count))
               (kept (plist-get result :kept-count)))
          (should (= pruned 1))
          (should (= kept 1))))
    (test-prune--teardown)))

(ert-deftest test-prune/caps-per-topic ()
  "Per-topic cap of MAX-PER-TOPIC enforced even for recent memories."
  (unwind-protect
      (progn
        (let ((mems '()))
          ;; 8 recent memories all sharing topic "shared-topic-<hash>"
          ;; (trailing 6+ hex chars) — cap is 5, so 3 should be pruned
          (dotimes (i 8)
            (push (list :name (format "shared-topic-abc123-%d.md" i)
                        :content (format "memory %d" i)
                        :mtime (time-subtract (current-time)
                                              (days-to-time (1+ i))))
                  mems))
          (test-prune--setup-memories mems))
        (let* ((gptel-auto-workflow-mementum-prune-max-age-days 30)
               (gptel-auto-workflow-mementum-prune-max-per-topic 5)
               (result (gptel-auto-workflow--mementum-prune-stale)))
          (should (= (plist-get result :kept-count) 5))
          (should (= (plist-get result :pruned-count) 3))))
    (test-prune--teardown)))

(ert-deftest test-prune/no-op-when-all-recent-and-few ()
  "No pruning needed when memories are recent and within cap."
  (unwind-protect
      (progn
        (test-prune--setup-memories
         (list
          (list :name "insight-fresh1.md" :content "fresh 1"
                :mtime (time-subtract (current-time) (days-to-time 1)))
          (list :name "insight-fresh2.md" :content "fresh 2"
                :mtime (time-subtract (current-time) (days-to-time 2)))))
        (let* ((gptel-auto-workflow-mementum-prune-max-age-days 30)
               (gptel-auto-workflow-mementum-prune-max-per-topic 10)
               (result (gptel-auto-workflow--mementum-prune-stale)))
          (should (= (plist-get result :pruned-count) 0))
          (should (= (plist-get result :kept-count) 2))))
    (test-prune--teardown)))

(provide 'test-mementum-prune)
;;; test-mementum-prune.el ends here
