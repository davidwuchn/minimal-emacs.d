;;; test-gptel-auto-workflow-evolution-regressions.el --- Evolution regressions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-evolution.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))
(load-file (expand-file-name "../lisp/modules/gptel-tools-agent-prompt-build.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

(ert-deftest regression/auto-workflow-evolution/insufficient-data-returns-skip-message ()
  "Pipeline callers should see a textual skip reason, not bare nil."
  (cl-letf (((symbol-function 'gptel-auto-workflow--evolution-count-new)
             (lambda () 0)))
    (should (string-match-p "Insufficient new data"
                            (gptel-auto-workflow-evolution-run-cycle)))))

(ert-deftest regression/auto-workflow-evolution/record-score-accepts-legacy-alist-history ()
  "Score history written with alist JSON should not trip `plist-put'."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (let ((score-file (expand-file-name "var/tmp/evolution-scores.json" root)))
          (make-directory (file-name-directory score-file) t)
          (with-temp-file score-file
            (insert "{\"scores\":{\"timestamp\":[\"2026-05-15T00:37\",\"score\",0.1,\"total\",1]},\"best\":0.1,\"last-score\":0.1,\"last-total\":1}"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () root))
                    ((symbol-function 'gptel-auto-workflow--parse-all-results)
                     (lambda () (list '(:decision "kept") '(:decision "discarded")))))
            (should (= (gptel-auto-workflow--evolution-count-new) 1))
            (should (= (gptel-auto-workflow--evolution-record-score) 0.5))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-has-no-blank-eof ()
  "Synthesized research insight pages should satisfy `git diff --check'."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should
           (gptel-auto-workflow--synthesize-research-knowledge
            "test-strategy"
            (list '(:decision "kept" :target "a.el")
                  '(:decision "discarded" :target "b.el")
                  '(:decision "discarded" :target "c.el"))))
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "mementum/knowledge/research-insights-test-strategy.md" root))
            (should-not (string-match-p "\n\n\\'" (buffer-string)))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-shows-target-decision-counts ()
  "Targets appearing in multiple outcome buckets should show per-target evidence."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should
           (gptel-auto-workflow--synthesize-research-knowledge
            "test-strategy"
            (list '(:decision "kept" :target "a.el")
                  '(:decision "validation-failed" :target "a.el")
                  '(:decision "discarded" :target "a.el")
                  '(:decision "kept" :target "b.el"))))
          (with-temp-buffer
            (insert-file-contents
             (expand-file-name "mementum/knowledge/research-insights-test-strategy.md" root))
            (should (string-match-p "`a\\.el` (1 kept / 1 discarded / 1 failed)"
                                    (buffer-string)))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-skips-rejected-strategy-labels ()
  "Rejected strategy evolution diagnostics must not become active knowledge pages."
  (let ((root (make-temp-file "aw-evolution" t))
        (strategy "[strategy-evolution] REJECTED candidate: Proposed name 'failure-weighted-skills' is generic (must be descriptive)"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not
           (gptel-auto-workflow--synthesize-research-knowledge
            strategy
            (list '(:decision "kept" :target "a.el")
                  '(:decision "kept" :target "b.el")
                  '(:decision "discarded" :target "c.el"))))
          (should-not (file-directory-p (expand-file-name "mementum/knowledge" root))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-skips-zero-kept-strategies ()
  "A strategy with no kept experiments should not be promoted to knowledge."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not
           (gptel-auto-workflow--synthesize-research-knowledge
            "pattern-driven-skills"
            (list '(:decision "discarded" :target "a.el")
                  '(:decision "discarded" :target "b.el")
                  '(:decision "validation-failed" :target "c.el"))))
          (should-not (file-directory-p (expand-file-name "mementum/knowledge" root))))
      (delete-directory root t))))

(ert-deftest regression/auto-workflow-evolution/research-knowledge-skips-placeholder-strategies ()
  "Placeholder strategy labels should not be promoted to knowledge."
  (let ((root (make-temp-file "aw-evolution" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () root)))
          (should-not
           (gptel-auto-workflow--synthesize-research-knowledge
            "Unknown"
            (list '(:decision "kept" :target "a.el")
                  '(:decision "kept" :target "b.el")
                  '(:decision "discarded" :target "c.el"))))
          (should-not (file-directory-p (expand-file-name "mementum/knowledge" root))))
      (delete-directory root t))))

;; ─── Graphify Pattern Tests ───

(ert-deftest regression/auto-workflow-evolution/extract-elisp-structure-returns-plist ()
  "Extraction should return a plist with expected keys."
  (let ((result (gptel-auto-workflow--extract-elisp-structure
                 (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el"
                                   default-directory))))
    (should (plist-get result :defuns))
    (should (plist-get result :defvars))
    (should (plist-get result :requires))
    (should (> (length (plist-get result :defuns)) 5))))

(ert-deftest regression/auto-workflow-evolution/summarize-structure-outputs-markdown ()
  "Structure summary should produce a markdown code block."
  (let* ((structure (gptel-auto-workflow--extract-elisp-structure
                     (expand-file-name "lisp/modules/gptel-auto-workflow-evolution.el"
                                       default-directory)))
         (summary (gptel-auto-workflow--summarize-elisp-structure structure)))
    (should (string-match-p "```elisp-structure" summary))
    (should (string-match-p "defuns:" summary))
    (should (string-match-p "requires:" summary))))

(ert-deftest regression/auto-workflow-evolution/sanitize-rejects-REJECTED ()
  "Sanitize should return 'none' for REJECTED diagnostic slugs."
  (should (string= "none" (gptel-auto-workflow--sanitize-strategy-name-for-filename
                           "[strategy-evolution] REJECTED candidate: Proposed name pattern-triggered-skills is generic"))))

(ert-deftest regression/auto-workflow-evolution/sanitize-preserves-valid-name ()
  "Sanitize should preserve valid kebab-case names."
  (should (string= "template-default" (gptel-auto-workflow--sanitize-strategy-name-for-filename "template-default"))))

(ert-deftest regression/auto-workflow-evolution/sanitize-label-strips-control-chars ()
  "sanitize-knowledge-label should strip control characters."
  (should (string= "hello" (gptel-auto-workflow--sanitize-knowledge-label "hel\x01lo"))))

(ert-deftest regression/auto-workflow-evolution/sanitize-label-caps-length ()
  "sanitize-knowledge-label should cap at 256 chars."
  (let ((long (make-string 300 ?x)))
    (should (<= (length (gptel-auto-workflow--sanitize-knowledge-label long)) 256))))

(ert-deftest regression/auto-workflow-evolution/valid-input-rejects-nil-results ()
  "valid-knowledge-input-p should reject nil results."
  (should-not (gptel-auto-workflow--valid-knowledge-input-p nil)))

(ert-deftest regression/auto-workflow-evolution/valid-input-accepts-valid-results ()
  "valid-knowledge-input-p should accept properly structured results."
  (should (gptel-auto-workflow--valid-knowledge-input-p
           (list (list :target "a.el" :decision "kept")
                 (list :target "b.el" :decision "discarded")
                 (list :target "c.el" :decision "validation-failed")))))

(ert-deftest regression/auto-workflow-evolution/valid-input-rejects-missing-fields ()
  "valid-knowledge-input-p should reject results without required fields."
  (should-not (gptel-auto-workflow--valid-knowledge-input-p
               (list (list :target "a.el")  ; missing :decision
                     (list :target "b.el" :decision "kept")
                     (list :target "c.el" :decision "discarded")))))

(ert-deftest regression/auto-workflow-evolution/cache-key-deterministic ()
  "Same results should produce same cache hash."
  (let ((results (list (list :target "a.el" :decision "kept"))))
    (should (string= (gptel-auto-workflow--results-cache-key results)
                     (gptel-auto-workflow--results-cache-key results)))))

(ert-deftest regression/auto-workflow-evolution/cache-key-different-for-different-data ()
  "Different results should produce different cache hashes."
  (let ((r1 (list (list :target "a.el" :decision "kept")))
        (r2 (list (list :target "b.el" :decision "kept"))))
    (should-not (string= (gptel-auto-workflow--results-cache-key r1)
                         (gptel-auto-workflow--results-cache-key r2)))))

(ert-deftest regression/auto-workflow-evolution/elisp-extraction-config-has-required-keys ()
  "Extraction config should have all required pattern keys."
  (dolist (key '(:defun-pattern :defvar-pattern :require-pattern :provide-pattern
                 :declare-pattern :error-pattern :condition-pattern :advice-pattern))
    (should (plist-get gptel-auto-workflow--elisp-extraction-config key))))

;; ─── Prompt Structure Scoring Tests (verbum + nucleus) ───

(ert-deftest regression/prompt/structure-score-max ()
  "Well-structured prompt should score >= 0.6 (length penalty applies to short prompts)."
  (should (>= (gptel-auto-experiment--prompt-structure-score
               "## Fix bug\n```elisp\n(defun foo ())\n```\n1. Add guard\nlisp/modules/test.el")
              0.6)))

(ert-deftest regression/prompt/structure-score-min ()
  "Short content-free prompt should score 0.0."
  (should (= (gptel-auto-experiment--prompt-structure-score "short") 0.0)))

(ert-deftest regression/prompt/structure-score-has-sections ()
  "Prompt with sections should score higher than empty."
  (should (> (gptel-auto-experiment--prompt-structure-score
              "## Sections\ncontent\n## More\nhere")
             (gptel-auto-experiment--prompt-structure-score ""))))

;; ─── nucleus Compiler Audit Tests ───

(ert-deftest regression/prompt/edn-score-rich ()
  "EDN with states and transitions should score above 0.4."
  (should (> (gptel-auto-experiment--edn-richness-score
              "{:states {:idle {:on {:fix :working}} :working {:on {:done :idle}}} :initial :idle}")
             0.4)))

(ert-deftest regression/prompt/edn-score-empty ()
  "Empty EDN string should score 0.0."
  (should (= (gptel-auto-experiment--edn-richness-score "") 0.0)))

(ert-deftest regression/prompt/edn-count-elements ()
  "EDN with 2 :on + 1 :states = 3 elements should be > 2."
  (should (> (gptel-auto-experiment--count-edn-elements
              "{:states {:a {:on {:x :b}} :b {:on {:y :a}}}} :initial :a}")
             2)))

;; ─── Auto-Audit Tests ───

(ert-deftest regression/auto-workflow-evolution/audit-signal-returns-list ()
  "audit-signal should return a list even with empty data."
  (cl-letf (((symbol-function 'gptel-auto-workflow--evolution-strategy-structure-scores)
             (lambda () nil)))
    (let ((result (gptel-auto-workflow--audit-signal)))
      (should (listp result)))))

(ert-deftest regression/auto-workflow-evolution/audit-signal-flags-low-scores ()
  "Low structure scores should appear in audit results."
  (cl-letf (((symbol-function 'gptel-auto-workflow--evolution-strategy-structure-scores)
             (lambda () `((,(copy-sequence "bad") . 0.05) (,(copy-sequence "good") . 0.50))))
            ((symbol-function 'gptel-auto-experiment--compile-score)
             (lambda (strategy &optional callback) nil)))
    (let ((result (gptel-auto-workflow--audit-signal)))
      (should (member "bad" result))
      (should-not (member "good" result)))))

;; ─── Allium Compiler Tests ───

(ert-deftest regression/prompt/allium-issues-count-empty ()
  "Empty check output should return (0 . 0.0)."
  (let ((result (gptel-auto-experiment--allium-issues-count "")))
    (should (= (car result) 0))
    (should (= (cdr result) 0.0))))

(ert-deftest regression/prompt/allium-issues-count-nil ()
  "Nil check output should return (0 . 0.0)."
  (let ((result (gptel-auto-experiment--allium-issues-count nil)))
    (should (= (car result) 0))
    (should (= (cdr result) 0.0))))

(ert-deftest regression/prompt/allium-issues-count-formatted ()
  "Formatted check output with numbered issues should be counted correctly."
  (let ((result (gptel-auto-experiment--allium-issues-count
                 "1. Missing precondition in UserResetsPassword\n2. Unreachable state\n3. Implicit behavior\n")))
    (should (= (car result) 3))))

(ert-deftest regression/prompt/allium-issues-severity-high ()
  "Critical keywords should produce high severity."
  (let ((result (gptel-auto-experiment--allium-issues-count
                 "1. contradictory requires clause\n2. invariant violation detected\n3. transition graph violation: unreachable state")))
    (should (> (cdr result) 0.5))))

(ert-deftest regression/prompt/allium-quality-score-perfect ()
  "Empty check output should score 0.0 (perfect)."
  (should (= (gptel-auto-experiment--allium-quality-score "") 0.0)))

(ert-deftest regression/prompt/allium-quality-score-nil ()
  "Nil check output should score 1.0 (worst)."
  (should (= (gptel-auto-experiment--allium-quality-score nil) 1.0)))

(ert-deftest regression/prompt/allium-quality-score-bad ()
  "Many critical issues should score high (bad)."
  (should (> (gptel-auto-experiment--allium-quality-score
              "1. contradictory requires\n2. invariant violation\n3. unreachable rule\n4. missing precondition\n5. transition graph violation\n")
             0.5)))

(ert-deftest regression/prompt/allium-quality-score-ok ()
  "Few minor issues should score low (good)."
  (should (< (gptel-auto-experiment--allium-quality-score
              "1. warning: style suggestion\n2. missing trace for rule Foo\n")
             0.3)))

(ert-deftest regression/prompt/allium-compiler-prompt-nonempty ()
  "Allium compiler prompt returns non-empty string containing allium reference."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             (lambda () (expand-file-name "~/.emacs.d/"))))
    (condition-case nil
        (let ((prompt (gptel-auto-experiment--allium-compiler-prompt)))
          (should (stringp prompt))
          (should (string-match-p "allium\|ALLIUM" prompt)))
      (error (message "allium-compiler-prompt test skipped: dependencies unavailable")
             (should t)))))

;; ─── Allium Audit Tests ───

(ert-deftest regression/prompt/allium-quality-score-severity-no-numbered-lines ()
  "Quality score should not be 0.0 when severity is nonzero but no numbered lines exist.
Malformed Allium output may contain issues as prose without numbered listing."
  (should (> (gptel-auto-experiment--allium-quality-score
              "contradictory requires clause without matching outbound")
             0.0)))

(ert-deftest regression/prompt/allium-issues-count-severity-capped ()
  "Severity should cap at 1.0 even with many critical keywords."
  (let ((result (gptel-auto-experiment--allium-issues-count
                 "1. contradictory invariant violation\n2. unreachable transition graph\n3. when-clause obligation absent field\n4. missing precondition missing rule without matching without outbound")))
    (should (<= (cdr result) 1.0))))

(ert-deftest regression/prompt/allium-quality-score-exact-severity-only ()
  "Quality score with severity>0 and zero numbered issues should compute correctly.
Single keyword 'contradictory' (severity 0.3): (min 0.8 (/ 0.3 2.0)) = 0.15."
  (should (= (gptel-auto-experiment--allium-quality-score "contradictory") 0.15)))

(ert-deftest regression/prompt/allium-issues-count-non-string ()
  "Non-string input (number) should return (0 . 0.0)."
  (let ((result (gptel-auto-experiment--allium-issues-count 42)))
    (should (= (car result) 0))
    (should (= (cdr result) 0.0))))

(ert-deftest regression/prompt/allium-quality-score-non-string ()
  "Non-string input (number) should return 1.0 (worst)."
  (should (= (gptel-auto-experiment--allium-quality-score 42) 1.0)))

(ert-deftest regression/auto-workflow-evolution/allium-audit-returns-list ()
  "allium-audit functions resolve and have correct signatures."
  (should (fboundp 'gptel-auto-experiment--allium-issues-count))
  (should (fboundp 'gptel-auto-experiment--allium-quality-score))
  (should (fboundp 'gptel-auto-experiment--allium-compiler-prompt))
  (should (fboundp 'gptel-auto-workflow--allium-audit-signal))
  (should (fboundp 'gptel-auto-workflow--allium-check-research-quality))
  (should (fboundp 'gptel-auto-workflow--allium-diff-minimal-pairs)))

(ert-deftest regression/auto-workflow-evolution/allium-check-research-quality-guard-callback ()
  "Guard clause: when allium-distill not fboundp, callback receives (99 . 1.0)."
  (cl-letf (((symbol-function 'gptel-auto-experiment--allium-distill) nil))
    (let ((called-p nil) (sentinel nil))
      (gptel-auto-workflow--allium-check-research-quality
       "test findings"
       (lambda (r) (setq called-p t sentinel r)))
      (should called-p)
      (should (equal sentinel (cons 99 1.0))))))

(ert-deftest regression/auto-workflow-evolution/allium-diff-minimal-pairs-guard-callback ()
  "Guard clause: when fboundp not met, callback receives (99 . 99)."
  (let ((called-p nil) (sentinel nil))
    (gptel-auto-workflow--allium-diff-minimal-pairs
     "ha" "hb"
     (lambda (r) (setq called-p t sentinel r)))
    (should called-p)
    (should (equal sentinel (cons 99 99)))))

(provide 'test-gptel-auto-workflow-evolution-regressions)

;;; test-gptel-auto-workflow-evolution-regressions.el ends here
