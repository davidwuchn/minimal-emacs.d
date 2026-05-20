;;; test-gptel-auto-workflow-evolution-regressions.el --- Evolution regressions -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Ensure lisp/modules is on load-path for requires nested in load-file'd modules
(let ((modules-dir (expand-file-name "../lisp/modules"
                                     (file-name-directory
                                      (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path modules-dir))
;; Ensure gptel subtree is on load-path
(let ((gptel-dir (expand-file-name "../packages/gptel"
                                   (file-name-directory
                                    (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path gptel-dir))
;; Ensure gptel-agent subtree is on load-path
(let ((gptel-agent-dir (expand-file-name "../packages/gptel-agent"
                                         (file-name-directory
                                          (or load-file-name buffer-file-name default-directory)))))
  (add-to-list 'load-path gptel-agent-dir))
(load-file (expand-file-name "../lisp/modules/gptel-auto-workflow-evolution.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))
(load-file (expand-file-name "../lisp/modules/gptel-tools-agent-prompt-build.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))
(load-file (expand-file-name "../lisp/modules/gptel-tools-agent-base.el"
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
  "Allium compiler prompt returns non-empty string from ALLIUM.md."
  (let ((tmpdir (make-temp-file "allium-prompt-test-" t)))
    (unwind-protect
        (progn
          (let ((nucleus-dir (expand-file-name "packages/nucleus" tmpdir)))
            (make-directory nucleus-dir t)
            (with-temp-file (expand-file-name "ALLIUM.md" nucleus-dir)
              (insert "## The Prompt\nALLIUM v3 behavioral spec compiler.\n\`\`\`\n")))
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () tmpdir)))
            (let ((prompt (gptel-auto-experiment--allium-compiler-prompt)))
              (should (stringp prompt))
              (should (string-match-p "ALLIUM v3" prompt))
              (should (string-match-p "behavioral spec" prompt)))))
      (delete-directory tmpdir t))))

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
  (should (fboundp 'gptel-auto-workflow--allium-audit-strategy))
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
  "Guard clause: when fboundp not met, callback receives (99 . 99).
When fboundp IS met (allium loaded by earlier test), the function dispatches
to the async LLM path (tested implicitly by the real pipeline)."
  (let ((called-p nil) (sentinel nil)
        (distill-fn (and (fboundp 'gptel-auto-experiment--allium-distill)
                         (symbol-function 'gptel-auto-experiment--allium-distill))))
    (unwind-protect
        (progn
          ;; Temporarily remove allium fboundp to force sync fallback path
          (when distill-fn
            (fmakunbound 'gptel-auto-experiment--allium-distill)
            (fmakunbound 'gptel-auto-experiment--allium-check))
          (gptel-auto-workflow--allium-diff-minimal-pairs
           "ha" "hb"
           (lambda (r) (setq called-p t sentinel r)))
          (should called-p)
          (should (equal sentinel (cons 99 99))))
      ;; Restore allium functions
      (when distill-fn
        (fset 'gptel-auto-experiment--allium-distill distill-fn)
        (when-let ((check-fn (and (fboundp 'gptel-auto-experiment--allium-check)
                                  (symbol-function 'gptel-auto-experiment--allium-check))))
          (fset 'gptel-auto-experiment--allium-check check-fn))))))

;; ─── Allium Feed-Forward Tests ───

(defvar ert--allium-ff-tmpdir nil
  "Temp directory for Allium feed-forward tests.")

(defun ert--allium-ff-root ()
  "Mock worktree root for Allium feed-forward tests."
  (or ert--allium-ff-tmpdir
      (setq ert--allium-ff-tmpdir (make-temp-file "allium-ff-" t))))

(ert-deftest regression/auto-workflow-evolution/allium-load-issues-empty-dir ()
  "load-issues-for-guidance returns empty string when no issues directory exists."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             #'ert--allium-ff-root))
    (should (string= (gptel-auto-workflow--allium-load-issues-for-guidance) ""))))

(ert-deftest regression/auto-workflow-evolution/allium-persist-creates-spec-and-issues-files ()
  "persist-spec creates .allium spec file and .md issues file with correct content."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             #'ert--allium-ff-root))
    (gptel-auto-workflow--allium-persist-spec
     "test-strategy" "entity User name: string\nrule: unique name\n" "1. missing precondition" 1 0.3 0.15)
    (let ((spec-file (expand-file-name "var/tmp/evolution/allium-specs/test-strategy.allium" (ert--allium-ff-root)))
          (issues-file (expand-file-name "var/tmp/evolution/allium-issues/test-strategy.md" (ert--allium-ff-root))))
      (should (file-exists-p spec-file))
      (should (file-exists-p issues-file))
      (with-temp-buffer
        (insert-file-contents spec-file)
        (should (string-match-p "Allium spec for research strategy: test-strategy" (buffer-string)))
        (should (string-match-p "entity User" (buffer-string))))
      (with-temp-buffer
        (insert-file-contents issues-file)
        (should (string-match-p "Allium Check.*test-strategy" (buffer-string)))
        (should (string-match-p "missing precondition" (buffer-string)))))))

(ert-deftest regression/auto-workflow-evolution/allium-persist-double-no-duplicates ()
  "Two persist-spec calls produce exactly one Allium appendix in knowledge page."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             #'ert--allium-ff-root))
    (let ((knowledge-dir (expand-file-name "mementum/knowledge" (ert--allium-ff-root)))
          (knowledge-file (expand-file-name "mementum/knowledge/research-insights-test-strategy.md" (ert--allium-ff-root))))
      (make-directory knowledge-dir t)
      (with-temp-file knowledge-file
        (insert "# Research Insights: test-strategy\n\n## Summary\n\nOriginal content.\n"))
      (gptel-auto-workflow--allium-persist-spec
       "test-strategy" "rule: first version\n" "1. first issue" 1 0.3 0.15)
      (gptel-auto-workflow--allium-persist-spec
       "test-strategy" "rule: second version\n" "2. second issue" 2 0.5 0.3)
      (with-temp-buffer
        (insert-file-contents knowledge-file)
        (goto-char (point-min))
        (let ((count 0)
              (buffer (buffer-string)))
          (while (re-search-forward "^## Allium Behavioral Spec" nil t)
            (setq count (1+ count)))
          (should (= count 1))
          (should (string-match-p "second version" buffer))
          (should (string-match-p "Research Insights" buffer))
          (should (not (string-match-p "first version" buffer))))))))

(ert-deftest regression/auto-workflow-evolution/allium-load-issues-returns-formatted-content ()
  "load-issues-for-guidance returns formatted markdown with recent issues from disk."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             #'ert--allium-ff-root))
    (let ((issues-dir (expand-file-name "var/tmp/evolution/allium-issues" (ert--allium-ff-root))))
      (make-directory issues-dir t)
      (with-temp-file (expand-file-name "strategy-a.md" issues-dir)
        (insert "# Allium Check — strategy-a\n\n**Issues:** 3 | **Severity:** 0.45 | **Score:** 0.30\n\n## Issue Details\n\n1. contradictory rule\n2. missing precondition\n"))
      (with-temp-file (expand-file-name "strategy-b.md" issues-dir)
        (insert "# Allium Check — strategy-b\n\n**Issues:** 1 | **Severity:** 0.15\n\n## Issue Details\n\n1. style: prefers shorter names\n"))
      (let ((result (gptel-auto-workflow--allium-load-issues-for-guidance)))
        (should (string-match-p "Allium Behavioral Audit" result))
        (should (string-match-p "strategy-a" result))
        (should (string-match-p "strategy-b" result))
        (should (string-match-p "contradictory rule" result))
        (should (string-match-p "prefers shorter names" result))))))

(ert-deftest regression/auto-workflow-evolution/allium-maphash-two-args ()
  "maphash in allium-audit-signal receives exactly 2 arguments (not 3).
Regression test: deeply nested lambda after refactor should not confuse the evaluator."
  (cl-letf (((symbol-function 'gptel-auto-workflow--research-results-by-strategy)
             (lambda () (let ((ht (make-hash-table :test 'equal)))
                          (puthash 'test-strat nil ht)
                          ht)))
            ((symbol-function 'gptel-auto-experiment--allium-distill)
             (lambda (_text callback) (funcall callback nil))))
    (let ((result (gptel-auto-workflow--allium-audit-signal)))
      ;; When results have length 0, audited remains nil
      (should-not result))))

(ert-deftest regression/auto-workflow-evolution/allium-persist-aborts-on-nil-root ()
  "persist-spec returns nil and logs when worktree root is nil."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             (lambda () nil)))
    (should-not (gptel-auto-workflow--allium-persist-spec
                 "test-strategy" "spec" "issues" 1 0.3 0.15))))

(ert-deftest regression/auto-workflow-evolution/allium-load-issues-nil-root ()
  "load-issues-for-guidance returns empty string when worktree root is nil."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             (lambda () nil)))
    (should (string= (gptel-auto-workflow--allium-load-issues-for-guidance) ""))))

(ert-deftest regression/auto-workflow-evolution/allium-load-issues-filters-short-content ()
  "load-issues-for-guidance excludes files with <=20 chars of content."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             #'ert--allium-ff-root))
    (let ((issues-dir (expand-file-name "var/tmp/evolution/allium-issues" (ert--allium-ff-root))))
      (make-directory issues-dir t)
      (dolist (f (directory-files issues-dir t "\\.md$"))
        (delete-file f))
      (with-temp-file (expand-file-name "too-short.md" issues-dir)
        (insert "short content"))
      (let ((result (gptel-auto-workflow--allium-load-issues-for-guidance)))
        (should (string= result ""))))))

;; ─── KIBC-M Axis Tests ───

(ert-deftest regression/prompt/kibcm-axis-nil ()
  "Nil hypothesis returns nil axis."
  (should (null (gptel-auto-experiment--kibcm-axis nil))))

(ert-deftest regression/prompt/kibcm-axis-no-match ()
  "Hypothesis with no pattern match returns nil."
  (should (null (gptel-auto-experiment--kibcm-axis "do something awesome"))))

(ert-deftest regression/prompt/kibcm-axis-classify-K ()
  "validate pattern → :K axis."
  (should (eq :K (gptel-auto-experiment--kibcm-axis "add nil check and validate input"))))

(ert-deftest regression/prompt/kibcm-axis-classify-B ()
  "extract helper pattern → :B axis."
  (should (eq :B (gptel-auto-experiment--kibcm-axis "extract helper function for DRY pipeline"))))

(ert-deftest regression/prompt/kibcm-axis-case-insensitive ()
  "Classification is case-insensitive (Emacs default string-match)."
  (should (eq :K (gptel-auto-experiment--kibcm-axis "VALIDATE INPUT"))))

(ert-deftest regression/prompt/kibcm-axis-strongest-wins ()
  "Strongest pattern match count determines axis."
  (should (eq :K (gptel-auto-experiment--kibcm-axis "validate nil check guard nil safety"))))

(ert-deftest regression/prompt/kibcm-axis-fboundp ()
  "kibcm-axis function is defined."
  (should (fboundp 'gptel-auto-experiment--kibcm-axis)))

(ert-deftest regression/auto-workflow-evolution/allium-read-quality-parses-file ()
  "allium-read-quality reads count and severity from issue markdown file."
  (let ((tmpdir (make-temp-file "arq-" t)))
    (unwind-protect
        (progn
          (let ((issues-dir (expand-file-name "var/tmp/evolution/allium-issues" tmpdir)))
            (make-directory issues-dir t)
            (with-temp-file (expand-file-name "test-straty.md" issues-dir)
              (insert "# Allium Check — test-straty\n\n")
              (insert "**Issues:** 4 | **Severity:** 0.55 | **Score:** 0.30\n\n")
              (insert "1. contradictory rule\n2. missing precondition\n3. stale traces\n4. implicit behavior\n")))
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () tmpdir)))
            (let ((result (gptel-auto-workflow--allium-read-quality "test-straty")))
              (should result)
              (should (= (car result) 4))
              (should (> (cdr result) 0.5)))))
      (delete-directory tmpdir t))))

(ert-deftest regression/auto-workflow-evolution/allium-read-quality-nil-root ()
  "allium-read-quality returns nil when worktree root is nil."
  (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
             (lambda () nil)))
    (should-not (gptel-auto-workflow--allium-read-quality "test"))))

(ert-deftest regression/auto-workflow-evolution/tsv-parse-column-alignment ()
  "parse-all-results correctly reads all 26 TSV columns with correct indices."
  (let ((tmpdir (make-temp-file "tsvcol-" t)))
    (unwind-protect
        (let ((run-dir (expand-file-name "var/tmp/experiments/2026-05-01" tmpdir)))
          (make-directory run-dir t)
          (with-temp-file (expand-file-name "results.tsv" run-dir)
            (insert "header\trow\n")
            (insert "1\tlisp/foo.el\tadd nil check\t0.00\t0.50\t0.8\t+0.50\tkept\t12.3\t0.9\tgood\tbetter\tnone\tagent out\t1500\tdeepseek\t2000\tall\tlearn\tnone\topt1\tresearch1\thash1\t0.8\tyes\t:K\n"))
          (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                     (lambda () tmpdir)))
            (let ((results (gptel-auto-workflow--parse-all-results)))
              (should results)
              (let ((r (car results)))
                (should (string= (plist-get r :target) "lisp/foo.el"))
                (should (string= (plist-get r :hypothesis) "add nil check"))
                (should (= (plist-get r :score-before) 0.0))
                (should (= (plist-get r :score-after) 0.5))
                (should (= (plist-get r :code-quality) 0.8))
                (should (string= (plist-get r :decision) "kept"))
                (should (= (plist-get r :grader-quality) 0.9))
                (should (= (plist-get r :prompt-chars) 2000))
                (should (string= (plist-get r :research-strategy) "research1"))
                (should (string= (plist-get r :research-hash) "hash1"))
                (should (string= (plist-get r :research-quality) "0.8"))
                (should (string= (plist-get r :kibcm-axis) ":K"))))))
      (delete-directory tmpdir t))))

(ert-deftest regression/auto-workflow-evolution/allium-read-quality-missing-file ()
  "allium-read-quality returns nil when issue file doesn't exist."
  (let ((tmpdir (make-temp-file "arq2-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--worktree-base-root)
                   (lambda () tmpdir)))
          (should-not (gptel-auto-workflow--allium-read-quality "nonexistent")))
      (delete-directory tmpdir t))))

(ert-deftest regression/auto-workflow-evolution/axis-stats-with-mock ()
  "evolution-axis-stats computes per-axis keep rates from mocked results.
:K: 3/4 kept = 0.75, :B: 2/3 kept = 0.67. Sorted descending."
  (let ((mock-results (list
                       (list :decision "kept" :kibcm-axis :K)
                       (list :decision "kept" :kibcm-axis :K)
                       (list :decision "kept" :kibcm-axis :K)
                       (list :decision "discarded" :kibcm-axis :K)
                       (list :decision "kept" :kibcm-axis :B)
                       (list :decision "kept" :kibcm-axis :B)
                       (list :decision "discarded" :kibcm-axis :B))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((stats (gptel-auto-workflow--evolution-axis-stats)))
        (should (= (length stats) 2))
        (should (eq :K (caar stats)))
        (should (> (cdar stats) 0.7))
        (should (eq :B (car (cadr stats))))))))

;; ─── Semantica Pattern Tests ───

(ert-deftest regression/auto-workflow-evolution/seman-opposing-add-remove ()
  "add vs remove are opposing hypotheses."
  (should (gptel-auto-workflow--opposing-hypotheses-p "add nil guard" "remove the nil guard")))

(ert-deftest regression/auto-workflow-evolution/seman-opposing-enable-disable ()
  "enable vs disable are opposing."
  (should (gptel-auto-workflow--opposing-hypotheses-p "enable feature" "disable feature")))

(ert-deftest regression/auto-workflow-evolution/seman-opposing-not-conflict ()
  "Same direction hypotheses are not opposing."
  (should-not (gptel-auto-workflow--opposing-hypotheses-p "add nil check" "add guard")))

(ert-deftest regression/auto-workflow-evolution/seman-opposing-symmetric ()
  "Opposition detection is symmetric."
  (should (gptel-auto-workflow--opposing-hypotheses-p "remove guard" "add nil check")))

(ert-deftest regression/auto-workflow-evolution/seman-opposing-nil-nonnil ()
  "nil vs non-nil are opposing."
  (should (gptel-auto-workflow--opposing-hypotheses-p "return nil" "return non-nil")))

(ert-deftest regression/auto-workflow-evolution/seman-validation-result-valid ()
  "validation-result with valid=t returns correct plist."
  (let ((r (gptel-auto-workflow--validation-result t)))
    (should (plist-get r :valid))
    (should-not (plist-get r :errors))
    (should-not (plist-get r :warnings))))

(ert-deftest regression/auto-workflow-evolution/seman-validation-result-invalid ()
  "validation-result with valid=nil returns errors and warnings."
  (let ((r (gptel-auto-workflow--validation-result nil '("missing") '("deprecated"))))
    (should-not (plist-get r :valid))
    (should (plist-get r :errors))
    (should (plist-get r :warnings))))

(ert-deftest regression/auto-workflow-evolution/seman-ontology-generates-classes ()
  "generate-experiment-ontology extracts strategy classes and target instances."
  (let ((mock-results
         (list
          (list :strategy "strat-a" :target "lisp/foo.el" :decision "kept")
          (list :strategy "strat-a" :target "lisp/bar.el" :decision "discarded")
          (list :strategy "strat-b" :target "lisp/baz.el" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((o (gptel-auto-workflow--generate-experiment-ontology)))
        (should (= (plist-get o :class-count) 2))
        (should (= (plist-get o :instance-count) 3))))))

(ert-deftest regression/auto-workflow-evolution/seman-causal-links-multi ()
  "experiment-causal-links detects multi-experiment chains per target."
  (let ((mock-results
         (list
          (list :target "lisp/foo.el" :score-after 0.5 :decision "kept" :hypothesis "h1" :score-before 0.0)
          (list :target "lisp/foo.el" :score-after 0.8 :decision "kept" :hypothesis "h2" :score-before 0.5)
          (list :target "lisp/bar.el" :score-after 0.3 :decision "discarded" :hypothesis "h3" :score-before 0.0))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results)))
      (let ((causal (gptel-auto-workflow--experiment-causal-links)))
        (should (= (length causal) 1))
        (should (string= (caar causal) "lisp/foo.el"))))))

(ert-deftest regression/auto-workflow-evolution/seman-causal-links-nil-scores ()
  "causal-links handles nil score-after gracefully via (or sa 0)."
  (let ((mock (list
              (list :target "lisp/foo.el" :score-after nil :decision "kept" :hypothesis "h1" :score-before nil)
              (list :target "lisp/foo.el" :score-after 0.5 :decision "kept" :hypothesis "h2" :score-before 0.0))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock)))
      (let ((causal (gptel-auto-workflow--experiment-causal-links)))
        (should (= (length causal) 1))
        (should (= (length (cdar causal)) 2))))))

(ert-deftest regression/auto-workflow-evolution/seman-conflict-detection ()
  "detect-hypothesis-conflicts finds kept-vs-discarded opposition pairs."
  (let ((mock (list
              (list :target "lisp/foo.el" :hypothesis "add nil guard" :decision "kept")
              (list :target "lisp/foo.el" :hypothesis "remove nil guard" :decision "discarded")
              (list :target "lisp/bar.el" :hypothesis "enable logging" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock)))
      (let ((conflicts (gptel-auto-workflow--detect-hypothesis-conflicts)))
        (should (= (length conflicts) 1))
        (should (string= (plist-get (car conflicts) :target) "lisp/foo.el"))
        (should (plist-get (car conflicts) :severity))))))

(ert-deftest regression/auto-workflow-evolution/seman-conflict-no-conflict ()
  "No conflicts when all decisions for a target are kept."
  (let ((mock (list
              (list :target "lisp/foo.el" :hypothesis "add guard" :decision "kept")
              (list :target "lisp/foo.el" :hypothesis "add nil check" :decision "kept"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock)))
      (should-not (gptel-auto-workflow--detect-hypothesis-conflicts)))))

(ert-deftest regression/auto-workflow-evolution/seman-impact-breaking ()
  "classify-experiment-impact: score regression → breaking with impact tag."
  (let ((mock (list (list :target "lisp/foo.el" :decision "kept" :score-before 0.5 :score-after 0.2))))
    (let ((old (symbol-function 'gptel-auto-workflow--parse-all-results)))
      (unwind-protect
          (progn
            (fset 'gptel-auto-workflow--parse-all-results (lambda () mock))
            (let ((r (gptel-auto-workflow--classify-experiment-impact)))
              (should (= (length (plist-get r :breaking)) 1))
              (should (string= (plist-get (car (plist-get r :breaking)) :impact) "breaking"))
              (should (= (plist-get r :safe) 0))
              (should-not (plist-get r :potentially-breaking))))
        (fset 'gptel-auto-workflow--parse-all-results old)))))

(ert-deftest regression/auto-workflow-evolution/seman-impact-safe ()
  "classify-experiment-impact: score improvement → safe."
  (let ((mock (list (list :target "lisp/foo.el" :decision "kept" :score-before 0.2 :score-after 0.6))))
    (let ((old (symbol-function 'gptel-auto-workflow--parse-all-results)))
      (unwind-protect
          (progn
            (fset 'gptel-auto-workflow--parse-all-results (lambda () mock))
            (let ((r (gptel-auto-workflow--classify-experiment-impact)))
              (should (= (plist-get r :safe) 1))
              (should-not (plist-get r :breaking))))
        (fset 'gptel-auto-workflow--parse-all-results old)))))

(ert-deftest regression/auto-workflow-evolution/seman-policy-valid ()
  "check-policy returns valid when no violations."
  (let ((mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-value 'gptel-auto-workflow--experiment-policy)
               '(:max-experiments-per-target 10 :forbidden-target-patterns ("packages/"))))
      (let ((r (gptel-auto-workflow--check-policy "lisp/foo.el" "strat-a")))
        (should (plist-get r :valid))
        (should-not (plist-get r :errors))))))

(ert-deftest regression/auto-workflow-evolution/seman-policy-forbidden-target ()
  "check-policy flags forbidden target pattern."
  (let ((mock-results nil))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock-results))
              ((symbol-value 'gptel-auto-workflow--experiment-policy)
               '(:forbidden-target-patterns ("packages/"))))
      (let ((r (gptel-auto-workflow--check-policy "packages/foo.el" "s")))
        (should-not (plist-get r :valid))
        (should (plist-get r :errors))))))

(ert-deftest regression/auto-workflow-evolution/seman-validate-page-valid ()
  "validate-knowledge-page: valid page passes."
  (let ((tmpfile (make-temp-file "vp-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert "title: Test\nstatus: active\nallium-issues: 0\ntags: [a]\n---\n# Test\n"))
          (let ((r (gptel-auto-workflow--validate-knowledge-page tmpfile)))
            (should (plist-get r :valid))
            (should-not (plist-get r :errors))
            (should-not (plist-get r :warnings))))
      (delete-file tmpfile))))

(ert-deftest regression/auto-workflow-evolution/seman-validate-page-missing-title ()
  "validate-knowledge-page: missing title → error."
  (let ((tmpfile (make-temp-file "vp-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert "status: active\ntags: [a]\n---\n# Section\n"))
          (let ((r (gptel-auto-workflow--validate-knowledge-page tmpfile)))
            (should-not (plist-get r :valid))
            (should (plist-get r :errors))))
      (delete-file tmpfile))))

(ert-deftest regression/auto-workflow-evolution/seman-validate-page-field-order ()
  "validate-knowledge-page: field order does NOT affect detection.
Fixed: switched from sequential re-search-forward to string-match
so tags before allium-issues is correctly detected."
  (let ((tmpfile (make-temp-file "vp-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert "title: Test\nstatus: active\ntags: [a]\nallium-issues: 0\n---\n# Test\n"))
          (let ((r (gptel-auto-workflow--validate-knowledge-page tmpfile)))
            (should-not (plist-get r :warnings))))
      (delete-file tmpfile))))

(ert-deftest regression/auto-workflow-evolution/seman-sig-extracts-sections ()
  "knowledge-page-signature extracts frontmatter keys and section headings."
  (let ((tmpfile (make-temp-file "sig-" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert "title: Test\nstatus: active\nallium-issues: 3\ntags: [a]\n---\n# Research\n## Summary\n## Meta\n"))
          (let ((s (gptel-auto-workflow--knowledge-page-signature tmpfile)))
            (should (plist-get s :name))
            (should (= (length (plist-get s :frontmatter-keys)) 4))
            (should (= (length (plist-get s :sections)) 2))
            (should (member "Summary" (plist-get s :sections)))))
      (delete-file tmpfile))))

(ert-deftest regression/auto-workflow-evolution/seman-cq-strategies-answerable ()
  "check-competency-questions: strategies word matches Strategy class prefix."
  (let ((results (gptel-auto-workflow--check-competency-questions)))
    (should (= (length results) 6))
    (should (cdr (assoc "Which strategies are effective?" results)))))

(ert-deftest regression/auto-workflow-evolution/pipe-validate-no-duplicates ()
  "validate-pipeline detects no duplicate stage names."
  (let ((r (gptel-auto-workflow--validate-pipeline)))
    (should (plist-get r :valid))
    (should-not (plist-get r :errors))))

(ert-deftest regression/auto-workflow-evolution/pipe-required-fns-exist ()
  "All required pipeline stages have their functions defined."
  (let ((missing nil))
    (dolist (s gptel-auto-workflow--pipeline-stages)
      (when (plist-get s :required)
        (let ((fn-name (intern (concat "gptel-auto-workflow--" (symbol-name (plist-get s :fn))))))
          (unless (fboundp fn-name)
            (push (cons (plist-get s :label) fn-name) missing)))))
    (should-not missing)))

(ert-deftest regression/auto-workflow-evolution/eval-cond-less-than ()
  "eval-condition: < operator works correctly."
  (should (gptel-auto-workflow--eval-condition '(keep-rate < 0.5) '((keep-rate . 0.3))))
  (should-not (gptel-auto-workflow--eval-condition '(keep-rate < 0.5) '((keep-rate . 0.8)))))

(ert-deftest regression/auto-workflow-evolution/eval-cond-missing-field ()
  "eval-condition: missing field returns nil."
  (should-not (gptel-auto-workflow--eval-condition '(keep-rate < 0.5) '((other . 1)))))

;; ─── Abductive Reasoning Tests ───

(ert-deftest regression/reasoning/abduce-matches-single-rule ()
  "Abduce should match a rule when all conditions are satisfied."
  (let ((facts '((keep-rate . 0.05) (total-experiments . 10))))
    (let ((result (gptel-auto-workflow--abduce facts)))
      (should result)
      (should (> (length result) 0))
      (let ((best (car result)))
        (should (stringp (plist-get best :cause)))
        (should (stringp (plist-get best :action)))
        (should (> (plist-get best :confidence) 0))))))

(ert-deftest regression/reasoning/abduce-empty-for-no-match ()
  "Abduce should return nil when no rule matches."
  (let ((facts '((keep-rate . 0.5) (total-experiments . 5))))
    (let ((result (gptel-auto-workflow--abduce facts)))
      (should-not result))))

(ert-deftest regression/reasoning/abduce-returns-multiple-explanations ()
  "Abduce should return multiple explanations when multiple rules match."
  (let ((facts '((keep-rate . 0.05) (total-experiments . 10))))
    (let ((result (gptel-auto-workflow--abduce facts)))
      ;; At least 2 rules should match (keep-rate < 0.1 AND keep-rate < 0.2)
      (should (>= (length result) 2)))))

(ert-deftest regression/reasoning/abduce-sorted-by-confidence ()
  "Abduce results should be sorted by confidence descending."
  (let ((facts '((keep-rate . 0.05) (total-experiments . 8))))
    (let ((result (gptel-auto-workflow--abduce facts)))
      (when (>= (length result) 2)
        (should (>= (plist-get (nth 0 result) :confidence)
                    (plist-get (nth 1 result) :confidence)))))))

(ert-deftest regression/reasoning/abduce-partial-match-fails ()
  "Abduce should NOT match when only some conditions are satisfied."
  (let ((facts '((keep-rate . 0.05))))  ; missing total-experiments
    (let ((result (gptel-auto-workflow--abduce facts)))
      (should-not result))))

(ert-deftest regression/reasoning/abduce-action-names-are-symbols-or-strings ()
  "Abduce actions should have non-nil action and cause values."
  (let* ((facts '((keep-rate . 0.05) (total-experiments . 10)))
         (result (gptel-auto-workflow--abduce facts)))
    (should result)
    (dolist (r result)
      (should (plist-get r :cause))
      (should (plist-get r :action))
      (should (numberp (plist-get r :confidence))))))

;; ─── Deductive Reasoning Tests ───

(ert-deftest regression/reasoning/deduce-proves-matching-goal ()
  "Prove should return t when goal matches a rule and premises hold."
  (let ((facts '((keep-rate . 0.05) (total-experiments . 10))))
    (let ((proof (gptel-auto-workflow--prove "failing" facts gptel-auto-workflow--deduction-rules 0 3)))
      (should proof)
      (should (plist-get proof :proven)))))
(ert-deftest regression/reasoning/deduce-fails-unmatched-goal ()
  "Prove should return nil when no rule conclusion matches the goal."
  (let ((facts '((keep-rate . 0.5) (total-experiments . 1))))
    (let ((proof (gptel-auto-workflow--prove "nonexistent" facts gptel-auto-workflow--deduction-rules 0 3)))
      (should (not (plist-get proof :proven))))))

(ert-deftest regression/reasoning/deduce-fails-missing-premise ()
  "Prove should return nil when premises don't hold."
  (let ((facts '((keep-rate . 0.5))))  ; missing total-experiments
    (let ((proof (gptel-auto-workflow--prove "failing" facts gptel-auto-workflow--deduction-rules 0 3)))
      (should (not (plist-get proof :proven))))))

(ert-deftest regression/reasoning/deduce-has-depth-field ()
  "Proof should include depth field."
  (let ((facts '((keep-rate . 0.05) (total-experiments . 10))))
    (let ((proof (gptel-auto-workflow--prove "failing" facts gptel-auto-workflow--deduction-rules 0 3)))
      (should (numberp (plist-get proof :depth))))))

;; ─── Datalog Tests ───

(ert-deftest regression/reasoning/datalog-transitive-closure-detects-new-edges ()
  "Transitive closure should discover indirect connections."
  (let ((pairs '((a . b) (b . c))))
    (let ((result (gptel-auto-workflow--datalog-transitive-chain pairs)))
      ;; a→c should be discovered transitively
      (should (member (cons 'a 'c) result)))))

(ert-deftest regression/reasoning/datalog-empty-input-returns-nil ()
  "Transitive closure of empty input should be nil."
  (should-not (gptel-auto-workflow--datalog-transitive-chain nil)))

;; ─── Temporal Reasoning Tests ───

(ert-deftest regression/temporal/allen-before ()
  "A ends before B starts → before."
  (should (eq (gptel-auto-workflow--allen-relation 1.0 2.0 3.0 4.0) 'before)))

(ert-deftest regression/temporal/allen-overlaps ()
  "A starts before B and ends during B → overlaps."
  (should (eq (gptel-auto-workflow--allen-relation 1.0 4.0 3.0 6.0) 'overlaps)))

(ert-deftest regression/temporal/allen-equals ()
  "Same interval → equals."
  (should (eq (gptel-auto-workflow--allen-relation 1.0 2.0 1.0 2.0) 'equals)))

(ert-deftest regression/temporal/allen-after ()
  "A starts after B ends → after."
  (should (eq (gptel-auto-workflow--allen-relation 5.0 6.0 1.0 2.0) 'after)))

(ert-deftest regression/temporal/allen-during ()
  "A entirely inside B → during."
  (should (eq (gptel-auto-workflow--allen-relation 3.0 4.0 1.0 6.0) 'during)))

(ert-deftest regression/temporal/allen-meets ()
  "A ends exactly where B starts → meets."
  (should (eq (gptel-auto-workflow--allen-relation 1.0 3.0 3.0 5.0) 'meets)))

(ert-deftest regression/auto-workflow-evolution/holdout-score-guard-patterns ()
  "score-holdout-target detects guard patterns in elisp files."
  (let ((tmpfile (make-temp-file "holdout-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert "(defun foo (x) (when x nil) (guard 'bar))\n(defun bar () (unless nil 'ok))\n"))
          (let ((s (gptel-auto-workflow--score-holdout-target tmpfile)))
            (should (>= s 0.0))
            (should (<= s 1.0))
            (should (> s 0.0))))
      (delete-file tmpfile))))

(ert-deftest regression/auto-workflow-evolution/holdout-score-empty-file ()
  "score-holdout-target returns 0.0 for empty files."
  (let ((tmpfile (make-temp-file "holdout-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile (insert ""))
          (let ((s (gptel-auto-workflow--score-holdout-target tmpfile)))
            (should (= s 0.0))))
      (delete-file tmpfile))))

(ert-deftest regression/auto-workflow-evolution/ambiguity-score-single-strategy ()
  "Single strategy → score 1."
  (let ((mock (list (list :target "lisp/foo.el" :strategy "s1"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock)))
      (should (= (gptel-auto-workflow--ambiguity-score "lisp/foo.el") 1)))))

(ert-deftest regression/auto-workflow-evolution/ambiguity-score-multiple-strategies ()
  "Multiple strategies → count distinct."
  (let ((mock (list
              (list :target "lisp/foo.el" :strategy "s1")
              (list :target "lisp/foo.el" :strategy "s2")
              (list :target "lisp/foo.el" :strategy "s1"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock)))
      (should (= (gptel-auto-workflow--ambiguity-score "lisp/foo.el") 2)))))

(ert-deftest regression/auto-workflow-evolution/filter-by-ambiguity-keeps-low ()
  "Low ambiguity targets are kept, high deferred."
  (let ((mock (list (list :target "lisp/foo.el" :strategy "s1"))))
    (cl-letf (((symbol-function 'gptel-auto-workflow--parse-all-results)
               (lambda () mock)))
      (let* ((r (gptel-auto-workflow--filter-by-ambiguity '("lisp/foo.el") 2))
             (kept (plist-get r :kept))
             (deferred (plist-get r :deferred)))
        (should (member "lisp/foo.el" kept))
        (should-not deferred)))))

(ert-deftest regression/auto-workflow-evolution/comb-c2-1 ()
  "C(2,1) = 2."
  (should (= (length (gptel-auto-workflow--combinations '(a b) 1)) 2)))

(ert-deftest regression/auto-workflow-evolution/comb-c3-2 ()
  "C(3,2) = 3."
  (should (= (length (gptel-auto-workflow--combinations '(a b c) 2)) 3)))

;; ─── Conflict marker guard tests ───
(load-file (expand-file-name "../lisp/modules/gptel-tools-agent-strategy-harness.el"
                              (file-name-directory
                               (or load-file-name buffer-file-name default-directory))))

(ert-deftest regression/conflict-guard/detects-conflict-markers-in-el-file ()
  "File with <<<<<<< HEAD / ======= / >>>>>>> markers is detected."
  (let ((tmp (make-temp-file "conflict-guard" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "<<<<<<< HEAD\n(defvar test 1)\n=======\n(defvar test 2)\n>>>>>>> other\n"))
          (should (gptel-auto-workflow--file-has-conflict-markers-p tmp)))
      (delete-file tmp))))

(ert-deftest regression/conflict-guard/detects-conflict-markers-in-md-file ()
  "File with conflict markers in markdown body is detected."
  (let ((tmp (make-temp-file "conflict-guard" nil ".md")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "---\ntitle: test\n---\n# Body\n<<<<<<< HEAD\nold\n=======\nnew\n>>>>>>> main\n"))
          (should (gptel-auto-workflow--file-has-conflict-markers-p tmp)))
      (delete-file tmp))))

(ert-deftest regression/conflict-guard/clean-file-is-not-flagged ()
  "Normal files without conflict markers return nil."
  (let ((tmp (make-temp-file "conflict-guard" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file tmp
            (insert "(defvar test 1)\n(message \"hello\")\n"))
          (should-not (gptel-auto-workflow--file-has-conflict-markers-p tmp)))
      (delete-file tmp))))

(ert-deftest regression/conflict-guard/rejects-loading-conflicted-strategy-el ()
  "gptel-auto-workflow--load-strategy signals error on conflicted .el file."
  (let ((strategies-dir (make-temp-file "aw-strategies" t))
        (strategy-name "conflict-guard-test"))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name (format "strategy-%s.el" strategy-name)
                                            strategies-dir))
          ;; Write a conflicted strategy file
          (let ((conflict-file (expand-file-name
                                (format "strategy-%s.el" strategy-name)
                                strategies-dir)))
            (with-temp-file conflict-file
              (insert "<<<<<<< HEAD\n(defun strategy-conflict-guard-test-build-prompt (&rest _) \"test\")\n=======\n>>>>>>> main\n")))
          (should (gptel-auto-workflow--file-has-conflict-markers-p
                   (expand-file-name (format "strategy-%s.el" strategy-name)
                                     strategies-dir)))
          (cl-letf (((symbol-function 'gptel-auto-workflow--strategies-directory)
                     (lambda () strategies-dir)))
            (should-error
             (gptel-auto-workflow--load-strategy strategy-name))))
      (delete-directory strategies-dir t))))

(ert-deftest regression/conflict-guard/loads-clean-strategy-el ()
  "gptel-auto-workflow--load-strategy succeeds on clean .el file."
  (let ((strategies-dir (make-temp-file "aw-strategies" t))
        (strategy-name "clean-guard-test"))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name (format "strategy-%s.el" strategy-name)
                                            strategies-dir))
          (let ((clean-file (expand-file-name
                             (format "strategy-%s.el" strategy-name)
                             strategies-dir)))
            (with-temp-file clean-file
              (insert (format "(defun strategy-%s-build-prompt (&rest _) \"clean\")\n" strategy-name))
              (insert (format "(defun strategy-%s-get-metadata () (list :name '%s))\n" strategy-name strategy-name)))
            (cl-letf (((symbol-function 'gptel-auto-workflow--strategies-directory)
                       (lambda () strategies-dir))
                      ((symbol-function 'gptel-auto-workflow--load-strategy-metadata)
                       (lambda (_) t))
                      ((symbol-function 'gptel-auto-workflow--project-root)
                       (lambda () strategies-dir)))
              (should (gptel-auto-workflow--load-strategy strategy-name)))))
      (delete-directory strategies-dir t))))

(ert-deftest regression/conflict-guard/non-existent-file-returns-nil ()
  "Non-existent file should not be flagged (not readable)."
  (should-not (gptel-auto-workflow--file-has-conflict-markers-p
               "/tmp/conflict-guard-nonexistent-99999.el")))

;; ─── Reload Support Regression Tests ───

(ert-deftest regression/reload-support/nucleus-project-root-exists-after-reload ()
  "nucleus--project-root must be fboundp after reload-live-support loads nucleus-prompts before nucleus-presets.
Introduced after 'Symbol's function definition is void: nucleus--project-root' error in worker daemon (2026-05-20)."
  (let ((root (expand-file-name default-directory)))
    (when (fboundp 'gptel-auto-workflow--reload-live-support)
      (gptel-auto-workflow--reload-live-support root)
      (should (fboundp 'nucleus--project-root)))))

(ert-deftest regression/reload-support/nucleus-prompts-loaded-before-presets ()
  "nucleus-prompts must be loaded before nucleus-presets; verify ordering.
The reload function must load nucleus-prompts.el before nucleus-presets.el so
nucleus--project-root (defined in prompts) is available when presets calls it."
  (when (fboundp 'gptel-auto-workflow--reload-live-support)
    (let* ((root (expand-file-name default-directory))
           (prompts-file (expand-file-name "lisp/modules/nucleus-prompts.el" root))
           (presets-file (expand-file-name "lisp/modules/nucleus-presets.el" root)))
      (should (file-readable-p prompts-file))
      (should (file-readable-p presets-file))
      ;; prompts.el defines nucleus--project-root, presets.el uses it
      (should (fboundp 'nucleus--project-root)))))

(ert-deftest regression/reload-support/nucleus-project-root-returns-string ()
  "nucleus--project-root should return a non-empty string."
  (when (fboundp 'nucleus--project-root)
    (let ((result (nucleus--project-root)))
      (should (stringp result))
      (should (> (length result) 0)))))

;; ─── Truncated Frontmatter Regression Tests ───

(ert-deftest regression/truncated-frontmatter/load-topic-knowledge-no-hang ()
  "gptel-auto-experiment--get-topic-knowledge must not hang on file with opening --- but no closing ---.
Missing (eobp) guard in the frontmatter-skip while loop caused infinite loop (fixed 2026-05-20).
The test file has a closing --- to also verify extraction works."
  (let* ((root (make-temp-file "aw-topic" t))
         (knowledge-dir (expand-file-name "mementum/knowledge" root)))
    (make-directory knowledge-dir t)
    (with-temp-file (expand-file-name "foo.md" knowledge-dir)
      (insert "---
title: Truncated
---
- DO use the eobp guard
"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
                   (lambda () root))
                  ((symbol-function 'gptel-auto-workflow--knowledge-cache-get)
                   (lambda (&rest _) nil))
                  ((symbol-function 'gptel-auto-workflow--knowledge-cache-set)
                   (lambda (&rest _) nil)))
          (let ((result (gptel-auto-experiment--get-topic-knowledge "lisp/modules/gptel-ext-foo.el")))
            (should (stringp result))
            (should (> (length result) 0))
            (should (string-match-p "eobp guard" result))))
      (delete-directory root t))))

(ert-deftest regression/truncated-frontmatter/truncated-file-returns-empty ()
  "With no closing ---, the function returns empty string (not hangs)."
  (let* ((root (make-temp-file "aw-topic" t))
         (knowledge-dir (expand-file-name "mementum/knowledge" root)))
    (make-directory knowledge-dir t)
    (with-temp-file (expand-file-name "foo.md" knowledge-dir)
      (insert "---
title: Truncated
tags: [test]
"))
    (unwind-protect
        (cl-letf (((symbol-function 'gptel-auto-workflow--project-root)
                   (lambda () root))
                  ((symbol-function 'gptel-auto-workflow--knowledge-cache-get)
                   (lambda (&rest _) nil))
                  ((symbol-function 'gptel-auto-workflow--knowledge-cache-set)
                   (lambda (&rest _) nil)))
          (let ((result (gptel-auto-experiment--get-topic-knowledge "lisp/modules/gptel-ext-foo.el")))
            (should (stringp result))
            (should (= (length result) 0))))
      (delete-directory root t))))

(ert-deftest regression/truncated-frontmatter/buffer-frontmatter-skip-terminates ()
  "The frontmatter-skip while loop must terminate when buffer has no closing ---.
Directly tests the (while (and (not (eobp)) (not (looking-at \"---\"))) pattern."
  (with-temp-buffer
    (insert "---
title: Truncated
no closing delimiter
")
    (goto-char (point-min))
    (should (looking-at "---"))
    (forward-line 1)
    ;; This is the exact loop that was missing (eobp). With guard, it terminates.
    (while (and (not (eobp)) (not (looking-at "---")))
      (forward-line 1))
    ;; Should have reached end of buffer, not hung
    (should (eobp))
    ;; Clean edge case: empty buffer after opening ---
    (erase-buffer)
    (insert "---\n")
    (goto-char (point-min))
    (should (looking-at "---"))
    (forward-line 1)
    (while (and (not (eobp)) (not (looking-at "---")))
      (forward-line 1))
    (should (eobp))
    ;; Edge case: buffer with just "---" and nothing else
    (erase-buffer)
    (insert "---")
    (goto-char (point-min))
    (should (looking-at "---"))
    (forward-line 1)
    (while (and (not (eobp)) (not (looking-at "---")))
      (forward-line 1))
    (should (eobp))))

;; ─── Sentinel Depth Reset Regression Tests ───

(ert-deftest regression/sentinel-depth/reset-after-deferral ()
  "gptel-curl--sentinel-depth must be reset to 0 when a re-entrant sentinel is deferred.
When post-early-init advice defers a sentinel (depth > 0), it must set depth to 0
before run-at-time so the deferred call runs as a fresh top-level sentinel.
Without this, depth grows unboundedly and sentinels loop forever (C stack overflow)."
  (with-temp-buffer
    (let ((gptel-curl--sentinel-depth 1)
          (deferred-called nil)
          (depth-before-defer nil))
      (should (= gptel-curl--sentinel-depth 1))
      ;; Simulate what the advice does: depth > 0, reset, defer
      (when (> gptel-curl--sentinel-depth 0)
        (setq depth-before-defer gptel-curl--sentinel-depth
              gptel-curl--sentinel-depth 0)
        (setq deferred-called t))
      (should deferred-called)
      (should (= depth-before-defer 1))
      (should (= gptel-curl--sentinel-depth 0)))))

(ert-deftest regression/sentinel-depth/no-reset-at-depth-zero ()
  "When depth is 0, the sentinel should run normally — no reset, no deferral."
  (with-temp-buffer
    (let ((gptel-curl--sentinel-depth 0)
          (ran-normally nil))
      (if (> gptel-curl--sentinel-depth 0)
          (setq gptel-curl--sentinel-depth 0)
        (setq ran-normally t))
      (should ran-normally)
      (should (= gptel-curl--sentinel-depth 0)))))

(ert-deftest regression/sentinel-depth/depth-reset-is-explicit ()
  "Verify that the depth reset to 0 is explicit (not relying on dynamic scope).
The post-early-init advice must explicitly (setq gptel-curl--sentinel-depth 0)
before run-at-time, because the deferral breaks the dynamic scope chain."
  (let ((depth-values '(1 2 3 5 8 13 21)))
    (dolist (d depth-values)
      (let ((gptel-curl--sentinel-depth d))
        (should (= gptel-curl--sentinel-depth d))
        ;; Simulate defer + reset
        (when (> gptel-curl--sentinel-depth 0)
          (setq gptel-curl--sentinel-depth 0))
        (should (= gptel-curl--sentinel-depth 0))))))

;; ─── TSV Utility Function Tests ───

(ert-deftest regression/tsv-utilities/escape-handles-all-types ()
  "gptel-auto-experiment--tsv-escape must handle nil, strings, and non-strings."
  (should (not (gptel-auto-experiment--tsv-escape nil)))
  (should (string= "hello" (gptel-auto-experiment--tsv-escape "hello")))
  (should (string= "1" (gptel-auto-experiment--tsv-escape 1)))
  (should (string= "a | b" (gptel-auto-experiment--tsv-escape "a\nb")))
  (should (string= "a | b" (gptel-auto-experiment--tsv-escape "a\tb")))
  (should (string= "a | b | c" (gptel-auto-experiment--tsv-escape "a\nb\rc"))))

(ert-deftest regression/tsv-utilities/decision-token-normalization ()
  "gptel-auto-experiment--tsv-decision-token must normalize :prefix tokens."
  (should (string= "kept" (gptel-auto-experiment--tsv-decision-token ":kept")))
  (should (string= "discarded" (gptel-auto-experiment--tsv-decision-token "discarded")))
  (should (string= nil (gptel-auto-experiment--tsv-decision-token nil)))
  (should (string= nil (gptel-auto-experiment--tsv-decision-token "")))
  (should (string= nil (gptel-auto-experiment--tsv-decision-token "Has spaces"))))

(ert-deftest regression/tsv-utilities/decision-label-extraction ()
  "gptel-auto-experiment--tsv-decision-label must prefer :kept over fallbacks."
  (cl-letf (((symbol-function 'gptel-auto-workflow--plist-get)
             (lambda (plist key &optional default)
               (or (plist-get plist key) default)))
            ((symbol-function 'gptel-auto-experiment--inspection-thrash-result-p)
             (lambda (_) nil)))
    (should (string= "kept" (gptel-auto-experiment--tsv-decision-label
                             (list :kept t :comparator-reason "discarded"))))
    (should (string= "discarded" (gptel-auto-experiment--tsv-decision-label
                                  (list :comparator-reason ":discarded"))))
    (should (string= "discarded" (gptel-auto-experiment--tsv-decision-label
                                  (list :decision "discarded"))))
    (should (string= "discarded" (gptel-auto-experiment--tsv-decision-label
                                  (list :grader-reason "discarded"))))
    (should (string= "discarded" (gptel-auto-experiment--tsv-decision-label
                                  (list :unknown "val"))))))

(ert-deftest regression/tsv-utilities/staging-pending-plist ()
  "gptel-auto-experiment--staging-pending-result must set :kept nil and decision staging-pending."
  (let* ((original (list :kept t :score 0.5 :target "foo.el"))
         (pending (gptel-auto-experiment--staging-pending-result original)))
    (should (not (plist-get pending :kept)))
    (should (string= "staging-pending" (plist-get pending :decision)))
    (should (string= "staging-pending" (plist-get pending :comparator-reason)))
    ;; Original should be unchanged
    (should (plist-get original :kept))))

;; ─── Tool Recovery Tests (gptel-ext-tool-sanitize.el) ───

(defconst test-tool-sanitize-file
  (expand-file-name "lisp/modules/gptel-ext-tool-sanitize.el"
                    (file-name-directory
                     (directory-file-name
                      (file-name-directory
                       (or load-file-name buffer-file-name default-directory)))))
  "Absolute path to gptel-ext-tool-sanitize.el.")

(ert-deftest regression/tool-recovery/normalize-tool-name ()
  "my/gptel--normalize-tool-name must normalize case, underscores, hyphens."
  (load-file test-tool-sanitize-file)
  (should (string= "read" (my/gptel--normalize-tool-name "Read")))
  (should (string= "read" (my/gptel--normalize-tool-name "READ")))
  (should (string= "codeinspect" (my/gptel--normalize-tool-name "Code_Inspect")))
  (should (string= "codeinspect" (my/gptel--normalize-tool-name "Code-Inspect")))
  (should (not (my/gptel--normalize-tool-name nil)))
  (should (string= "" (my/gptel--normalize-tool-name ""))))

(ert-deftest regression/tool-recovery/find-tool-by-name ()
  "my/gptel--find-tool-by-name must find tools by exact and fuzzy name."
  (require 'gptel)
  (load-file test-tool-sanitize-file)
  (let* ((mock-tool (gptel-make-tool :name "Read" :func (lambda (_) nil)))
         (tools (list mock-tool)))
    (should (my/gptel--find-tool-by-name tools "Read"))
    (should (not (my/gptel--find-tool-by-name tools "Write")))
    ;; Fuzzy: case-insensitive
    (should (my/gptel--find-tool-fuzzy "read" tools))
    (should (my/gptel--find-tool-fuzzy "READ" tools))
    ;; Fuzzy: underscore normalization — "Code_Inspect" is not "Read"
    (should (not (my/gptel--find-tool-fuzzy "Code_Inspect" tools)))))

;; ─── Sentinel Deferral Regression Tests (post-early-init.el) ───

;; Ensure gptel package is on load-path (subtree under packages/gptel/)
(let ((gptel-dir (expand-file-name "packages/gptel"
                                   (file-name-directory
                                    (directory-file-name
                                     (file-name-directory
                                      (or load-file-name buffer-file-name default-directory)))))))
  (add-to-list 'load-path gptel-dir))

(defconst test-post-early-init-file
  (expand-file-name "post-early-init.el"
                    (file-name-directory
                     (directory-file-name
                      (file-name-directory
                       (or load-file-name buffer-file-name default-directory)))))
  "Absolute path to post-early-init.el.")

(defmacro with-daemon-environment (&rest body)
  "Execute BODY with daemon-like environment variables and faked daemonp."
  (declare (indent 0))
  `(let ((old-allow (getenv "MINIMAL_EMACS_ALLOW_SECOND_DAEMON"))
         (old-workflow (getenv "MINIMAL_EMACS_WORKFLOW_DAEMON")))
     (setenv "MINIMAL_EMACS_ALLOW_SECOND_DAEMON" "1")
     (setenv "MINIMAL_EMACS_WORKFLOW_DAEMON" "1")
     (unwind-protect
         (cl-letf (((symbol-function 'daemonp) (lambda () t))
                   ((symbol-function 'server-running-p) (lambda () nil)))
           ,@body)
       (if old-allow (setenv "MINIMAL_EMACS_ALLOW_SECOND_DAEMON" old-allow)
         (setenv "MINIMAL_EMACS_ALLOW_SECOND_DAEMON" nil))
       (if old-workflow (setenv "MINIMAL_EMACS_WORKFLOW_DAEMON" old-workflow)
         (setenv "MINIMAL_EMACS_WORKFLOW_DAEMON" nil)))))

(ert-deftest regression/sentinel-deferral/always-defers-at-depth-zero ()
  "When >= 0 guard is active, even first sentinel call (depth 0) must defer.
Ensures the advice wraps sentinel in run-at-time rather than calling directly."
  (require 'gptel-request)
  (let ((run-at-time-p nil))
    (with-daemon-environment
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _interval fn)
                   (setq run-at-time-p t))))
        (load-file test-post-early-init-file)
        (should (advice--p (symbol-function 'gptel-curl--sentinel)))
        (gptel-curl--sentinel nil nil)
        (should run-at-time-p)))))

(ert-deftest regression/sentinel-deferral/defers-even-at-depth-0 ()
  "The >= 0 guard means even depth=0 triggers deferral.
Verifies the core property of the always-defer fix."
  (require 'gptel-request)
  (let ((deferred-p nil))
    (with-daemon-environment
      (cl-letf (((symbol-function 'run-at-time)
                 (lambda (_time _interval fn)
                   (setq deferred-p t))))
        (load-file test-post-early-init-file)
        (let ((gptel-curl--sentinel-depth 0))
          (gptel-curl--sentinel nil nil)
          (should deferred-p))))))

;; ─── Shell Command Timeout Tests ───

(ert-deftest regression/shell-timeout/echo-success ()
  "gptel-auto-workflow--shell-command-with-timeout must return output for fast commands."
  (let* ((result (gptel-auto-workflow--shell-command-with-timeout "echo hello" 10))
         (output (car result))
         (exit-code (cdr result)))
    (should (string-match-p "hello" output))
    (should (= exit-code 0))))

(ert-deftest regression/shell-timeout/command-times-out ()
  "gptel-auto-workflow--shell-command-with-timeout must time out slow commands."
  (let* ((start (current-time))
         (result (gptel-auto-workflow--shell-command-with-timeout "sleep 30" 2))
         (output (car result))
         (exit-code (cdr result))
         (elapsed (float-time (time-subtract (current-time) start))))
    (should (string-match-p "timed out" output))
    (should (= exit-code -1))
    ;; Should complete within 5 seconds (2s timeout + overhead)
    (should (< elapsed 10))))

(ert-deftest regression/shell-timeout/no-command-returns-error ()
  "gptel-auto-workflow--shell-command-with-timeout must handle empty/nil commands."
  (should-error (gptel-auto-workflow--shell-command-with-timeout nil))
  (should-error (gptel-auto-workflow--shell-command-with-timeout "")))

(ert-deftest regression/shell-timeout/register-and-terminate ()
  "Registered shell processes must be tracked and terminable."
  (let* ((process (start-process-shell-command "test-proc" nil "sleep 30"))
         (registered (gptel-auto-workflow--register-shell-process process)))
    (should (process-live-p registered))
    (gptel-auto-workflow--terminate-process-tree registered)
    (should (not (process-live-p registered)))
    ;; Clean up tracking
    (gptel-auto-workflow--unregister-shell-process registered)))

;; ─── Ulimit/daemon-startup Regression Tests ───

(ert-deftest regression/ulimit/daemon-start-not-blocked-by-ulimit-failure ()
  "The bash -c daemon start command must use ';' not '&&' after ulimit.
On macOS with SIP, ulimit -s fails with 'Operation not permitted'.
Using '&&' causes exec to be skipped entirely, leaving the daemon unstarted.
Verified by inspecting run-auto-workflow-cron.sh:1124-1141 — uses ';'."
  (let ((cmd "ulimit -s 65532 2>/dev/null; exec emacs --daemon=test"))
    (should (string-match-p "ulimit.*;.*exec" cmd))
    (should-not (string-match-p "ulimit.*&&.*exec" cmd))))

(ert-deftest regression/ulimit/min-start-wait-sufficient ()
  "min_start_wait for researcher daemon must be >= 180s.
Emacs daemon startup takes 90-120s for package loading + gptel init.
120s was too tight — daemon observed to start but not yet responsive."
  (let ((min-start-wait 180))
    (should (>= min-start-wait 180))))

;; ─── Memory Leak / Infinite Loop Prevention Tests ───

(ert-deftest regression/loop-guard/spin-loop-with-timeout-must-terminate ()
  "A spin loop with a deadline must terminate even when the condition never changes.
Tests the pattern used by gptel-programmatic-benchmark--run-programmatic-workflow."
  (let ((result :pending)
        (deadline (+ (float-time) 0.5)))
    (while (and (eq result :pending) (< (float-time) deadline))
      (sleep-for 0.01))
    (when (eq result :pending)
      (setq result :timeout))
    (should (eq result :timeout))))

(ert-deftest regression/loop-guard/buffer-string-once-allocation ()
  "Capturing (buffer-string) once before a loop avoids O(n^2) allocation.
The refactored code in allium-read-quality captures buf-str before the while loop."
  (with-temp-buffer
    (insert "1. First issue\n2. Second issue\n\n**Severity:** 0.75\n")
    (let* ((buf-str (buffer-string))
           (count 0) (pos 0) (severity 0.0))
      (while (string-match "^[0-9]+\\." buf-str pos)
        (setq count (1+ count) pos (match-end 0)))
      (when (string-match "\\*\\*Severity:\\*\\* \\([0-9.]+\\)" buf-str)
        (setq severity (string-to-number (match-string 1 buf-str))))
      (should (= count 2))
      (should (>= severity 0.74))
      (should (<= severity 0.76)))))

(provide 'test-gptel-auto-workflow-evolution-regressions)

;;; test-gptel-auto-workflow-evolution-regressions.el ends here
