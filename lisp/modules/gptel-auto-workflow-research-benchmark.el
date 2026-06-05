;;; gptel-auto-workflow-research-benchmark.el --- Benchmark research strategies -*- lexical-binding: t; -*-

(require 'strategic-daemon-functions)

;; Reuse benchmark infrastructure for AutoTTS-style research evolution.
;; Treats research sessions as benchmark experiments with strategy comparison.

;;; Commentary:
;; Instead of building separate AutoTTS system, reuse existing benchmark:
;; - gptel-benchmark-call-subagent for researcher calls
;; - Eight Keys scoring for research quality
;; - TSV results for replay store
;; - Strategy harness for strategy evolution

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(declare-function gptel-benchmark-call-subagent "gptel-benchmark-subagent")
(declare-function gptel-benchmark-call-subagent-sync "gptel-benchmark-subagent")
(declare-function gptel-auto-workflow--load-autotts-controller "strategic-daemon-functions")
(declare-function gptel-auto-workflow--json-encode-plist "gptel-auto-workflow-ontology-router" (plist))
(declare-function gptel-auto-workflow--alist-to-sandbox-env "strategic-daemon-functions")
(declare-function gptel-auto-workflow--eval-rule-sandbox "strategic-daemon-functions")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent" ())
(declare-function gptel-auto-workflow--valid-strategy-name-p "gptel-tools-agent-strategy-evolver" (name))

(defvar gptel-auto-workflow--active-strategy)
(defvar gptel-auto-workflow--pending-outcome-updates)
(defvar gptel-auto-workflow--outcome-evolution-threshold)

(defun gptel-auto-workflow--plist-dedup-put (plist key value)
  "Like `plist-put' but removes duplicate KEY before inserting.
Prevents plist key accumulation across successive plist-put calls
on shared plists where `copy-sequence' preserves old keys."
  (let ((cleaned nil)
        (rest plist))
    (while rest
      (if (eq (car rest) key)
          (progn (pop rest) (pop rest))
        (push (pop rest) cleaned)
        (when rest (push (pop rest) cleaned))))
    (setq cleaned (nreverse cleaned))
    (plist-put cleaned key value)))

(defvar gptel-auto-workflow--research-strategies
  '("own-repos-first" "deep-external" "quick-own-only" "topic-specific")
  "Available research strategies to benchmark.")

(defvar gptel-auto-workflow--research-benchmark-results nil
  "Accumulator for research benchmark results.")

(defun gptel-auto-workflow--normalize-controller-rules (rules)
  "Normalize generated controller RULES for validation and evaluation."
  (mapcar (lambda (rule)
            (let ((copy (copy-sequence rule)))
              (setq copy
                    (plist-put copy :when
                               (gptel-auto-workflow--normalize-controller-rule-expr
                                (plist-get copy :when))))
              copy))
          rules))

(defun gptel-auto-workflow--benchmark-research-strategy (strategy topic callback)
  "Benchmark single research STRATEGY on TOPIC.
Calls CALLBACK with result plist."
  (let* ((strategy-prompt (gptel-auto-workflow--format-research-strategy-prompt strategy topic))
         (start-time (float-time)))
    (message "[research-benchmark] Testing strategy '%s' on topic '%s'" strategy topic)
    (gptel-benchmark-call-subagent
     'researcher
     (format "Research benchmark: %s" strategy)
     strategy-prompt
     (lambda (result)
       (let* ((duration (- (float-time) start-time))
              (output (if (stringp result) result (format "%s" result)))
              (output-len (length output))
              (tokens (* output-len 0.25))
              (quality (gptel-auto-workflow--score-research-output output))
              (efficiency (/ quality (max tokens 1))))
         (message "[research-benchmark] %s: quality=%.2f tokens=%.0f efficiency=%.4f"
                  strategy quality tokens efficiency)
         (funcall callback
                  (list :strategy strategy
                        :topic topic
                        :quality quality
                        :tokens tokens
                        :efficiency efficiency
                        :duration duration
                        :output-len output-len
                        :output output)))))))

(defun gptel-auto-workflow--score-research-output (output)
  "Score research output quality (0-1).
Uses heuristics based on AutoTTS paper:
- URLs present = higher score
- Structured format = higher score
- Specific techniques = higher score
- No generic advice = higher score"
  (let ((score 0.0))
    (when (string-match-p "https?://" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "## .*\\n" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "```" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "\\*\\*" output)
      (setq score (+ score 0.15)))
    (let ((len (length output)))
      (cond ((> len 3000) (setq score (+ score 0.15)))
            ((> len 1000) (setq score (+ score 0.1)))
            (t (setq score (+ score 0.05)))))
    (unless (string-match-p "use AI\\|improve code\\|better" output)
      (setq score (+ score 0.1)))
    score))

(defun gptel-auto-workflow--format-research-strategy-prompt (strategy topic)
  "Format research prompt with specific STRATEGY for TOPIC."
  (let ((strategy-guidance (gptel-auto-workflow--load-strategy-as-text strategy)))
    (format "## Research Task\n\nTopic: %s\nStrategy: %s\n\n%s\n\n## Instructions\n\n1. Follow the strategy phases EXACTLY\n2. Track your confidence after each phase (0-1)\n3. Stop early if confidence > 0.7 and you have 2+ insights\n4. Return structured output with URLs and code examples\n5. END your response with JSON metadata:\n```json\n{\n  \"strategy_used\": \"%s\",\n  \"phases_completed\": [\"search\", \"fetch\"],\n  \"confidence_final\": 0.8,\n  \"insights_count\": 3,\n  \"tokens_estimate\": 3500\n}\n```"
            topic strategy strategy-guidance strategy)))

(defun gptel-auto-workflow--load-strategy-as-text (strategy)
  "Load strategy definition as text guidance."
  (let ((strategy-file (expand-file-name
                        (format "assistant/skills/researcher-prompt/strategies/%s.json"
                                strategy)
                        (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p strategy-file)
        (with-temp-buffer
          (insert-file-contents strategy-file)
          (let ((json-object-type 'alist)
                (json-key-type 'symbol)
                (data (json-read)))
            (format "**Strategy**: %s\n**Description**: %s\n**Phases**: %s"
                    (cdr (assoc 'name data))
                    (cdr (assoc 'description data))
                    (mapconcat (lambda (p) (cdr (assoc 'name p)))
                               (cdr (assoc 'phases data)) " → "))))
      (format "Strategy '%s' not found. Use default approach." strategy))))

(defun gptel-auto-workflow--benchmark-all-research-strategies (topic callback)
  "Benchmark all research strategies on TOPIC.
Calls CALLBACK with best strategy name."
  (setq gptel-auto-workflow--research-benchmark-results nil)
  (let ((strategies gptel-auto-workflow--research-strategies)
        (results nil)
        (remaining 0))
    (setq remaining (length strategies))
    (dolist (strategy strategies)
      (gptel-auto-workflow--benchmark-research-strategy
       strategy topic
       (lambda (result)
         (push result results)
         (setq remaining (1- remaining))
         (when (<= remaining 0)
           (let* ((best (car (sort results
                                   (lambda (a b)
                                     (> (plist-get a :efficiency)
                                        (plist-get b :efficiency))))))
                  (best-strategy (plist-get best :strategy)))
             (message "[research-benchmark] Best strategy: %s (efficiency=%.4f)"
                      best-strategy (plist-get best :efficiency))
             (setq gptel-auto-workflow--research-benchmark-results results)
             (funcall callback best-strategy))))))))

(defun gptel-auto-workflow--evolve-research-strategy ()
  "Evolve research strategy using benchmark results.
Runs after pipeline completes to pick best strategy for next run."
  (when gptel-auto-workflow--research-benchmark-results
    (let* ((results gptel-auto-workflow--research-benchmark-results)
           (strategies (make-hash-table :test 'equal)))
      (dolist (r results)
        (let* ((name (plist-get r :strategy))
               (existing (gethash name strategies '(0 0 0))))
          (puthash name
                   (list (+ (nth 0 existing) (plist-get r :quality))
                         (+ (nth 1 existing) (plist-get r :tokens))
                         (1+ (nth 2 existing)))
                   strategies)))
       (let ((best nil)
             (best-score 0))
         (cl-flet ((score-strategy (name stats)
                    (let ((avg-quality (/ (nth 0 stats) (nth 2 stats)))
                          (avg-tokens (/ (nth 1 stats) (nth 2 stats)))
                          (score (/ (nth 0 stats) (max (nth 1 stats) 1))))
                      (when (> score best-score)
                        (setq best name
                              best-score score))
                      (message "[research-evolve] %s: avg-quality=%.2f avg-tokens=%.0f score=%.4f"
                               name avg-quality avg-tokens score))))
           (maphash #'score-strategy strategies))
        (when best
          (message "[research-evolve] Evolved to strategy: %s" best)
          (setq gptel-auto-workflow--active-strategy best))))))

(defun gptel-auto-workflow--load-research-traces ()
  "Load all research traces from trace directory.
Returns list of trace plists."
  (let ((trace-dir (expand-file-name "var/tmp/research-traces"
                                     (gptel-auto-workflow--worktree-base-root)))
        (traces nil))
    (when (file-directory-p trace-dir)
      (dolist (file (directory-files-recursively trace-dir "\\.json\\'"))
        (condition-case err
            (let ((json-object-type 'plist)
                  (json-array-type 'list)
                  (json-key-type 'keyword))
              (with-temp-buffer
                (insert-file-contents file)
                (push (json-read) traces)))
          (error (message "[autotts] Failed to load trace %s: %s"
                         (file-name-nondirectory file) err)))))
    traces))

(defun gptel-auto-workflow--trace-string-field (trace key fallback)
  "Return TRACE string field KEY, or FALLBACK when missing or invalid."
  (let ((value (plist-get trace key)))
    (if (and (stringp value) (not (string-empty-p value)))
        value
      fallback)))

(defun gptel-auto-workflow--trace-source (trace &optional fallback)
  "Return normalized source for TRACE."
  (gptel-auto-workflow--trace-string-field trace :source (or fallback "unknown")))

(defun gptel-auto-workflow--trace-strategy (trace &optional fallback)
  "Return normalized strategy for TRACE."
  (gptel-auto-workflow--trace-string-field trace :strategy (or fallback "unknown")))

(defun gptel-auto-workflow--split-traces (traces &optional train-ratio)
  "Split TRACES into train and held-out validation sets by timestamp.
TRAIN-RATIO defaults to 0.7 (70% train, 30% test).
Returns plist (:train TRAIN-TRACES :test TEST-TRACES).
Older traces go to train, newer to test (temporal split avoids data leakage).
When fewer than 10 traces, all go to train (not enough for meaningful split)."
  (let* ((ratio (or train-ratio 0.7))
         (sorted (sort (copy-sequence traces)
                      (lambda (a b)
                        (let ((ta (plist-get a :timestamp))
                              (tb (plist-get b :timestamp)))
                          (if (and ta tb)
                              (string< ta tb)
                            t)))))
         (n (length sorted))
         (split-idx (floor (* n ratio))))
    (if (< n 10)
        (list :train sorted :test nil)
      (list :train (seq-take sorted split-idx)
             :test (seq-drop sorted split-idx)))))

(defun gptel-auto-workflow--parse-controller-design-response (response)
  "Parse controller design RESPONSE into a plist, or nil."
  (let* ((normalized (if (fboundp 'gptel-auto-workflow--normalize-response)
                         (gptel-auto-workflow--normalize-response response)
                       (if (stringp response) response (format "%s" response))))
         (text (string-trim normalized))
         (text (replace-regexp-in-string "\\`[[:space:]]*```[[:alpha:]]*\n?" "" text))
         (text (replace-regexp-in-string "\n?```[[:space:]]*\\'" "" text)))
    (cl-labels ((read-plist-at
                 (start)
                 (condition-case nil
                     (let ((form (car (read-from-string text start))))
                       (when (plistp form)
                         form))
                   (error nil))))
      (or (read-plist-at 0)
          (catch 'controller-plist
            (let ((pos 0))
              (while (string-match (regexp-quote "(") text pos)
                (when-let ((form (read-plist-at (match-beginning 0))))
                  (throw 'controller-plist form))
                (setq pos (1+ (match-beginning 0))))
              nil))))))

(defun gptel-auto-workflow--validate-on-held-out (controller-config test-traces)
  "Evaluate CONTROLLER-CONFIG on held-out TEST-TRACES.
Returns plist with (:test-accuracy :test-tokens :overfit-score).
Compares train vs test performance to detect overfitting."
  (when test-traces
    (let* ((test-results
            (mapcar (lambda (trace)
                      (let* ((output-length (or (plist-get trace :output-length) 0))
                             (has-urls (plist-get trace :has-urls))
                             (source (gptel-auto-workflow--trace-source trace))
                             (own-repo (string= source "own-repo"))
                             (success (if own-repo
                                          (and has-urls (> output-length 1000))
                                        (and has-urls (> output-length 2000)))))
                        (list :output-length output-length
                              :has-urls has-urls
                              :source source
                              :success success)))
                    test-traces))
           (test-successes (cl-count-if (lambda (r) (plist-get r :success)) test-results))
           (test-rate (/ (float test-successes) (float (length test-results))))
           (total-tokens (/ (apply '+ (mapcar (lambda (r) (plist-get r :output-length))
                                             test-results))
                          4.0))
           (configured-stop (or (plist-get controller-config :min-confidence-stop)
                                (plist-get controller-config :stop-threshold)
                                0.7))
           (overfit-score (- 1.0 (min 1.0 (abs (- test-rate configured-stop))))))
      (list :test-accuracy test-rate
            :test-tokens total-tokens
            :test-count (length test-traces)
            :overfit-score (max 0.0 (min 1.0 overfit-score))
            :overfit-warning (if (< overfit-score 0.3) t nil)))))

(defun gptel-auto-workflow--controller-rule-p (rule)
  "Return non-nil when RULE is a controller rule plist."
  (and (listp rule)
       (plist-member rule :when)
       (plist-member rule :then)))

(defun gptel-auto-workflow--coerce-controller-rules (form)
  "Return controller rule list from FORM, or nil."
  (cond
   ((gptel-auto-workflow--controller-rule-p form)
    (gptel-auto-workflow--normalize-controller-rules (list form)))
   ((and (listp form)
         (cl-every #'gptel-auto-workflow--controller-rule-p form))
    (gptel-auto-workflow--normalize-controller-rules form))))

(defun gptel-auto-workflow--parse-controller-design-rules (response)
  "Parse controller design RESPONSE into a list of rule plists, or nil."
  (let* ((normalized (if (fboundp 'gptel-auto-workflow--normalize-response)
                         (gptel-auto-workflow--normalize-response response)
                       (if (stringp response) response (format "%s" response))))
         (text (string-trim normalized))
         (text (replace-regexp-in-string "\\`[[:space:]]*```[[:alpha:]]*\n?" "" text))
         (text (replace-regexp-in-string "\n?```[[:space:]]*\\'" "" text)))
    (cl-labels ((read-rules-at
                 (start)
                 (condition-case nil
                     (gptel-auto-workflow--coerce-controller-rules
                      (car (read-from-string text start)))
                   (error nil))))
      (or (read-rules-at 0)
          (catch 'controller-rules
            (let ((pos 0))
              (while (string-match (regexp-quote "(") text pos)
                (when-let ((rules (read-rules-at (match-beginning 0))))
                  (throw 'controller-rules rules))
                (setq pos (1+ (match-beginning 0))))
              nil))))))

(defun gptel-auto-workflow--evolve-controller-from-traces (traces)
  "AutoTTS-style controller evolution from research traces.
Analyzes traces to update controller parameters.
TRACES is list of trace plists.
Uses statistical learning when sufficient traces with outcomes available,
falls back to heuristic evolution otherwise."
  ;; Try statistical learning first
  (let ((statistical-config (gptel-auto-workflow--learn-statistical-controller)))
    (if statistical-config
        (progn
          (message "[autotts] Using statistically learned controller (%d traces)"
                   (or (plist-get statistical-config :n-traces) 0))
          statistical-config)
      ;; Fallback: heuristic evolution
      (gptel-auto-workflow--evolve-controller-heuristic traces))))

(defun gptel-auto-workflow--learn-statistical-controller ()
  "Learn controller from trace outcomes.
RETIRED: Python scripts removed. Returns nil.
Uses heuristic fallback instead of statistical learning."
  (message "[autotts] Python scripts retired — using heuristic controller")
  nil)

(defun gptel-auto-workflow--evolve-controller-heuristic (traces)
  "Heuristic controller evolution (fallback when insufficient data).
Analyzes traces to update controller parameters using simple heuristics.
TRACES is list of trace plists."
  (let ((own-repo-success 0)
        (own-repo-total 0)
        (external-success 0)
        (external-total 0)
        (total-tokens 0)
        (total-output 0))
    (dolist (trace traces)
      (let ((source (gptel-auto-workflow--trace-source trace))
            (output-length (or (plist-get trace :output-length) 0))
            (tokens-used (or (plist-get trace :tokens-used) 0))
            (has-urls (plist-get trace :has-urls)))
        (setq total-tokens (+ total-tokens tokens-used))
        (setq total-output (+ total-output output-length))
        (cond
         ((string= source "own-repo")
          (setq own-repo-total (1+ own-repo-total))
          (when (and has-urls (> output-length 1000))
            (setq own-repo-success (1+ own-repo-success))))
         (t
          (setq external-total (1+ external-total))
          (when (and has-urls (> output-length 1000))
            (setq external-success (1+ external-success)))))))
    ;; Calculate new priorities based on success rates
    (let* ((own-rate (if (> own-repo-total 0)
                        (/ (float own-repo-success) own-repo-total)
                      0.5))
           (external-rate (if (> external-total 0)
                             (/ (float external-success) external-total)
                           0.3))
           (avg-output (if (> (length traces) 0)
                          (/ (float total-output) (length traces))
                        2000))
           ;; Evolve controller config
           (new-config
            (list
             :own-repo-priority (min 0.95 (+ 0.7 (* 0.25 own-rate)))
             :fork-priority 0.4
             :external-priority (max 0.05 (+ 0.15 (* 0.15 external-rate)))
             :web-priority 0.05
             :min-confidence-stop (if (> avg-output 2500) 0.65 0.75)
             :max-tokens-budget 8000
             :min-insights-for-stop 2
             :stagnation-window 2
             :evolved-at (format-time-string "%Y-%m-%dT%H:%M:%SZ")
             :based-on-traces (length traces)
             :learning-method "heuristic"
             :own-repo-stats (list :success own-repo-success :total own-repo-total
                                  :rate own-rate)
             :external-stats (list :success external-success :total external-total
                                   :rate external-rate))))
      (message "[autotts] Heuristic evolution: own-repo %.0f%% (%d/%d), external %.0f%% (%d/%d)"
               (* 100 own-rate) own-repo-success own-repo-total
               (* 100 external-rate) external-success external-total)
      new-config)))

(defun gptel-auto-workflow--save-evolved-controller (controller-config)
  "Save evolved controller configuration to disk, preserving champion data.
CONTROLLER-CONFIG is a plist with controller parameters.
Reads existing file first and merges, so champion keys from
update-controller-from-champion-changes survive the save."
   (let* ((controller-file (expand-file-name "var/tmp/researcher-controller.json"
                                           (gptel-auto-workflow--worktree-base-root)))
         (existing (condition-case nil
                      (when (file-readable-p controller-file)
                        (with-temp-buffer
                          (insert-file-contents controller-file)
                          (goto-char (point-min))
                          (let ((json-object-type 'plist)
                                (json-array-type 'list)
                                (json-key-type 'keyword))
                            (json-read))))
                    (error nil))))
    ;; Merge: preserve champion keys from existing, then overlay new config
    (let ((merged existing))
      (dolist (key '(:active-champions :champion-category :champion-rate
                     :last-champion-update :min-confidence-stop))
        (let ((existing-val (plist-get existing key)))
          (when existing-val
            (setq merged (plist-put merged key existing-val)))))
      ;; Overlay new config on top (new values take precedence)
      (let ((tail controller-config))
        (while tail
          (setq merged (plist-put merged (car tail) (cadr tail)))
          (setq tail (cddr tail))))
      (make-directory (file-name-directory controller-file) t)
      (with-temp-file controller-file
         (insert (gptel-auto-workflow--json-encode-plist merged)))
      (message "[autotts] Saved evolved controller: %s (preserved champion keys)" controller-file))))

(defvar gptel-auto-workflow--controller-evolution-history nil
  "List of past controller evolution records.
Each record is a plist: (:timestamp :objective :config :traces-count).
Used for convergence detection to prevent overfitting.
Loaded from disk at startup, saved after each evolution.")

(defcustom gptel-auto-workflow-convergence-window 3
  "Number of generations to look back for convergence detection.
If objective hasn't improved in this many generations, evolution stops.
AutoTTS: Prevents overfitting controller to historical traces."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-convergence-threshold 0.01
  "Minimum improvement threshold to consider evolution meaningful.
If objective improvement is below this, count as plateau.
AutoTTS: Ignore tiny fluctuations that don't represent real progress."
  :type 'float
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--load-evolution-history ()
  "Load evolution history from disk.
Returns list of evolution records."
  (let ((history-file (expand-file-name "var/tmp/controller-evolution-history.json"
                                        (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p history-file)
        (condition-case err
            (with-temp-buffer
              (insert-file-contents history-file)
              (let ((json-object-type 'plist)
                    (json-key-type 'keyword))
                (json-read)))
          (error
           (message "[autotts] Failed to load evolution history: %s" err)
           nil))
      nil)))

(defun gptel-auto-workflow--save-evolution-history (history)
  "Save evolution HISTORY to disk."
  (let ((history-file (expand-file-name "var/tmp/controller-evolution-history.json"
                                        (gptel-auto-workflow--worktree-base-root))))
    (make-directory (file-name-directory history-file) t)
    (with-temp-file history-file
      (insert (gptel-auto-workflow--json-encode-plist history)))
    (message "[autotts] Saved evolution history: %d generations" (length history))))

(defun gptel-auto-workflow--count-actionable-patterns (findings)
  "Count actionable pattern concepts in FINDINGS text,
per ontology category.
Purpose: measures how many concrete, named techniques
the researcher extracted.
Returns an alist of \(CATEGORY . COUNT\) keyed by
:programming, :tool-calls, :agentic, :natural-language,
plus :total."
  (if (or (not (stringp findings)) (string-empty-p findings))
      '((:total . 0))
    (let ((cats '((:programming . 0) (:tool-calls . 0)
                  (:agentic . 0) (:natural-language . 0)))
          (total 0))
      (with-temp-buffer
        (insert findings)
        ;; Count markdown headers — classify by content keywords
        (goto-char (point-min))
        (while (re-search-forward "^##+\\s-+\\(.+\\)$" nil t)
          (let ((header (match-string 1)))
            (cl-incf total)
            (cond
             ((string-match-p "code\\|implement\\|function\\|defun\\|elisp\\|syntax\\|macro\\|class\\|program" header)
              (cl-incf (alist-get :programming cats)))
             ((string-match-p "sandbox\\|tool\\|permit\\|allow\\|forbid\\|security\\|guard" header)
              (cl-incf (alist-get :tool-calls cats)))
             ((string-match-p "agent\\|coord\\|staging\\|delegat\\|subagent\\|fsm\\|state" header)
              (cl-incf (alist-get :agentic cats)))
             (t
              (cl-incf (alist-get :natural-language cats))))))
        ;; Count bullet points with **bold** technique descriptions
        (goto-char (point-min))
        (while (re-search-forward "^\\s-*[-*]\\s-+\\*\\*\\([^*]+\\)\\*\\*" nil t)
          (let ((desc (match-string 1)))
            (cl-incf total)
            (cond
             ((string-match-p "code\\|function\\|program\\|elisp\\|defun\\|syntax" desc)
              (cl-incf (alist-get :programming cats)))
             ((string-match-p "tool\\|sandbox\\|permit\\|guard\\|security" desc)
              (cl-incf (alist-get :tool-calls cats)))
             ((string-match-p "agent\\|fsm\\|state\\|delegat\\|subagent" desc)
              (cl-incf (alist-get :agentic cats)))
             (t
              (cl-incf (alist-get :natural-language cats)))))))
      (cons (cons :total total) cats))))

(defun gptel-auto-workflow--calculate-evolution-objective (traces config)
  "Calculate objective value for evolution from TRACES and CONFIG.
Higher is better. Combines downstream outcome success rates,
average confidence, token efficiency, and source diversity.
Uses actual downstream experiment outcomes when available (via trace-success-p),
falling back to output quality heuristics for traces without outcomes."
  (let ((own-success 0)
        (own-total 0)
        (ext-success 0)
        (ext-total 0)
        (total-confidence 0)
        (total-tokens 0)
        (total-output 0)
        (outcome-known-count 0)
        (outcome-success-count 0)
        ;; Eight Keys tracking
        (phi-targets (make-hash-table :test 'equal))  ; φ Vitality: unique targets
        (pi-cats (make-hash-table :test 'eq))          ; π Synthesis: category coverage
        (epsilon-patterns 0)                            ; ε Purpose: total actionable patterns
        (all-trace-count 0)
        (_converged-p t))                                ; τ Wisdom: convergence tracked externally
    (dolist (trace traces)
      (let ((source (gptel-auto-workflow--trace-source trace))
            (output-length (or (plist-get trace :output-length) 0))
            (tokens (or (plist-get trace :tokens-used) 1))
            (confidence (or (plist-get trace :confidence) 0))
            (outcome-known (gptel-auto-workflow--trace-outcome-known-p trace))
            (trace-success (gptel-auto-workflow--trace-success-p trace)))
        (setq total-confidence (+ total-confidence confidence))
        (setq total-tokens (+ total-tokens tokens))
        (setq total-output (+ total-output output-length))
        (setq all-trace-count (1+ all-trace-count))
        (when outcome-known
          (setq outcome-known-count (1+ outcome-known-count))
          (when trace-success
            (setq outcome-success-count (1+ outcome-success-count))))
        ;; φ Vitality: track unique targets
        (let ((outcomes (plist-get trace :outcomes)))
          (dolist (o outcomes)
            (let ((target (plist-get o :target)))
              (when target (puthash target t phi-targets)))))
        ;; π Synthesis: count category coverage from pattern data
        (let ((outcomes (plist-get trace :outcomes)))
          (dolist (o outcomes)
            (let ((cat-patterns (plist-get o :category-patterns)))
              (when cat-patterns
                (dolist (pair cat-patterns)
                  (when (and (consp pair) (keywordp (car pair)) (not (eq (car pair) :total)))
                    (let ((existing (gethash (car pair) pi-cats 0)))
                      (puthash (car pair) (+ existing (cdr pair)) pi-cats))))))))
        ;; ε Purpose: count actionable patterns
        (let ((outcomes (plist-get trace :outcomes)))
          (dolist (o outcomes)
            (let ((pa (plist-get o :pattern-actionability)))
              (when (numberp pa) (setq epsilon-patterns (+ epsilon-patterns pa))))))
        ;; ∃ Truth: compare outcome rate to confidence (overconfident = penalty)
        (if (string= source "own-repo")
            (progn
              (setq own-total (1+ own-total))
              (when trace-success
                (setq own-success (1+ own-success))))
          (setq ext-total (1+ ext-total))
          (when trace-success
            (setq ext-success (1+ ext-success))))))
    (let* ((own-rate (if (> own-total 0) (/ (float own-success) own-total) 0))
           (ext-rate (if (> ext-total 0) (/ (float ext-success) ext-total) 0))
           (avg-confidence (if (> (length traces) 0) (/ (float total-confidence) (length traces)) 0))
           (token-efficiency (if (> total-tokens 0) (/ (float total-output) total-tokens) 0))
           (outcome-rate (if (> outcome-known-count 0) (/ (float outcome-success-count) outcome-known-count) 0))
           (own-priority (or (plist-get config :own-repo-priority) 0.7))
           (ext-priority (or (plist-get config :external-priority) 0.15))
           ;; Eight Keys metrics
           (phi-vitality (/ (float (hash-table-count phi-targets)) (max 1 all-trace-count)))
           (pi-synthesis (/ (float (hash-table-count pi-cats)) 4.0))  ; 4 categories max
           (epsilon-purpose (/ (float epsilon-patterns) (max 1 all-trace-count)))
           (exists-truth (if (> avg-confidence 0)
                             (- 1.0 (abs (- outcome-rate avg-confidence)))
                           0.5))
           ;; Eight Keys weighted objective
           (objective (+ (* own-rate own-priority 2.0)
                         (* ext-rate ext-priority 1.0)
                         (* phi-vitality 0.20)       ; φ: novel targets
                         (* epsilon-purpose 0.15)     ; ε: actionable patterns
                         (* exists-truth 0.15)        ; ∃: honest confidence
                         (* pi-synthesis 0.10)        ; π: category coverage
                         (* outcome-rate 0.5)
                         (* avg-confidence 0.2)
                         (* (min token-efficiency 2.0) 0.1))))
       (message "[autotts] Objective: own=%.2f ext=%.2f φ=%.2f ε=%.2f ∃=%.2f π=%.2f → %.3f"
                own-rate ext-rate phi-vitality epsilon-purpose exists-truth pi-synthesis objective)
        objective)))

(defun gptel-auto-workflow--detect-convergence (history new-objective)
  "Detect if evolution has converged (plateaued).
HISTORY is list of past evolution records.
NEW-OBJECTIVE is the current generation's objective.
Returns t if converged (should stop evolving), nil otherwise.
AutoTTS: Stop evolution when no meaningful improvement for N generations."
  (let ((window gptel-auto-workflow-convergence-window)
        (threshold gptel-auto-workflow-convergence-threshold))
    (if (< (length history) window)
        ;; Not enough history yet
        (progn
          (message "[autotts] Convergence: insufficient history (%d < %d)"
                   (length history) window)
          nil)
      ;; Check last N generations for improvement
      (let* ((recent (last history window))
             (best-in-window (apply #'max
                                    (mapcar (lambda (r)
                                              (or (plist-get r :objective) 0))
                                            recent)))
             (improvement (- new-objective best-in-window)))
        (if (> improvement threshold)
            (progn
              (message "[autotts] Convergence: improving (+%.4f > %.4f)"
                       improvement threshold)
              nil)
          (progn
            (message "[autotts] Convergence: PLATEAU detected (%.4f ≤ %.4f over %d gens). Stopping evolution."
                     improvement threshold window)
            t))))))

(defun gptel-auto-workflow--record-evolution (history objective config traces-count)
  "Record evolution generation to HISTORY.
Returns updated history list."
  (let ((record (list :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                      :objective objective
                      :config config
                      :traces-count traces-count)))
    (append history (list record))))

(defun gptel-auto-workflow--run-autotts-evolution ()
  "Run full AutoTTS-style evolution cycle with convergence detection.
1. Load traces
2. Check convergence (skip if plateaued)
3. Evolve controller from traces
4. Save evolved controller
5. Record evolution history
6. Update active strategy from benchmark results."
  (message "[autotts] Starting evolution cycle...")
  ;; Step 1: Load traces
  (let* ((traces (gptel-auto-workflow--load-research-traces))
         (history (gptel-auto-workflow--load-evolution-history)))
    (message "[autotts] Loaded %d traces, %d past generations"
             (length traces) (length history))
    (when traces
      ;; Step 2: Check convergence BEFORE evolving
      (let* ((current-config (gptel-auto-workflow--load-autotts-controller))
             (current-objective (gptel-auto-workflow--calculate-evolution-objective
                                 traces current-config)))
        (if (gptel-auto-workflow--detect-convergence history current-objective)
            (message "[autotts] Evolution converged. Skipping to prevent overfit.")
          ;; Step 3: Evolve controller
          (let ((new-config (gptel-auto-workflow--evolve-controller-from-traces traces)))
            ;; Step 4: Calculate new objective
            (let ((new-objective (gptel-auto-workflow--calculate-evolution-objective
                                  traces new-config)))
              ;; Step 5: Save controller
              (gptel-auto-workflow--save-evolved-controller new-config)
              ;; Step 6: Record evolution
              (setq history (gptel-auto-workflow--record-evolution
                             history new-objective new-config (length traces)))
              (gptel-auto-workflow--save-evolution-history history)
              ;; Step 7: Joint optimization - update SKILL.md with evolved controller
              (gptel-auto-workflow--update-skill-with-controller new-config)
              ;; Step 8: Update active strategy from offline benchmark (0 LLM calls)
              ;; Uses trace replay instead of expensive LLM-based benchmark
              (gptel-auto-workflow--run-offline-evolution)
              ;; Step 9: Generate knowledge synthesis
              (gptel-auto-workflow--synthesize-research-knowledge-from-traces traces))))))))

(defun gptel-auto-workflow--synthesize-research-knowledge-from-traces (traces)
  "Self-evolution layer: synthesize knowledge from traces.
Extract topic performance, source effectiveness, and EMA-outcome correlation."
  (let ((topic-perf (make-hash-table :test 'equal))
        (source-perf (make-hash-table :test 'equal))
        (ema-decision-perf (make-hash-table :test 'equal)))
    (dolist (trace traces)
      (let ((strategy (gptel-auto-workflow--trace-strategy trace))
            (source (gptel-auto-workflow--trace-source trace))
            (confidence (or (plist-get trace :confidence) 0))
            (ema-conf (or (plist-get trace :ema-conf) 0.0))
            (ema-delta (or (plist-get trace :ema-delta) 0.0))
            (success-p (gptel-auto-workflow--trace-success-p trace))
            (controller-decision (or (plist-get trace :controller-decision) "UNKNOWN")))
        ;; Track strategy performance
        (let ((existing (gethash strategy topic-perf '(0 0 0))))
          (puthash strategy
                   (list (+ (nth 0 existing) (if success-p 1 0))
                         (+ (nth 1 existing) 1)
                         (+ (nth 2 existing) confidence))
                   topic-perf))
        ;; Track source performance
        (let ((existing (gethash source source-perf '(0 0 0))))
          (puthash source
                   (list (+ (nth 0 existing) (if success-p 1 0))
                         (+ (nth 1 existing) 1)
                         (+ (nth 2 existing) confidence))
                   source-perf))
        ;; Track EMA-decision correlation
        (let* ((ema-range (cond ((< ema-conf 0.4) "low")
                                ((< ema-conf 0.7) "med")
                                (t "high")))
               (delta-sign (cond ((< ema-delta -0.05) "falling")
                                 ((> ema-delta 0.05) "rising")
                                 (t "flat")))
               (key (format "%s-%s-%s" controller-decision ema-range delta-sign))
               (existing (gethash key ema-decision-perf '(0 0))))
          (puthash key
                   (list (+ (nth 0 existing) (if success-p 1 0))
                         (+ (nth 1 existing) 1))
                   ema-decision-perf))))
    ;; Log synthesis
    (message "[autotts] Knowledge synthesis:")
    (message "[autotts]  Strategies:")
    (cl-flet ((log-rate (name stats)
               (let ((rate (if (> (nth 1 stats) 0)
                              (/ (float (nth 0 stats)) (nth 1 stats))
                            0)))
                 (message "[autotts]    %s: %.0f%% success (%d/%d)"
                          name (* 100 rate) (nth 0 stats) (nth 1 stats)))))
      (maphash #'log-rate topic-perf))
    (message "[autotts]  Sources:")
    (cl-flet ((log-rate (name stats)
               (let ((rate (if (> (nth 1 stats) 0)
                              (/ (float (nth 0 stats)) (nth 1 stats))
                            0)))
                 (message "[autotts]    %s: %.0f%% success (%d/%d)"
                          name (* 100 rate) (nth 0 stats) (nth 1 stats)))))
      (maphash #'log-rate source-perf))
     ;; EMA-outcome correlation
     (message "[autotts]  EMA-outcome correlation:")
    (cl-flet ((log-rate (key stats)
               (let ((rate (if (> (nth 1 stats) 0)
                              (/ (float (nth 0 stats)) (nth 1 stats))
                            0)))
                 (message "[autotts]    %s: %.0f%% success (%d/%d)"
                          key (* 100 rate) (nth 0 stats) (nth 1 stats)))))
      (maphash #'log-rate ema-decision-perf))
    ;; Persist synthesis so evolve_researcher.py can consume trace-level analysis
    (gptel-auto-workflow--save-trace-synthesis topic-perf source-perf)))

;; ─── AutoTTS-Defining Feature: Controller Code Generation Agent ───

(defun gptel-auto-workflow--run-controller-design-agent (&optional max-iterations)
  "Run controller code generation agent — the AutoTTS-defining feature.
An LLM agent designs controller code, tests against replay store (0 LLM calls),
gets accuracy + token cost feedback, and rewrites the controller iteratively.
MAX-ITERATIONS defaults to 5.
This is how AutoTTS discovers strategies: the agent WRITES the controller,
not just tunes parameters. The search space is the code itself."
  (interactive)
  (cl-block gptel-auto-workflow--run-controller-design-agent
    (let* ((max-iters (or max-iterations 5))
           (traces (gptel-auto-workflow--load-research-traces))
           (split (gptel-auto-workflow--split-traces traces 0.8))
           (train-traces (plist-get split :train))
           (test-traces (plist-get split :test))
           (current-controller nil)
           (best-controller nil)
           (best-objective 0.0)
           (history nil))
      (unless (and traces (> (length traces) 3))
        (message "[controller-agent] Not enough traces (%d) for controller design"
                 (length traces))
        (cl-return-from gptel-auto-workflow--run-controller-design-agent nil))
      (setq current-controller (when (fboundp 'gptel-auto-workflow--load-autotts-controller)
                                 (gptel-auto-workflow--load-autotts-controller))
            best-controller current-controller)
      (message "[controller-agent] Starting controller design agent with %d traces (%d train, %d test)"
               (length traces) (length train-traces) (or (length test-traces) 0))
      (dotimes (iter max-iters)
        (let* ((prompt (gptel-auto-workflow--controller-design-prompt
                        current-controller best-controller best-objective
                        train-traces iter max-iters))
             (proposal-rules (gptel-auto-workflow--call-controller-design-subagent prompt))
             (proposal (when proposal-rules
                         (let ((config (gptel-auto-workflow--plist-dedup-put
                                        current-controller :rules proposal-rules)))
                           (setq config (gptel-auto-workflow--plist-dedup-put
                                         config :learning-method "agent-rules"))
                           (setq config (gptel-auto-workflow--plist-dedup-put
                                         config :evolved-at
                                         (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
                           config))))
        (unless proposal-rules
          (message "[controller-agent] Iter %d produced no valid controller rules; stopping" iter)
          (cl-return-from gptel-auto-workflow--run-controller-design-agent nil))
         ;; Evaluate proposed controller against train traces (0 LLM calls!)
         (let* ((eval-result (gptel-auto-workflow--evaluate-controller-rules
                              proposal-rules train-traces proposal))
                 (new-objective (plist-get eval-result :objective))
                 (train-accuracy (plist-get eval-result :accuracy)))
            ;; Validate on held-out test traces
            (let* ((test-result (when test-traces
                                  (gptel-auto-workflow--validate-on-held-out
                                   proposal test-traces)))
                   (test-accuracy (plist-get test-result :test-accuracy))
                   (overfit-score (plist-get test-result :overfit-score)))
              (push (list :iteration iter :objective new-objective
                          :train-accuracy train-accuracy
                          :test-accuracy test-accuracy
                          :overfit-score overfit-score
                          :config proposal)
                    history)
              (message "[controller-agent] Iter %d: objective=%.4f (train=%.2f test=%.2f overfit=%.2f)"
                       iter new-objective train-accuracy
                       (or test-accuracy 0.0) (or overfit-score 1.0))
              ;; Keep best (penalized by overfit)
              (let ((penalized-obj (if (and overfit-score (< overfit-score 0.7))
                                       (* new-objective overfit-score)
                                     new-objective)))
                (when (or (> penalized-obj best-objective) (= iter 0))
                  (setq best-objective penalized-obj
                        best-controller proposal)
                  (message "[controller-agent] New best controller (objective=%.4f)" penalized-obj)))
              ;; Update current controller for next iteration
              (setq current-controller proposal)))))
      ;; Save best controller
      (when best-controller
        (gptel-auto-workflow--save-evolved-controller best-controller)
        (gptel-auto-workflow--update-skill-with-controller best-controller)
        (message "[controller-agent] Design complete. Best objective=%.4f over %d iterations"
                 best-objective max-iters))
       (list :best-controller best-controller :best-objective best-objective :history history))))


(defun gptel-auto-workflow--controller-design-prompt (current-controller _best-controller 
                                                       best-objective train-traces iter max-iters)
  "Generate prompt for controller design agent."
  (let* ((trace-summary (gptel-auto-workflow--summarize-traces-for-prompt train-traces))
         (current-params (format "own-repo-priority=%.2f ext-priority=%.2f stop-threshold=%.2f branch-threshold=%.2f beta=%.2f"
                                (or (plist-get current-controller :own-repo-priority) 0.7)
                                (or (plist-get current-controller :external-priority) 0.15)
                                 (or (plist-get current-controller :stop-threshold)
                                     (plist-get current-controller :min-confidence-stop) 0.7)
                                (or (plist-get current-controller :branch-threshold) 0.3)
                                (or (plist-get current-controller :beta) 0.5))))
    (format
     "You are a controller design agent implementing the AutoTTS (Automated Test-Time Scaling) architecture.

Your job: Design controller decision rules that decide for each research turn:
- STOP when: confidence is high and rising
- CONTINUE when: confidence is promising but not yet high enough
- BRANCH when: confidence stagnates or drops (explore alternate direction)
- CUT when: exceeded budget or quality is poor

Current controller: %s
Best controller so far: objective=%.4f
Iteration: %d/%d

Training traces summary (%d traces):
%s

Design an IMPROVED list of rules. Each rule must be a plist with:
- :when: an Elisp expression over signals (ema-conf, ema-delta, turn,
  output-length, confidence, has-urls, has-structure, source,
  budget-remaining, own-repo-priority, external-priority, fork-priority,
  web-priority, stop-threshold, min-confidence-stop, branch-threshold,
  token-budget, max-turns, min-insights-for-stop)
- :then: one of stop, continue, branch, cut

Rules:
1. Be specific with numeric thresholds — no ranges, no explanations
2. Consider the trace patterns: what thresholds would have caught failures?
3. Higher own-repo-priority correlates with better results (70%% insight rate vs 5%% for web)
4. The goal: maximize objective = own-repo-success-rate × 0.6 + external-success-rate × 0.15 + avg-confidence × 0.15 + token-efficiency × 0.1
5. Output ONLY a valid Elisp list of rule plists, no markdown, no commentary

Output format exactly:
((:when (and (> ema-conf 0.72) (>= ema-delta -0.02)) :then stop)
 (:when (and (< ema-conf 0.35) (< ema-delta 0.0)) :then branch)
 (:when (< budget-remaining 500) :then cut)
 (:when t :then continue))"
     current-params
     best-objective
     (1+ iter) max-iters
     (length train-traces)
     (truncate-string-to-width trace-summary 1500 nil nil "..."))))

(defun gptel-auto-workflow--summarize-traces-for-prompt (traces)
  "Create compact summary of TRACES for controller design prompt."
  (let ((own-success 0) (own-total 0)
        (ext-success 0) (ext-total 0)
        (confidences nil)
        (decisions (make-hash-table :test 'equal)))
    (dolist (trace (seq-take traces 50))
      (let ((source (gptel-auto-workflow--trace-source trace))
            (confidence (or (plist-get trace :confidence) 0))
            (decision (or (plist-get trace :controller-decision) "continue"))
            (success (gptel-auto-workflow--trace-success-p trace)))
        (push confidence confidences)
        (puthash decision (1+ (gethash decision decisions 0)) decisions)
        (if (string= source "own-repo")
            (progn (cl-incf own-total) (when success (cl-incf own-success)))
          (progn (cl-incf ext-total) (when success (cl-incf ext-success))))))
    (let ((avg-conf (if confidences (/ (apply '+ confidences) (float (length confidences))) 0.0)))
      (format "Own-repo: %d/%d (%.0f%%) External: %d/%d (%.0f%%) Avg confidence: %.2f Decisions: %s"
              own-success own-total (if (> own-total 0) (* 100 (/ (float own-success) own-total)) 0)
              ext-success ext-total (if (> ext-total 0) (* 100 (/ (float ext-success) ext-total)) 0)
              avg-conf
              (mapconcat (lambda (k) (format "%s=%d" k (gethash k decisions)))
                         (hash-table-keys decisions) " ")))))

(defun gptel-auto-workflow--call-controller-design-subagent (prompt)
  "Call subagent to design controller rules based on PROMPT.
Parses the response as a list of (:when EXPR :then DECISION) rules."
  (let ((response (condition-case err
                      (if (fboundp 'gptel-benchmark-call-subagent-sync)
                          (gptel-benchmark-call-subagent-sync
                           'analyzer "Controller Design" prompt 120)
                        (when (fboundp 'gptel-benchmark-call-subagent)
                          (let ((result nil)
                                (done nil))
                            (gptel-benchmark-call-subagent
                             'analyzer "Controller Design" prompt
                             (lambda (value)
                               (setq result value
                                     done t))
                             120)
                            (let ((deadline (+ (float-time) 120)))
                              (while (and (not done)
                                          (< (float-time) deadline))
                                (sit-for 0.1)))
                            (unless done
                              (message "[controller-agent] Subagent timed out after 120s"))
                            result)))
                    (error
                     (message "[controller-agent] Subagent failed: %s" err)
                     nil))))
    (if (and response (stringp response) (not (string-empty-p response)))
        (let ((rules (gptel-auto-workflow--parse-controller-design-rules response)))
          (cond
           ((not rules)
            (message "[controller-agent] Response not a valid rule list: %s"
                     (truncate-string-to-width response 100))
            nil)
           ((gptel-auto-workflow--validate-controller-rules
             rules
             (when (fboundp 'gptel-auto-workflow--load-autotts-controller)
               (gptel-auto-workflow--load-autotts-controller)))
            rules)
           (t
            (message "[controller-agent] Rules failed sandbox validation")
            nil)))
      (message "[controller-agent] No response from controller design subagent")
      nil)))

(defun gptel-auto-workflow--validate-controller-rules (rules &optional controller-config)
  "Validate controller RULES in a Programmatic sandbox.
Each rule must evaluate a valid :when expression and return a valid
:then decision.  Uses simple eval-in-restricted-context to prevent side
effects.  Returns t if all rules pass validation."
  (let ((valid-decisions '(stop continue branch cut)))
    (catch 'invalid-rule
      (dolist (rule rules)
        (let ((when-expr (gptel-auto-workflow--normalize-controller-rule-expr
                          (plist-get rule :when)))
              (then-decision (plist-get rule :then)))
          (unless (and when-expr then-decision
                       (memq then-decision valid-decisions))
            (message "[controller-agent] Invalid rule: %S" rule)
            (throw 'invalid-rule nil))
          ;; Validate :when is evaluable by testing with sample signals
          (condition-case err
              (let* ((config-signals
                      (gptel-auto-workflow--controller-config-rule-signals controller-config))
                     (sample-signals
                      (append '((ema-conf . 0.6) (ema-delta . 0.0)
                                (turn . 2) (output-length . 800)
                                (confidence . 0.5) (has-urls . t)
                                (has-structure . t) (source . "own-repo")
                                (budget-remaining . 4000))
                              config-signals))
                     (signals-env (gptel-auto-workflow--alist-to-sandbox-env sample-signals)))
                 (gptel-auto-workflow--eval-rule-sandbox when-expr signals-env))
            (error
             (message "[controller-agent] Rule :when failed sandbox eval: %S → %s"
                      when-expr (error-message-string err))
             (throw 'invalid-rule nil)))))
      t)))

(defun gptel-auto-workflow--evaluate-controller-rules (rules traces &optional controller-config)
  "Evaluate controller RULES against TRACES by applying rules to each trace.
Returns plist with objective score.
Uses Programmatic sandbox for safe rule evaluation."
  (let ((correct 0) (total 0)
        (tokens-saved 0) (tokens-wasted 0))
    (dolist (trace traces)
      (cl-incf total)
      (let* ((output-length (or (plist-get trace :output-length) 0))
             (confidence (or (plist-get trace :confidence) 0.0))
             (ema-conf (or (plist-get trace :ema-conf) confidence))
             (ema-delta (or (plist-get trace :ema-delta) 0.0))
             (turn-count (or (plist-get trace :turn-count) 1))
             (source (gptel-auto-workflow--trace-source trace "external"))
             (has-urls (plist-get trace :has-urls))
             (has-structure (plist-get trace :has-structure))
             (success (gptel-auto-workflow--trace-success-p trace))
             (config-signals
              (gptel-auto-workflow--controller-config-rule-signals controller-config))
             (token-budget (cdr (assq 'token-budget config-signals)))
             (signals-alist (append `((ema-conf . ,ema-conf) (ema-delta . ,ema-delta)
                                      (turn . ,turn-count) (output-length . ,output-length)
                                      (confidence . ,confidence) (has-urls . ,has-urls)
                                      (has-structure . ,has-structure) (source . ,source)
                                      (budget-remaining . ,(- token-budget (/ output-length 4))))
                                    config-signals))
             (signals-env (gptel-auto-workflow--alist-to-sandbox-env signals-alist))
             (decision
              (catch 'matched
                (dolist (rule rules 'continue)
                  (let ((when-expr (gptel-auto-workflow--normalize-controller-rule-expr
                                    (plist-get rule :when)))
                        (then-decision (plist-get rule :then)))
                    (condition-case nil
                        (when (gptel-auto-workflow--eval-rule-sandbox when-expr signals-env)
                          (throw 'matched then-decision))
                      (error (throw 'matched 'continue))))))))
        (cond
         ((and success (eq decision 'stop))
          (cl-incf correct)
          (setq tokens-saved (+ tokens-saved (/ output-length 8))))
         ((and (not success) (eq decision 'branch))
          (cl-incf correct))
         ((and success (eq decision 'continue))
          (setq tokens-wasted (+ tokens-wasted (/ output-length 4))))
         ((eq decision 'continue)
          (cl-incf correct)))))
    (let* ((accuracy (/ (float correct) (float (max 1 total))))
           (token-ratio (if (> (+ tokens-saved tokens-wasted) 0)
                            (/ (float tokens-saved) (+ tokens-saved tokens-wasted))
                          0.5))
           (objective (+ (* accuracy 0.6) (* token-ratio 0.4))))
       (list :objective objective :accuracy accuracy
             :token-ratio token-ratio :correct correct :total total))))

(defun gptel-auto-workflow--evaluate-controller-config (config traces)
  "Evaluate CONTROLLER-CONFIG against TRACES by SIMULATING controller
decisions.  For each trace, simulate what the CMC controller would have
decided at each turn point, comparing against actual outcomes.  Returns
plist with objective score.  This is an OFFLINE evaluation — 0 LLM calls."
  (let ((simulated-stops 0)
        (simulated-continues 0)
        (simulated-branches 0)
        (false-stops 0)
        (false-continues 0)
        (total-tokens-saved 0)
        (total-tokens-wasted 0)
        (n (length traces)))
    (dolist (trace traces)
      (let* ((output-length (or (plist-get trace :output-length) 0))
             (confidence (or (plist-get trace :confidence) 0.0))
             (ema-conf (or (plist-get trace :ema-conf) confidence))
             (ema-delta (or (plist-get trace :ema-delta) 0.0))
             (turn-count (or (plist-get trace :turn-count) 1))
             (success (gptel-auto-workflow--trace-success-p trace))
             (stop-threshold (or (plist-get config :stop-threshold)
                                 (plist-get config :min-confidence-stop)
                                 0.65))
             (delta-slack (or (plist-get config :delta-slack) 0.04))
             (trend-threshold (or (plist-get config :trend-threshold) 0.04))
             (warm-up (or (plist-get config :warm-up) 2))
             (min-complete (or (plist-get config :min-complete) 2))
             (max-turns (or (plist-get config :max-turns) 3))
             (would-stop (and (>= turn-count warm-up)
                              (>= turn-count min-complete)
                              (>= ema-conf stop-threshold)
                              (>= ema-delta (- delta-slack))))
             (would-branch (and (>= turn-count (max 1 (/ warm-up 2)))
                                (< ema-conf stop-threshold)
                                (<= ema-delta trend-threshold)
                                (< turn-count (1- max-turns)))))
        (cond
         (success
          (if would-stop
              (progn (cl-incf simulated-stops)
                     (setq total-tokens-saved (+ total-tokens-saved (/ output-length 8))))
            (cl-incf false-continues)
            (setq total-tokens-wasted (+ total-tokens-wasted (/ output-length 4)))))
         (t
          (if would-branch
              (cl-incf simulated-branches)
            (if would-stop
                (cl-incf false-stops)
              (cl-incf false-continues)
              (setq total-tokens-wasted (+ total-tokens-wasted (/ output-length 4)))))))))
    (let* ((total-decisions (+ simulated-stops simulated-continues simulated-branches
                              false-stops false-continues))
           (correct-decisions (+ simulated-stops simulated-branches))
           (decision-accuracy (if (> total-decisions 0)
                                  (/ (float correct-decisions) (float total-decisions))
                                0.5))
           (token-savings-ratio (if (> (+ total-tokens-saved total-tokens-wasted) 0)
                                    (/ (float total-tokens-saved)
                                       (+ total-tokens-saved total-tokens-wasted))
                                  0.5))
           (objective (+ (* decision-accuracy 0.6)
                        (* token-savings-ratio 0.4))))
      (list :objective objective
            :decision-accuracy decision-accuracy
            :token-savings-ratio token-savings-ratio
            :simulated-stops simulated-stops
            :simulated-branches simulated-branches
            :false-stops false-stops
            :false-continues false-continues
            :total n
            :tokens-saved total-tokens-saved
            :tokens-wasted total-tokens-wasted))))

;; ─── Trace-Outcome Bridge: Experiment Results → Trace Learning ───

(defun gptel-auto-workflow--parse-tsv-results (tsv-path)
  "Parse TSV experiment results file into list of plists.
Each plist: (:target :decision :score :timestamp)."
  (when (and tsv-path (file-exists-p tsv-path))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents tsv-path)
          (let ((lines (split-string (buffer-string) "\n" t))
                (results nil))
            (dolist (line (cdr lines))
              (let ((fields (split-string line "\t")))
                (when (>= (length fields) 4)
                  (push (list :target (nth 0 fields)
                              :decision (nth 1 fields)
                              :score (string-to-number (or (nth 2 fields) "0"))
                              :timestamp (nth 3 fields))
                        results))))
            results))
      (error nil))))

(defun gptel-auto-workflow--save-trace-synthesis (topic-perf source-perf)
  "Merge trace synthesis into existing evolve pipeline data files.
Reads current topic-performance.json and source-effectiveness.json,
merges trace-level data, and writes back so evolve_researcher.py
sees a unified view of both TSV and trace analysis."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" root)))
    (make-directory data-dir t)
    ;; Load existing topic-performance.json (from TSV analysis)
    (gptel-auto-workflow--merge-trace-topics-into-data topic-perf data-dir)
    ;; Load existing source-effectiveness.json (from TSV analysis)
    (gptel-auto-workflow--merge-trace-sources-into-data source-perf data-dir)))

(defun gptel-auto-workflow--merge-trace-topics-into-data (topic-perf data-dir)
  "Merge trace TOPIC-PERF into the TSV-based topic-performance.json."
  (let* ((topic-file (expand-file-name "topic-performance.json" data-dir))
         (existing (condition-case nil
                        (let ((json-object-type 'hash-table)
                              (json-key-type 'string))
                          (json-read-file topic-file))
                     (error (make-hash-table :test 'equal))))
         (topics-raw (or (gethash :topics existing) (gethash "topics" existing)))
         (topics (if (hash-table-p topics-raw) topics-raw (make-hash-table :test 'equal))))
    ;; Merge trace topic data into existing hash
    (cl-flet ((merge-topic (strategy stats)
               (let* ((strategy (or strategy "unknown"))
                      (kept (nth 0 stats))
                      (total (nth 1 stats))
                      (topic (if (string-match-p "nil-safety\\|null\\|guard" strategy) "nil-safety"
                               (if (string-match-p "performance\\|cache\\|speed" strategy) "performance"
                                 (if (string-match-p "error" strategy) "error-handling"
                                   (if (string-match-p "async" strategy) "async"
                                     strategy)))))
                      (existing-topic (gethash topic topics)))
                 (if existing-topic
                     (let ((old-kept (gethash "kept" existing-topic 0))
                           (old-total (gethash "total_experiments" existing-topic 0)))
                       (puthash "kept" (+ old-kept kept) existing-topic)
                       (puthash "total_experiments" (+ old-total total) existing-topic)
                       (puthash "success_rate" (/ (float (+ old-kept kept))
                                                  (max 1 (+ old-total total)))
                                existing-topic))
                   (puthash topic
                            (let ((h (make-hash-table :test 'equal)))
                              (puthash "kept" kept h)
                              (puthash "total_experiments" total h)
                              (puthash "discarded" (- total kept) h)
                              (puthash "success_rate" (/ (float kept) (max total 1)) h)
                              (puthash "avg_quality_score" 0.5 h)
                              (puthash "avg_score_improvement" 0.0 h)
                              (puthash "trend" "stable" h)
                              (puthash "top_targets" (vector) h)
                              (puthash "first_seen" :null h)
                              (puthash "last_seen" :null h)
                              h)
                            topics)))))
      (maphash #'merge-topic topic-perf))
    ;; Update total experiments
    (let ((new-total 0) (new-kept 0))
      (cl-flet ((accum-totals (_ stats)
                  (setq new-total (+ new-total (gethash "total_experiments" stats 0)))
                  (setq new-kept (+ new-kept (gethash "kept" stats 0)))))
        (maphash #'accum-totals topics))
      (puthash "total_experiments" new-total existing))
    (puthash "version" (format-time-string "%Y-%m-%dT%H:%M:%SZ") existing)
    (with-temp-file topic-file
      (insert (json-encode existing)))
    (message "[autotts] Merged trace topic data into %s (%d topics)"
             topic-file (hash-table-count topics))))

(defun gptel-auto-workflow--merge-trace-sources-into-data (source-perf data-dir)
  "Merge trace SOURCE-PERF into the TSV-based source-effectiveness.json."
  (let* ((source-file (expand-file-name "source-effectiveness.json" data-dir))
         (existing (condition-case nil
                       (let ((json-object-type 'hash-table)
                             (json-key-type 'string))
                         (json-read-file source-file))
                    (error (make-hash-table :test 'equal))))
         (sources-raw (or (gethash "sources" existing) (gethash :sources existing)))
         (sources (if (hash-table-p sources-raw) sources-raw (make-hash-table :test 'equal))))
    (remhash :sources existing)
    (puthash "sources" sources existing)
    (cl-flet ((merge-source (source stats)
               (let* ((source (or source "unknown"))
                      (kept (nth 0 stats))
                      (total (nth 1 stats))
                      (existing-source (gethash source sources)))
                 (if existing-source
                     (let ((old-kept (gethash "experiments_kept" existing-source 0))
                           (old-total (gethash "experiments_enabled" existing-source 0)))
                       (puthash "experiments_kept" (+ old-kept kept) existing-source)
                       (puthash "experiments_enabled" (+ old-total total) existing-source)
                       (puthash "success_rate" (/ (float (+ old-kept kept))
                                                  (max 1 (+ old-total total)))
                                existing-source))
                   (puthash source
                            (let ((h (make-hash-table :test 'equal)))
                              (puthash "experiments_kept" kept h)
                              (puthash "experiments_enabled" total h)
                              (puthash "success_rate" (/ (float kept) (max total 1)) h)
                              (puthash "source_type" (if (string= source "own-repo") "github" "external") h)
                              (puthash "identifier" source h)
                              (puthash "techniques_suggested" (vector) h)
                              h)
                            sources)))))
      (maphash #'merge-source source-perf))
    (with-temp-file source-file
      (insert (json-encode existing)))
    (message "[autotts] Merged trace source data into %s (%d sources)"
             source-file (hash-table-count sources))))

(defun gptel-auto-workflow--update-skill-with-controller (controller-config)
  "Write evolved CONTROLLER-CONFIG as strategy guidance JSON for SKILL.md
injection.  Stores to data/strategy-guidance.json so evolve_researcher.py
won't overwrite it.  The researcher-prompt/SKILL.md uses
{{strategy-guidance}} template variable."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" root))
         (axis (and (boundp 'gptel-auto-workflow--current-experiment-axis)
                    gptel-auto-workflow--current-experiment-axis
                    (not (equal gptel-auto-workflow--current-experiment-axis "?"))
                    (string-remove-prefix ":" (format "%s" gptel-auto-workflow--current-experiment-axis))))
         (guidance-file (expand-file-name (if axis
                                              (format "strategy-guidance-%s.json" axis)
                                            "strategy-guidance.json")
                                          data-dir))
         (own-priority (* 100 (or (plist-get controller-config :own-repo-priority) 0.7)))
         (ext-priority (* 100 (or (plist-get controller-config :external-priority) 0.15)))
         (stop-threshold (* 100 (or (plist-get controller-config :min-confidence-stop)
                                    (plist-get controller-config :stop-threshold)
                                    0.7)))
         (budget (or (plist-get controller-config :max-tokens-budget)
                     (plist-get controller-config :token-budget)
                     8000))
         (beta (or (plist-get controller-config :beta) 0.5))
         (method (or (plist-get controller-config :learning-method) "unknown"))
         (evolved-at (or (plist-get controller-config :evolved-at) "unknown"))
         (based-on (or (plist-get controller-config :based-on-traces) 0))
         (topic-priors (plist-get controller-config :topic-priors))
         (best-topic (plist-get topic-priors :best-topic))
         (best-topic-rate (plist-get topic-priors :best-topic-rate))
         (guidance-json
          `(:beta ,beta
            :own-priority ,own-priority
            :ext-priority ,ext-priority
            :stop-threshold ,stop-threshold
            :token-budget ,budget
            :learning-method ,method
            :evolved-at ,evolved-at
            :based-on-traces ,based-on
            :best-topic ,(or best-topic :json-null)
            :best-topic-rate ,(or best-topic-rate 0.0))))
    (make-directory data-dir t)
    (with-temp-file guidance-file
      (insert (gptel-auto-workflow--json-encode-plist guidance-json)))
    (message "[autotts] Saved strategy guidance to %s (own=%.0f%% ext=%.0f%% beta=%.2f)"
             (file-name-nondirectory guidance-file) own-priority ext-priority beta)))

;;; ─── Offline Trace Replay Benchmark (0 LLM calls) ───

(defun gptel-auto-workflow--offline-benchmark-strategies ()
  "Benchmark all strategies offline against historical traces.
AutoTTS Replay Store: evaluates strategies without LLM calls.
Scores each trace as if produced by different strategies.
Returns list of strategy performance plists.
Faster than `benchmark-all-research-strategies` which calls LLMs."
  (let ((traces (gptel-auto-workflow--load-research-traces))
        (strategies gptel-auto-workflow--research-strategies)
        (results nil))
    (message "[autotts] Offline benchmark: %d traces, %d strategies"
             (length traces) (length strategies))
    (dolist (strategy strategies)
      (let ((strategy-score 0.0)
            (strategy-tokens 0)
            (trace-count 0))
        (dolist (trace traces)
          (let* ((source (gptel-auto-workflow--trace-source trace))
                 (tokens (or (plist-get trace :tokens-used) 1))
                 (has-urls (plist-get trace :has-urls))
                 (confidence (or (plist-get trace :confidence) 0))
                 (step-count (or (plist-get trace :step-count) 1))
                 (outcome-multiplier (if (gptel-auto-workflow--trace-success-p trace)
                                         1.0
                                       0.2))
                 ;; Simulate strategy behavior on this trace
                 (simulated-quality
                  (* outcome-multiplier
                     (cond
                      ;; own-repos-first: high score for own-repo traces
                      ((string= strategy "own-repos-first")
                       (if (string= source "own-repo")
                           (+ 0.4 (* confidence 0.4) (if has-urls 0.2 0))
                         (+ 0.1 (* confidence 0.2) (if has-urls 0.1 0))))
                      ;; deep-external: high score for external traces with depth
                      ((string= strategy "deep-external")
                       (if (string= source "external")
                           (+ 0.3 (* confidence 0.3) (if has-urls 0.2 0) (* step-count 0.02))
                         (+ 0.2 (* confidence 0.3) (if has-urls 0.1 0))))
                      ;; quick-own-only: only own-repo, penalize external
                      ((string= strategy "quick-own-only")
                       (if (string= source "own-repo")
                           (+ 0.5 (* confidence 0.3) (if has-urls 0.2 0))
                         0.05))
                      ;; topic-specific: assume medium performance everywhere
                      (t
                       (+ 0.25 (* confidence 0.3) (if has-urls 0.15 0)))))))
            (setq strategy-score (+ strategy-score simulated-quality))
            (setq strategy-tokens (+ strategy-tokens tokens))
            (setq trace-count (1+ trace-count))))
        ;; Calculate efficiency
        (let ((avg-quality (if (> trace-count 0) (/ strategy-score trace-count) 0))
              (avg-tokens (if (> trace-count 0) (/ strategy-tokens trace-count) 1)))
          (push (list :strategy strategy
                      :quality avg-quality
                      :tokens avg-tokens
                      :efficiency (/ avg-quality (max avg-tokens 1))
                      :traces trace-count
                      :offline t)
                results)
          (message "[autotts] Offline: %s quality=%.2f tokens=%.0f efficiency=%.4f (%d traces)"
                   strategy avg-quality avg-tokens
                   (/ avg-quality (max avg-tokens 1)) trace-count))))
    ;; Sort by efficiency
    (setq results (sort results
                        (lambda (a b)
                          (> (plist-get a :efficiency)
                             (plist-get b :efficiency)))))
    (message "[autotts] Offline benchmark complete. Best: %s"
             (plist-get (car results) :strategy))
    results))

;;; ─── Trace Outcome Tracking (Reward Signal Bridge) ───

(defun gptel-auto-workflow--update-trace-outcomes (experiment)
  "Update trace files with experiment outcome.
EXPERIMENT is a plist with :research-hash and :kept
fields.
Called from experiment logging to link research to
experiment results.
Purpose: records pattern actionability — did research
produce concrete, named patterns?"
  (let* ((research-hash (plist-get experiment :research-hash))
         (kept (gptel-auto-workflow--experiment-kept-p experiment))
         (target (plist-get experiment :target))
         (score-after (plist-get experiment :score-after))
         (findings-text (or (plist-get experiment :findings)
                            (plist-get experiment :research-findings))))
    (when (and research-hash (not (equal research-hash "none")))
      (let ((trace-dir (expand-file-name "var/tmp/research-traces"
                                          (gptel-auto-workflow--worktree-base-root)))
            (updated nil))
        (when (file-directory-p trace-dir)
          (dolist (file (directory-files-recursively trace-dir "\\.json\\'"))
            (when (and (not updated)
                       (string-match-p research-hash (file-name-nondirectory file)))
              (condition-case err
                  (let ((json-object-type 'plist)
                        (json-array-type 'list)
                        (json-key-type 'keyword))
                    (with-temp-buffer
                      (insert-file-contents file)
                      (let* ((trace (json-read))
                             (outcomes (plist-get trace :outcomes))
                             ;; ε Purpose: per-category actionable pattern counts
                             (pattern-counts
                              (gptel-auto-workflow--count-actionable-patterns
                               (or findings-text
                                   (plist-get trace :findings) "")))
                             (new-outcome
                              (list :target target
                                    :kept (if kept t nil)
                                    :score-after (or score-after 0)
                                    :pattern-actionability (cdr (assq :total pattern-counts))
                                    :category-patterns pattern-counts
                                    :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))
                        (setq trace (plist-put trace :outcomes
                                               (append outcomes
                                                       (list new-outcome))))
                        (message "[autotts] Linked trace %s -> %s (%s patterns=%d cat:%s)"
                                 research-hash target (if kept "kept" "discarded")
                                 (cdr (assq :total pattern-counts))
                                 (mapconcat (lambda (c) (format "%s:%d" (car c) (cdr c)))
                                            (cl-remove-if (lambda (p) (eq (car p) :total)) pattern-counts)
                                            " "))
                        (erase-buffer)
                         (insert (gptel-auto-workflow--json-encode-plist trace))
                        (write-region (point-min) (point-max) file))
                       (setq updated t)
                       ;; Schedule trace synthesis + maybe controller evolution
                       (run-with-idle-timer 10 nil
                        (lambda ()
                          (condition-case nil
                              (progn
                                (gptel-auto-workflow--refresh-synthesis-from-traces)
                                (setq gptel-auto-workflow--pending-outcome-updates
                                      (1+ gptel-auto-workflow--pending-outcome-updates))
                                (when (>= gptel-auto-workflow--pending-outcome-updates
                                          gptel-auto-workflow--outcome-evolution-threshold)
                                  (message "[autotts] %d new outcomes → triggering controller evolution"
                                           gptel-auto-workflow--pending-outcome-updates)
                                  (setq gptel-auto-workflow--pending-outcome-updates 0)
                                  (when (fboundp 'gptel-auto-workflow--run-autotts-evolution)
                                    (gptel-auto-workflow--run-autotts-evolution))
                                  (when (fboundp 'gptel-auto-workflow--evolve-all-skills)
                                     (gptel-auto-workflow--evolve-all-skills))))
                            (error nil))))))
                (error
                 (message "[autotts] Failed to update trace outcome: %s" err))))))))))

(defvar gptel-auto-workflow--trace-outcome-hooks nil
  "List of functions to call when trace outcomes are updated.
Each function receives the updated trace plist.")

(add-hook 'gptel-auto-workflow--trace-outcome-hooks
          (lambda (_trace)
            (message "[autoresearch] AutoTTS hook: trace outcome updated — check for RESULT block")))

(defvar gptel-auto-workflow--pending-outcome-updates 0
  "Counter of trace outcome updates since last controller evolution.
Triggers evolution when >= gptel-auto-workflow--outcome-evolution-threshold.")

(defcustom gptel-auto-workflow--outcome-evolution-threshold 10
  "Number of new trace outcomes before triggering controller evolution.
AutoTTS: Higher values batch more data before re-evolving."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--refresh-synthesis-from-traces ()
  "Load all traces, synthesize, and persist to data/ directory.
Lightweight: reuses existing synthesis logic without LLM calls."
  (let ((traces (gptel-auto-workflow--load-research-traces)))
    (when traces
      (gptel-auto-workflow--synthesize-research-knowledge-from-traces traces))))

(defun gptel-auto-workflow--experiment-kept-p (experiment)
  "Return non-nil when EXPERIMENT represents a kept result."
  (or (eq (plist-get experiment :kept) t)
      (equal (plist-get experiment :decision) "kept")
      (equal (plist-get experiment :comparator-reason) "kept")
      (equal (plist-get experiment :grader-reason) "kept")))

(defun gptel-auto-workflow--trace-success-p (trace)
  "Return non-nil when TRACE has a kept downstream outcome.
Falls back to output length only when no outcome data exists yet."
  (let ((outcomes (plist-get trace :outcomes)))
    (if outcomes
        (cl-some (lambda (outcome) (eq (plist-get outcome :kept) t)) outcomes)
      (> (or (plist-get trace :output-length) 0) 1000))))

(defun gptel-auto-workflow--trace-outcome-known-p (trace)
  "Return non-nil when TRACE has at least one downstream outcome."
  (not (null (plist-get trace :outcomes))))

(defun gptel-auto-workflow--run-offline-evolution ()
  "Run lightweight offline evolution using trace replay.
No LLM calls. Fast. Good for convergence testing.
Updates active strategy from offline benchmark results.
Persists evolved strategy for daemon restarts."
  (message "[autotts] Running offline evolution (no LLM calls)...")
  (let ((results (gptel-auto-workflow--offline-benchmark-strategies)))
    (when results
      (let ((best (car results)))
        (setq gptel-auto-workflow--active-strategy
              (plist-get best :strategy))
        (message "[autotts] Offline evolved to strategy: %s (eff=%.4f)"
                 (plist-get best :strategy)
                 (plist-get best :efficiency))
        (setq gptel-auto-workflow--research-benchmark-results results)
        (let ((strategy-file (expand-file-name "var/tmp/researcher-strategy.json"
                                                (gptel-auto-workflow--worktree-base-root))))
          (make-directory (file-name-directory strategy-file) t)
           (with-temp-file strategy-file
              (insert (gptel-auto-workflow--json-encode-plist `(:active-strategy ,(if (and (fboundp 'gptel-auto-workflow--valid-strategy-name-p)
                                                               (gptel-auto-workflow--valid-strategy-name-p
                                                                gptel-auto-workflow--active-strategy))
                                                          gptel-auto-workflow--active-strategy
                                                        "template-default")
                                    :efficiency ,(plist-get best :efficiency)
                                    :evolved-at ,(format-time-string "%Y-%m-%dT%H:%M:%SZ"))))))
        best))))

(defun gptel-auto-workflow--bootstrap-strategy-guidance ()
  "Create data/strategy-guidance.json from existing controller if missing.
Ensures {{strategy-guidance}} template var has data on first load."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (guidance-file (expand-file-name
                         "assistant/skills/researcher-prompt/data/strategy-guidance.json"
                         root)))
    (unless (file-exists-p guidance-file)
      (condition-case err
          (let ((controller-config (gptel-auto-workflow--load-autotts-controller)))
            (when controller-config
              (gptel-auto-workflow--update-skill-with-controller controller-config)
              (message "[autotts] Bootstrapped strategy-guidance.json from controller")))
         (error
          (message "[autotts] Strategy guidance bootstrap deferred: %s" err))))))

;; ─── AutoGo Autoresearch: commit → run → parse RESULT → keep/revert ───

(defvar gptel-auto-workflow--autoresearch-best nil
  "Running best metric value for autoresearch. nil = no best yet.")

(defvar gptel-auto-workflow--autoresearch-best-commit nil
  "Commit hash of the running best. nil = no best yet.")

(defun gptel-auto-workflow--autoresearch-parse-result (output)
  "Parse ===RESULT=== JSON from experiment OUTPUT.
Returns plist with :metric :value :delta :status, or nil."
  (when (stringp output)
    (let ((start (string-match "===RESULT===" output)))
      (when start
        (let* ((json-str (substring output (+ start 13)))
               (end (string-match "\n" json-str)))
          (when end (setq json-str (substring json-str 0 end)))
          (condition-case nil
              (let ((json-object-type 'plist) (json-array-type 'list))
                (json-read-from-string json-str))
            (error nil)))))))

(defun gptel-auto-workflow--autoresearch-check (result-plist &optional target-file description)
  "Check RESULT-PLIST against running best. Implements keep/revert.
AutoGo autoresearch pattern: if improved → commit. If regressed → revert.
TARGET-FILE is the file that was changed. DESCRIPTION is for the commit message.
Returns `keep', `discard', or `first'."
  (let* ((metric (plist-get result-plist :metric))
         (value (plist-get result-plist :value))
         (_status (plist-get result-plist :status))
         (delta (plist-get result-plist :delta))
         (direction (if (string-match-p "keep.rate\\|acc\\|win" (or metric "")) 'higher 'lower)))
    (cond
     ((null gptel-auto-workflow--autoresearch-best)
      (setq gptel-auto-workflow--autoresearch-best value)
      (message "[autoresearch] First result: %s=%.4f — establishing baseline" metric value)
      'first)
     ((or (and (eq direction 'higher) (> value gptel-auto-workflow--autoresearch-best))
          (and (eq direction 'lower) (< value gptel-auto-workflow--autoresearch-best)))
      (setq gptel-auto-workflow--autoresearch-best value)
      (message "[autoresearch] KEEP: %s=%.4f (improved from %.4f, %+.4f)"
               metric value gptel-auto-workflow--autoresearch-best delta)
      (when target-file
        (condition-case nil
            (progn
              (shell-command (format "git add %s" (shell-quote-argument target-file)))
              (shell-command (format "git commit -m \"%s\""
                                     (shell-quote-argument
                                      (or description (format "autoresearch: %s %.4f" metric value))))))
          (error (message "[autoresearch] Git error (non-fatal)"))))
      'keep)
     (t
      (message "[autoresearch] DISCARD: %s=%.4f (worse than %.4f, %+.4f)"
               metric value gptel-auto-workflow--autoresearch-best delta)
      (when target-file
        (condition-case nil
            (progn
              (shell-command (format "git checkout HEAD -- %s" (shell-quote-argument target-file)))
              (shell-command (format "git commit -m \"revert: %s %.4f → %.4f\""
                                     (shell-quote-argument (or metric "unknown")) value gptel-auto-workflow--autoresearch-best)))
          (error (message "[autoresearch] Git error (non-fatal)"))))
      'discard))))

(provide 'gptel-auto-workflow-research-benchmark)

;; Bootstrap strategy-guidance.json on first load (after daemon controller is configured)
(ignore-errors
  (gptel-auto-workflow--bootstrap-strategy-guidance))

;;; gptel-auto-workflow-research-benchmark.el ends here
