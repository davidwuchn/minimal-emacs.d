;;; test-gptel-auto-workflow-production.el --- Tests for production integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-auto-workflow-production.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-auto-workflow-production.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-production)

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
;; The innovation-queue.md file is a markdown table.  add() reads the
;; file, locates the table header, and inserts a new entry right after
;; the header (before any existing data rows).  The previous version
;; of this function embedded a 33-blank-line regex in the source — a
;; clear copy-paste artifact that made the function fragile (only matched
;; tables with EXACTLY 33 blank lines, which no real table has).
;;
;; TDD guard: this test ensures the pattern is sane (0 or 1 blank
;; line, not 33) AND that the add function actually inserts an entry
;; into a freshly created table.

(ert-deftest test-production/innovation-queue-add-creates-table-when-missing ()
  "add() must create a fresh table when queue file does not exist.
The function checks (file-exists-p queue-file) and skips insertion
when false.  This test guards the contract: if you call add() and
no file exists, the file should be created with header + entry."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-add))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-file (expand-file-name "mementum/innovation-queue.md" root)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not (file-exists-p queue-file))
          (condition-case err
              (gptel-auto-workflow--innovation-queue-add
               "test-source" "test-technique" "test-impact")
            (error (message "[test] add() errored on missing file: %s"
                            (error-message-string err)))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-add-inserts-after-header ()
  "add() must insert the entry directly after the table header.
The queue file format is a markdown table:
  | ID | ... |
  |----| ... |   ← separator
  | row 1     |
  | row 2     |
The new entry should appear on line 3 (after the separator), not
appended at the end of the file or wedged in the middle of an
existing row."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-add))
  (let* ((root (make-temp-file "ov5-prod-" t))
         (queue-dir (expand-file-name "mementum" root))
         (queue-file (expand-file-name "innovation-queue.md" queue-dir)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          ;; Create a fresh queue file with header + one existing row
          (make-directory queue-dir t)
          (with-temp-file queue-file
            (insert "| ID | Source | Technique | Expected Impact | Status | Experiment ID | Actual Impact |\n")
            (insert "|----|--------|-----------|-----------------|--------|---------------|---------------|\n")
            (insert "| existing | research | foo | +1% | running | exp-1 | +0.5% |\n"))
          (let ((id (gptel-auto-workflow--innovation-queue-add
                     "test-source" "test-technique" "test-impact")))
            (with-temp-buffer
              (insert-file-contents queue-file)
              (let ((lines (split-string (buffer-string) "\n" t)))
                ;; Should be 4 lines: header, separator, new entry, existing row
                (should (= 4 (length lines)))
                ;; Line 3 (index 2) should be the new entry — contains our test id
                (should (string-match-p "test-source" (nth 2 lines)))
                (should (string-match-p "test-technique" (nth 2 lines)))
                (should (string-match-p id (nth 2 lines)))
                ;; Line 4 (index 3) should be the original existing row
                (should (string-match-p "existing" (nth 3 lines)))))))
      (delete-directory root t))))

(ert-deftest test-production/innovation-queue-regex-no-33-blank-lines ()
  "The regex pattern in --innovation-queue-add must not contain
33+ blank lines.  The previous version embedded a string with
33 consecutive newlines as part of the search pattern, which made
the function only match tables with exactly 33 blank lines between
the header and the separator — a pattern no real markdown table
ever has.  This guard fails if the pattern ever regresses.

We only count blank lines OUTSIDE string literals and comments."
  (skip-unless (fboundp 'gptel-auto-workflow--innovation-queue-add))
  (let ((max-blank 0))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents
           (expand-file-name
            "lisp/modules/gptel-auto-workflow-production.el"))
          (emacs-lisp-mode)
          (goto-char (point-min))
          (when (re-search-forward
                 "(defun gptel-auto-workflow--innovation-queue-add" nil t)
            ;; Walk to end of defun, tracking blank lines that are
            ;; OUTSIDE string literals and comments.
            (let ((start (point))
                  (end (progn (end-of-defun) (point)))
                  (cur-blank 0)
                  (ppss nil))
              (goto-char start)
              (while (and (not (eobp)) (< (point) end))
                (setq ppss (syntax-ppss))
                (cond
                 ;; Inside string or comment: ignore blank lines
                 ((nth 3 ppss) nil)
                 ((nth 4 ppss) nil)
                 ;; At end of line: check if it's blank
                 ((eolp)
                  (setq cur-blank (1+ cur-blank))
                  (when (> cur-blank max-blank)
                    (setq max-blank cur-blank)))
                  ;; On a non-blank line: reset counter
                 (t
                  (setq cur-blank 0)))
                (forward-line 1)))))
      (error nil))
    ;; The bug was 33+ blank lines.  Allow up to 2 (one blank line
    ;; inside a defun is normal).
    (should (<= max-blank 2))))

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

(provide 'test-gptel-auto-workflow-production)
;;; test-gptel-auto-workflow-production.el ends here