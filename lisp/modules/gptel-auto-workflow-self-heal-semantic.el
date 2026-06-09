;;; gptel-auto-workflow-self-heal-semantic.el --- Layer 2+3 self-heal -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; Layer 1 (byte-compile) catches syntax/void-function/arity issues.
;; This module is Layer 2 (semantic assertions) + Layer 3 (operational
;; guards). It catches bugs that compile fine but misbehave at runtime.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; ── Issue accumulator ──

(defvar gptel-auto-workflow--semantic-audit-log nil
  "List of semantic audit issues found.")

(defun gptel-auto-workflow--semantic-audit-reset ()
  "Clear the semantic audit log."
  (setq gptel-auto-workflow--semantic-audit-log nil))

(defun gptel-auto-workflow--semantic-audit-record (file line type message)
  "Record a semantic audit issue at FILE:LINE of TYPE with MESSAGE."
  (push (list :file file :line line :type type :message message)
        gptel-auto-workflow--semantic-audit-log))

;; ── Check 1: (let ...) used to bind functions (should be cl-letf) ──

(defun gptel-auto-workflow--audit-let-binding-functions (file)
  "Audit FILE for `(let ((some-fn ...)))` patterns."
  (let ((issues 0))
    (progn
      (when (string-match-p "test-" (file-name-nondirectory file))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (re-search-forward
                  "let.*gptel-auto-workflow--.*lambda"
                  nil t)
            (setq issues (1+ issues))
            (gptel-auto-workflow--semantic-audit-record
             file (line-number-at-pos (match-beginning 0))
             'let-binding-function
             "Use cl-letf to mock functions"))))
      issues)))

;; ── Check 2: Hardcoded resource limits ──

(defun gptel-auto-workflow--audit-hardcoded-limits (file)
  "Audit FILE for hardcoded resource limits.
Skips lines that are comments, docstrings, or string literals."
  (let ((issues 0)
        (lines (split-string (with-temp-buffer
                               (insert-file-contents file)
                               (buffer-string))
                             "\n" t)))
    (dolist (line lines)
      ;; Skip: comment lines (;), docstring/section comments (;;;),
      ;; or lines inside strings (starts/ends with ").
      (unless (or (string-prefix-p ";" line)
                  (string-match-p "^\".*1572864.*\"$" line)
                  ;; Lines with only text describing the limit (not code)
                  (string-match-p "^\\s-*\\w.*\\(threshold\\|limit\\|memory\\)" line))
        (when (string-match-p "1572864" line)
          (setq issues (1+ issues))
          (gptel-auto-workflow--semantic-audit-record
           file (1+ issues)
           'hardcoded-limit
           "Hardcoded 1.5GB limit - should be configurable"))))
    issues))

;; ── Check 3: score=0 logic ──

(defun gptel-auto-workflow--audit-score-zero-bug (file)
  "Audit FILE for the bug pattern (greater-than score 0) as grader-broken."
  (let ((issues 0))
    (progn
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "(>\\s-+score\\s-+0)" nil t)
          (setq issues (1+ issues))
          (gptel-auto-workflow--semantic-audit-record
           file (line-number-at-pos (match-beginning 0))
           'score-zero-bug
           "(> score 0) as grader-broken is wrong - score=0 can be legitimate")))
      issues)))

;; ── Audit dispatcher ──

(defvar gptel-auto-workflow--semantic-audit-checks
  '((let-binding-function . gptel-auto-workflow--audit-let-binding-functions)
    (hardcoded-limit . gptel-auto-workflow--audit-hardcoded-limits)
    (score-zero-bug . gptel-auto-workflow--audit-score-zero-bug))
  "Alist of audit check name (symbol) to audit function.")

(cl-defun gptel-auto-workflow--semantic-audit-file (file &key (_auto-fix nil))
  "Run all semantic audit checks on FILE."
  (gptel-auto-workflow--semantic-audit-reset)
  (let ((total-issues 0))
    (dolist (check gptel-auto-workflow--semantic-audit-checks)
      (let ((issues (funcall (cdr check) file)))
        (setq total-issues (+ total-issues issues))))
    (list :issues total-issues
          :log (nreverse (copy-sequence gptel-auto-workflow--semantic-audit-log)))))

(cl-defun gptel-auto-workflow--semantic-audit-all (&key (_auto-fix nil))
  "Run semantic audit on all Elisp files in lisp/modules/.
Skips the self-heal-semantic module itself to avoid false positives
from the audit patterns embedded in the code."
  (let* ((modules-dir (or (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
                               (gptel-auto-workflow--expand-workspace-path "lisp/modules"))
                          "lisp/modules"))
         (files (and (file-directory-p modules-dir)
                     (directory-files modules-dir t "\\.el\\'")))
         (total-issues 0)
         (report nil))
    (when files
      (dolist (file files)
        ;; Skip our own module (contains audit patterns)
        (unless (string-match-p "self-heal-semantic" (file-name-nondirectory file))
          (let* ((result (gptel-auto-workflow--semantic-audit-file file))
                 (issues (plist-get result :issues)))
            (setq total-issues (+ total-issues issues))
            (when (> issues 0)
              (push (list :file file :issues issues
                          :log (plist-get result :log))
                    report))))))
    (list :total-issues total-issues
          :files-checked (length files)
          :report (nreverse report))))

;; ── Integration with existing self-heal pipeline ──

(defun gptel-auto-workflow--self-heal-semantic ()
  "Layer 2+3 self-heal: detect semantic/operational bugs."
  (interactive)
  (let ((result (gptel-auto-workflow--semantic-audit-all)))
    (when (> (plist-get result :total-issues) 0)
      (message "[self-heal-semantic] Found %d issues"
               (plist-get result :total-issues)))
    result))

(provide 'gptel-auto-workflow-self-heal-semantic)
;;; gptel-auto-workflow-self-heal-semantic.el ends here
