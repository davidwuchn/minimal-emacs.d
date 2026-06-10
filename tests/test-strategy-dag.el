;;; test-strategy-dag.el --- Tests for strategy DAG (APEX insight) -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

;; Set up load path for modules (go up one dir from tests/)
(let* ((base-dir (file-name-directory
                  (directory-file-name
                   (file-name-directory (or load-file-name
                                            (buffer-file-name)
                                            default-directory)))))
       (modules-dir (expand-file-name "lisp/modules" base-dir)))
  (add-to-list 'load-path modules-dir)
  (load (expand-file-name "gptel-tools-agent-strategy-harness" modules-dir) nil t))

(ert-deftest test-strategy-dag/prerequisites-met-when-empty ()
  "Strategy with no prerequisites is always available."
  (let ((gptel-auto-workflow--strategy-dag (make-hash-table :test 'equal)))
    (should (gptel-auto-workflow--strategy-prerequisites-met-p "any-strategy"))))

(ert-deftest test-strategy-dag/prerequisites-blocked ()
  "Strategy with prerequisites is blocked until they succeed."
  (let ((gptel-auto-workflow--strategy-dag (make-hash-table :test 'equal)))
    (puthash "complex" '("basic") gptel-auto-workflow--strategy-dag)
    ;; Mock: "basic" has 0 kept experiments
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-strategy-performance)
               (lambda (name)
                 (list :total 1 :kept 0 :success-rate 0.0 :avg-score 0.0))))
      ;; Should be blocked because "basic" has no successes
      (should-not (gptel-auto-workflow--strategy-prerequisites-met-p "complex")))))

(ert-deftest test-strategy-dag/prerequisites-unblocked ()
  "Strategy becomes available when prerequisites have successes."
  (let ((gptel-auto-workflow--strategy-dag (make-hash-table :test 'equal)))
    (puthash "complex" '("basic") gptel-auto-workflow--strategy-dag)
    ;; Mock: "basic" has 1 kept experiment
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-strategy-performance)
               (lambda (name)
                 (if (equal name "basic")
                     (list :total 1 :kept 1 :success-rate 1.0 :avg-score 1.0)
                   (list :total 0 :kept 0 :success-rate 0.0 :avg-score 0.0)))))
      ;; Should now be available
      (should (gptel-auto-workflow--strategy-prerequisites-met-p "complex")))))

(ert-deftest test-strategy-dag/filter-removes-blocked ()
  "Filtering removes strategies whose prerequisites aren't met."
  (let ((gptel-auto-workflow--strategy-dag (make-hash-table :test 'equal)))
    (puthash "complex" '("basic") gptel-auto-workflow--strategy-dag)
    ;; Mock: no strategy has successes
    (cl-letf (((symbol-function 'gptel-auto-workflow--get-strategy-performance)
               (lambda (name)
                 (list :total 1 :kept 0 :success-rate 0.0 :avg-score 0.0))))
      (let ((filtered (gptel-auto-workflow--strategy-filter-by-dag '("basic" "complex"))))
        ;; "basic" has no prerequisites so it's available
        ;; "complex" is blocked because "basic" has no successes
        (should (member "basic" filtered))
        (should-not (member "complex" filtered))))))

(ert-deftest test-strategy-dag/register-overwrites ()
  "Registering prerequisites overwrites existing ones."
  (let ((gptel-auto-workflow--strategy-dag (make-hash-table :test 'equal)))
    (gptel-auto-workflow--strategy-dag-register "s" '("a"))
    (should (equal (gethash "s" gptel-auto-workflow--strategy-dag) '("a")))
    (gptel-auto-workflow--strategy-dag-register "s" '("b"))
    (should (equal (gethash "s" gptel-auto-workflow--strategy-dag) '("b")))))

(provide 'test-strategy-dag)
;;; test-strategy-dag.el ends here
