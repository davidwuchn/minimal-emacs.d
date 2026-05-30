;;; strategic-daemon-functions.el --- AutoTTS-style research controller functions -*- lexical-binding: t; -*-
;;; Commentary:
;; AutoTTS integration for research controller.
;; Implements EMA momentum confidence, beta parameterization, and trend-based decisions.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(declare-function gptel-sandbox--eval-expr "gptel-sandbox" (expr env))

(defvar gptel-auto-workflow--research-accumulated-findings)
(defvar gptel-auto-workflow--research-total-tokens)
(defvar gptel-auto-workflow--research-current-turn)
(defvar gptel-auto-workflow--research-prompt)
(defvar gptel-auto-workflow--research-controller-config)
(defvar gptel-auto-workflow--current-research-context)

(declare-function gptel-auto-workflow--normalize-response "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--research-has-external-content-p "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--research-error-p "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--local-research-patterns "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--estimate-confidence "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--log-research-step "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--format-research-strategy-prompt "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--save-research-trace "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--digest-research-findings "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--statistical-prob-kept "gptel-auto-workflow-strategic")
(declare-function gptel-benchmark-call-subagent "gptel-benchmark-subagent")

(defun gptel-auto-workflow--autotts-root ()
  "Return project root used for AutoTTS state files."
  (file-name-as-directory
   (or (ignore-errors
         (and (fboundp 'gptel-auto-workflow--worktree-base-root)
              (gptel-auto-workflow--worktree-base-root)))
       (ignore-errors
         (and (fboundp 'gptel-auto-workflow--effective-project-root)
              (gptel-auto-workflow--effective-project-root)))
       user-emacs-directory
       default-directory)))

(defun gptel-auto-workflow--autotts-file (relative-path)
  "Return absolute AutoTTS state path for RELATIVE-PATH."
  (expand-file-name relative-path (gptel-auto-workflow--autotts-root)))

(defun gptel-auto-workflow--load-evolved-controller-config ()
  "Load raw evolved controller JSON from disk, or nil."
  (let ((controller-file (gptel-auto-workflow--autotts-file
                          "var/tmp/researcher-controller.json")))
    (when (file-exists-p controller-file)
      (condition-case err
          (let ((json-object-type 'plist)
                (json-array-type 'list)
                (json-key-type 'keyword))
            (with-temp-buffer
              (insert-file-contents controller-file)
              (json-read)))
        (error
         (message "[autotts] Failed to load controller config: %s" err)
         nil)))))

;; Beta parameterization: single scalar controls all research thresholds
(defvar gptel-auto-workflow--research-beta 0.5
  "Beta parameter for research controller (0.0 = conservative, 1.0 = aggressive).")

;; EMA confidence tracking
(defvar gptel-auto-workflow--research-ema-conf 0.0
  "Exponential moving average of research confidence.")
(defvar gptel-auto-workflow--research-ema-history nil
  "History of EMA confidence values for trend analysis.")
(defvar gptel-auto-workflow--research-ema-alpha 0.5
  "EMA smoothing factor (higher = more responsive to recent changes).")
(defvar gptel-auto-workflow--research-ema-window 6
  "Number of turns to keep in EMA history for trend analysis.")

(defvar gptel-auto-workflow--controller-decision-history nil
  "History of controller decisions for doom loop detection.
Each entry: (decision ema-range delta-sign output-hash).")

(defvar gptel-auto-workflow--controller-doom-loop-threshold 3
  "Number of identical controller decision patterns before doom loop abort.")

;; Execution trace recording
(defvar gptel-auto-workflow--research-trace-log nil
  "Log of detailed execution traces for each research turn.")

;; ─── Multi-Branch Pool (CMC Coupled Width-Depth Control) ───

(defvar gptel-auto-workflow--branch-pool nil
  "List of active research branches (plists).
Each branch plist: (:id :strategy :findings :tokens :turn :alignment
:ema :alive-since).")

(defvar gptel-auto-workflow--branch-pool-max 6
  "Maximum number of concurrent branches in the pool.")

(defvar gptel-auto-workflow--branch-id-counter 0
  "Counter for generating unique branch IDs.")

(defun gptel-auto-workflow--branch-pool-init ()
  "Initialize or clear the branch pool."
  (setq gptel-auto-workflow--branch-pool nil
        gptel-auto-workflow--branch-id-counter 0))

(defun gptel-auto-workflow--branch-pool-active-count ()
  "Return number of alive branches in the pool."
  (length gptel-auto-workflow--branch-pool))

(defun gptel-auto-workflow--branch-pool-add (strategy findings tokens)
  "Add a new branch to the pool with STRATEGY, initial FINDINGS, and TOKENS.
Returns the branch plist."
  (when (< (gptel-auto-workflow--branch-pool-active-count)
           gptel-auto-workflow--branch-pool-max)
    (setq gptel-auto-workflow--branch-id-counter
          (1+ gptel-auto-workflow--branch-id-counter))
    (let ((branch (list :id gptel-auto-workflow--branch-id-counter
                        :strategy (or strategy "default")
                        :findings (or findings "")
                        :tokens (or tokens 0)
                        :turn 0
                        :alignment 'neutral
                        :ema 0.0
                        :alive-since (float-time))))
      (push branch gptel-auto-workflow--branch-pool)
      (message "[autotts] Branch pool: added branch %d (%s), %d active"
               gptel-auto-workflow--branch-id-counter strategy
               (gptel-auto-workflow--branch-pool-active-count))
      branch)))

(defun gptel-auto-workflow--branch-pool-remove (branch-id)
  "Remove branch BRANCH-ID from the pool."
  (setq gptel-auto-workflow--branch-pool
        (cl-remove-if (lambda (b) (= (plist-get b :id) branch-id))
                      gptel-auto-workflow--branch-pool)))

(defun gptel-auto-workflow--branch-pool-get-best ()
  "Return the branch with highest alignment and findings length."
  (car (sort (copy-sequence gptel-auto-workflow--branch-pool)
             (lambda (a b)
               (> (+ (* 10 (if (eq (plist-get a :alignment) 'aligned) 1 0))
                     (length (plist-get a :findings)))
                  (+ (* 10 (if (eq (plist-get b :alignment) 'aligned) 1 0))
                     (length (plist-get b :findings))))))))

(defun gptel-auto-workflow--branch-pool-get-deviant (patience)
  "Return the branch that has been deviant for PATIENCE+ turns, or nil."
  (car (cl-remove-if-not
        (lambda (b)
          (and (eq (plist-get b :alignment) 'deviant)
               (>= (plist-get b :turn) patience)))
        gptel-auto-workflow--branch-pool)))

(defun gptel-auto-workflow--branch-pool-stagnation-p (controller-config)
  "Return non-nil if the branch pool is stagnant (EMA delta below threshold)."
  (let ((ema-delta (gptel-auto-workflow--research-ema-delta))
        (trend-threshold (plist-get controller-config :trend-threshold)))
    (and ema-delta (< ema-delta trend-threshold))))

(defun gptel-auto-workflow--branch-pool-widen (controller-config prompt callback)
  "WIDEN: open a new branch with alternative strategy.
Returns non-nil if a new branch was opened."
  (let* ((widen-burst (plist-get controller-config :widen-burst))
         (active-count (gptel-auto-workflow--branch-pool-active-count))
         (can-open (- (or widen-burst 2) active-count)))
    (when (and (> can-open 0)
               (< active-count gptel-auto-workflow--branch-pool-max))
      (let ((alt-strategies '("deep-external" "cross-reference" "implementation-focused"
                              "error-patterns" "code-clarity")))
        (dotimes (i (min can-open 2))
          (let ((strat (nth i alt-strategies)))
            (gptel-auto-workflow--branch-pool-add
             strat "" 0)
            ;; Start a lightweight research turn for this branch
            (gptel-auto-workflow--run-research-turn
             (or prompt "") 0 callback "" 0 'branch)))))
      t))

;; ─── End Multi-Branch Pool ───

(defun gptel-auto-workflow--research-beta-schedule (beta)
  "Return parameter plist for research controller based on BETA.
BETA is in [0,1]: 0 = conservative (few turns, easy to stop),
1 = aggressive (many turns, hard to stop)."
  (let* ((b (max 0.0 (min 1.0 (float beta))))
         ;; Budget parameters (non-decreasing with beta)
         (max-turns (max 2 (round (+ 2 (* 6 b)))))
         (token-budget (round (+ 4000 (* 8000 b))))
         (warm-up (max 2 (round (+ 2 (* 8 b)))))
         (abandon-patience (max 3 (round (+ 3 (* 9 b)))))
         ;; Confidence parameters
         (stop-threshold (+ 0.65 (* 0.12 b)))
         (branch-threshold (+ 0.15 (* 0.15 b)))
         (delta-slack (- 0.04 (* 0.03 b)))
         ;; EMA parameters
         (ema-alpha (- 0.70 (* 0.40 b)))
         (ema-window (max 2 (round (+ 2 (* 6 b)))))
         ;; Widening parameters
         (widen-burst (max 1 (round (+ 1 (* 3 b)))))
         (trend-threshold (- 0.04 (* 0.03 b)))
         ;; Source parameters
         (own-repo-priority (+ 0.5 (* 0.45 b)))
         (min-complete (max 2 (round (+ 2 (* 3 b))))))
    (list :max-turns max-turns
          :token-budget token-budget
          :warm-up warm-up
          :abandon-patience abandon-patience
          :stop-threshold stop-threshold
          :branch-threshold branch-threshold
          :delta-slack delta-slack
          :ema-alpha ema-alpha
          :ema-window ema-window
          :widen-burst widen-burst
          :trend-threshold trend-threshold
          :own-repo-priority own-repo-priority
          :min-complete min-complete
          :beta b)))

(defun gptel-auto-workflow--update-research-ema (new-confidence)
  "Update EMA with NEW-CONFIDENCE reading.
Uses gptel-auto-workflow--research-ema-alpha for smoothing.
Adjusts alpha based on mementum knowledge page confidence."
  ;; ASSUMPTION: new-confidence should be a number; caller may pass nil
  ;; BEHAVIOR: Clamp nil/non-number to 0.0, compute adaptive EMA update
  ;; EDGE CASE: nil or non-number new-confidence defaults to 0.0
  ;; TEST: Call with nil, non-number, and valid number inputs
  (let* ((new-confidence (if (numberp new-confidence) new-confidence 0.0))
         (mementum-conf (when (fboundp 'gptel-auto-workflow--mementum-confidence-factor)
                          (gptel-auto-workflow--mementum-confidence-factor "template-default")))
         (alpha (* (if (numberp gptel-auto-workflow--research-ema-alpha)
                       gptel-auto-workflow--research-ema-alpha
                     0.5)
                   (cond ((and mementum-conf (numberp mementum-conf) (> mementum-conf 0.7)) 0.7)
                         ((and mementum-conf (numberp mementum-conf) (< mementum-conf 0.3)) 1.3)
                         (t 1.0)))))
    (setq gptel-auto-workflow--research-ema-conf
          (+ (* (- 1.0 alpha) (if (numberp gptel-auto-workflow--research-ema-conf)
                                  gptel-auto-workflow--research-ema-conf
                                0.0))
             (* alpha new-confidence)))
    (push gptel-auto-workflow--research-ema-conf
          gptel-auto-workflow--research-ema-history)
    ;; Keep only recent history
    (when (> (length gptel-auto-workflow--research-ema-history)
             (if (natnump gptel-auto-workflow--research-ema-window)
                 gptel-auto-workflow--research-ema-window
               6))
      (setq gptel-auto-workflow--research-ema-history
            (butlast gptel-auto-workflow--research-ema-history)))
    gptel-auto-workflow--research-ema-conf))

(defun gptel-auto-workflow--research-ema-delta ()
  "Calculate EMA trend (delta) from history.
Returns difference between most recent and oldest EMA in window.
Positive = improving confidence, negative = declining."
  (if (>= (length gptel-auto-workflow--research-ema-history) 2)
      (- (car gptel-auto-workflow--research-ema-history)
         (car (last gptel-auto-workflow--research-ema-history)))
    0.0))

(defun gptel-auto-workflow--record-research-trace (turn data)
  "Record detailed trace of research TURN for feedback.
DATA is a plist with turn metadata."
  (push (list :turn turn
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
              :controller-decision (plist-get data :decision)
              :confidence (plist-get data :confidence)
              :ema-conf (plist-get data :ema-conf)
              :ema-delta (plist-get data :ema-delta)
              :source-effectiveness (plist-get data :source-effectiveness)
              :output-length (plist-get data :output-length)
              :tokens-used (plist-get data :tokens-used)
              :findings-quality (plist-get data :findings-quality))
        gptel-auto-workflow--research-trace-log))

(defun gptel-auto-workflow--reset-research-ema ()
  "Reset EMA state for new research session."
  (setq gptel-auto-workflow--research-ema-conf 0.0)
  (setq gptel-auto-workflow--research-ema-history nil)
  (setq gptel-auto-workflow--research-trace-log nil))

(defun gptel-auto-workflow--load-statistical-model ()
  "Load statistical model from evolved controller JSON.
Returns plist with :model-intercept, :model-weights, etc., or nil."
  (let ((config (gptel-auto-workflow--load-evolved-controller-config)))
    (when (plist-get config :statistical-model)
      (list :statistical-model t
            :model-intercept (plist-get config :model-intercept)
            :model-weights (plist-get config :model-weights)
            :model-n-traces (plist-get config :model-n-traces)
            :model-n-kept (plist-get config :model-n-kept)
            :model-base-rate (plist-get config :model-base-rate)
            :topic-models (plist-get config :topic-models)))))

(defun gptel-auto-workflow--load-researcher-feedback ()
  "Load researcher feedback from disk and return adjustment plist.
Reads var/tmp/researcher-feedback.sexp and suggests beta/threshold tweaks."
  (let ((feedback-file (gptel-auto-workflow--autotts-file
                        "var/tmp/researcher-feedback.sexp")))
    (when (file-exists-p feedback-file)
      (condition-case err
          (let ((feedback (with-temp-buffer
                           (insert-file-contents feedback-file)
                           (read (current-buffer)))))
            (let ((best-rate (or (plist-get feedback :best-rate) 0.5)))
              ;; Adjust beta based on success rate: higher rate = higher beta (more exploration)
              (list :feedback-beta-offset (- best-rate 0.5)
                    :feedback-best-quality (plist-get feedback :best-quality)
                    :feedback-timestamp (plist-get feedback :timestamp))))
        (error
         (let ((msg (format "[autotts] Failed to load researcher feedback: %s" err)))
           (message "%s" msg)
           nil))))))

(defun gptel-auto-workflow--load-skill-topic-priors ()
  "Load topic success rates from data/topic-performance.json as controller
priors.  Returns plist with :topic-rates alist and :best-topic for
warm-starting decisions."
  (let* ((data-dir (gptel-auto-workflow--autotts-file
                    "assistant/skills/researcher-prompt/data"))
         (topic-file (expand-file-name "topic-performance.json" data-dir)))
    (when (file-exists-p topic-file)
      (condition-case err
          (let* ((json-object-type 'hash-table)
                 (json-key-type 'string)
                 (data (json-read-file topic-file))
                 (topics (gethash "topics" data))
                 (rates nil)
                 (best-topic nil)
                 (best-rate 0.0))
            (when (hash-table-p topics)
              (cl-flet ((scan-topic (topic stats)
                         (let ((rate (gethash "success_rate" stats 0.0))
                               (total (gethash "total_experiments" stats 0)))
                           (push (cons topic rate) rates)
                           (when (and (> total 4) (> rate best-rate))
                             (setq best-rate rate
                                   best-topic topic)))))
                (maphash #'scan-topic topics))
              (message "[autotts] Loaded %d topic priors from skill data (best: %s %.0f%%)"
                       (length rates) (or best-topic "none") (* 100 best-rate))
              (list :topic-rates rates
                    :best-topic best-topic
                    :best-topic-rate best-rate
                    :n-topics (length rates))))
        (error
         (message "[autotts] Failed to load topic priors: %s" err)
         nil)))))

(defun gptel-auto-workflow--load-autotts-controller ()
  "Load AutoTTS controller config with beta parameterization.
Returns plist with controller parameters."
  (let* ((base-beta (or gptel-auto-workflow--research-beta 0.5))
         ;; Load researcher feedback before scheduling so beta affects thresholds.
         (feedback (gptel-auto-workflow--load-researcher-feedback))
         (adjusted-beta (if feedback
                            (max 0.0 (min 1.0 (+ base-beta (or (plist-get feedback :feedback-beta-offset) 0))))
                          base-beta))
         (params (gptel-auto-workflow--research-beta-schedule adjusted-beta))
         (evolved (gptel-auto-workflow--load-evolved-controller-config))
         (statistical-model (gptel-auto-workflow--load-statistical-model))
         (topic-priors (gptel-auto-workflow--load-skill-topic-priors))
         (stop-threshold (or (plist-get evolved :min-confidence-stop)
                             (plist-get evolved :stop-threshold)
                             (plist-get params :stop-threshold)))
         (branch-threshold (or (plist-get evolved :branch-threshold)
                               (plist-get params :branch-threshold)))
         (token-budget (or (plist-get evolved :max-tokens-budget)
                           (plist-get evolved :token-budget)
                           (plist-get params :token-budget)))
         (own-priority (or (plist-get evolved :own-repo-priority)
                           (plist-get params :own-repo-priority))))
    (append (list :beta adjusted-beta
                  :stop-threshold stop-threshold
                  :min-confidence-stop stop-threshold
                  :branch-threshold branch-threshold
                  :token-budget token-budget
                  :max-tokens-budget token-budget
                  :own-repo-priority own-priority
                  :external-priority (or (plist-get evolved :external-priority) 0.15)
                  :fork-priority (or (plist-get evolved :fork-priority) 0.4)
                  :web-priority (or (plist-get evolved :web-priority) 0.05)
                  :min-insights-for-stop (or (plist-get evolved :min-insights-for-stop) 2)
                  :based-on-traces (or (plist-get evolved :based-on-traces)
                                       (plist-get statistical-model :model-n-traces)
                                       0)
                  :learning-method (or (plist-get evolved :learning-method)
                                       (and statistical-model "statistical")
                                       "beta-schedule")
                  :evolved-at (or (plist-get evolved :evolved-at) "not-yet"))
             statistical-model
             evolved
             params
             feedback
             topic-priors)))



;; ─── Agent-Generated Rule Evaluation ───

(defun gptel-auto-workflow--controller-config-rule-signals (controller-config)
  "Return controller config values exposed to generated rule expressions."
  (let* ((token-budget (or (plist-get controller-config :token-budget)
                           (plist-get controller-config :max-tokens-budget)
                           8000))
          (stop-threshold (or (plist-get controller-config :stop-threshold)
                              (plist-get controller-config :min-confidence-stop)
                              0.65))
          (min-confidence-stop (or (plist-get controller-config :min-confidence-stop)
                                   stop-threshold))
          (branch-threshold (or (plist-get controller-config :branch-threshold) 0.3))
          (max-turns (or (plist-get controller-config :max-turns) 3))
          (own-priority (or (plist-get controller-config :own-repo-priority) 0.7))
          (external-priority (or (plist-get controller-config :external-priority) 0.15)))
    `((own-repo-priority . ,own-priority)
      (own-priority . ,own-priority)
      (external-priority . ,external-priority)
      (ext-priority . ,external-priority)
      (fork-priority . ,(or (plist-get controller-config :fork-priority) 0.4))
      (web-priority . ,(or (plist-get controller-config :web-priority) 0.05))
      (stop-threshold . ,stop-threshold)
      (min-confidence-stop . ,min-confidence-stop)
      (branch-threshold . ,branch-threshold)
      (token-budget . ,token-budget)
      (max-tokens-budget . ,token-budget)
      (max-turns . ,max-turns)
      (min-insights-for-stop . ,(or (plist-get controller-config :min-insights-for-stop) 2))
      (beta . ,(or (plist-get controller-config :beta) 0.5))
      (delta-slack . ,(or (plist-get controller-config :delta-slack) 0.04))
      (trend-threshold . ,(or (plist-get controller-config :trend-threshold) 0.04))
      (warm-up . ,(or (plist-get controller-config :warm-up) 2))
      (min-complete . ,(or (plist-get controller-config :min-complete) 2))
      (turn-count . ,(or (plist-get controller-config :turn-count) 0)))))

(defun gptel-auto-workflow--controller-source-literal-string (value)
  "Return VALUE as a source string literal, or nil when VALUE is not a literal."
  (cond
   ((and (consp value) (eq (car value) 'quote))
    (gptel-auto-workflow--controller-source-literal-string (cadr value)))
   ((stringp value)
    (let ((cleaned (replace-regexp-in-string "\\\\\"" "\"" value)))
      (string-trim cleaned "[\\\"']+" "[\\\"']+")))
   ((and (symbolp value) (not (eq value 'source)))
    (let ((cleaned (replace-regexp-in-string
                    "\\\\\"" "\"" (symbol-name value))))
      (string-trim cleaned "[\\\"']+" "[\\\"']+")))
   (t nil)))

(defun gptel-auto-workflow--normalize-controller-rule-expr (expr)
  "Normalize common generated controller rule variants in EXPR."
  (if (consp expr)
      (let* ((op (car expr))
             (args (mapcar #'gptel-auto-workflow--normalize-controller-rule-expr
                           (cdr expr))))
        (if (and (memq op '(= equal eq eql string=))
                 (= (length args) 2)
                 (or (eq (car args) 'source) (eq (cadr args) 'source)))
            (let* ((literal (if (eq (car args) 'source) (cadr args) (car args)))
                   (source-value
                    (gptel-auto-workflow--controller-source-literal-string literal)))
              (if (and source-value (not (string-empty-p source-value)))
                  `(equal source ,source-value)
                (cons op args)))
          (cons op args)))
    expr))

(defun gptel-auto-workflow--apply-controller-rules (controller-config output-text)
  "Apply agent-generated decision rules from CONTROLLER-CONFIG.
Evaluates (:when EXPR :then DECISION) rules against current signals.
Uses Programmatic sandbox for safe evaluation.
Returns the decision from the first matching rule, or nil if no rules exist."
  (let ((rules (plist-get controller-config :rules)))
    (when (and rules (listp rules))
      (let* ((config-signals (gptel-auto-workflow--controller-config-rule-signals controller-config))
             (token-budget (cdr (assq 'token-budget config-signals)))
             (turn-count (cdr (assq 'turn-count config-signals)))
             (signals-alist (append
                              `((ema-conf . ,gptel-auto-workflow--research-ema-conf)
                                (ema-delta . ,(gptel-auto-workflow--research-ema-delta))
                                (turn . ,turn-count)
                                (output-length . ,(length (or output-text "")))
                                (confidence . ,(if (and (fboundp 'gptel-auto-workflow--estimate-confidence)
                                                        (functionp (symbol-function 'gptel-auto-workflow--estimate-confidence)))
                                                   (or (gptel-auto-workflow--estimate-confidence output-text) 0.0)
                                                 0.0))
                                (has-urls . ,(and output-text (string-match-p "https?://" output-text) t))
                                (has-structure . ,(and output-text (string-match-p "## .*\\n" output-text) t))
                                (source . ,(if (string-match-p "davidwuchn\\|own.repo" (or output-text ""))
                                               "own-repo" "external"))
                                (budget-remaining . ,(- token-budget (/ (length (or output-text "")) 4))))
                              config-signals))
             (signals-env (gptel-auto-workflow--alist-to-sandbox-env signals-alist)))
        (catch 'rule-matched
          (dolist (rule rules nil)
            (condition-case nil
                (let ((normalized-expr
                       (gptel-auto-workflow--normalize-controller-rule-expr
                        (plist-get rule :when))))
                  (when (gptel-auto-workflow--eval-rule-sandbox normalized-expr signals-env)
                    (throw 'rule-matched (plist-get rule :then))))
              (ignore))))))))

(defun gptel-auto-workflow--alist-to-sandbox-env (alist)
  "Convert ALIST to Programmatic sandbox hash-table environment."
  (let ((env (make-hash-table :test 'eq)))
    (dolist (entry alist)
      (when (consp entry)
        (puthash (car entry) (cdr entry) env)))
    env))

(defun gptel-auto-workflow--eval-rule-expr-fallback (expr env)
  "Evaluate simple rule EXPR against hash-table ENV without the full
sandbox.  Handles numbers, strings, symbol lookup, comparisons, boolean
logic, and arithmetic.  Used when gptel-sandbox is not loaded."
  (cond
   ((numberp expr) expr)
   ((stringp expr) expr)
   ((eq expr t) t)
   ((null expr) nil)
   ((symbolp expr)
    (if (hash-table-p env)
        (gethash expr env nil)
      (alist-get expr env nil)))
   ((not (consp expr)) nil)
   (t
    (let ((op (car expr))
          (args (cdr expr)))
      (pcase op
        ('quote (car args))
        ('and (cl-every
               (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env))
               args))
        ('or (cl-some
              (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env))
              args))
        ('not (not (gptel-auto-workflow--eval-rule-expr-fallback (car args) env)))
        ('null (null (gptel-auto-workflow--eval-rule-expr-fallback (car args) env)))
        ('> (let ((vals (mapcar (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env)) args)))
              (and (cl-every #'numberp vals) (apply #'> vals))))
        ('< (let ((vals (mapcar (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env)) args)))
              (and (cl-every #'numberp vals) (apply #'< vals))))
        ('>= (let ((vals (mapcar (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env)) args)))
               (and (cl-every #'numberp vals) (apply #'>= vals))))
        ('<= (let ((vals (mapcar (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env)) args)))
               (and (cl-every #'numberp vals) (apply #'<= vals))))
        ('= (let ((vals (mapcar (lambda (a) (gptel-auto-workflow--eval-rule-expr-fallback a env)) args)))
              (and (cl-every #'numberp vals) (apply #'= vals))))
        ('eq (eq (gptel-auto-workflow--eval-rule-expr-fallback (car args) env)
                 (gptel-auto-workflow--eval-rule-expr-fallback (cadr args) env)))
        ('eql (eql (gptel-auto-workflow--eval-rule-expr-fallback (car args) env)
                   (gptel-auto-workflow--eval-rule-expr-fallback (cadr args) env)))
        ('equal (equal (gptel-auto-workflow--eval-rule-expr-fallback (car args) env)
                       (gptel-auto-workflow--eval-rule-expr-fallback (cadr args) env)))
        ('string= (string= (gptel-auto-workflow--eval-rule-expr-fallback (car args) env)
                           (gptel-auto-workflow--eval-rule-expr-fallback (cadr args) env)))
        ('+ (apply #'+ (mapcar (lambda (a) (let ((v (gptel-auto-workflow--eval-rule-expr-fallback a env)))
                                             (if (numberp v) v 0)))
                                args)))
        ('- (apply #'- (mapcar (lambda (a) (let ((v (gptel-auto-workflow--eval-rule-expr-fallback a env)))
                                             (if (numberp v) v 0)))
                                args)))
        ('* (apply #'* (mapcar (lambda (a) (let ((v (gptel-auto-workflow--eval-rule-expr-fallback a env)))
                                             (if (numberp v) v 1)))
                                args)))
        ('/ (apply #'/ (mapcar (lambda (a) (let ((v (gptel-auto-workflow--eval-rule-expr-fallback a env)))
                                             (if (numberp v) v 1)))
                                args)))
        (_ nil))))))

(defun gptel-auto-workflow--eval-rule-sandbox (expr env)
  "Evaluate rule EXPR in Programmatic sandbox ENV.
Returns non-nil if expression is truthy, nil otherwise.
Falls back to a simple expression evaluator when sandbox is unavailable."
  (condition-case err
      (if (and (fboundp 'gptel-sandbox--eval-expr)
               (hash-table-p env))
          (gptel-sandbox--eval-expr expr env)
        (gptel-auto-workflow--eval-rule-expr-fallback expr env))
    (error
     (message "[autotts] Rule eval error: %s" (error-message-string err))
     nil)))

;; ─── End Agent-Generated Rule Evaluation ───

;; ─── Controller Doom Loop Detection (ml-intern pattern) ───

(defun gptel-auto-workflow--controller-decision-signature (decision ema-conf ema-delta output-text)
  "Return doom loop signature for controller decision.
Signature: (decision ema-range delta-sign output-hash).
Includes output-hash so legitimate progress isn't flagged."
  (let* ((ema-range (cond ((>= ema-conf 0.7) 'high)
                          ((>= ema-conf 0.4) 'medium)
                          (t 'low)))
         (delta-sign (cond ((> ema-delta 0.02) 'rising)
                           ((< ema-delta -0.02) 'falling)
                           (t 'stable)))
         (output-hash (when output-text
                        (md5 (substring output-text 0 (min 100 (length output-text)))))))
    (list decision ema-range delta-sign output-hash)))

(defun gptel-auto-workflow--detect-controller-doom-loop ()
  "Check if controller is stuck in repeated decision pattern.
Returns corrective action or nil."
  (let ((history gptel-auto-workflow--controller-decision-history)
        (threshold gptel-auto-workflow--controller-doom-loop-threshold))
    (when (and history (>= (length history) threshold))
      (let ((recent (seq-take history threshold)))
        (when (seq-every-p (lambda (x) (and (consp x) (equal x (car recent)))) recent)
          (let* ((stuck (car (car recent)))
                 (corrective (if (eq stuck 'continue) 'branch 'stop)))
            (message "[autotts] Doom loop: %s × %d → forcing %s"
                     stuck threshold corrective)
            corrective))))))

(defun gptel-auto-workflow--record-controller-decision (decision ema-conf ema-delta output-text)
  "Record controller decision in history for doom loop detection."
  (let ((sig (gptel-auto-workflow--controller-decision-signature
              decision ema-conf ema-delta output-text)))
    (push sig gptel-auto-workflow--controller-decision-history)
    (when (> (length gptel-auto-workflow--controller-decision-history) 10)
      (setq gptel-auto-workflow--controller-decision-history
            (seq-take gptel-auto-workflow--controller-decision-history 10)))))

(defun gptel-auto-workflow--controller-decide-with-doom-check (controller-config output-length output-text)
  "Controller with doom loop detection wrapper.
Calls controller, checks for doom loop, records history, returns final decision."
  (let* ((decision (gptel-auto-workflow--controller-decide-research-flow
                    controller-config output-length output-text))
         (ema-conf gptel-auto-workflow--research-ema-conf)
         (ema-delta (gptel-auto-workflow--research-ema-delta))
         (doom (gptel-auto-workflow--detect-controller-doom-loop)))
    (if doom
        doom
      (gptel-auto-workflow--record-controller-decision decision ema-conf ema-delta output-text)
      decision)))

;; ─── End Controller Doom Loop Detection ───

(defun gptel-auto-workflow--category-stop-threshold (text base-threshold)
  "Adjust STOP threshold based on research content category.
τ Wisdom: different categories converge at different rates.
:text-programming converges faster (lower threshold = fewer turns needed).
:tool-calls and :agentic need more turns (higher threshold)."
  (let ((cat (cond
              ((string-match-p "code\\|function\\|elisp\\|syntax\\|macro\\|program\\|defun" (or text ""))
               :programming)
              ((string-match-p "tool\\|sandbox\\|permit\\|security\\|guard\\|forbid" (or text ""))
               :tool-calls)
              ((string-match-p "agent\\|fsm\\|state\\|coordinat\\|delegat\\|subagent" (or text ""))
               :agentic)
              (t :natural-language))))
    (cl-case cat
      (:programming (- base-threshold 0.10))   ; converges fast, stop sooner
      (:tool-calls   (+ base-threshold 0.10))   ; needs more turns for safety
      (:agentic      (+ base-threshold 0.05))   ; coordination needs more turns
      (t             base-threshold))))           ; natural-language: default

(defun gptel-auto-workflow--controller-decide-research-flow (controller-config output-length &optional output-text)
  "AutoTTS controller with EMA momentum gate.
Decides: stop, continue, branch, or cut.
Uses EMA trend analysis for momentum-aware stopping."
  (let* ((tokens-used (/ output-length 4))
         (max-tokens (or (plist-get controller-config :token-budget)
                         (plist-get controller-config :max-tokens-budget) 8000))
         (text (or output-text ""))
         (has-urls (string-match-p "https?://" text))
         (has-structure (string-match-p "## .*\\n" text))
         (has-code (string-match-p "```" text))
         (turn-count (or (plist-get controller-config :turn-count) 0))
         ;; EMA state
         (ema-conf gptel-auto-workflow--research-ema-conf)
         (ema-delta (gptel-auto-workflow--research-ema-delta))
          ;; Thresholds from beta schedule
          (stop-threshold (or (plist-get controller-config :stop-threshold)
                              (plist-get controller-config :min-confidence-stop) 0.65))
          ;; τ Wisdom: per-category convergence rates
          (stop-threshold (gptel-auto-workflow--category-stop-threshold text stop-threshold))
          (branch-threshold (or (plist-get controller-config :branch-threshold) 0.3))
         (delta-slack (or (plist-get controller-config :delta-slack) 0.04))
         (trend-threshold (or (plist-get controller-config :trend-threshold) 0.04))
         (warm-up (or (plist-get controller-config :warm-up) 2))
         (min-complete (or (plist-get controller-config :min-complete) 2))
         ;; Statistical model
         (statistical-model (plist-get controller-config :statistical-model))
         (prob-kept (when statistical-model
                     (gptel-auto-workflow--statistical-prob-kept
                      controller-config output-length text))))
    (cond
     ;; ─── Agent-Generated Rules (AutoTTS-defining feature) ───
     ;; Evaluate rules discovered by the controller design agent.
     ;; Agent writes decision rules, sandbox validates, controller applies them.
     ;; Rules are evaluated before hardcoded logic — agent can override defaults.
     ((let ((rule-result (gptel-auto-workflow--apply-controller-rules controller-config text)))
        (when rule-result
          (message "[autotts] Agent rule: %s" rule-result)
          rule-result)))
     
     ;; Over budget → cut (always check first)
     ((> tokens-used max-tokens)
      (message "[autotts] Controller: CUT (budget %d/%d)" tokens-used max-tokens)
      'cut)
     
      ;; ─── Multi-Branch Pool: Widen/Abandon/Narrow ───
      ;; Check if branch pool stagnation warrants widening
      ((and (>= turn-count 1)
            (gptel-auto-workflow--branch-pool-stagnation-p controller-config)
            (< (gptel-auto-workflow--branch-pool-active-count)
               (or (plist-get controller-config :widen-burst) 2)))
       (message "[autotts] Controller: WIDEN (branch pool stagnant, %d active, widen-burst=%d)"
                (gptel-auto-workflow--branch-pool-active-count)
                (or (plist-get controller-config :widen-burst) 2))
       'widen)
      
      ;; Check if any branch has been deviant too long → abandon
      ((let ((deviant (gptel-auto-workflow--branch-pool-get-deviant
                       (plist-get controller-config :abandon-patience))))
         (when deviant
           (gptel-auto-workflow--branch-pool-remove (plist-get deviant :id))
           (message "[autotts] Controller: ABANDON branch %d (deviant for %d turns, patience=%d)"
                    (plist-get deviant :id) (plist-get deviant :turn)
                    (plist-get controller-config :abandon-patience))
           t))
       ;; After abandoning, re-evaluate: continue if aligned branches exist
       (if (> (gptel-auto-workflow--branch-pool-active-count) 0) 'continue 'stop))
      
      ;; EMA Momentum Gate: Stop when confidence is high AND trend is non-negative
     ;; Only after warm-up and minimum completion
     ((and (>= turn-count warm-up)
           (>= turn-count min-complete)
           (>= ema-conf stop-threshold)
           (>= ema-delta (- delta-slack)))
      (message "[autotts] Controller: STOP (EMA conf=%.2f >= %.2f, delta=%.2f >= %.2f) [momentum gate]"
               ema-conf stop-threshold ema-delta (- delta-slack))
      'stop)
     
     ;; Trend-based widening: Branch when confidence stagnates or declines
     ;; AND we're past warm-up AND confidence is below stop threshold
      ((and (>= turn-count (max 1 (/ warm-up 2)))
            (< ema-conf stop-threshold)
            (<= ema-delta trend-threshold)
            (< turn-count (1- (or (plist-get controller-config :max-turns) 3))))
      (message "[autotts] Controller: BRANCH (EMA conf=%.2f < %.2f, delta=%.2f <= %.2f) [trend-based]"
               ema-conf stop-threshold ema-delta trend-threshold)
      'branch)
     
     ;; Statistical model fallback
     (statistical-model
      (let* ((topic (when (fboundp 'gptel-auto-workflow--detect-research-topic)
                     (gptel-auto-workflow--detect-research-topic text)))
             (topic-model (when (fboundp 'gptel-auto-workflow--get-topic-model)
                           (gptel-auto-workflow--get-topic-model controller-config topic)))
             (use-topic-thresholds (and topic-model
                                        (> (or (plist-get topic-model :n-traces) 0) 3)))
             (base-stop (if use-topic-thresholds
                           (or (plist-get topic-model :stop-threshold) stop-threshold)
                         stop-threshold))
             (base-branch (if use-topic-thresholds
                             (or (plist-get topic-model :branch-threshold) branch-threshold)
                           branch-threshold)))
        (cond
         ;; High probability → stop
         ((and prob-kept (> prob-kept base-stop))
          (message "[autotts] Controller: STOP (P(kept)=%.2f > %.2f) [statistical %s]"
                   prob-kept base-stop
                   (if use-topic-thresholds (concat "topic:" topic) "global"))
          'stop)
         ;; Low probability → branch (fixed bug: no mutually exclusive conditions)
         ((and prob-kept (< prob-kept base-branch) (>= turn-count warm-up))
          (message "[autotts] Controller: BRANCH (P(kept)=%.2f < %.2f) [statistical %s]"
                   prob-kept base-branch
                   (if use-topic-thresholds (concat "topic:" topic) "global"))
          'branch)
         ;; Medium probability → continue
         (t
          (message "[autotts] Controller: CONTINUE (P(kept)=%.2f, EMA=%.2f) [statistical]"
                   (or prob-kept 0.5) ema-conf)
          'continue))))
     
     ;; Heuristic fallback (fixed: no dead code paths)
     (t
      (let ((min-insights (or (plist-get controller-config :min-insights-for-stop) 2))
            (insights-count (+ (if has-urls 1 0)
                              (if has-structure 1 0)
                              (if has-code 1 0))))
        (cond
         ;; Good output: long + URLs + structure → stop
         ((and (> output-length 2000)
               has-urls
               (>= insights-count min-insights))
          (message "[autotts] Controller: STOP (good output: %d chars, %d insights) [heuristic]"
                   output-length insights-count)
          'stop)
         ;; Stagnation: short output, no URLs, past warm-up → branch
         ((and (< output-length 1000)
               (not has-urls)
               (>= turn-count warm-up))
          (message "[autotts] Controller: BRANCH (stagnation: short, no URLs) [heuristic]")
          'branch)
         ;; Default → continue
         (t
          (message "[autotts] Controller: CONTINUE (len=%d, insights=%d, EMA=%.2f) [heuristic]"
                   output-length insights-count ema-conf)
          'continue)))))))

(defun gptel-auto-workflow--run-research-turn (research-prompt turn callback 
                                                       &optional accumulated-findings total-tokens previous-decision)
  "Run a single research TURN with AutoTTS-style controller.
RESEARCH-PROMPT is the prompt for this turn.
TURN is the turn number (0-indexed).
CALLBACK receives final digested findings.
ACCUMULATED-FINDINGS is findings from previous turns.
TOTAL-TOKENS tracks cumulative token usage across turns.
PREVIOUS-DECISION is the controller decision from the previous turn."
  ;; Reset EMA on first turn
  (when (= turn 0)
    (gptel-auto-workflow--reset-research-ema)
    (when (fboundp 'gptel-auto-workflow--load-active-strategy)
      (gptel-auto-workflow--load-active-strategy)))
  
  ;; Store state in global variables to avoid closure capture issues
  (setq gptel-auto-workflow--research-accumulated-findings accumulated-findings)
  (setq gptel-auto-workflow--research-total-tokens total-tokens)
  (setq gptel-auto-workflow--research-current-turn turn)
  (setq gptel-auto-workflow--research-prompt research-prompt)
  
  ;; Load controller with beta parameterization
  (setq gptel-auto-workflow--research-controller-config (gptel-auto-workflow--load-autotts-controller))
  
  ;; Update EMA alpha from controller config
  (setq gptel-auto-workflow--research-ema-alpha
        (or (plist-get gptel-auto-workflow--research-controller-config :ema-alpha) 0.5))
  (setq gptel-auto-workflow--research-ema-window
        (or (plist-get gptel-auto-workflow--research-controller-config :ema-window) 6))
  
   (let* ((controller-config gptel-auto-workflow--research-controller-config)
          (max-turns (or (plist-get controller-config :max-turns) 3))
          ;; Add turn count to controller config for decision function
          (controller-config-with-turn (plist-put controller-config :turn-count turn))
          (base-prompt (if (and accumulated-findings (> (length accumulated-findings) 0))
                           (gptel-auto-workflow--build-adaptive-followup-prompt
                            research-prompt accumulated-findings turn previous-decision)
                         research-prompt))
          (current-prompt (gptel-auto-workflow--inject-source-directive
                           base-prompt controller-config turn accumulated-findings))
           (turn-label (format "External research turn %d/%d" (1+ turn) max-turns)))
    (message "[autotts] Starting %s (beta=%.1f)" turn-label (or gptel-auto-workflow--research-beta 0.5))
    (gptel-benchmark-call-subagent
     'researcher turn-label current-prompt
     (lambda (result)
       (let* ((raw-findings (gptel-auto-workflow--normalize-response result))
              (has-external (gptel-auto-workflow--research-has-external-content-p raw-findings))
              ;; Handle timeout/error
              (timeout-p (and (not has-external) 
                              gptel-auto-workflow--research-accumulated-findings 
                              (> (length gptel-auto-workflow--research-accumulated-findings) 0)))
               (research-error-p (and (not timeout-p)
                                      (gptel-auto-workflow--research-error-p raw-findings)))
               ;; ─── Failure Classification ───
               ;; Classify WHY research failed so controller can adapt
               ;; Returns symbol: timeout, no-external-content, quota-exhausted, error-response, empty-response, success
               (failure-reason
                (cond
                 (timeout-p 'timeout)
                 ((and raw-findings (string-match-p "\\`Error:.*timed out" raw-findings))
                  'timeout)
                 ((and raw-findings (string-match-p "quota\\|rate.?limit\\|429\\|exhausted" raw-findings))
                  'quota-exhausted)
                 ((and raw-findings (string-match-p "\\`Error:" raw-findings))
                  'error-response)
                 ((or (null raw-findings) (string-empty-p raw-findings) (< (length raw-findings) 50))
                  'empty-response)
                 ((not has-external)
                  'no-external-content)
                 (t 'success)))
               ;; ─── End Failure Classification ───
               (effective-findings (cond
                                    (timeout-p
                                     (message "[autotts] Turn %d timeout, using accumulated findings" (1+ turn))
                                     (or gptel-auto-workflow--research-accumulated-findings ""))
                                    (research-error-p
                                     (gptel-auto-workflow--local-research-patterns))
                                    (t (or raw-findings ""))))
               (findings-hash (sha1 (or raw-findings "")))
              (strategy (or (and (boundp 'gptel-auto-workflow--active-strategy)
                                 gptel-auto-workflow--active-strategy)
                            "default"))
              ;; Calculate confidence and update EMA
               (turn-confidence (if timeout-p
                                   (gptel-auto-workflow--estimate-confidence
                                    (or gptel-auto-workflow--research-accumulated-findings ""))
                                 (gptel-auto-workflow--estimate-confidence (or raw-findings ""))))
              (ema-conf (gptel-auto-workflow--update-research-ema turn-confidence))
              (ema-delta (gptel-auto-workflow--research-ema-delta))
              ;; Token tracking
               (turn-tokens (if timeout-p 0 (/ (length (or raw-findings "")) 4)))
              (cumulative-tokens (+ (or gptel-auto-workflow--research-total-tokens 0) turn-tokens))
              ;; Merge findings
              (merged-findings (if (and gptel-auto-workflow--research-accumulated-findings 
                                        (> (length gptel-auto-workflow--research-accumulated-findings) 0))
                                   (concat gptel-auto-workflow--research-accumulated-findings 
                                           "\n\n---\n\n" effective-findings)
                                 effective-findings))
              ;; Controller decision with EMA-enhanced config + doom loop detection
               (controller-decision (if timeout-p
                                        'timeout
                                      (gptel-auto-workflow--controller-decide-with-doom-check
                                        controller-config-with-turn (length merged-findings) merged-findings))))
          ;; Record execution trace with failure classification
          (gptel-auto-workflow--record-research-trace
           turn
           (list :decision controller-decision
                 :confidence turn-confidence
                 :ema-conf ema-conf
                 :ema-delta ema-delta
                  :output-length (length (or raw-findings ""))
                 :tokens-used turn-tokens
                 :findings-quality (if timeout-p 0.0 turn-confidence)
                 :failure-reason failure-reason))
         ;; Log turn
         (gptel-auto-workflow--log-research-step
          'search
          (list :query (format "turn-%d" turn)
                :output-length (length (or raw-findings ""))
                :cumulative-tokens cumulative-tokens
                :ema-conf ema-conf
                :ema-delta ema-delta)
          turn-confidence)
         (message "[autotts] Turn %d result: %d chars, conf=%.2f, EMA=%.2f, delta=%.2f, decision=%s"
                   (1+ turn) (length (or raw-findings "")) turn-confidence ema-conf ema-delta controller-decision)
         
         ;; Check controller decision
         (cond
          ;; TIMEOUT: Return accumulated findings
          ((eq controller-decision 'timeout)
           (message "[autotts] Controller TIMEOUT after turn %d, returning accumulated findings"
                    (1+ turn))
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision turn-confidence cumulative-tokens callback))
          ;; STOP: We have good findings
          ((eq controller-decision 'stop)
           (message "[autotts] Controller STOP after turn %d (EMA confidence stabilized)"
                    (1+ turn))
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision turn-confidence cumulative-tokens callback))
          ;; CUT: Over budget
          ((eq controller-decision 'cut)
           (message "[autotts] Controller CUT after turn %d (budget exceeded)"
                    (1+ turn))
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision turn-confidence cumulative-tokens callback))
          ;; WIDEN: Open parallel branches (multi-branch pool)
          ((eq controller-decision 'widen)
           (message "[autotts] Controller WIDEN after turn %d (opening parallel branches)"
                    (1+ turn))
           (gptel-auto-workflow--branch-pool-add
            (or strategy "default") merged-findings cumulative-tokens)
           ;; Guard: ensure callback fires only once (WIDEN creates parallel branches)
           (let* ((widen-cb-fired nil)
                  (widen-once-cb
                   (lambda (findings)
                     (unless widen-cb-fired
                       (setq widen-cb-fired t)
                       (funcall callback findings)))))
             (gptel-auto-workflow--branch-pool-widen
              gptel-auto-workflow--research-controller-config
              research-prompt widen-once-cb)
             ;; Continue current branch too if not at max turns
             (if (< turn (1- max-turns))
                 (gptel-auto-workflow--run-research-turn
                  research-prompt (1+ turn) widen-once-cb
                  merged-findings cumulative-tokens 'widen)
               (gptel-auto-workflow--finalize-research
                research-prompt merged-findings strategy findings-hash
                controller-decision turn-confidence cumulative-tokens
                widen-once-cb))))
          ;; BRANCH: Try alternate strategy (simple single-branch switch)
          ((eq controller-decision 'branch)
           (message "[autotts] Controller BRANCH after turn %d, trying alternate strategy"
                    (1+ turn))
           (let ((alt-strategy (if (string= strategy "own-repos-first")
                                   "deep-external"
                                 "own-repos-first")))
              (gptel-auto-workflow--run-research-turn
               (gptel-auto-workflow--format-research-strategy-prompt alt-strategy "branch-alternate")
               (1+ turn) callback merged-findings cumulative-tokens 'branch)))
          ;; CONTINUE: Keep going if not at max turns
          ((< turn (1- max-turns))
           (message "[autotts] Controller %s, proceeding to turn %d"
                    controller-decision (1+ turn))
           (gptel-auto-workflow--run-research-turn
            research-prompt (1+ turn) callback
            merged-findings cumulative-tokens controller-decision))
          ;; Max turns reached
          (t
           (message "[autotts] Max turns (%d) reached, returning accumulated findings"
                    max-turns)
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            'max-turns turn-confidence cumulative-tokens callback)))))
     ;; Alignment-aware timeout: own-repo sources get more time (they yield better results)
     ;; Base timeout scales with turn and source alignment
     (let* ((source-classification (when accumulated-findings
                                     (gptel-auto-workflow--classify-source
                                      "own-research" accumulated-findings)))
             (base-timeout 300)
             ;; Alignment multiplier: aligned=1.5x, neutral=1.0x, deviant=0.7x
             (alignment-factor (cond
                                ((eq source-classification 'aligned) 1.5)
                                ((eq source-classification 'deviant) 0.7)
                                (t 1.0))))
        (if (> turn 0)
            ;; Turn 1+: timeout scales with alignment only
            ;; (own-priority is <1 and would always reduce timeout if multiplied)
            (let ((timeout (max 180 (min 600 (* base-timeout alignment-factor)))))
             (when source-classification
               (message "[autotts] Source classification: %s -> timeout=%ds (factor=%.1f)"
                        source-classification timeout alignment-factor))
             timeout)
         ;; Turn 0: standard initial search timeout
          (max 300 base-timeout))))))

;; ─── Programmatic Source Scheduling ───

(defun gptel-auto-workflow--inject-source-directive (prompt controller-config turn accumulated-findings)
  "Inject PROGRAMMATIC source selection directive into PROMPT.
The controller actively selects which sources to search next, not just
advisory text.  Based on source classification and effectiveness data.
Returns modified prompt with source directive appended."
  (let* ((own-priority (or (plist-get controller-config :own-repo-priority) 0.7))
         (external-priority (or (plist-get controller-config :external-priority) 0.15))
         (classification (when accumulated-findings
                           (gptel-auto-workflow--classify-source
                            "own-research" accumulated-findings)))
         (own-score (gptel-auto-workflow--source-priority-score "own-repo"))
         (ext-score (gptel-auto-workflow--source-priority-score "external"))
         ;; Build directive based on controller state
         (directive
          (cond
           ;; Aligned + own repos effective → deep dive own repos
           ((and (eq classification 'aligned)
                 (> own-score 0.5))
            (format "SOURCE DIRECTIVE (controller-enforced):
MUST search your own GitHub repos FIRST: %s/%s/*
Then IF findings are insufficient, search 1-2 external sources.
Budget: %.0f%% own repos, %.0f%% external."
                    (or (getenv "GITHUB_USER") "davidwuchn")
                    (or (getenv "GITHUB_USER") "davidwuchn")
                    (* 100 own-priority) (* 100 external-priority)))
           ;; Deviant → switch sources aggressively
           ((eq classification 'deviant)
            (format "SOURCE DIRECTIVE (controller-enforced):
Previous sources DEVIANT — switch to NEW sources.
PROBE FIRST: Skim source titles/abstracts before deep-reading.
Search: external trending repos, arxiv, github explore.
Avoid: sources previously searched (they produced deviant results).
Priority: 100%% external. Budget: 60s per source probe, 120s for deep read if probe passes."))
           ;; Neutral → balanced approach
           ((>= turn 2)
            (format "SOURCE DIRECTIVE (controller-enforced):
Cross-reference: search complementary sources to earlier findings.
Own repos score: %.1f, External score: %.1f
Prioritize: %s"
                    own-score ext-score
                    (if (> own-score ext-score) "own repos" "external")))
           ;; Default first turn
           (t
            (format "SOURCE DIRECTIVE (controller-enforced):
Start with own repos: gh search repos davidwuchn
Followed by: 1-2 external references.
Budget: %.0f%% own repos, %.0f%% external."
                    (* 100 own-priority) (* 100 external-priority))))))
    (concat prompt "\n\n" directive)))

;; ─── End Programmatic Source Scheduling ───

(defun gptel-auto-workflow--build-adaptive-followup-prompt (base-prompt accumulated-findings turn
                                                               &optional previous-decision)
  "Build adaptive follow-up prompt with EMA-aware guidance.
BASE-PROMPT is the original research prompt.
PREVIOUS-DECISION is the controller decision from the previous turn."
  ;; ASSUMPTION: base-prompt is a non-empty string
  (unless (stringp base-prompt)
    (error "gptel-auto-workflow--build-adaptive-followup-prompt: base-prompt must be a string, got %S" base-prompt))
  ;; ASSUMPTION: turn is a non-negative integer
  (unless (and (integerp turn) (>= turn 0))
    (error "gptel-auto-workflow--build-adaptive-followup-prompt: turn must be a non-negative integer, got %S" turn))
  (let* ((ema-conf gptel-auto-workflow--research-ema-conf)
         (ema-delta (gptel-auto-workflow--research-ema-delta))
         (accumulated-findings (or accumulated-findings ""))
         (controller-guidance
          (cond
           ;; BRANCH: Previous approach was stagnant, try different angle
           ((eq previous-decision 'branch)
            (format "**Controller Decision: BRANCH**\nEMA confidence: %.2f (delta: %.2f)\nPrevious approach produced limited results. Try a DIFFERENT angle:\n- Search different sources (if you searched own repos, try external)\n- Look for alternative techniques or implementations\n- Explore a related but different topic\n- Focus on a specific sub-problem not yet covered"
                    ema-conf ema-delta))
           ;; CONTINUE: Previous findings were promising, dig deeper
           ((eq previous-decision 'continue)
            (format "**Controller Decision: CONTINUE**\nEMA confidence: %.2f (delta: %.2f)\nPrevious findings show promise but need more depth. Focus on:\n- Implementation details and concrete code examples\n- How techniques apply to our specific modules\n- Specific modules or functions that could be improved\n- Integration steps and potential pitfalls"
                    ema-conf ema-delta))
           ;; Default / first turn
           (t
            "**Continue researching.** Focus on gaps or new angles not covered above. Avoid repeating what was already found.")))
         (budget-guidance
          (if (> turn 1)
              (format "\n\n**Budget Note:** This is turn %d+. EMA confidence: %.2f. Be concise. Focus on highest-impact insights only."
                      (1+ turn) ema-conf)
            "")))
    (format "%s\n\n---\n\n**Previous findings (turn %d):**\n%s\n\n%s%s"
            base-prompt
            turn
            (truncate-string-to-width accumulated-findings 2000 nil nil "...")
            controller-guidance
            budget-guidance)))

(defun gptel-auto-workflow--finalize-research (prompt findings strategy hash 
                                                      controller-decision confidence tokens-used callback)
  "Finalize research session and invoke CALLBACK.
Saves trace, logs results, and digests findings."
  ;; Store raw research context
  (setq gptel-auto-workflow--current-research-context
        (list :strategy strategy
              :hash hash
              :findings findings
              :source "external"
              :ema-confidence gptel-auto-workflow--research-ema-conf
              :ema-delta (gptel-auto-workflow--research-ema-delta)
              :trace-log gptel-auto-workflow--research-trace-log
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
  (message "[auto-workflow] External research raw: %d chars (hash: %s, EMA=%.2f)"
           (length findings) (substring hash 0 8) gptel-auto-workflow--research-ema-conf)
  ;; Save research trace
  (gptel-auto-workflow--save-research-trace
   prompt findings strategy hash
   controller-decision confidence tokens-used)
  ;; Run AutoTTS benchmark if available
  (when (fboundp 'gptel-auto-workflow--benchmark-research-strategy)
    (gptel-auto-workflow--benchmark-research-strategy
     strategy "external-research"
     (lambda (result)
       (message "[benchmark] Research strategy '%s' scored: %.2f"
                strategy (or (plist-get result :quality) 0.0)))))
  ;; Digest and callback
  (gptel-auto-workflow--digest-research-findings
   findings
   (lambda (digested)
     ;; Write internal patterns to separate file
      (let ((internal-file (expand-file-name "var/tmp/internal-research.md"
                                             (or (when (fboundp 'gptel-auto-workflow--effective-project-root)
                                                   (gptel-auto-workflow--effective-project-root))
                                                 default-directory))))
       (make-directory (file-name-directory internal-file) t)
       (with-temp-file internal-file
         (insert (format "# Internal Code Analysis\n\n> Updated: %s\n> EMA Confidence: %.2f\n> Final Decision: %s\n\n%s"
                         (format-time-string "%Y-%m-%d %H:%M")
                         gptel-auto-workflow--research-ema-conf
                         controller-decision
                         digested))))
     ;; Always pass findings to callback
     (funcall callback digested))))

;; Source classification (aligned / neutral / deviant)
(defvar gptel-auto-workflow--source-effectiveness-table (make-hash-table :test 'equal)
  "Table tracking source effectiveness scores.")

(defun gptel-auto-workflow--extract-consensus (findings)
  "Extract consensus topics/techniques from FINDINGS.
Returns list of normalized keywords representing the main findings."
  (let ((text (downcase (or findings "")))
        (keywords '()))
    ;; Extract technique names (lines starting with ## or containing technique)
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (while (re-search-forward "## \\([^\n]+\\)" nil t)
        (push (downcase (string-trim (match-string 1))) keywords)))
    ;; Extract module names
    (when (string-match-p "gptel-" text)
      (push "gptel" keywords))
    (when (string-match-p "nucleus" text)
      (push "nucleus" keywords))
    (when (string-match-p "mementum" text)
      (push "mementum" keywords))
    ;; Deduplicate and return
    (delete-dups (nreverse keywords))))

(defun gptel-auto-workflow--source-agrees-p (source findings)
  "Check if SOURCE content agrees with FINDINGS consensus.
Returns non-nil if source mentions similar topics/techniques."
  (let ((source-text (downcase (or source "")))
        (consensus (gptel-auto-workflow--extract-consensus findings)))
    (and consensus
         (> (length consensus) 0)
         (cl-some (lambda (topic)
                   (string-match-p (regexp-quote topic) source-text))
                 consensus))))

(defun gptel-auto-workflow--source-deviant-p (source findings)
  "Check if SOURCE contradicts FINDINGS or produces low-quality output.
Returns non-nil if source is empty, error-like, or contradicts consensus."
  (let ((source-text (or source ""))
        (consensus (gptel-auto-workflow--extract-consensus findings)))
    (or (string-empty-p source-text)
        (< (length source-text) 200)
        (string-match-p "error\\|failed\\|timeout\\|unavailable" (downcase source-text))
        ;; Source mentions topics but none match consensus
        (and consensus
             (> (length consensus) 0)
             (not (cl-some (lambda (topic)
                            (string-match-p (regexp-quote topic) (downcase source-text)))
                          consensus))))))

(defun gptel-auto-workflow--classify-source (source findings)
  "Classify SOURCE based on agreement with FINDINGS consensus.
Returns symbol: aligned, neutral, or deviant."
  (cond
   ;; Empty or error → deviant
   ((or (null source) (string-empty-p (or source "")))
    'deviant)
   ;; Agrees with consensus → aligned
   ((gptel-auto-workflow--source-agrees-p source findings)
    'aligned)
   ;; Contradicts or low quality → deviant
   ((gptel-auto-workflow--source-deviant-p source findings)
    'deviant)
   ;; No clear signal → neutral
   (t 'neutral)))

(defun gptel-auto-workflow--update-source-effectiveness (source classification quality)
  "Update effectiveness score for SOURCE based on CLASSIFICATION and QUALITY."
  (let* ((current (gethash source gptel-auto-workflow--source-effectiveness-table
                          (list :aligned 0 :neutral 0 :deviant 0 :total-quality 0.0 :count 0)))
         (new-count (1+ (plist-get current :count)))
         (new-quality (+ (plist-get current :total-quality) quality)))
    (setq current (plist-put current (intern (concat ":" (symbol-name classification)))
                             (1+ (or (plist-get current (intern (concat ":" (symbol-name classification)))) 0))))
    (setq current (plist-put current :total-quality new-quality))
    (setq current (plist-put current :count new-count))
    (setq current (plist-put current :avg-quality (/ new-quality new-count)))
    (puthash source current gptel-auto-workflow--source-effectiveness-table)))

(defun gptel-auto-workflow--get-source-effectiveness (source)
  "Get effectiveness data for SOURCE.
Returns plist with :aligned :neutral :deviant :avg-quality."
  (or (gethash source gptel-auto-workflow--source-effectiveness-table)
      (list :aligned 0 :neutral 0 :deviant 0 :total-quality 0.0 :count 0)))

(defun gptel-auto-workflow--source-priority-score (source)
  "Calculate priority score for SOURCE based on effectiveness.
Higher score = more aligned and higher quality."
  (let ((stats (gptel-auto-workflow--get-source-effectiveness source)))
    (if (> (or (plist-get stats :count) 0) 0)
        (let ((aligned-ratio (/ (float (plist-get stats :aligned))
                               (plist-get stats :count)))
              (quality (or (plist-get stats :avg-quality) 0.0)))
          (+ (* aligned-ratio 0.7)    ;; 70% weight on alignment
             (* quality 0.3)))        ;; 30% weight on quality
      0.5)))                           ;; Default: neutral

;; Source scheduling and researcher skill integration

(defun gptel-auto-workflow--generate-source-priority-guidance ()
  "Generate source priority section for researcher skill.
Returns formatted string with source effectiveness data."
  (let ((sources '())
        (guidance "## Source Effectiveness (AutoTTS Tracking)\n\n"))
    ;; Collect all tracked sources
    (cl-flet ((collect-source (source stats)
               (push (cons source stats) sources)))
      (maphash #'collect-source gptel-auto-workflow--source-effectiveness-table))
    ;; Sort by priority score
    (setq sources (sort sources
                       (lambda (a b)
                         (> (gptel-auto-workflow--source-priority-score (car a))
                            (gptel-auto-workflow--source-priority-score (car b))))))
    ;; Format top sources
    (if sources
        (progn
          (setq guidance (concat guidance "Sources ranked by effectiveness (aligned ratio + quality):\n\n"))
          (dolist (entry (cl-subseq sources 0 (min 10 (length sources))))
            (let* ((source (car entry))
                   (stats (cdr entry))
                   (score (gptel-auto-workflow--source-priority-score source))
                   (aligned (plist-get stats :aligned))
                   (neutral (plist-get stats :neutral))
                   (deviant (plist-get stats :deviant))
                   (total (+ aligned neutral deviant))
                   (quality (or (plist-get stats :avg-quality) 0.0)))
              (setq guidance
                    (concat guidance
                            (format "- **%s**: score=%.2f (aligned:%d/%d, quality:%.2f)\n"
                                    source score aligned total quality)))))
          (setq guidance (concat guidance "\n### Source Scheduling Guidance\n\n"))
          (setq guidance (concat guidance "- **HIGH PRIORITY** (score > 0.7): Focus research here first\n"))
          (setq guidance (concat guidance "- **MEDIUM PRIORITY** (score 0.3-0.7): Check if new content available\n"))
          (setq guidance (concat guidance "- **LOW PRIORITY** (score < 0.3): Skip unless specifically relevant\n"))
          (setq guidance (concat guidance "\n**Strategy**: Start with highest-scoring sources, allocate more turns to aligned sources.\n")))
      (setq guidance (concat guidance "*No source effectiveness data yet. Using default priorities.*\n")))
    guidance))

;; Beta auto-tuning

(defun gptel-auto-workflow--auto-tune-beta (topic &optional min-traces)
  "Automatically tune beta for TOPIC based on cached traces.
Requires at least MIN-TRACES (default: 20) cached traces."
  (let* ((min-required (or min-traces 20))
         (traces (when (fboundp 'gptel-auto-workflow--get-cached-traces)
                  (gptel-auto-workflow--get-cached-traces topic))))
    (if (and traces (>= (length traces) min-required))
        (progn
          (message "[autotts] Auto-tuning beta for '%s' (%d traces)..." topic (length traces))
          (let* ((result (when (fboundp 'gptel-auto-workflow--sweep-beta-offline)
                          (gptel-auto-workflow--sweep-beta-offline topic '(0.0 0.25 0.5 0.75 1.0))))
                 (best-beta (when result (plist-get result :best-beta))))
            (when best-beta
              (setq gptel-auto-workflow--research-beta best-beta)
              (message "[autotts] Auto-tuned beta for '%s' to %.2f" topic best-beta)
              best-beta)))
      (message "[autotts] Not enough traces for '%s' (%d/%d), using default beta=%.2f"
               topic (or (length traces) 0) min-required gptel-auto-workflow--research-beta)
      nil)))

;; Source scheduling in controller

(defun gptel-auto-workflow--apply-source-priority-to-prompt (prompt &optional _findings)
  "Enhance PROMPT with source priority scheduling.
If FINDINGS provided, classifies sources and adds scheduling guidance."
  (let* ((prompt (or prompt ""))
         (source-guidance (gptel-auto-workflow--generate-source-priority-guidance)))
    (if (> (hash-table-count gptel-auto-workflow--source-effectiveness-table) 0)
        (format "%s\n\n%s" prompt source-guidance)
      prompt)))

;; Persist learned parameters across runs

(defvar gptel-auto-workflow--research-params-file
  (gptel-auto-workflow--autotts-file "var/tmp/research-params.el")
  "File to persist learned research parameters.")

(defun gptel-auto-workflow--save-research-params ()
  "Save current research parameters to disk."
  (let ((params (list :beta gptel-auto-workflow--research-beta
                     :ema-alpha gptel-auto-workflow--research-ema-alpha
                     :ema-window gptel-auto-workflow--research-ema-window
                     :source-table gptel-auto-workflow--source-effectiveness-table
                     :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
    (make-directory (file-name-directory gptel-auto-workflow--research-params-file) t)
    (with-temp-file gptel-auto-workflow--research-params-file
      (prin1 params (current-buffer)))
    (message "[autotts] Saved research params (beta=%.2f)" gptel-auto-workflow--research-beta)))

(defun gptel-auto-workflow--load-research-params ()
  "Load research parameters from disk.
Also populates source effectiveness table from historical traces if empty."
  (when (file-exists-p gptel-auto-workflow--research-params-file)
    (condition-case err
        (let ((params (with-temp-buffer
                       (insert-file-contents gptel-auto-workflow--research-params-file)
                       (read (current-buffer)))))
          (setq gptel-auto-workflow--research-beta (or (plist-get params :beta) 0.5))
          (setq gptel-auto-workflow--research-ema-alpha (or (plist-get params :ema-alpha) 0.5))
          (setq gptel-auto-workflow--research-ema-window (or (plist-get params :ema-window) 6))
          (when (plist-get params :source-table)
            (setq gptel-auto-workflow--source-effectiveness-table (plist-get params :source-table)))
          (message "[autotts] Loaded research params (beta=%.2f, %d sources)"
                   gptel-auto-workflow--research-beta
                   (hash-table-count gptel-auto-workflow--source-effectiveness-table)))
      (error
       (message "[autotts] Failed to load research params: %s" err))))
  ;; Populate from historical traces even when params file does not exist yet.
  (when (and (= (hash-table-count gptel-auto-workflow--source-effectiveness-table) 0)
             (fboundp 'gptel-auto-workflow--load-research-traces))
    (let ((traces (gptel-auto-workflow--load-research-traces)))
      (dolist (trace traces)
        (let* ((source (or (plist-get trace :source) "unknown"))
               (quality (or (plist-get trace :quality)
                            (plist-get trace :confidence)
                            0.5))
               (classification (cond ((> quality 0.6) 'aligned)
                                     ((< quality 0.3) 'deviant)
                                     (t 'neutral))))
          (gptel-auto-workflow--update-source-effectiveness
           source classification quality))))))

;; Initialize on load
(gptel-auto-workflow--load-research-params)

(provide 'strategic-daemon-functions)
;;; strategic-daemon-functions.el ends here
