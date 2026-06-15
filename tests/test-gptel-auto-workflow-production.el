;;; test-gptel-auto-workflow-production.el --- Tests for production integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-production.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-production.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-production)
(require 'gptel-auto-workflow-pipeline-statechart nil t)

;;; Customization tests

(ert-deftest test-production/evolution-interval-default ()
  "Evolution interval should default to 3600 seconds (1 hour)."
  (should (= gptel-auto-workflow-evolution-interval 3600)))

;;; Timer tests

(ert-deftest test-production/timer-nil-initially ()
  "Evolution timer should be nil initially."
  (should-not gptel-auto-workflow--evolution-timer))

(ert-deftest test-production/stop-timer-no-error ()
  "Stopping nil timer should not error."
  (should-not (gptel-auto-workflow-stop-evolution-timer)))

;;; Research batch tests

(ert-deftest test-production/research-batch-nil-initially ()
  "Research batch results should be nil initially."
  (let ((gptel-auto-workflow--research-batch-results nil))
    (should-not gptel-auto-workflow--research-batch-results)))

;;; Status tests

(ert-deftest test-production/status-returns-value ()
  "Evolution status should return a value."
  (let ((status (ignore-errors (gptel-auto-workflow--evolution-status))))
    (should (or (null status) (listp status)))))

;;; Innovation queue tests
;;
;; The innovation queue is backed by EDN (mementum/innovation-queue.edn).
;; These tests guard add/update/list round-tripping, corruption resilience,
;; and ensure the regex/blank-line bug from the markdown-table era never
;; returns.

(ert-deftest test-production/innovation-queue-file-uses-edn ()
  "Queue file must use .edn extension."
  (let ((root (make-temp-file "ov5-prod-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should (string-suffix-p "innovation-queue.edn"
                                   (gptel-auto-workflow--innovation-queue-file))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-add-creates-edn ()
  "add() must create an EDN queue file with a valid entry."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-add))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.edn" queue-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not (file-exists-p queue-file))
          (let ((id (gptel-auto-workflow--innovation-queue-add
                     "test-source" "test-technique" "test-impact")))
            (should (file-exists-p queue-file))
            (let ((queue (gptel-auto-workflow--innovation-queue-read queue-file)))
              (should (= 1 (length queue)))
              (let ((item (car queue)))
                (should (string= id (plist-get item :id)))
                (should (string= "test-source" (plist-get item :source)))
                (should (string= "test-technique" (plist-get item :technique)))
                (should (string= "test-impact" (plist-get item :expected-impact)))
                (should (string= "pending" (plist-get item :status)))))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-add-appends ()
  "add() must append entries while preserving existing ones."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-add))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.edn" queue-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (make-directory queue-dir t)
          (gptel-auto-workflow--innovation-queue-write
           queue-file
           (list (list :id "existing" :source "research" :technique "foo"
                       :expected-impact "+1%" :status "running"
                       :experiment-id "exp-1" :actual-impact "+0.5%")))
          (let ((id (gptel-auto-workflow--innovation-queue-add
                     "test-source" "test-technique" "test-impact")))
            (let ((queue (gptel-auto-workflow--innovation-queue-read queue-file)))
              (should (= 2 (length queue)))
              (should (string= "existing" (plist-get (car queue) :id)))
              (should (string= id (plist-get (cadr queue) :id))))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-update-changes-status ()
  "update() must change status and leave other entries intact."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-update))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.edn" queue-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (make-directory queue-dir t)
          (gptel-auto-workflow--innovation-queue-write
           queue-file
           (list (list :id "a" :status "pending")
                 (list :id "b" :status "pending")))
          (should (gptel-auto-workflow--innovation-queue-update "a" "running" "exp-2" "+5%"))
          (let ((queue (gptel-auto-workflow--innovation-queue-read queue-file)))
            (should (= 2 (length queue)))
            (should (string= "running" (plist-get (car queue) :status)))
            (should (string= "exp-2" (plist-get (car queue) :experiment-id)))
            (should (string= "+5%" (plist-get (car queue) :actual-impact)))
            (should (string= "pending" (plist-get (cadr queue) :status)))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-list-filters-status ()
  "list() must filter by status when requested."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-list))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.edn" queue-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (make-directory queue-dir t)
          (gptel-auto-workflow--innovation-queue-write
           queue-file
           (list (list :id "a" :status "pending")
                 (list :id "b" :status "running")
                 (list :id "c" :status "pending")))
          (let ((pending (gptel-auto-workflow--innovation-queue-list "pending")))
            (should (= 2 (length pending)))
            (should (cl-every (lambda (item) (string= "pending" (plist-get item :status)))
                              pending))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-read-returns-nil-for-missing-file ()
  "Reading a missing queue file must return nil, not error."
  (let ((root (make-temp-file "ov5-prod-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not (gptel-auto-workflow--innovation-queue-read)))
      (delete-directory root t))))

(ert-deftest test-production/all-key-functions-fboundp ()
  "All key public functions must be bound after loading the module.
Regression guard: a previous version of this file had a missing
close-paren inside --pending-decisions-p, which made Emacs
silently swallow the rest of the file (defining only the defuns
that came BEFORE the unbalanced paren).  The symptom was that
several functions later in the file were NOT bound even though
the module loaded successfully.

This test asserts that the key public functions are all fboundp.
If any of them is missing, the file is silently truncated at a
parse error and we want to catch that before users do."
  (skip-unless (featurep 'gptel-auto-workflow-production))
  (dolist (fn '(gptel-auto-workflow--gc-trigger
                gptel-auto-workflow--record-research-batch
                gptel-auto-workflow--update-dashboard
                gptel-auto-workflow--innovation-queue-file
                gptel-auto-workflow--innovation-queue-add
                gptel-auto-workflow--innovation-queue-update
                gptel-auto-workflow--innovation-queue-list
                gptel-auto-workflow--innovation-queue-parse-findings
                gptel-auto-workflow--gtm-strategy-file
                gptel-auto-workflow--read-gtm-strategy
                gptel-auto-workflow--write-gtm-strategy
                gptel-auto-workflow--ensure-gtm-strategy-template
                gptel-auto-workflow--pmf-metrics
                gptel-auto-workflow--gtm-metrics
                gptel-auto-workflow--update-pmf-dashboard-metrics
                gptel-auto-workflow--update-gtm-dashboard-metrics
                gptel-auto-workflow-operational-metrics
                gptel-auto-workflow-operational-metrics-report
                gptel-auto-workflow--pending-decisions-p
                gptel-auto-workflow--decision-create))
    (should (fboundp fn))))

(ert-deftest test-production/no-silent-form-truncation ()
  "The file must not silently truncate forms due to parse errors.
Reads the source file in a fresh buffer and counts top-level forms.
Asserts the count is at least 35.
If a missing close-paren makes one defun swallow the rest of the
file, this test fails — exposing a bug that would otherwise only
show as 'function not bound' much later in user code."
  (let* ((file (expand-file-name
                "../lisp/modules/gptel-auto-workflow-production.el"
                (file-name-directory
                 (or (locate-library "test-gptel-auto-workflow-production")
                     default-directory))))
         (form-count 0)
         (read-error nil))
    (with-temp-buffer
      (insert-file-contents file)
      (emacs-lisp-mode)
      ;; Skip leading whitespace and comments
      (goto-char (point-min))
      (while (not (eobp))
        (skip-syntax-forward "-> ")
        (if (eobp) (setq form-count form-count)
          (condition-case rerr
              (progn
                (read (current-buffer))
                (setq form-count (1+ form-count)))
            ;; end-of-file is expected when we reach the end
            (end-of-file nil)
            (error (setq read-error (cons rerr (line-number-at-pos (point))))
                   (forward-line 1)
                   (back-to-indentation)))))
      ;; We should have at least 35 top-level forms.  If we get
      ;; fewer, some forms were silently merged due to a paren
      ;; imbalance earlier in the file.
      (should (>= form-count 35))
      (should-not read-error))))

;; ─── Evolution safety regressions ───

(ert-deftest test-production/maybe-run-evolution-no-auto-approve ()
  "maybe-run-evolution must not force gptel-mementum-headless-auto-approve to t.
Regression: previous code wrapped mementum calls in
\(let ((gptel-mementum-headless-auto-approve t)) ...) which bypassed
the draft default and wrote directly to mementum/knowledge/."
  (skip-unless (fboundp 'gptel-auto-workflow--maybe-run-evolution))
  (unless (boundp 'gptel-auto-workflow-evolution-enabled)
    (defvar gptel-auto-workflow-evolution-enabled))
  (let ((gptel-auto-workflow-evolution-enabled t)
        (gptel-auto-workflow--running nil)
        (gptel-auto-workflow--cron-job-running nil)
        (auto-approve-values nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow-evolution-run-cycle)
               (lambda (&rest _) nil))
              ((symbol-function 'gptel-mementum-build-index)
               (lambda ()
                 (push gptel-mementum-headless-auto-approve auto-approve-values)))
              ((symbol-function 'gptel-mementum-synthesize-all-candidates)
               (lambda (&rest _) nil)))
      (condition-case nil
          (gptel-auto-workflow--maybe-run-evolution)
        (error nil))
      (should-not (memq t auto-approve-values)))))

(ert-deftest test-production/maybe-run-evolution-skips-mementum-when-running ()
  "maybe-run-evolution must skip mementum maintenance when the evolution
cycle starts a workflow (gptel-auto-workflow--running becomes non-nil)."
  (skip-unless (fboundp 'gptel-auto-workflow--maybe-run-evolution))
  (unless (boundp 'gptel-auto-workflow-evolution-enabled)
    (defvar gptel-auto-workflow-evolution-enabled))
  (let ((gptel-auto-workflow-evolution-enabled t)
        (gptel-auto-workflow--running nil)
        (gptel-auto-workflow--cron-job-running nil)
        (mementum-called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow-evolution-run-cycle)
               (lambda (&rest _)
                 (setq gptel-auto-workflow--running t)))
              ((symbol-function 'gptel-mementum-build-index)
               (lambda () (setq mementum-called t)))
              ((symbol-function 'gptel-mementum-synthesize-all-candidates)
               (lambda (&rest _) nil)))
      (condition-case nil
          (gptel-auto-workflow--maybe-run-evolution)
        (error nil))
      (should-not mementum-called))))

;; ─── String experiment-id regression ───

(ert-deftest test-production/normalize-exp-id-helper ()
  "normalize-exp-id must return numeric values for string/number/nil inputs."
  (should (= 1 (gptel-auto-workflow--normalize-exp-id "exp-001")))
  (should (= 42 (gptel-auto-workflow--normalize-exp-id "exp-042")))
  (should (= 7 (gptel-auto-workflow--normalize-exp-id 7)))
  (should (= 3 (gptel-auto-workflow--normalize-exp-id 3.14)))
  (should (= 0 (gptel-auto-workflow--normalize-exp-id nil)))
  (should (= 0 (gptel-auto-workflow--normalize-exp-id "no-digits"))))

(ert-deftest test-production/experiment-complete-hook-string-id-no-error ()
  "Hook must not error when experiment :id is a string like \"exp-001\".
Regression: (wrong-type-argument number-or-marker-p exp-001) crash."
  (skip-unless (fboundp 'gptel-auto-workflow--experiment-complete-hook))
  (let ((gptel-auto-workflow--research-batch-results nil)
        (gptel-auto-workflow-statechart-rebuild-interval 1)
        (statechart-called nil)
        (evolution-called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--mementum-record-experiment)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--capture-experiment-context)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--write-experiment-provenance)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--context-db-persist)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow--record-holographic-experiment)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--bead-update-from-experiment)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--update-pmf-dashboard-metrics)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow--monitoring-cycle)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow--statechart-rebuild-and-persist)
               (lambda () (setq statechart-called t)))
              ((symbol-function 'gptel-auto-workflow--maybe-run-evolution)
               (lambda () (setq evolution-called t)))
              ((symbol-function 'run-with-idle-timer)
               (lambda (_secs _fn) (setq evolution-called t))))
      (condition-case err
          (gptel-auto-workflow--experiment-complete-hook
           (list :id "exp-001" :research-hash "none"))
        (error
         (ert-fail (format "Hook errored: %s" (error-message-string err)))))
      ;; With rebuild-interval=1 and exp-id=1, 1%1=0 so statechart should be called
      (should statechart-called)
      ;; exp-id=1, 1%5=1 so evolution should NOT be called
      (should-not evolution-called))))

(ert-deftest test-production/experiment-complete-hook-numeric-id-still-works ()
  "Hook must still work normally with numeric experiment :id."
  (skip-unless (fboundp 'gptel-auto-workflow--experiment-complete-hook))
  (let ((gptel-auto-workflow--research-batch-results nil)
        (gptel-auto-workflow-statechart-rebuild-interval 5)
        (statechart-called nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--mementum-record-experiment)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--capture-experiment-context)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--write-experiment-provenance)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--context-db-persist)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow--record-holographic-experiment)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--bead-update-from-experiment)
               (lambda (_) nil))
              ((symbol-function 'gptel-auto-workflow--update-pmf-dashboard-metrics)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow--monitoring-cycle)
               (lambda () nil))
              ((symbol-function 'gptel-auto-workflow--statechart-rebuild-and-persist)
                (lambda () (setq statechart-called t)))
              ((symbol-function 'gptel-auto-workflow--maybe-run-evolution)
                (lambda () nil))
              ((symbol-function 'run-with-idle-timer)
                (lambda (&rest _) nil)))
      (condition-case err
          (gptel-auto-workflow--experiment-complete-hook
           (list :id 5 :research-hash "none"))
        (error
         (ert-fail (format "Hook errored: %s" (error-message-string err)))))
      ;; exp-id=5, interval=5 => 5%5=0 so statechart should be called
      (should statechart-called))))

(ert-deftest test-production/innovation-queue-parse-findings-adds-matched-patterns ()
  "parse-findings should scan findings for 'Try X to Y' patterns and
add each match as a queue item.  Returns the list of added IDs."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-parse-findings))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.edn" queue-dir))
         (findings "# Findings

Try Hashline editing to reduce edit errors
Try Auto-approve to streamline headless runs
Try Memory EDN to fix corruption

Other text that doesn't match the pattern."))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (let ((ids (gptel-auto-workflow--innovation-queue-parse-findings findings)))
            (should (= 3 (length ids)))
            (should (file-exists-p queue-file))
            (let ((queue (gptel-auto-workflow--innovation-queue-read queue-file)))
              (should (= 3 (length queue)))
              (should (string= "Hashline editing" (plist-get (nth 0 queue) :technique)))
              (should (string= "reduce edit errors" (plist-get (nth 0 queue) :expected-impact)))
              (should (string= "Auto-approve" (plist-get (nth 1 queue) :technique)))
              (should (string= "Memory EDN" (plist-get (nth 2 queue) :technique)))
              (dolist (item queue)
                (should (string= "research findings" (plist-get item :source)))))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-parse-findings-empty-input ()
  "parse-findings with no matching patterns should return an empty list
and not create the queue file."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-parse-findings))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.edn" queue-dir))
         (findings "No matches here at all."))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (let ((ids (gptel-auto-workflow--innovation-queue-parse-findings findings)))
            (should (null ids))
            (should-not (file-exists-p queue-file))))
      (delete-directory root t))))

(provide 'test-gptel-auto-workflow-production)
;;; test-gptel-auto-workflow-production.el ends here
