;;; test-world-store-branch.el --- Branching tests for World Store -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-ext-world-store-branch.el and clj/ov5/world_store/branch.clj.
;; Each test uses an isolated database + nREPL port for independence.
;; Port range: 8000+ to avoid collision with bootstrap (7800+) and query (7900+).

;;; Code:

(require 'ert)

;; ── Load modules ──

(condition-case err
    (progn
      (require 'gptel-ext-world-store)
      (require 'gptel-ext-world-store-branch))
  (error
   (message "[world-store-branch-test] Module load failed: %s" (error-message-string err))
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

(defvar test-world-store-branch--counter 0
  "Counter for unique test IDs.")

(defun test-world-store-branch--next-id ()
  "Generate a unique test ID."
  (setq test-world-store-branch--counter (1+ test-world-store-branch--counter))
  test-world-store-branch--counter)

(defun test-world-store-branch--with-branch-store (body)
  "Run BODY with a fresh World Store branch test setup.
Uses unique DB and nREPL port per test.
Port base is 8000 to avoid bootstrap (7800) and query (7900) tests."
  (let* ((id (test-world-store-branch--next-id))
         (db-path (format "/tmp/ov5-ws-branch-test-%d" id))
         (nrepl-port (+ 8000 id))
         (ov5-world-store-directory db-path)
         (ov5-world-store-nrepl-port nrepl-port))
    (test-world-store--skip-if-unavailable)
    (when (file-exists-p db-path)
      (delete-directory db-path t))
    (unwind-protect
        (progn
          (ov5-world-store-connect)
          (when (fboundp 'ov5-world-store-branch-ensure-main)
            (ov5-world-store-branch-ensure-main))
          (funcall body))
      (ov5-world-store-disconnect)
      (when (file-exists-p db-path)
        (delete-directory db-path t)))))

;; ── Helper: seed experiment data ──

(defun test-world-store-branch--seed-experiment (exp-id target &optional decision)
  "Insert a single experiment into the current store."
  (ov5-world-store-transact
   `((:experiment/id ,exp-id
      :experiment/target ,target
      :experiment/hypothesis "test hypothesis"
      :experiment/score-before 0.5
      :experiment/score-after 0.9
      :experiment/decision ,(or decision "kept")
      :experiment/backend "TestBackend"
      :experiment/strategy "direct"))))

;; ────────────────────────────────────────────────────────────
;; Tests
;; ────────────────────────────────────────────────────────────

(ert-deftest world-store-branch/create-and-list ()
  "Test branch creation and listing."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "test-branch-1")
     (ov5-world-store-branch-create "test-branch-2")
     (ov5-world-store-branch-create "test-branch-3")
     (let ((branches (ov5-world-store-branch-list)))
       ;; Registry should contain main plus our three branches
       (should (string-match-p "main" branches))
       (should (string-match-p "test-branch-1" branches))
       (should (string-match-p "test-branch-2" branches))
       (should (string-match-p "test-branch-3" branches))))))

(ert-deftest world-store-branch/create-with-metadata ()
  "Test branch creation with metadata in registry."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "meta-branch" "main"
                                    '(:experiment/run-id "run-42"))
     (let ((branches (ov5-world-store-branch-list)))
       (should (string-match-p "meta-branch" branches))
       (should (string-match-p "run-42" branches))
       ;; Verify parent is main
       (should (string-match-p ":branch/parent" branches))))))

(ert-deftest world-store-branch/switch-and-write ()
  "Test switching to a branch and writing experiment data."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "write-branch")
     (ov5-world-store-branch-switch "write-branch")
     (test-world-store-branch--seed-experiment "exp-write-1" "test.el" "kept")
     (let ((count (ov5-world-store-experiment-count)))
       ;; Branch should have the experiment
       (should (>= count 1))))))

(ert-deftest world-store-branch/isolation ()
  "Test that writing to a branch does not affect main."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "iso-branch")
     (ov5-world-store-branch-switch "iso-branch")
     (test-world-store-branch--seed-experiment "exp-iso-1" "test.el" "kept")
     ;; Switch back to main
     (ov5-world-store-branch-switch "main")
     (let ((count (ov5-world-store-experiment-count)))
       ;; Main should still be empty (0 experiments)
       (should (<= count 0))))))

(ert-deftest world-store-branch/merge-into-main ()
  "Test merging branch data into main."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "merge-branch")
     (ov5-world-store-branch-switch "merge-branch")
     (test-world-store-branch--seed-experiment "exp-merge-1" "test.el" "kept")
     (test-world-store-branch--seed-experiment "exp-merge-2" "bar.el" "discarded")
     ;; Merge into main
     (ov5-world-store-branch-merge "merge-branch" "main")
     ;; Switch to main and verify
     (ov5-world-store-branch-switch "main")
     (let ((count (ov5-world-store-experiment-count)))
       (should (>= count 2))))))

(ert-deftest world-store-branch/merge-idempotent ()
  "Test that merging the same branch twice does not create duplicates."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "idem-branch")
     (ov5-world-store-branch-switch "idem-branch")
     (test-world-store-branch--seed-experiment "exp-idem-1" "test.el" "kept")
     ;; First merge
     (ov5-world-store-branch-merge "idem-branch" "main")
     (ov5-world-store-branch-switch "main")
     (let ((count1 (ov5-world-store-experiment-count)))
       ;; Second merge should not increase count
       (ov5-world-store-branch-merge "idem-branch" "main")
       (let ((count2 (ov5-world-store-experiment-count)))
         (should (= count1 count2)))))))

(ert-deftest world-store-branch/promote ()
  "Test promoting a branch to become main."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "promo-branch")
     (ov5-world-store-branch-switch "promo-branch")
     (test-world-store-branch--seed-experiment "exp-promo-1" "test.el" "kept")
     ;; Promote to main
     (ov5-world-store-branch-promote "promo-branch")
     ;; After promotion, main should have the experiment
     (ov5-world-store-branch-switch "main")
     (let ((count (ov5-world-store-experiment-count)))
       (should (>= count 1)))
     ;; Old main should be archived in registry
     (let ((branches (ov5-world-store-branch-list)))
       (should (string-match-p "main-@" branches))))))

(ert-deftest world-store-branch/promote-safety ()
  "Test that promoting a non-existent branch errors."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (should-error
      (ov5-world-store-branch-promote "nonexistent-branch")))))

(ert-deftest world-store-branch/delete-branch ()
  "Test deleting a branch."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (ov5-world-store-branch-create "del-branch")
     (let ((before (ov5-world-store-branch-list)))
       (should (string-match-p "del-branch" before)))
     (ov5-world-store-branch-delete "del-branch")
     (let ((after (ov5-world-store-branch-list)))
       (should-not (string-match-p "del-branch" after))))))

(ert-deftest world-store-branch/delete-main-refused ()
  "Test that deleting \"main\" is refused."
  (skip-unless (executable-find "brepl"))
  (test-world-store-branch--with-branch-store
   (lambda ()
     (should-error
      (ov5-world-store-branch-delete "main")))))

;;; test-world-store-branch.el ends here
