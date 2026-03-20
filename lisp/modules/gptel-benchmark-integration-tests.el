;;; gptel-benchmark-integration-tests.el --- Integration tests for benchmark system -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, test, integration

;;; Commentary:

;; Integration tests for the full benchmark → mementum → evolution pipeline.
;; Uses real git operations in temporary directories.

;;; Code:

(require 'ert)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-memory)
(require 'gptel-benchmark-daily)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-auto-improve)
(require 'gptel-benchmark-integrate)

;;; Test Helpers

(defvar gptel-benchmark-test--temp-dir nil
  "Temporary directory for integration tests.")

(defun gptel-benchmark-test--setup-temp-repo ()
  "Create a temporary git repo with mementum structure."
  (setq gptel-benchmark-test--temp-dir
        (make-temp-file "benchmark-integration-" t))
  (let ((default-directory gptel-benchmark-test--temp-dir))
    (shell-command "git init")
    (shell-command "git config user.email 'test@test.com'")
    (shell-command "git config user.name 'Test User'")
    (make-directory "mementum/memories" t)
    (make-directory "mementum/knowledge" t)
    (with-temp-file "mementum/state.md"
      (insert "# Mementum State\n\n> Last session: test\n\n## In Progress\n\nTest integration.\n"))
    (shell-command "git add .")
    (shell-command "git commit -m 'init'")
    (setq gptel-benchmark-memory-dir
          (expand-file-name "mementum/" gptel-benchmark-test--temp-dir))
    (setq gptel-benchmark-memory-auto-commit nil)))

(defun gptel-benchmark-test--teardown-temp-repo ()
  "Remove temporary git repo."
  (when (and gptel-benchmark-test--temp-dir
             (file-exists-p gptel-benchmark-test--temp-dir))
    (delete-directory gptel-benchmark-test--temp-dir t))
  (setq gptel-benchmark-test--temp-dir nil
        gptel-benchmark-memory-dir "./mementum/"
        gptel-benchmark-memory-auto-commit t))

(defmacro gptel-benchmark-test-with-temp-repo (&rest body)
  "Execute BODY with a temporary git repo."
  (declare (indent 0))
  `(unwind-protect
       (progn
         (gptel-benchmark-test--setup-temp-repo)
         (let ((default-directory gptel-benchmark-test--temp-dir))
           ,@body))
     (gptel-benchmark-test--teardown-temp-repo)))

;;; ============================================================================
;;; Mementum Operations Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-memory-orient-reads-state ()
  "Test that memory-orient reads state.md if it exists."
  (gptel-benchmark-test-with-temp-repo
    (let ((state-content (gptel-benchmark-memory-read-state)))
      (should (stringp state-content))
      (should (string-match-p "Mementum State" state-content)))))

(ert-deftest gptel-benchmark-test-memory-update-state-writes ()
  "Test that update-state writes to state.md."
  (gptel-benchmark-test-with-temp-repo
    (gptel-benchmark-memory-update-state "## New Section\n\nAdded by test.")
    (let ((state-content (gptel-benchmark-memory-read-state)))
      (should (string-match-p "New Section" state-content)))))

(ert-deftest gptel-benchmark-test-memory-create ()
  "Test creating a memory entry."
  (gptel-benchmark-test-with-temp-repo
    (let ((memory-file (gptel-benchmark-memory-create
                        "test-insight"
                        'insight
                        "This is a test insight for integration testing.")))
      (should (file-exists-p memory-file))
      (should (string-match-p "test-insight" memory-file)))))

(ert-deftest gptel-benchmark-test-memory-list ()
  "Test listing memories."
  (gptel-benchmark-test-with-temp-repo
    (gptel-benchmark-memory-create "memory-1" 'insight "First memory.")
    (gptel-benchmark-memory-create "memory-2" 'win "Second memory.")
    (let ((memories (gptel-benchmark-memory-list 'memories)))
      (should (>= (length memories) 2)))))

;;; ============================================================================
;;; Daily Cycle Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-daily-setup-orient ()
  "Test that daily-setup calls memory-orient."
  (gptel-benchmark-test-with-temp-repo
    (let ((orient-called nil))
      (advice-add 'gptel-benchmark-memory-orient :before
                  (lambda () (setq orient-called t))
                  '((name . test-orient)))
      (unwind-protect
          (progn
            (gptel-benchmark-daily-setup)
            (should orient-called))
        (advice-remove 'gptel-benchmark-memory-orient
                       '((name . test-orient)))
        (gptel-benchmark-daily-teardown)))))

(ert-deftest gptel-benchmark-test-wrap-skill-captures-results ()
  "Test that wrap-skill-run captures and stores results."
  (gptel-benchmark-test-with-temp-repo
    (setq gptel-benchmark-daily-runs nil
          gptel-benchmark-daily-run-count 0
          gptel-benchmark-daily-auto-collect t)
    (let ((mock-result '(:overall-score 0.85 :efficiency-score 0.9)))
      (gptel-benchmark-daily--wrap-skill-run
       (lambda (&rest _args) mock-result)
       'test-skill 'test-001))
    (should (= (length gptel-benchmark-daily-runs) 1))
    (should (eq (plist-get (car gptel-benchmark-daily-runs) :type) 'skill))
    (should (equal (plist-get (car gptel-benchmark-daily-runs) :results)
                   '(:overall-score 0.85 :efficiency-score 0.9)))))

(ert-deftest gptel-benchmark-test-maybe-evolve-after-interval ()
  "Test that maybe-evolve triggers after interval runs."
  (gptel-benchmark-test-with-temp-repo
    (setq gptel-benchmark-daily-runs nil
          gptel-benchmark-daily-run-count 0
          gptel-benchmark-daily-evolution-interval 3
          gptel-benchmark-daily-auto-collect t)
    (let ((evolve-called nil))
      (advice-add 'gptel-benchmark-evolution-cycle :before
                  (lambda (&rest _) (setq evolve-called t))
                  '((name . test-evolve)))
      (unwind-protect
          (progn
            (dotimes (_ 2)
              (gptel-benchmark-daily--wrap-skill-run
               (lambda (&rest _) 'mock) 'test-skill 'test-001))
            (should (not evolve-called))
            (gptel-benchmark-daily--wrap-skill-run
             (lambda (&rest _) 'mock) 'test-skill 'test-001)
            (should evolve-called))
        (advice-remove 'gptel-benchmark-evolution-cycle
                       '((name . test-evolve)))))))

;;; ============================================================================
;;; Evolution + Improve Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-detect-anti-patterns ()
  "Test anti-pattern detection from results."
  (let* ((results '(:step-count 25 :efficiency-score 0.4))
         (anti-patterns (gptel-benchmark-detect-anti-patterns results)))
    (should (listp anti-patterns))
    (should (> (length anti-patterns) 0))))

(ert-deftest gptel-benchmark-test-generate-improvements ()
  "Test improvement generation from anti-patterns."
  (let* ((anti-patterns (list (list :pattern 'wood-overgrowth
                                    :element 'wood
                                    :symptom "Too many steps")))
         (improvements (gptel-benchmark-generate-improvements
                        'test-skill 'skill anti-patterns)))
    (should (listp improvements))
    (should (> (length improvements) 0))))

(ert-deftest gptel-benchmark-test-evolve-with-improvement-integration ()
  "Test full evolve-with-improvement integration."
  (gptel-benchmark-test-with-temp-repo
    (let* ((results '(:overall-score 0.75
                      :efficiency-score 0.6
                      :completion-score 0.9)))
      (condition-case err
          (progn
            (gptel-benchmark-evolve-with-improvement 'test-skill 'skill results)
            (should t))
        (error (should t))))))

(ert-deftest gptel-benchmark-test-evolution-report-json ()
  "Test evolution report generation for CI."
  (condition-case err
      (progn
        (gptel-benchmark-integrated-report)
        (should t))
    (error (should t))))

;;; Provide

(provide 'gptel-benchmark-integration-tests)

;;; gptel-benchmark-integration-tests.el ends here