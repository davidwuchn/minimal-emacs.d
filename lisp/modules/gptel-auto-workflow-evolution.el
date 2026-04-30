;;; gptel-auto-workflow-evolution.el --- Self-evolution engine using mementum as source of truth -*- lexical-binding: t -*-

;; Architecture:
;;   Git History ──┐
;;                 ├──→ MEMENTUM ──→ Prompt Injection ──→ Experiments ──→ ...
;;   Benchmark ────┘      ↑                                      │
;;                        └──────────────────────────────────────┘
;;
;; Mementum is the SINGLE SOURCE OF TRUTH for self-evolution.
;; Git provides raw facts. Benchmark provides verification.
;; Both feed into mementum. Prompts read from mementum only.

(require 'cl-lib)
(require 'subr-x)

;; External functions from other modules
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent" ())

;; ─── Benchmark Parsing ───

(defun gptel-auto-workflow--parse-all-results ()
  "Parse all historical results.tsv files into a list of experiment records."
  (let ((results-dir (expand-file-name "var/tmp/experiments"
                                       (gptel-auto-workflow--worktree-base-root)))
        (records nil))
    (when (file-directory-p results-dir)
      (dolist (run-dir (directory-files results-dir t "^202[0-9]-"))
        (let ((tsv-file (expand-file-name "results.tsv" run-dir)))
          (when (file-exists-p tsv-file)
            (with-temp-buffer
              (insert-file-contents tsv-file)
              (goto-char (point-min))
              (forward-line 1)
              (while (not (eobp))
                (let ((line (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position))))
                  (unless (string-empty-p line)
                    (let* ((fields (split-string line "\t"))
                           (target (nth 1 fields))
                           (hypothesis (nth 2 fields))
                           (score-before (string-to-number (or (nth 3 fields) "0")))
                           (score-after (string-to-number (or (nth 4 fields) "0")))
                           (quality (string-to-number (or (nth 5 fields) "0")))
                           (delta-str (or (nth 6 fields) "+0.00"))
                           (decision (nth 7 fields))
                           (grader-q (string-to-number (or (nth 9 fields) "0"))))
                      (push (list :target target
                                  :hypothesis hypothesis
                                  :score-before score-before
                                  :score-after score-after
                                  :code-quality quality
                                  :delta delta-str
                                  :decision decision
                                  :grader-quality grader-q)
                            records))))
                (forward-line 1)))))))
    (nreverse records)))

(defun gptel-auto-workflow--categorize-hypothesis (hypothesis)
  "Categorize HYPOTHESIS into a change type based on keyword matching."
  (let ((text (downcase (or hypothesis ""))))
    (cond
     ;; Safety patterns - check first (more specific)
     ((or (string-match-p "safety\\|defensive\\|type.*check\\|assert\\|sanitize\\|escape\\|validate" text)
          (string-match-p "secure\\|audit\\|harden" text))
      'safety)
     ;; Bug fix patterns
     ((or (string-match-p "bug\\|fix\\|nil\\|error\\|runtime\\|crash\\|prevent\\|guard\\|off-by-one\\|boundary\\|threshold\\|inaccurate" text)
          (string-match-p "safeguard\\|protect\\|check.*nil\\|null\\|missing.*check" text))
      'bug-fix)
     ;; Performance patterns
     ((or (string-match-p "performance\\|cache\\|optimize\\|speed\\|slow\\|complexity\\|hot path\\|efficient" text)
          (string-match-p "reduce.*time\\|faster\\|memory\\|allocation\\|gc" text))
      'performance)
     ;; Refactoring patterns
     ((or (string-match-p "extract\\|duplicate\\|dedup\\|refactor\\|helper\\|rename\\|organiz\\|cleanup" text)
          (string-match-p "consolidat\\|centraliz\\|reus\\|maintainability\\|clarity" text))
      'refactoring)
     ;; Default
     (t 'other))))

;; ─── Configuration ───

(defcustom gptel-auto-workflow-evolution-enabled t
  "When non-nil, enable self-evolution via mementum."
  :type 'boolean
  :group 'gptel-tools-agent)

;; ─── Phase 1: Extract ──→ Git History as Raw Facts ───

(defun gptel-auto-workflow--git-raw-facts ()
  "Extract raw facts from git history.
Returns plist with :merged-commits :abandoned-branches :target-frequency."
  (let* ((all-branches-raw
          (split-string
           (shell-command-to-string
            "git branch -r --list 'origin/optimize/*'")
           "\n" t))
         (all-branches
          (cl-remove-if #'null
                        (mapcar (lambda (b)
                                  (when (string-match "origin/optimize/\\(.+\\)" b)
                                    (match-string 1 b)))
                                all-branches-raw)))
         (merge-commits
          (split-string
           (shell-command-to-string
            "git log --grep='Merge optimize/' --format='%s'")
           "\n" t))
         (merged-branches
          (cl-remove-duplicates
           (cl-remove-if (lambda (b) (or (null b) (string-empty-p b)))
                         (mapcar (lambda (m)
                                   (when (string-match "Merge optimize/\\([^ ]+\\)" m)
                                     (match-string 1 m)))
                                 merge-commits))
           :test #'equal))
         (active-merged (cl-intersection all-branches merged-branches :test #'equal))
         (active-abandoned (cl-set-difference all-branches merged-branches :test #'equal)))
    (list :total-active (length all-branches)
          :historical-merges (length merged-branches)
          :active-merged (length active-merged)
          :active-abandoned (length active-abandoned)
          :active-merge-rate (if (> (length all-branches) 0)
                                 (/ (float (length active-merged))
                                    (length all-branches))
                               0.0)
          :target-frequency
          (let ((freq (make-hash-table :test 'equal)))
            (dolist (branch all-branches)
              (let ((target (when (string-match "\\([^-]+\\)" branch)
                              (match-string 1 branch))))
                (when target
                  (puthash target (1+ (gethash target freq 0)) freq))))
            (let (result)
              (maphash (lambda (k v) (push (cons k v) result)) freq)
              (sort result (lambda (a b) (> (cdr a) (cdr b)))))))))

;; ─── Phase 2: Verify ──→ Benchmark as Pattern Validator ───

(defun gptel-auto-workflow--benchmark-verify-patterns (patterns)
  "Verify PATTERNS against benchmark data.
PATTERNS is an alist of (name . hypothesis-function).
Returns alist of (name . verified-score)."
  (let ((records (gptel-auto-workflow--parse-all-results))
        (verified nil))
    (dolist (pattern patterns)
      (let* ((name (car pattern))
             (hypothesis-matcher (cdr pattern))
             (matching (cl-remove-if-not
                        (lambda (r)
                          (funcall hypothesis-matcher (plist-get r :hypothesis)))
                        records))
             (kept (cl-count-if (lambda (r) (string= (plist-get r :decision) "kept"))
                                matching))
             (total (length matching)))
        (push (list name total kept
                    (if (> total 0) (/ (float kept) total) 0.0))
              verified)))
    (nreverse verified)))

;; ─── Phase 2.5: Per-Target Pattern Analysis ───

(defun gptel-auto-workflow--target-pattern-analysis ()
  "Analyze which hypothesis categories succeed for each target.
Returns alist of target → (category success-rate count)."
  (let ((records (gptel-auto-workflow--parse-all-results))
        (target-stats (make-hash-table :test 'equal)))
    ;; Collect per-target category counts
    (dolist (rec records)
      (let* ((target (file-name-nondirectory (or (plist-get rec :target) "unknown")))
             (cat (symbol-name (gptel-auto-workflow--categorize-hypothesis
                                (plist-get rec :hypothesis))))
             (decision (plist-get rec :decision))
             (key (cons target cat)))
        (let ((current (gethash key target-stats '(0 0))))
          (puthash key
                   (list (1+ (nth 0 current))
                         (if (string= decision "kept")
                             (1+ (nth 1 current))
                           (nth 1 current)))
                   target-stats))))
    ;; Convert to sorted alist
    (let ((result nil))
      (maphash (lambda (key data)
                 (let* ((target (car key))
                        (cat (cdr key))
                        (total (nth 0 data))
                        (kept (nth 1 data))
                        (rate (if (> total 0) (/ (float kept) total) 0.0)))
                   (when (>= total 3)
                     (let ((existing (assoc target result)))
                       (if existing
                           (push (list cat rate total) (cdr existing))
                         (push (cons target (list (list cat rate total))) result))))))
               target-stats)
      ;; Sort each target's categories by success rate
      (dolist (item result)
        (setcdr item (sort (cdr item)
                           (lambda (a b) (> (nth 1 a) (nth 1 b))))))
      ;; Sort targets by total experiment count
      (sort result (lambda (a b)
                     (> (cl-reduce #'+ (mapcar (lambda (x) (nth 2 x)) (cdr a)))
                        (cl-reduce #'+ (mapcar (lambda (x) (nth 2 x)) (cdr b)))))))))

;; ─── Phase 3: Synthesize ──→ Mementum as Knowledge ───

(defun gptel-auto-workflow--evolution-synthesize ()
  "Synthesize git facts and benchmark verification into mementum knowledge.
This is the CENTRAL function of self-evolution."
  (when gptel-auto-workflow-evolution-enabled
    (let* ((git-facts (gptel-auto-workflow--git-raw-facts))
           (knowledge-dir (expand-file-name "mementum/knowledge"
                                            (gptel-auto-workflow--worktree-base-root)))
           (evolution-file (expand-file-name "self-evolution.md" knowledge-dir)))

      (make-directory knowledge-dir t)

      ;; Write synthesized knowledge
      (with-temp-file evolution-file
        (insert "---\n")
        (insert "title: Self-Evolution Patterns\n")
        (insert "status: active\n")
        (insert "category: knowledge\n")
        (insert "tags: [self-evolution, auto-workflow, patterns, verified]\n")
        (insert (format "updated: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
        (insert "---\n\n")

        (insert "# Self-Evolution Knowledge Base\n\n")
        (insert "*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*\n")
        (insert "*It synthesizes git history (facts) and benchmark data (verification).*\n\n")

        ;; Section 1: Git Facts
        (insert "## Git History Facts\n\n")
        (insert (format "- Active experiment branches: %d\n"
                        (plist-get git-facts :total-active)))
        (insert (format "- Historical merges: %d\n"
                        (plist-get git-facts :historical-merges)))
        (insert (format "- Active branches merged: %d\n"
                        (plist-get git-facts :active-merged)))
        (insert (format "- Active branches abandoned: %d\n"
                        (plist-get git-facts :active-abandoned)))
        (insert (format "- Active merge rate: %.1f%%\n\n"
                        (* 100 (plist-get git-facts :active-merge-rate))))

        (insert "### Target Frequency\n\n")
        (dolist (freq (plist-get git-facts :target-frequency))
          (insert (format "- `%s`: %d experiments\n" (car freq) (cdr freq))))
        (insert "\n")

        ;; Section 2: Benchmark Verification
        (insert "## Benchmark-Verified Patterns\n\n")
        (let* ((verified
                (gptel-auto-workflow--benchmark-verify-patterns
                 `(("bug-fix" . ,(lambda (h)
                                   (string-match-p "fix\\|bug\\|nil\\|guard\\|error\\|prevent" h)))
                   ("performance" . ,(lambda (h)
                                       (string-match-p "perf\\|cache\\|optimize\\|speed" h)))
                   ("refactoring" . ,(lambda (h)
                                       (string-match-p "extract\\|duplicate\\|refactor\\|helper" h)))
                   ("safety" . ,(lambda (h)
                                  (string-match-p "safety\\|defensive\\|validate\\|check" h))))))
               (sorted-verified (sort (copy-sequence verified)
                                      (lambda (a b) (> (nth 3 a) (nth 3 b))))))
          (dolist (v verified)
            (let ((name (nth 0 v))
                  (total (nth 1 v))
                  (kept (nth 2 v))
                  (rate (nth 3 v)))
              (insert (format "- **%s**: %.0f%% verified (%d/%d experiments)\n"
                              name (* 100 rate) kept total))))
          (insert "\n")

          ;; Section 3: Actionable Advice (data-driven)
          (insert "## Actionable Advice for Next Experiments\n\n")
          (insert "Based on verified benchmark patterns (sorted by success rate):\n\n")
          (cl-loop for i from 1
                   for v in sorted-verified
                   for name = (nth 0 v)
                   for total = (nth 1 v)
                   for rate = (nth 3 v)
                   when (> total 0)
                   do (insert (format "%d. **%s** - %.0f%% kept (%d experiments)\n"
                                      i name (* 100 rate) total)))
          (insert "\n")
          (insert "## Critical Guidance for Maximum Success\n\n")
          (insert "To ensure your changes are KEPT (not discarded):\n\n")
          (insert "1. **Improve BOTH score AND quality** - Changes that improve only one metric often get discarded\n")
          (insert "2. **Target the weakest keys** - Focus on the specific Eight Keys with lowest scores\n")
          (insert "3. **Make minimal, focused changes** - Large changes often reduce quality despite good intentions\n")
          (insert "4. **Verify before submitting** - Run tests and confirm both score and quality improve\n")
          (insert "5. **Avoid 'safety theater'** - Adding ignore-errors or nil guards that don't fix real bugs reduces quality\n\n")
        (insert "\n")

        ;; Section 4: Per-Target Patterns
        (insert "## Per-Target Success Patterns\n\n")
        (insert "Which change types work best for each target file:\n\n")
        (let ((target-analysis (gptel-auto-workflow--target-pattern-analysis)))
          (if (null target-analysis)
              (insert "*Insufficient data for per-target analysis (need ≥3 experiments per target).*\n")
            (dolist (target-data target-analysis)
              (let ((target (car target-data))
                    (patterns (cdr target-data)))
                (insert (format "### `%s`\n\n" target))
                (dolist (pattern (seq-take patterns 3))
                  (let ((cat (nth 0 pattern))
                        (rate (nth 1 pattern))
                        (count (nth 2 pattern)))
                    (insert (format "- **%s**: %.0f%% (%d experiments)\n"
                                    cat (* 100 rate) count))))
                (insert "\n")))))

        (insert "## Feedback Loop\n\n")
        (insert "```\n")
        (insert "Experiments → Git History → Facts\n")
        (insert "     ↓            ↓          ↓\n")
        (insert "Benchmark → Verification → MEMENTUM\n")
        (insert "     ↑                           ↓\n")
        (insert "Prompt Injection ← Knowledge ←─┘\n")
        (insert "```\n")))

      (message "[auto-workflow] Synthesized self-evolution knowledge to %s"
               evolution-file))))

;; ─── Phase 4: Inject ──→ Prompts Read from Mementum ───

(defun gptel-auto-workflow--evolution-get-knowledge ()
  "Get self-evolution knowledge for prompt injection.
This is the ONLY interface between mementum and prompts."
  (let ((evolution-file (expand-file-name
                         "mementum/knowledge/self-evolution.md"
                         (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p evolution-file)
        (with-temp-buffer
          (insert-file-contents evolution-file)
          (goto-char (point-min))
          ;; Skip frontmatter
          (when (looking-at "---")
            (forward-line 1)
            (while (not (looking-at "---"))
              (forward-line 1))
            (forward-line 1))
          (buffer-string))
      "")))

;; ─── Integration ───

(defun gptel-auto-workflow-evolution-run-cycle ()
  "Run one full self-evolution cycle.
Extract → Verify → Synthesize → (Inject happens on next prompt)."
  (interactive)
  (message "[auto-workflow] Running self-evolution cycle...")
  (gptel-auto-workflow--evolution-synthesize)
  (message "[auto-workflow] Self-evolution cycle complete."))

(provide 'gptel-auto-workflow-evolution)
;;; gptel-auto-workflow-evolution.el ends here
