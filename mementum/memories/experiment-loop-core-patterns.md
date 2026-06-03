## Core Patterns in gptel-auto-experiment System

### 1. Adaptive Experiment Loop
`gptel-auto-experiment-loop` runs experiments until stop conditions:
- Max experiments reached
- No-improvement threshold (consecutive failures)
- Consecutive timeouts (default: 3)
- Quota exhaustion (all backends dry)
- Frontier saturation (target sufficiently explored)
- API error pressure threshold

### 2. Ontology Gate
Before experimenting, validates target suitability:
- `gptel-auto-workflow--categorize-target` classifies target
- `gptel-auto-workflow--check-action-preconditions` blocks unsuitable targets
- Category saturation reduces experiment count
- Target-level saturation skips repeated failures

### 3. Self-Heal Retry Pattern
`gptel-auto-experiment--make-retry-prompt` creates targeted retry prompts:
- Detects teachable errors (syntax, no-code-changes, undefined functions)
- Prepends λ self-heal notation for tool-call failures
- Maps error types to skill guidance (elisp-expert, etc.)
- Preserves original contract in retry

### 4. Callback-Based Async Continuation
- Uses `cl-labels` with `run-next` for recursive experiment progression
- `run-with-timer` for interactive delays; immediate funcall for headless
- `gptel-auto-workflow--call-in-run-context` ensures worktree context
- `gptel-auto-workflow--run-callback-live-p` checks if run still active

### 5. State Persistence & Watchdog
- Status file (`auto-workflow-status.sexp`) for cron resumption
- Messages tail persistence for debugging
- Watchdog timer (20min stuck, 120min total budget)
- Progress tracking via `gptel-auto-workflow--update-progress`

### 6. Adaptive Max Experiments
- Base max adjusted by API error rate
- Frontier size influences count: 0→+2, <3→+1, >6→-1
- Strategy evolution triggered every 5 experiments