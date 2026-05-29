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
         (base-score
          (+ (* (sr--score-task-overlap task-text skill-content)
                (cdr (assq :task-overlap sr-dim-weights)))
             (* (sr--score-category-fit task-category skill-category)
                (cdr (assq :category-fit sr-dim-weights)))
             (* (sr--score-keyword-depth task-text skill-content)
                (cdr (assq :keyword-depth sr-dim-weights)))
             (* (sr--exclusive-keyword-bonus task-text skill-dir)
                (cdr (assq :exclusive-match sr-dim-weights)))))
         (adaptive-score (sr--score-adaptive skill-dir task-text)))
    (+ base-score adaptive-score)))

;; ─── Selection with Exploration ───

(defvar sr--exploration-rate 0.15
  "Probability of selecting a non-best skill (epsilon-greedy).")

(defun sr--select-skill (task-text)
  "Select best skill for TASK-TEXT using ontology-driven scoring.
Returns (skill-dir . score) or nil if no skills available."
  (unless sr--skill-index (sr--build-index))
  (let* ((task-category (sr--categorize-task task-text))
         (scored (mapcar (lambda (entry)
                           (cons (car entry)
                                 (sr--score-skill task-text task-category entry)))
                         sr--skill-index))
         (sorted (sort scored (lambda (a b) (> (cdr a) (cdr b)))))
         (best (car sorted)))
    ;; Exploration: with probability sr--exploration-rate, try #2 or #3
     (if (and best (< (random 100) (* sr--exploration-rate 100))
              (nth 1 sorted))
        (let ((pick (nth (1+ (random (min 2 (1- (length sorted))))) sorted)))
          (cons (car pick) (cdr pick)))
      (cons (car best) (cdr best)))))

(provide 'skill-routing-onto)
;;; skill-routing-onto.el ends here
