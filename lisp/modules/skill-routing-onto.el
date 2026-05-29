;;; skill-routing-onto.el --- Ontology-driven skill selection for OV5  -*- lexical-binding: t; -*-

;; Adapts OV5's ontology router (4-dim scoring + holographic memory +
;; VSM auto-tuning + exploration) from backend routing to skill routing.
;; The ontology router was designed for 5 backends; this generalizes to N skills.

(require 'cl-lib)

;; ─── Category Ontology (ported from ontology-router:294-340) ───

(defconst sr-category-patterns
  '((:programming . "\\(?:benchmark\\|fsm\\|retry\\|reasoning\\|introspection\\|test\\|code\\|compile\\|elisp\\|refactor\\|validate\\|debug\\|discover\\|replace\\|function\\|syntax\\|macro\\|defun\\|byte-compil\\|segfault\\|infinite.loop\\|clojure\\|namespace\\|deps.edn\\|repl\\)")
    (:tool-calls  . "\\(?:sandbox\\|tool\\|bash\\|grep\\|glob\\|edit\\|apply\\|preview\\|programmatic\\|security\\|profile\\|permission\\|restrict\\|audit\\)")
    (:agentic     . "\\(?:agent\\|workflow\\|strategy\\|evolution\\|meta\\|propos\\|expert\\|prompt\\|system.prompt\\|code.review\\|pipeline\\)")
    (:natural-language . "\\(?:context\\|chat\\|conversation\\|language\\|text\\|summarize\\|stream\\|research\\|digest\\|reddit\\|benchmark-llm\\|llm\\|provider\\|structured.output\\)"))
  "Task category patterns: regex → category keyword.")

(defun sr--categorize-task (task-text)
  "Map TASK-TEXT to a category keyword using keyword overlap."
  (let ((lower (downcase task-text))
        (scores nil))
    (dolist (pair sr-category-patterns)
      (let* ((cat (car pair))
             (pattern (cdr pair))
             (matches (with-temp-buffer
                        (insert lower)
                        (goto-char (point-min))
                        (let ((count 0))
                          (while (re-search-forward pattern nil t)
                            (setq count (1+ count)))
                          count))))
        (when (> matches 0)
          (push (cons cat matches) scores))))
    (if scores
        (car (car (sort scores (lambda (a b) (> (cdr a) (cdr b))))))
      :natural-language)))

;; ─── Skill Index ───

(defvar sr--skill-index nil
  "Alist of (skill-dir . (category . content)) for all loaded skills.")

(defun sr--build-index ()
  "Scan assistant/skills/ and build index: (dir . (category . content))."
  (let* ((skills-dir (expand-file-name "assistant/skills"
                      (or (bound-and-true-p user-emacs-directory)
                          default-directory)))
         (index nil))
    (when (file-directory-p skills-dir)
      (dolist (dir (directory-files skills-dir t "^[^_]"))
        (when (file-directory-p dir)
          (let* ((skill-dir (file-name-nondirectory dir))
                 (content (sr--read-skill-content dir))
                 (category (sr--categorize-task (or skill-dir ""))))
            (when (> (length content) 50)
              (push (cons skill-dir (cons category content)) index))))))
    (setq sr--skill-index (nreverse index))))

(defun sr--read-skill-content (dir)
  "Read all content files from skill DIR."
  (let ((result ""))
    (dolist (f (list "SKILL.md" "DIRECTIVE.md" "agent-behavior.md"
                     "evals.json" "validation-pipeline.md"))
      (let ((file (expand-file-name f dir)))
        (when (file-readable-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (setq result (concat result "\n---\n" (buffer-string)))))))
    result))

;; ─── Multi-Dimensional Scoring (4 dims, ported from ontology-router:501-551) ───

(defconst sr-dim-weights
  '((:task-overlap . 0.10)   ;; keyword overlap is noisy
    (:category-fit . 0.20)   ;; category suitability
    (:keyword-depth . 0.20)  ;; unique keyword depth
    (:exclusive-match . 0.50)) ;; identity word bonus — strongest signal
  "Weight for each scoring dimension. Sums to 1.0.")

(defun sr--score-task-overlap (task-text skill-content)
   "How many task-relevant keywords appear in skill content.
Normalized to 0.0-1.0. Higher = better match.
Uses exclusive-word bonus: keywords unique to <3 skills get 2x weight,
reducing false positives from common words like 'code' or 'function'."
  (let* ((task-words (delete-dups
                      (split-string (downcase task-text) "[^a-z0-9-]+" t)))
         (common-words '("code" "function" "file" "use" "set" "new" "write"
                         "make" "fix" "change" "create" "add" "run" "need"
                         "work" "way" "get" "find" "implement" "support"
                         "configure" "check" "handle" "based" "following"))
         (content-lower (downcase (or skill-content "")))
         (score 0) (total-weight 0))
    (dolist (word task-words)
      (when (> (length word) 3)
        (let* ((is-common (member word common-words))
               (weight (if is-common 0.3 1.0))
               (present (string-match-p (regexp-quote word) content-lower)))
           (setq total-weight (+ total-weight weight))
           (when present
             (setq score (+ score weight))))))
    (if (zerop total-weight) 0.0
      (/ score total-weight))))

(defun sr--category-name (cat)
  "Return category keyword as string for comparison."
  (when (symbolp cat) (symbol-name cat)))

(defun sr--score-category-fit (task-category skill-category)
  "Score how well SKILL-CATEGORY matches TASK-CATEGORY.
Exact match = 1.0, programming→tool-calls or agentic = 0.3, else 0.0."
  (if (eq task-category skill-category) 1.0
    (let ((task-str (sr--category-name task-category))
          (skill-str (sr--category-name skill-category)))
      (if (and task-str skill-str)
          ;; programming-related tasks can fit tool-calls or agentic
          (if (and (string= task-str "programming")
                   (member skill-str '("tool-calls" "agentic")))
              0.3
            0.0)
        0.0))))

(defun sr--score-keyword-depth (task-text skill-content)
  "Ratio of task keywords that appear in skill content.
Measures breadth of coverage."
  (let* ((task-words (delete-dups
                      (split-string (downcase task-text) "[^a-z0-9-]+" t)))
         (content-lower (downcase (or skill-content "")))
         (matched 0))
    (dolist (word task-words)
      (when (and (> (length word) 3)
                 (string-match-p (regexp-quote word) content-lower))
         (setq matched (1+ matched))))
     (if (zerop (length task-words)) 0.0
       (/ (float matched) (length task-words)))))

;; ─── Health Ladder (ported from ontology-router:421-436) ───

(defvar sr--skill-strikes (make-hash-table :test 'equal)
  "Hash table: skill-dir → (consecutive-failures . last-failure-timestamp).
Skills with 3+ consecutive failures are quarantined (score reduced by 50%).")

(defconst sr-skill-stale-days 90
  "Days since last SKILL.md edit beyond which a skill is considered stale.
Stale skills receive a health penalty.")

(defun sr--skill-health (skill-dir skill-content)
  "Check SKILL-DIR health. Returns (healthy-p . penalty 0.0-0.5).
Penalty is subtracted from score. Ported from ontology-router `backend-quota-health`."
  (let* ((strikes (gethash skill-dir sr--skill-strikes '(0 . 0)))
         (consecutive-failures (car strikes))
         (stale-p (sr--skill-stale-p skill-dir))
         (penalty 0.0))
    ;; Consecutive-failure penalty
    (when (>= consecutive-failures 3)
      (setq penalty 0.5))
    ;; Stale-content penalty
    (when stale-p
      (setq penalty (+ penalty 0.2)))
    (cons (and (< penalty 0.5) (not stale-p)) penalty)))

(defun sr--skill-stale-p (skill-dir)
  "Check if SKILL-DIR's content files are stale (not modified in 90 days)."
  (let* ((skills-dir (expand-file-name "assistant/skills"
                      (or (bound-and-true-p user-emacs-directory)
                          default-directory)))
         (full-dir (expand-file-name skill-dir skills-dir))
         (latest-mtime 0))
    (dolist (f '("SKILL.md" "DIRECTIVE.md" "agent-behavior.md"))
      (let ((file (expand-file-name f full-dir)))
        (when (file-exists-p file)
          (setq latest-mtime (max latest-mtime
                                  (float-time (file-attribute-modification-time
                                               (file-attributes file))))))))
    (if (> latest-mtime 0)
        (> (/ (- (float-time) latest-mtime) 86400) sr-skill-stale-days)
      nil)))

(defun sr--record-skill-failure (skill-dir)
  "Record a consecutive failure for SKILL-DIR.
Resets when any other skill succeeds. Used by health ladder."
  (let ((current (gethash skill-dir sr--skill-strikes '(0 . 0))))
    (puthash skill-dir (cons (1+ (car current)) (float-time))
             sr--skill-strikes)))

(defun sr--record-skill-success (skill-dir)
  "Reset consecutive failure count on success."
  (let ((current (gethash skill-dir sr--skill-strikes '(0 . 0))))
    (puthash skill-dir (cons 0 (cdr current))
             sr--skill-strikes)))

;; ─── Exclusive-Keyword Bonus ───

(defun sr--exclusive-keyword-bonus (task-text skill-dir)
  "Bonus for skills whose directory name contains unique identity words.
Only scores when the word is RARE across all skill directories.
E.g., 'clojure' appears only in clojure-expert → full bonus.
'research' appears in researcher-prompt AND research-digest → reduced bonus.
Returns 0.0-0.5 bonus."
  (let* ((dir-name (downcase (or skill-dir "")))
         (task-lower (downcase task-text))
         (words (split-string dir-name "-" t))
         (bonus 0.0))
    (dolist (word words bonus)
      (when (and (> (length word) 2)
                 (string-match-p (regexp-quote word) task-lower))
        ;; Count how many OTHER skill dirs contain this word
        (let ((others 0))
          (dolist (entry sr--skill-index)
            (let ((other-dir (downcase (car entry))))
              (when (and (not (string= other-dir dir-name))
                         (string-match-p (regexp-quote word) other-dir))
                 (setq others (1+ others)))))
          ;; Bonus inversely proportional to how many other skills share this word
          ;; +0.4 if exclusive, +0.2 if shared with 1 other, +0.1 if shared with 2+
          (setq bonus (+ bonus (cond ((= others 0) 0.4)
                                     ((= others 1) 0.2)
                                     (t 0.1)))))))))

;; ─── Identity Keyword Boost ───

(defconst sr--identity-keywords
  '(("clojure-expert" . ("clojure" "deps.edn" "namespace" "macro expansion"))
    ("elisp-debug" . ("debug" "infinite loop" "segfault" "timer"))
    ("elisp-discover" . ("find usages" "deprecated" "discover"))
    ("elisp-validator" . ("byte-compil" "warning" "format" "validate"))
    ("elisp-refactor" . ("refactor" "cl-lib"))
    ("elisp-replace" . ("replace" "transient" "interactive"))
    ("benchmark-llm-prompts" . ("benchmark" "evaluate" "structured output" "llm"))
    ("evolution-patterns" . ("experiment" "outcomes" "discarded" "evolution"))
    ("research-digest" . ("digest" "findings"))
    ("strategy-proposer" . ("strategy" "propos" "gap"))
    ("agent-prompts" . ("prompt" "system prompt" "code-review"))
    ("sandbox-profiles" . ("sandbox" "restrict" "permission" "audit" "least-privilege"))
    ("reddit" . ("reddit" "post" "monitor"))
    ("auto-workflow" . ("pipeline" "workflow" "stage")))
  "Task keywords that strongly indicate a specific skill.
Format: (skill-dir . (keyword...)).")

(defun sr--identity-keyword-boost (task-text skill-dir)
  "Strong boost when TASK-TEXT contains identity keywords for SKILL-DIR.
Returns 0.0-1.5 boost."
  (let* ((task-lower (downcase task-text))
         (keywords (cdr (assoc skill-dir sr--identity-keywords)))
         (boost 0.0))
    (dolist (kw keywords)
      (when (string-match-p (regexp-quote kw) task-lower)
        (setq boost (+ boost 0.5))))
    (min boost 1.5)))

;; ─── Adaptive Scoring (ported from ontology-router:218-550) ───

(defvar sr--outcome-table (make-hash-table :test 'equal)
  "Hash table: skill-dir → (success-count . total-count) for outcome tracking.")

(defvar sr--holographic-memory (make-hash-table :test 'equal)
  "Hash table: (skill . task-category) → (success-fraction . total-attempts).

Records which skills work well for which task categories.
Used for holographic boost — analogous to ontology-router:2353-2403.")

(defun sr--record-outcome (skill-dir task-text success-p)
  "Record whether skill selection was successful.
Analogous to ontology-router `record-holographic-experiment` for backends."
  (let* ((category (sr--categorize-task task-text))
         (key (cons skill-dir category))
         (current (gethash skill-dir sr--outcome-table '(0 . 0)))
         (success (car current))
         (total (cdr current)))
    ;; Update outcome table
    (puthash skill-dir (cons (if success-p (1+ success) success) (1+ total))
             sr--outcome-table)
    ;; Update holographic memory
    (let ((hcurrent (gethash key sr--holographic-memory '(0 . 0))))
      (puthash key (cons (if success-p (1+ (car hcurrent)) (car hcurrent))
                         (1+ (cdr hcurrent)))
               sr--holographic-memory))))

(defun sr--skill-keep-rate (skill-dir)
  "Return keep-rate (success/total) for SKILL-DIR, or 0.25 if <3 attempts.
Bayesian smoothing prevents cold-start problem. Ported from ontology-router:511-519."
  (let* ((stats (gethash skill-dir sr--outcome-table '(0 . 0)))
         (success (car stats))
         (total (cdr stats)))
    (if (< total 3) 0.25          ; Bayesian floor for cold-start
      (/ (float success) total))))

(defun sr--skill-trend (skill-dir)
  "Compute trend: recent vs overall keep-rate.
Recent = last 5 attempts. Overall = all time.
Positive = improving. Ported from ontology-router:532-535."
  ;; Simplified: use overall rate as trend indicator, since we don't
  ;; have per-experiment timestamps yet. High keep-rate → positive trend.
  (let ((rate (sr--skill-keep-rate skill-dir)))
    (- rate 0.25)))               ; 0.25 is random baseline

(defun sr--skill-confidence (skill-dir)
  "Confidence in skill's keep-rate estimate.
More experiments → higher confidence. Ported from ontology-router:536-539."
  (let* ((stats (gethash skill-dir sr--outcome-table '(0 . 0)))
         (total (cdr stats)))
    (min 1.0 (/ total 10.0))))    ; caps at 10 experiments

(defun sr--holographic-boost (skill-dir task-text)
  "Boost skill if it historically performs well for this task category.
Ported from ontology-router `apply-holographic-boost`:2448-2468."
  (let* ((category (sr--categorize-task task-text))
         (key (cons skill-dir category))
         (stats (gethash key sr--holographic-memory nil)))
    (if stats
        (let* ((success (car stats))
               (total (cdr stats))
               (rate (if (> total 0) (/ (float success) total) 0.0)))
          (if (and (> total 2) (> rate 0.5))
              (* rate 0.15)       ; up to +0.15 boost
            0.0))
      0.0)))

(defconst sr-adaptive-weights
  '((:keep-rate . 0.30)      ;; rate analog — how often this skill succeeds
    (:trend . 0.15)           ;; trend analog — is it improving?
    (:confidence . 0.05)      ;; confidence analog — how much data do we have?
    (:holographic . 0.10))    ;; cross-skill pattern boost
  "Weights for adaptive scoring dimensions (sums to 0.60).
These are added to the base 4-dim score (which sums to 1.0) so total
score range is 0.0-1.6. Higher = more weight on learned behavior.")

(defun sr--score-adaptive (skill-dir task-text)
  "Compute adaptive score for SKILL-DIR based on historical outcomes.
Returns added score 0.0-0.6 (weighted sum of adaptive dimensions)."
  (+ (* (sr--skill-keep-rate skill-dir)
        (cdr (assq :keep-rate sr-adaptive-weights)))
     (* (sr--skill-trend skill-dir)
        (cdr (assq :trend sr-adaptive-weights)))
     (* (sr--skill-confidence skill-dir)
        (cdr (assq :confidence sr-adaptive-weights)))
     (sr--holographic-boost skill-dir task-text)))

;; ─── Updated Scoring with Adaptive Dimensions ───

(defun sr--score-skill (task-text task-category skill-entry)
  "Compute multi-dimensional score for SKILL-ENTRY against TASK-TEXT.
Returns score 0.0-1.6 (1.0 base + 0.6 adaptive)."
  (let* ((skill-dir (car skill-entry))
         (skill-data (cdr skill-entry))
         (skill-category (car skill-data))
         (skill-content (cdr skill-data))
         (health (sr--skill-health skill-dir skill-content))
         (healthy (car health))
         (health-penalty (cdr health))
         (base-score
          (+ (* (sr--score-task-overlap task-text skill-content)
                (cdr (assq :task-overlap sr-dim-weights)))
             (* (sr--score-category-fit task-category skill-category)
                (cdr (assq :category-fit sr-dim-weights)))
             (* (sr--score-keyword-depth task-text skill-content)
                (cdr (assq :keyword-depth sr-dim-weights)))
             (* (sr--exclusive-keyword-bonus task-text skill-dir)
                (cdr (assq :exclusive-match sr-dim-weights)))))
         (identity-boost (sr--identity-keyword-boost task-text skill-dir))
         (adaptive-score (sr--score-adaptive skill-dir task-text)))
    ;; Apply health penalty: quarantined skills drop by 50%, stale by 20%
    (let ((raw-score (+ base-score adaptive-score identity-boost)))
      (if healthy
          raw-score
        (* raw-score (- 1.0 health-penalty))))))


;; ─── Selection with Exploration ───

(defvar sr--exploration-rate 0.15
  "Probability of selecting a non-best skill (epsilon-greedy).")

(defvar sr--embedding-fallback-threshold 0.15
  "Min margin between top-1 and top-2 scores. When margin is below this,
the n-gram fallback is activated. Higher = more fallback (safer, slower).")

(defun sr--ngrams (text n)
  "Generate N-grams of length N from TEXT. Returns a hash table of ngram→count."
  (let ((ngrams (make-hash-table :test 'equal))
        (lower (downcase text))
        (i 0))
    (while (<= (+ i n) (length lower))
      (let ((ngram (substring lower i (+ i n))))
        (puthash ngram (1+ (gethash ngram ngrams 0)) ngrams)
        (setq i (1+ i))))
    ngrams))

(defun sr--ngram-similarity (text-a text-b)
  "Compute n-gram overlap similarity between TEXT-A and TEXT-B.
Uses 3-grams (trigrams). Returns 0.0-1.0. Simple embedding approximation."
  (let* ((a-grams (sr--ngrams text-a 3))
         (b-grams (sr--ngrams text-b 3))
         (intersection 0) (union 0))
    (maphash (lambda (k _) (when (gethash k b-grams) (setq intersection (1+ intersection)))) a-grams)
    (maphash (lambda (k v) (setq union (+ union v))) a-grams)
    (maphash (lambda (k v) (setq union (+ union v))) b-grams)
    (if (> union 0) (/ (float (* 2 intersection)) union) 0.0)))

(defun sr--embedding-fallback (task-text top-n)
  "Re-rank top-N candidates using n-gram similarity.
When the 8-dim scorer is uncertain (tight margins), use trigram overlap
as a cheap embedding approximation to break ties.
Returns reordered list of (skill-dir . score)."
  (let ((scored nil))
    (dolist (entry top-n)
      (let* ((dir (car entry))
             (entry-data (assoc dir sr--skill-index))
             (skill-content (if entry-data (cddr entry-data) ""))
             (sim (sr--ngram-similarity task-text skill-content)))
        (push (cons dir sim) scored)))
    (sort scored (lambda (a b) (> (cdr a) (cdr b))))))

(defun sr--select-skill (task-text)
  "Select best skill for TASK-TEXT using ontology-driven scoring.
When the margin between top-1 and top-2 is below the threshold,
fall back to n-gram similarity (cheap embedding approximation).
Returns (skill-dir . score) or nil if no skills available."
  (unless sr--skill-index (sr--build-index))
  (let* ((task-category (sr--categorize-task task-text))
         (scored (mapcar (lambda (entry)
                            (cons (car entry)
                                  (sr--score-skill task-text task-category entry)))
                          sr--skill-index))
         (sorted (sort scored (lambda (a b) (> (cdr a) (cdr b)))))
         (best (car sorted))
         (second (nth 1 sorted))
         (margin (if (and best second) (- (cdr best) (cdr second)) 1.0))
         (low-confidence (< margin sr--embedding-fallback-threshold)))
    ;; Low confidence → n-gram fallback for top candidates
    (if (and low-confidence second)
        (let* ((top-n (seq-take sorted (min 5 (length sorted))))
               (reranked (sr--embedding-fallback task-text top-n))
               (fallback-best (car reranked)))
          (when (bound-and-true-p gptel-log-level)
            (message "[embed-fallback] margin=%.3f < %.2f, n-gram fallback: %s→%s"
                     margin sr--embedding-fallback-threshold
                     (car best) (car fallback-best)))
          fallback-best)
      ;; High enough confidence — use 8-dim score directly
      (if (and best (< (random 100) (* sr--exploration-rate 100))
               second)
          (let ((pick (nth (1+ (random (min 2 (1- (length sorted))))) sorted)))
            (cons (car pick) (cdr pick)))
        (cons (car best) (cdr best))))))

(provide 'skill-routing-onto)
;;; skill-routing-onto.el ends here
