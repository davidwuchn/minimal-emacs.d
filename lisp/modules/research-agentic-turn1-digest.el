;; Research Digest: Agentic Patterns Turn 1/4
;; Generated from analysis of 5+ source modules

;; ## Technique 1: Inspection-Thrash Detection
;; - Impact: high — prevents infinite read loops that waste API calls
;; - Difficulty: medium — needs tool marker system (already in nucleus-tools)
;; - Description: Track consecutive read-only inspections on same file with
;;   file-size-aware threshold. Progressive warnings at 50%/75%/100% of
;;   threshold. Write tools reset the counter.
;; - Application: Already in gptel-ext-tool-sanitize.el (my/gptel--detect-inspection-thrash)
;; - Gap: No cross-session persistence. Agent can thrash across multiple
;;   experiments on same target.

;; ## Technique 2: Two-Level Timeout Architecture
;; - Impact: high — prevents both idle hangs and runaway sessions
;; - Difficulty: medium — needs timer management infrastructure (already in subagent)
;; - Description: Idle timeout rearms on each activity. Hard wallclock deadline
;;   from dispatch. Whichever fires first aborts the request with a descriptive
;;   error. Remaining-time calculation ensures hard deadline always wins.
;; - Application: Already in gptel-tools-agent-subagent.el
;; - Gap: No per-tool timeout customization. All tools share same idle timeout.

;; ## Technique 3: Provider Failover Chain with Blacklisting
;; - Impact: high — enables multi-provider resilience
;; - Difficulty: easy — infrastructure already exists
;; - Description: Rate-limited backends moved to end of fallback chain via
;;   demote. Persistent health tracking across runs via lambda-strike recording.
;;   Two-tier failover: transient errors advance without blacklisting; real
;;   rate limits permanently blacklist for current run.
;; - Application: Already in gptel-tools-agent-error.el
;; - Gap: No circuit breaker pattern. Repeated failover has linear backoff
;;   but no exponential backoff or jitter.

;; ## Technique 4: Pre-Grade Validation
;; - Impact: high — saves API costs on bad edits
;; - Difficulty: easy — pattern is fully implemented
;; - Description: Validate ALL modified files syntax before calling grader API.
;;   Teachable retry when validation fails with known pattern. Repeated focus
;;   detection skips grading if same symbol attempted multiple times.
;; - Application: Already in gptel-tools-agent-experiment-core.el
;; - Gap: No semantic validation. Only checks syntax, not runtime behavior.

;; ## Technique 5: FSM Registry with Context-Aware Selection
;; - Impact: medium — prevents wrong FSM in nested agent calls
;; - Difficulty: medium — needs bidirectional registry (already built)
;; - Description: Bidirectional FSM↔ID hashing enables O(1) lookup. Context
;;   ID matching prevents parent-child confusion. Most-recently-registered
;;   wins for child preference in nested scenarios.
;; - Application: Already in gptel-ext-fsm-utils.el
;; - Gap: No depth-based limit on nesting. Deep recursion could exhaust memory.

(provide 'research-agentic-turn1-digest)
;;; research-agentic-turn1-digest.el ends here
