;;; strategic-daemon-functions.el --- AutoTTS-style research controller functions -*- lexical-binding: t; -*-
;;; Commentary:
;; AutoTTS integration for research controller.
;; Implements EMA momentum confidence, beta parameterization, and trend-based decisions.

;;; Code:

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

;; Execution trace recording
(defvar gptel-auto-workflow--research-trace-log nil
  "Log of detailed execution traces for each research turn.")

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
Uses gptel-auto-workflow--research-ema-alpha for smoothing."
  (let ((alpha gptel-auto-workflow--research-ema-alpha))
    (setq gptel-auto-workflow--research-ema-conf
          (+ (* (- 1.0 alpha) gptel-auto-workflow--research-ema-conf)
             (* alpha new-confidence)))
    (push gptel-auto-workflow--research-ema-conf 
          gptel-auto-workflow--research-ema-history)
    ;; Keep only recent history
    (when (> (length gptel-auto-workflow--research-ema-history)
             gptel-auto-workflow--research-ema-window)
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

(defun gptel-auto-workflow--load-autotts-controller ()
  "Load AutoTTS controller config with beta parameterization.
Returns plist with controller parameters."
  (let* ((beta (or gptel-auto-workflow--research-beta 0.5))
         (params (gptel-auto-workflow--research-beta-schedule beta))
         ;; Load statistical model if available
         (statistical-model (when (fboundp 'gptel-auto-workflow--load-statistical-model)
                             (gptel-auto-workflow--load-statistical-model))))
    (append params (list :statistical-model statistical-model
                         :beta beta))))

(defun gptel-auto-workflow--controller-decide-research-flow (controller-config output-length &optional output-text)
  "AutoTTS controller with EMA momentum gate.
Decides: stop, continue, branch, or cut.
Uses EMA trend analysis for momentum-aware stopping."
  (let* ((tokens-used (/ output-length 4))
         (max-tokens (or (plist-get controller-config :token-budget) 8000))
         (text (or output-text ""))
         (has-urls (string-match-p "https?://" text))
         (has-structure (string-match-p "## .*\\n" text))
         (has-code (string-match-p "```" text))
         (turn-count (or (plist-get controller-config :turn-count) 0))
         ;; EMA state
         (ema-conf gptel-auto-workflow--research-ema-conf)
         (ema-delta (gptel-auto-workflow--research-ema-delta))
         ;; Thresholds from beta schedule
         (stop-threshold (or (plist-get controller-config :stop-threshold) 0.65))
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
     ;; Over budget → cut (always check first)
     ((> tokens-used max-tokens)
      (message "[autotts] Controller: CUT (budget %d/%d)" tokens-used max-tokens)
      'cut)
     
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
           (< turn-count (or (plist-get controller-config :max-turns) 3)))
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
    (gptel-auto-workflow--reset-research-ema))
  
  ;; Store state in global variables to avoid closure capture issues
  (setq gptel-auto-workflow--research-accumulated-findings accumulated-findings)
  (setq gptel-auto-workflow--research-total-tokens total-tokens)
  
  ;; Load controller with beta parameterization
  (setq gptel-auto-workflow--research-controller-config (gptel-auto-workflow--load-autotts-controller))
  
  ;; Update EMA alpha from controller config
  (setq gptel-auto-workflow--research-ema-alpha
        (or (plist-get gptel-auto-workflow--research-controller-config :ema-alpha) 0.5))
  (setq gptel-auto-workflow--research-ema-window
        (or (plist-get gptel-auto-workflow--research-controller-config :ema-window) 6))
  
  (let* ((controller-config gptel-auto-workflow--research-controller-config)
         (max-turns (plist-get controller-config :max-turns))
         ;; Add turn count to controller config for decision function
         (controller-config-with-turn (plist-put controller-config :turn-count turn))
         (current-prompt (if (and accumulated-findings (> (length accumulated-findings) 0))
                             (gptel-auto-workflow--build-adaptive-followup-prompt
                              research-prompt accumulated-findings turn previous-decision)
                           research-prompt))
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
              (effective-findings (cond
                                   (timeout-p
                                    (message "[autotts] Turn %d timeout, using accumulated findings" (1+ turn))
                                    gptel-auto-workflow--research-accumulated-findings)
                                   (research-error-p
                                    (gptel-auto-workflow--local-research-patterns))
                                   (t raw-findings)))
              (findings-hash (sha1 raw-findings))
              (strategy (or (and (boundp 'gptel-auto-workflow--active-strategy)
                                 gptel-auto-workflow--active-strategy)
                            "default"))
              ;; Calculate confidence and update EMA
              (turn-confidence (if timeout-p
                                  (gptel-auto-workflow--estimate-confidence 
                                   gptel-auto-workflow--research-accumulated-findings)
                                (gptel-auto-workflow--estimate-confidence raw-findings)))
              (ema-conf (gptel-auto-workflow--update-research-ema turn-confidence))
              (ema-delta (gptel-auto-workflow--research-ema-delta))
              ;; Token tracking
              (turn-tokens (if timeout-p 0 (/ (length raw-findings) 4)))
              (cumulative-tokens (+ (or gptel-auto-workflow--research-total-tokens 0) turn-tokens))
              ;; Merge findings
              (merged-findings (if (and gptel-auto-workflow--research-accumulated-findings 
                                        (> (length gptel-auto-workflow--research-accumulated-findings) 0))
                                   (concat gptel-auto-workflow--research-accumulated-findings 
                                           "\n\n---\n\n" effective-findings)
                                 effective-findings))
              ;; Controller decision with EMA-enhanced config
              (controller-decision (if timeout-p
                                       'timeout
                                     (gptel-auto-workflow--controller-decide-research-flow
                                      controller-config-with-turn (length merged-findings) merged-findings))))
         ;; Record execution trace
         (gptel-auto-workflow--record-research-trace
          turn
          (list :decision controller-decision
                :confidence turn-confidence
                :ema-conf ema-conf
                :ema-delta ema-delta
                :output-length (length raw-findings)
                :tokens-used turn-tokens
                :findings-quality (if timeout-p 0.0 turn-confidence)))
         ;; Log turn
         (gptel-auto-workflow--log-research-step
          'search
          (list :query (format "turn-%d" turn)
                :output-length (length raw-findings)
                :cumulative-tokens cumulative-tokens
                :ema-conf ema-conf
                :ema-delta ema-delta)
          turn-confidence)
         (message "[autotts] Turn %d result: %d chars, conf=%.2f, EMA=%.2f, delta=%.2f, decision=%s"
                  (1+ turn) (length raw-findings) turn-confidence ema-conf ema-delta controller-decision)
         
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
          ;; BRANCH: Try alternate strategy
          ((eq controller-decision 'branch)
           (message "[autotts] Controller BRANCH after turn %d, trying alternate strategy"
                    (1+ turn))
           (let ((alt-strategy (if (string= strategy "own-repos-first")
                                   "deep-external"
                                 "own-repos-first")))
             (gptel-auto-workflow--run-research-turn
              (gptel-auto-workflow--format-research-strategy-prompt alt-strategy "branch-alternate")
              turn callback merged-findings cumulative-tokens)))
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
     ;; Timeout: 300s for turn 1+, 180s for turn 0
     (if (> turn 0) 300 180))))

(defun gptel-auto-workflow--build-adaptive-followup-prompt (base-prompt accumulated-findings turn 
                                                               &optional previous-decision)
  "Build adaptive follow-up prompt with EMA-aware guidance.
BASE-PROMPT is the original research prompt.
PREVIOUS-DECISION is the controller decision from the previous turn."
  (let* ((ema-conf gptel-auto-workflow--research-ema-conf)
         (ema-delta (gptel-auto-workflow--research-ema-delta))
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

(defun gptel-auto-workflow--build-followup-prompt (base-prompt accumulated-findings turn)
  "Build follow-up prompt for turn TURN.
DEPRECATED: Use `gptel-auto-workflow--build-adaptive-followup-prompt' instead."
  (gptel-auto-workflow--build-adaptive-followup-prompt base-prompt accumulated-findings turn))

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
                                            (when (fboundp 'gptel-auto-workflow--effective-project-root)
                                              (gptel-auto-workflow--effective-project-root)
                                              "/tmp"))))
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
    (plist-put current classification (1+ (plist-get current classification)))
    (plist-put current :total-quality new-quality)
    (plist-put current :count new-count)
    (plist-put current :avg-quality (/ new-quality new-count))
    (puthash source current gptel-auto-workflow--source-effectiveness-table)))

(defun gptel-auto-workflow--get-source-effectiveness (source)
  "Get effectiveness data for SOURCE.
Returns plist with :aligned :neutral :deviant :avg-quality."
  (or (gethash source gptel-auto-workflow--source-effectiveness-table)
      (list :aligned 0 :neutral 0 :deviant 0 :avg-quality 0.0)))

(defun gptel-auto-workflow--source-priority-score (source)
  "Calculate priority score for SOURCE based on effectiveness.
Higher score = more aligned and higher quality."
  (let ((stats (gptel-auto-workflow--get-source-effectiveness source)))
    (if (> (plist-get stats :count) 0)
        (let ((aligned-ratio (/ (float (plist-get stats :aligned))
                               (plist-get stats :count)))
              (quality (or (plist-get stats :avg-quality) 0.0)))
          (+ (* aligned-ratio 0.7)    ;; 70% weight on alignment
             (* quality 0.3)))        ;; 30% weight on quality
      0.5)))                           ;; Default: neutral

(provide 'strategic-daemon-functions)
;;; strategic-daemon-functions.el ends here
