;;; test-gptel-ext-conversion-unit.el --- Tests for conversion unit registry -*- lexical-binding: t; -*-

(require 'ert)
(require 'gptel-ext-conversion-unit)

;; ─── Helpers ───

(defvar test-conversion-unit--orig-registry nil)

(defun test-conversion-unit--setup ()
  "Save original registry state."
  (setq test-conversion-unit--orig-registry
        (copy-hash-table gptel-conversion-unit--registry)))

(defun test-conversion-unit--teardown ()
  "Restore original registry state."
  (clrhash gptel-conversion-unit--registry)
  (maphash (lambda (k v) (puthash k v gptel-conversion-unit--registry))
           test-conversion-unit--orig-registry))

;; ─── Core Tests ───

(ert-deftest test-conversion-unit-add-and-get ()
  "Test adding and retrieving a conversion unit."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (let ((unit (gptel-conversion-unit-add
                     "exp-123" 'behavior
                     '(:category "old-cat")
                     '(:category "new-cat")
                     "test-file.el")))
          (should unit)
          (should (gptel-conversion-unit-p unit))
          (should (equal (gptel-conversion-unit-trial-id unit) "exp-123"))
          (should (eq (gptel-conversion-unit-conversion-type unit) 'behavior))
          (should (eq (gptel-conversion-unit-validation-status unit) 'pending))
          ;; Retrieve by ID
          (let ((retrieved (gptel-conversion-unit-get
                            (gptel-conversion-unit-id unit))))
            (should retrieved)
            (should (equal (gptel-conversion-unit-trial-id retrieved)
                           "exp-123")))))
    (test-conversion-unit--teardown)))

(ert-deftest test-conversion-unit-list ()
  "Test listing all conversion units."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (gptel-conversion-unit-add "exp-1" 'repair '(:a 1) '(:a 2))
        (gptel-conversion-unit-add "exp-2" 'drift '(:b 1) '(:b 2))
        (let ((all (gptel-conversion-unit-list)))
          (should (= (length all) 2))
          ;; Sorted by timestamp descending
          (should (> (gptel-conversion-unit-timestamp (car all))
                       (gptel-conversion-unit-timestamp (cadr all))))))
    (test-conversion-unit--teardown)))

(ert-deftest test-conversion-unit-filter-by-type ()
  "Test filtering by conversion type."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (gptel-conversion-unit-add "exp-1" 'repair '(:a 1) '(:a 2))
        (gptel-conversion-unit-add "exp-2" 'drift '(:b 1) '(:b 2))
        (gptel-conversion-unit-add "exp-3" 'repair '(:c 1) '(:c 2))
        (let ((repairs (gptel-conversion-unit-filter-by-type 'repair)))
          (should (= (length repairs) 2))
          (should (cl-every (lambda (u)
                              (eq (gptel-conversion-unit-conversion-type u)
                                  'repair))
                            repairs))))
    (test-conversion-unit--teardown)))

(ert-deftest test-conversion-unit-filter-by-trial ()
  "Test filtering by trial ID."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (gptel-conversion-unit-add "exp-x" 'behavior '(:a 1) '(:a 2))
        (gptel-conversion-unit-add "exp-y" 'behavior '(:b 1) '(:b 2))
        (gptel-conversion-unit-add "exp-x" 'drift '(:c 1) '(:c 2))
        (let ((x-units (gptel-conversion-unit-filter-by-trial "exp-x")))
          (should (= (length x-units) 2))
          (should (cl-every (lambda (u)
                              (equal (gptel-conversion-unit-trial-id u)
                                     "exp-x"))
                            x-units))))
    (test-conversion-unit--teardown)))

(ert-deftest test-conversion-unit-validate ()
  "Test validation status changes."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (let ((unit (gptel-conversion-unit-add "exp-1" 'behavior '(:a 1) '(:a 2))))
          (should (eq (gptel-conversion-unit-validation-status unit) 'pending))
          (gptel-conversion-unit-validate (gptel-conversion-unit-id unit))
          (should (eq (gptel-conversion-unit-validation-status unit) 'validated))
          ;; Reject
          (gptel-conversion-unit-validate (gptel-conversion-unit-id unit) 'rejected)
          (should (eq (gptel-conversion-unit-validation-status unit) 'rejected))))
    (test-conversion-unit--teardown)))

(ert-deftest test-conversion-unit-stats ()
  "Test statistics function."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (gptel-conversion-unit-add "exp-1" 'behavior '(:a 1) '(:a 2))
        (gptel-conversion-unit-add "exp-2" 'drift '(:b 1) '(:b 2))
        (let* ((unit (gptel-conversion-unit-add "exp-3" 'repair '(:c 1) '(:c 2)))
               (_ (gptel-conversion-unit-validate (gptel-conversion-unit-id unit))))
          (let ((stats (gptel-conversion-unit-stats)))
            (should (string-match-p "Total: 3" stats))
            (should (string-match-p "Pending: 2" stats))
            (should (string-match-p "Validated: 1" stats)))))
    (test-conversion-unit--teardown)))

;; ─── Persistence Tests ───

(ert-deftest test-conversion-unit-persist-and-load ()
  "Test JSONL persistence and loading."
  (test-conversion-unit--setup)
  (let ((test-dir (make-temp-file "conversion-units-" t)))
    (unwind-protect
        (let ((gptel-conversion-unit-persist-dir test-dir)
              (gptel-conversion-unit-enabled t))
          (gptel-conversion-unit-clear)
          ;; Add units
          (gptel-conversion-unit-add "exp-persist" 'behavior
                                      '(:category "before")
                                      '(:category "after")
                                      "test.el")
          ;; Persist
          (gptel-conversion-unit-persist)
          (should (file-exists-p (gptel-conversion-unit--current-file)))
          ;; Clear and reload
          (gptel-conversion-unit-clear)
          (should (= (gptel-conversion-unit-count) 0))
          (gptel-conversion-unit-load)
          (should (= (gptel-conversion-unit-count) 1))
          (let ((unit (car (gptel-conversion-unit-list))))
            (should (equal (gptel-conversion-unit-trial-id unit) "exp-persist"))
            (should (eq (gptel-conversion-unit-conversion-type unit) 'behavior))))
      ;; Cleanup
      (test-conversion-unit--teardown)
      (when (file-directory-p test-dir)
        (delete-directory test-dir t)))))

(ert-deftest test-conversion-unit-rotate ()
  "Test rotation of old JSONL files."
  (let ((test-dir (make-temp-file "conversion-units-" t)))
    (unwind-protect
        (let ((gptel-conversion-unit-persist-dir test-dir)
              (gptel-conversion-unit-max-age-days 1))
          ;; Create an old file (set mtime to 10 days ago)
          (let ((old-file (expand-file-name "2024-01.jsonl" test-dir)))
            (with-temp-file old-file
              (insert "{}\n"))
            (set-file-times old-file (- (float-time) (* 10 24 60 60)))
            ;; Create a recent file
            (let ((recent-file (expand-file-name "2026-06.jsonl" test-dir)))
              (with-temp-file recent-file
                (insert "{}\n"))
              ;; Rotate
              (gptel-conversion-unit-rotate)
              ;; Old file should be deleted
              (should (not (file-exists-p old-file)))
              ;; Recent file should remain
              (should (file-exists-p recent-file)))))
      (when (file-directory-p test-dir)
        (delete-directory test-dir t)))))

;; ─── Serialization Tests ───

(ert-deftest test-conversion-unit-serialize-roundtrip ()
  "Test plist serialization roundtrip."
  (let* ((unit (gptel-conversion-unit--create
                :id "test-id"
                :trial-id "exp-1"
                :conversion-type 'repair
                :before-state '(:category "old")
                :after-state '(:category "new")
                :timestamp 1234567890.0
                :validation-status 'validated
                :source-file "test.el"
                :context '(:extra "info")))
         (plist (gptel-conversion-unit--to-plist unit))
         (restored (gptel-conversion-unit--from-plist plist)))
    (should (equal (gptel-conversion-unit-id restored) "test-id"))
    (should (equal (gptel-conversion-unit-trial-id restored) "exp-1"))
    (should (eq (gptel-conversion-unit-conversion-type restored) 'repair))
    (should (equal (gptel-conversion-unit-before-state restored) '(:category "old")))
    (should (equal (gptel-conversion-unit-after-state restored) '(:category "new")))
    (should (= (gptel-conversion-unit-timestamp restored) 1234567890.0))
    (should (eq (gptel-conversion-unit-validation-status restored) 'validated))
    (should (equal (gptel-conversion-unit-source-file restored) "test.el"))
    (should (equal (gptel-conversion-unit-context restored) '(:extra "info")))))

;; ─── Edge Cases ───

(ert-deftest test-conversion-unit-disabled ()
  "Test that tracking is skipped when disabled."
  (test-conversion-unit--setup)
  (unwind-protect
      (let ((gptel-conversion-unit-enabled nil))
        (gptel-conversion-unit-clear)
        (gptel-conversion-unit-add "exp-1" 'behavior '(:a 1) '(:a 2))
        (should (= (gptel-conversion-unit-count) 0)))
    (test-conversion-unit--teardown)))

(ert-deftest test-conversion-unit-empty-registry ()
  "Test operations on empty registry."
  (test-conversion-unit--setup)
  (unwind-protect
      (progn
        (gptel-conversion-unit-clear)
        (should (= (gptel-conversion-unit-count) 0))
        (should (null (gptel-conversion-unit-list)))
        (should (null (gptel-conversion-unit-filter-by-type 'behavior)))
        (should (string-match-p "Total: 0" (gptel-conversion-unit-stats))))
    (test-conversion-unit--teardown)))

(provide 'test-gptel-ext-conversion-unit)
;;; test-gptel-ext-conversion-unit.el ends here
