;;; gptel-auto-workflow-git-learning.el --- Learn from git history for self-evolution -*- lexical-binding: t -*-

;; This module extracts patterns from git history to complement benchmark TSV data.
;; Git history provides:
;;   - Merge commits = successful experiments (kept)
;;   - Branch survival = which experiments survive to merge
;;   - Commit messages = hypothesis text and target files
;;   - Temporal patterns = success rates over time
;;   - Target patterns = which files respond well to experiments

(require 'cl-lib)
(require 'subr-x)

(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent" ())

;; ─── Helpers ───

(defvar gptel-auto-workflow--git-learning-repo-root nil
  "Cached git repository root for git-learning.
Captured at load time to avoid worktree issues.")

(defun gptel-auto-workflow--git-learning-repo-root ()
  "Return the git repository root for git-learning.
Uses cached value from load time, or detects from current directory."
  (or gptel-auto-workflow--git-learning-repo-root
      (setq gptel-auto-workflow--git-learning-repo-root
            (string-trim
             (shell-command-to-string
              "git rev-parse --show-toplevel 2>/dev/null || echo ''")))))

;; ─── Configuration ───

(defcustom gptel-auto-workflow-git-learning-enabled t
  "When non-nil, analyze git history for self-evolution patterns."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-git-min-commits-for-pattern 3
  "Minimum commits needed to establish a reliable pattern."
  :type 'integer
  :group 'gptel-tools-agent)

;; ─── Git Data Extraction ───

(defun gptel-auto-workflow--git-experiment-commits ()
  "Extract experiment commits from git history.
Returns list of plists with :branch :target :hypothesis :merged :date :score.
Always runs git commands from the main repo root to avoid worktree issues."
  (let* ((repo-root (or (gptel-auto-workflow--git-learning-repo-root)
                        (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))))
         (git-cmd (if (and repo-root (not (string-empty-p repo-root)))
                      (format "git -C '%s' " repo-root)
                    "git "))
         (commits nil)
         (merge-commits
          (split-string
           (shell-command-to-string
            (concat git-cmd "log --grep='Merge optimize/' --format='%H|%s|%ci' --reverse"))
           "\n" t)))
    (dolist (merge merge-commits)
      ;; Match "Merge optimize/BRANCH-NAME ..." - branch name has no spaces
      (when (string-match "Merge optimize/\\([^ ]+\\)" merge)
        (let* ((branch-name (match-string 1 merge))
               (full-branch (concat "origin/optimize/" branch-name))
               ;; Get the actual experiment commit on the branch
               (exp-commit
                (string-trim
                 (shell-command-to-string
                  (concat git-cmd
                          (format "log --format='%%H|%%s' %s --not origin/main --not origin/staging | head -1"
                                  full-branch))))))
          (when (string-match "\\([a-f0-9]+\\)|\\(.+\\)" exp-commit)
            (let ((exp-hash (match-string 1 exp-commit))
                  (message (match-string 2 exp-commit)))
              (push (list :branch branch-name
                          :hash exp-hash
                          :merged t
                          :message message
                          :date nil
                          ;; Extract target from branch name: TARGET-HOST-expN
                          :target (progn
                                    (string-match "\\([^-]+\\)" branch-name)
                                    (match-string 1 branch-name)))
                    commits))))))
    (nreverse commits)))

(defun gptel-auto-workflow--git-categorize-commit-message (message)
  "Categorize a git commit MESSAGE into change types.
Returns a list of category symbols."
  (let ((text (downcase (or message "")))
        (categories nil))
    ;; Bug fix patterns
    (when (or (string-match-p "fix\\|bug\\|nil\\|guard\\|error\\|crash\\|prevent\\|validation\\|safeguard\\|boundary\\|off-by-one\\|threshold\\|inaccurate" text)
              (string-match-p "handle.*error\\|check.*nil\\|null.*check\\|missing.*validation" text))
      (push 'bug-fix categories))
    ;; Performance patterns
    (when (or (string-match-p "perf\\|cache\\|optimize\\|speed\\|complexity\\|hot.path\\|efficient\\|faster\\|memory\\|allocation" text)
              (string-match-p "reduce.*time\\|improve.*performance" text))
      (push 'performance categories))
    ;; Refactoring patterns
    (when (or (string-match-p "refactor\\|extract\\|duplicate\\|dedup\\|helper\\|rename\\|organiz\\|cleanup\\|consolidat\\|centraliz" text)
              (string-match-p "reus\\|maintainability\\|clarity\\|remove.*duplication" text))
      (push 'refactoring categories))
    ;; Safety patterns
    (when (or (string-match-p "safety\\|defensive\\|type.check\\|assert\\|sanitize\\|escape\\|validate\\|secure\\|audit\\|harden" text)
              (string-match-p "add.*check\\|improve.*validation" text))
      (push 'safety categories))
    ;; Feature/enhancement patterns
    (when (or (string-match-p "feat\\|add\\|support\\|implement\\|enable\\|new\\|enhance" text)
              (string-match-p "introduce\\|extend\\|expand" text))
      (push 'feature categories))
    (or categories '(other))))

;; ─── Pattern Computation ───

(defun gptel-auto-workflow--git-compute-target-stats (commits)
  "Compute per-target statistics from git COMMITS.
Returns alist of target → (total-commits kept-count success-rate)."
  (let ((stats (make-hash-table :test 'equal)))
    (dolist (commit commits)
      (let* ((target (or (plist-get commit :target) "unknown"))
             (merged (plist-get commit :merged))
             (current (gethash target stats '(0 0 0.0))))
        (puthash target
                 (list (1+ (nth 0 current))
                       (if merged (1+ (nth 1 current)) (nth 1 current))
                       0.0)
                 stats)))
    ;; Compute rates
    (let ((result nil))
      (maphash
       (lambda (target data)
         (let* ((total (nth 0 data))
                (kept (nth 1 data))
                (rate (if (> total 0) (/ (float kept) total) 0.0)))
           (when (>= total gptel-auto-workflow-git-min-commits-for-pattern)
             (push (list target total kept rate) result))))
       stats)
      (sort result (lambda (a b) (> (nth 3 a) (nth 3 b)))))))

(defun gptel-auto-workflow--git-compute-category-stats (commits)
  "Compute per-category statistics from git COMMITS.
Returns alist of category → (total kept success-rate avg-delta)."
  (let ((stats (make-hash-table :test 'eq)))
    ;; Initialize
    (dolist (cat '(bug-fix performance refactoring safety feature other))
      (puthash cat (list 0 0 0.0 0.0) stats))
    ;; Accumulate
    (dolist (commit commits)
      (let* ((categories (gptel-auto-workflow--git-categorize-commit-message
                          (plist-get commit :message)))
             (merged (plist-get commit :merged)))
        (dolist (cat categories)
          (let ((current (gethash cat stats)))
            (puthash cat
                     (list (1+ (nth 0 current))
                           (if merged (1+ (nth 1 current)) (nth 1 current))
                           0.0 0.0)
                     stats)))))
    ;; Compute rates
    (let ((result nil))
      (maphash
       (lambda (cat data)
         (let* ((total (nth 0 data))
                (kept (nth 1 data))
                (rate (if (> total 0) (/ (float kept) total) 0.0)))
           (push (list cat total kept rate) result)))
       stats)
      (sort result (lambda (a b) (> (nth 3 a) (nth 3 b)))))))

(defun gptel-auto-workflow--git-compute-temporal-stats (commits)
  "Compute temporal patterns from git COMMITS.
Returns plist with :recent-rate :older-rate :trend."
  (let* ((now (current-time))
         (recent-commits nil)
         (older-commits nil))
    (dolist (commit commits)
      (let* ((date-str (plist-get commit :date))
             (date (when date-str (encode-time (parse-time-string date-str)))))
        (when date
          (if (< (float-time (time-subtract now date)) (* 7 24 60 60))
              (push commit recent-commits)
            (push commit older-commits)))))
    (list :recent-total (length recent-commits)
          :recent-kept (cl-count-if (lambda (c) (plist-get c :merged)) recent-commits)
          :older-total (length older-commits)
          :older-kept (cl-count-if (lambda (c) (plist-get c :merged)) older-commits)
          :trend (if (> (length recent-commits) 0)
                     (if (> (length older-commits) 0)
                         (/ (float (cl-count-if (lambda (c) (plist-get c :merged)) recent-commits))
                            (length recent-commits))
                       0.0)
                   0.0))))

;; ─── Formatting for Prompts ───

(defun gptel-auto-workflow--git-format-target-patterns (commits)
  "Format target statistics from git COMMITS for prompt injection."
  (let* ((stats (gptel-auto-workflow--git-compute-target-stats commits))
         (lines (list "## Git History Target Patterns")))
    (if (null stats)
        (string-join (append lines '("No sufficient git history for target patterns yet.")) "\n")
      (setq lines (append lines '("Files with highest experiment success rates:")))
      (dolist (stat (seq-take stats 5))
        (let* ((target (nth 0 stat))
               (total (nth 1 stat))
               (kept (nth 2 stat))
               (rate (nth 3 stat)))
          (push (format "- %s: %.0f%% kept (%d/%d experiments)"
                        target (* 100 rate) kept total)
                (cdr (last lines)))))
      (string-join lines "\n"))))

(defun gptel-auto-workflow--git-format-category-patterns (commits)
  "Format category statistics from git COMMITS for prompt injection."
  (let* ((stats (gptel-auto-workflow--git-compute-category-stats commits))
         (lines (list "## Git History Change Type Patterns"))
         (high-success nil)
         (low-success nil))
    (dolist (stat stats)
      (let* ((cat (nth 0 stat))
             (total (nth 1 stat))
             (kept (nth 2 stat))
             (rate (nth 3 stat))
             (cat-name (pcase cat
                         ('bug-fix "Bug fixes / error handling")
                         ('performance "Performance improvements")
                         ('refactoring "Refactoring / deduplication")
                         ('safety "Safety / defensive checks")
                         ('feature "New features / enhancements")
                         ('other "Other changes"))))
        (when (> total 0)
          (if (>= rate 0.30)
              (push (format "- **%s**: %.0f%% merged (%d/%d commits)"
                            cat-name (* 100 rate) kept total)
                    high-success)
            (push (format "- %s: %.0f%% merged (%d/%d commits)"
                          cat-name (* 100 rate) kept total)
                  low-success)))))
    (when high-success
      (setq lines (append lines '("Change types with highest merge rates:")
                          (nreverse high-success))))
    (when low-success
      (setq lines (append lines '(""
                                  "Change types with lower merge rates:")
                          (nreverse low-success))))
    (string-join lines "\n")))

(defun gptel-auto-workflow--git-format-temporal-patterns (commits)
  "Format temporal patterns from git COMMITS for prompt injection."
  (let* ((stats (gptel-auto-workflow--git-compute-temporal-stats commits))
         (recent-total (plist-get stats :recent-total))
         (recent-kept (plist-get stats :recent-kept))
         (older-total (plist-get stats :older-total))
         (older-kept (plist-get stats :older-kept))
         (recent-rate (if (> recent-total 0) (/ (float recent-kept) recent-total) 0.0))
         (older-rate (if (> older-total 0) (/ (float older-kept) older-total) 0.0)))
    (format "## Temporal Patterns
Recent experiments (last 7 days): %.0f%% success (%d/%d)
Older experiments: %.0f%% success (%d/%d)
Trend: %s"
            (* 100 recent-rate) recent-kept recent-total
            (* 100 older-rate) older-kept older-total
            (cond
             ((> recent-rate (+ older-rate 0.1)) "IMPROVING - recent experiments more successful")
             ((< recent-rate (- older-rate 0.1)) "DECLINING - recent experiments less successful")
             (t "STABLE - consistent success rate")))))

;; ─── Combined Learning ───

(defun gptel-auto-workflow--git-learn-patterns ()
  "Learn patterns from git history and return formatted text.
Combines target, category, and temporal analysis."
  (if (not gptel-auto-workflow-git-learning-enabled)
      ""
    (let* ((commits (gptel-auto-workflow--git-experiment-commits))
           (total (length commits)))
      (if (= total 0)
          ""
        (string-join
         (list (format "## Git History Analysis (%d experiment commits)" total)
               ""
               (gptel-auto-workflow--git-format-category-patterns commits)
               ""
               (gptel-auto-workflow--git-format-target-patterns commits)
               ""
               (gptel-auto-workflow--git-format-temporal-patterns commits))
         "\n")))))

;; ─── Init ───

;; Cache repo root at load time to avoid worktree issues later
(when (and (null gptel-auto-workflow--git-learning-repo-root)
           (fboundp 'gptel-auto-workflow--git-learning-repo-root))
  (gptel-auto-workflow--git-learning-repo-root))

(provide 'gptel-auto-workflow-git-learning)
;;; gptel-auto-workflow-git-learning.el ends here
