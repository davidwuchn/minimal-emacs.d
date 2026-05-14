(defun gptel-auto-workflow--run-research-turn (research-prompt turn callback 
                                                       &optional accumulated-findings total-tokens previous-decision)
  "Run a single research TURN with controller checkpoint.
RESEARCH-PROMPT is the prompt for this turn.
TURN is the turn number (0-indexed).
CALLBACK receives final digested findings.
ACCUMULATED-FINDINGS is findings from previous turns.
TOTAL-TOKENS tracks cumulative token usage across turns.
PREVIOUS-DECISION is the controller decision from the previous turn (for adaptive prompts).
AutoTTS: Controller decides after each turn whether to STOP, CONTINUE, or BRANCH."
  ;; Store state in global variables to avoid closure capture issues
  ;; in daemon environments where lexical-binding may not work properly
  (setq gptel-auto-workflow--research-accumulated-findings accumulated-findings)
  (setq gptel-auto-workflow--research-total-tokens total-tokens)
  (setq gptel-auto-workflow--research-controller-config (gptel-auto-workflow--load-autotts-controller))
  (let* ((controller-config gptel-auto-workflow--research-controller-config)
         (max-turns gptel-auto-workflow-max-research-turns)
         (current-prompt (if (and accumulated-findings (> (length accumulated-findings) 0))
                             (gptel-auto-workflow--build-adaptive-followup-prompt
                              research-prompt accumulated-findings turn previous-decision)
                           research-prompt))
         (turn-label (format "External research turn %d/%d" (1+ turn) max-turns)))
    (message "[autotts] Starting %s" turn-label)
    (gptel-benchmark-call-subagent
     'researcher turn-label current-prompt
     (lambda (result)
       (let* ((raw-findings (gptel-auto-workflow--normalize-response result))
              (has-external (gptel-auto-workflow--research-has-external-content-p raw-findings))
              ;; Handle timeout/error: if result is empty and we have accumulated findings, return them
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
              (confidence (if timeout-p
                              (gptel-auto-workflow--estimate-confidence 
                               gptel-auto-workflow--research-accumulated-findings)
                            (gptel-auto-workflow--estimate-confidence raw-findings)))
              (turn-tokens (if timeout-p 0 (/ (length raw-findings) 4)))
              (cumulative-tokens (+ (or gptel-auto-workflow--research-total-tokens 0) turn-tokens))
              ;; Merge with accumulated findings
              (merged-findings (if (and gptel-auto-workflow--research-accumulated-findings 
                                        (> (length gptel-auto-workflow--research-accumulated-findings) 0))
                                   (concat gptel-auto-workflow--research-accumulated-findings 
                                           "\n\n---\n\n" effective-findings)
                                 effective-findings))
              ;; Controller decision based on merged state
              (controller-decision (if timeout-p
                                       'timeout
                                     (gptel-auto-workflow--controller-decide-research-flow
                                      gptel-auto-workflow--research-controller-config (length merged-findings) merged-findings)))))
         ;; Log this turn as a step
         (gptel-auto-workflow--log-research-step
          'search
          (list :query (format "turn-%d" turn)
                :output-length (length raw-findings)
                :cumulative-tokens cumulative-tokens)
          confidence)
         (message "[autotts] Turn %d result: %d chars, confidence=%.2f, decision=%s, cumulative-tokens=%d"
                  (1+ turn) (length raw-findings) confidence controller-decision cumulative-tokens)
         ;; Check controller decision
         (cond
          ;; TIMEOUT: Return accumulated findings
          ((eq controller-decision 'timeout)
           (message "[autotts] Controller TIMEOUT after turn %d, returning accumulated findings"
                    (1+ turn))
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision confidence cumulative-tokens callback))
          ;; STOP: We have good findings, return them
          ((eq controller-decision 'stop)
           (message "[autotts] Controller STOP after turn %d (confidence=%.2f)"
                    (1+ turn) confidence)
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision confidence cumulative-tokens callback))
          ;; CUT: Over budget, return what we have
          ((eq controller-decision 'cut)
           (message "[autotts] Controller CUT after turn %d (budget exceeded)"
                    (1+ turn))
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision confidence cumulative-tokens callback))
          ;; BRANCH: Try alternate strategy in parallel
          ((eq controller-decision 'branch)
           (message "[autotts] Controller BRANCH after turn %d, trying alternate strategy"
                    (1+ turn))
           (let ((alt-strategy (if (string= strategy "own-repos-first")
                                   "deep-external"
                                 "own-repos-first")))
             ;; Run alternate strategy and merge results
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
            'max-turns confidence cumulative-tokens callback)))))
     ;; Timeout: 300s for turn 1+ (web fetches need more time), 180s for turn 0
     (if (> turn 0) 300 180)))
(defun gptel-auto-workflow--build-adaptive-followup-prompt (base-prompt accumulated-findings turn 
                                                               &optional previous-decision)
  "Build adaptive follow-up prompt for turn TURN with ACCUMULATED-FINDINGS.
BASE-PROMPT is the original research prompt.
PREVIOUS-DECISION is the controller decision from the previous turn.
Injects controller guidance to adapt researcher's strategy based on what happened."
  (let* ((controller-guidance 
          (cond
           ;; BRANCH: Previous approach was stagnant, try different angle
           ((eq previous-decision 'branch)
            "**Controller Decision: BRANCH**\nPrevious approach produced limited results. Try a DIFFERENT angle:\n- Search different sources (if you searched own repos, try external)\n- Look for alternative techniques or implementations\n- Explore a related but different topic\n- Focus on a specific sub-problem not yet covered")
           ;; CONTINUE: Previous findings were promising, dig deeper
           ((eq previous-decision 'continue)
            "**Controller Decision: CONTINUE**\nPrevious findings show promise but need more depth. Focus on:\n- Implementation details and concrete code examples\n- How techniques apply to our specific modules\n- Specific modules or functions that could be improved\n- Integration steps and potential pitfalls")
           ;; Default / first turn
           (t
            "**Continue researching.** Focus on gaps or new angles not covered above. Avoid repeating what was already found.")))
         (budget-guidance 
          (if (> turn 1)
              "\n\n**Budget Note:** This is turn 3+. Be concise. Focus on highest-impact insights only."
            "")))
    (format "%s\n\n---\n\n**Previous findings (turn %d):**\n%s\n\n%s%s"
            base-prompt
            turn
            (truncate-string-to-width accumulated-findings 2000 nil nil "...")
            controller-guidance
            budget-guidance)))
(defun gptel-auto-workflow--build-followup-prompt (base-prompt accumulated-findings turn)
  "Build follow-up prompt for turn TURN with ACCUMULATED-FINDINGS.
BASE-PROMPT is the original research prompt.
DEPRECATED: Use `gptel-auto-workflow--build-adaptive-followup-prompt' instead."
  (gptel-auto-workflow--build-adaptive-followup-prompt base-prompt accumulated-findings turn))
(defun gptel-auto-workflow--finalize-research (prompt findings strategy hash 
                                                      controller-decision confidence tokens-used callback)
  "Finalize research session and invoke CALLBACK with digested findings.
Saves trace, runs benchmark, and digests findings."
  ;; Store raw research context
  (setq gptel-auto-workflow--current-research-context
        (list :strategy strategy
              :hash hash
              :findings findings
              :source "external"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
  (message "[auto-workflow] External research raw: %d chars (hash: %s)"
           (length findings) (substring hash 0 8))
  ;; Save research trace for AutoTTS-style offline evaluation
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
     ;; Write internal patterns to separate file for DIRECTIVE.md
     (let ((internal-file (expand-file-name "var/tmp/internal-research.md"
                                            (gptel-auto-workflow--effective-project-root))))
       (make-directory (file-name-directory internal-file) t)
       (with-temp-file internal-file
         (insert (format "# Internal Code Analysis\n\n> Updated: %s\n\n%s"
                         (format-time-string "%Y-%m-%d %H:%M")
                          digested))))
      ;; Always pass findings to callback
      (funcall callback digested))))
