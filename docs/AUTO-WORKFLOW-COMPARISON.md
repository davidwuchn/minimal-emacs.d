# Auto-Workflow Comparison: Claude Code CLI KAIROS vs Emacs AI Code

> Comprehensive architectural comparison of autonomous agent systems.

## Executive Summary

| System | Claude Code KAIROS | Emacs Auto-Workflow |
|--------|-------------------|---------------------|
| **Primary Purpose** | Scheduled task execution (cron) | Autonomous optimization pipeline |
| **Autonomy Level** | Session-scoped reminders | Full LLM-driven optimization cycle |
| **Decision Making** | User-specified schedules | LLM selects targets, validates quality |
| **Memory** | `scheduled_tasks.json` + session | Mementum (git-based knowledge) |
| **Coordination** | Coordinator + Workers | RunAgent subagents |
| **Quality Metrics** | Basic telemetry | Eight Keys scoring + trend analysis |

---

## What KAIROS Actually Is

### KAIROS = Scheduled Task System (Not "Auto-Workflow")

**Source:** `src/tools/ScheduleCronTool/` and `src/utils/cronScheduler.ts`

KAIROS is a **cron-based task scheduler** for:
- One-shot reminders ("remind me at 3pm")
- Recurring tasks ("check CI every 5 minutes")
- Session-scoped prompts (durable: false) vs disk-persistent (durable: true)

```typescript
// Their architecture:
SessionCronTask { id, cron, prompt, createdAt, recurring?, permanent? }
File: .claude/scheduled_tasks.json

// Features:
- 5-field cron expressions (local timezone)
- Deterministic jitter (avoid thundering herd at :00/:30)
- Scheduler lock (prevent double-fire across sessions)
- Auto-expire after 7 days (recurringMaxAgeMs)
- Missed task catch-up on startup
- GrowthBook feature flag gating
```

**Key Insight:** KAIROS is NOT autonomous optimization. It's a **reminder system**.

---

## What Our Auto-Workflow Is

### Full Autonomous Optimization Pipeline

**Source:** `lisp/modules/gptel-auto-workflow*.el`

Our system is a **complete autonomous agent** with:
- LLM-driven target selection
- Multi-phase optimization workflow
- Quality validation with Eight Keys
- Git worktree isolation
- Mementum memory system

```
Our Pipeline:
┌─────────────────────────────────────────────────────────┐
│  1. SYNC staging from main                               │
│  2. EYES gather context (git history, TODOs, research)   │
│  3. BRAIN decides targets (LLM analyzer)                 │
│  4. HANDS execute in worktree (optimize/* branch)        │
│  5. BRAIN validates (LLM grader: 6/6 pass)               │
│  6. BRAIN decides keep/discard (LLM comparator)          │
│  7. MERGE to staging → verify → push                     │
│  8. Human reviews → merges to main                       │
└─────────────────────────────────────────────────────────┘

Safety: NEVER touches main. All changes wait in staging.
```

---

## Architectural Comparison

### 1. Task Scheduling vs Autonomous Optimization

| Feature | KAIROS | Our Auto-Workflow |
|---------|--------|-------------------|
| **Trigger** | Cron schedule | LLM strategic selection + cron schedule |
| **Decision Making** | User specifies prompt | LLM decides targets, mutations, quality |
| **Execution** | Fire prompt on schedule | 6-phase optimization cycle |
| **Validation** | None (just fires) | Grader (6/6), comparator, tests |
| **Learning** | None | Mementum metabolization |

**Winner:** Our auto-workflow for optimization tasks; KAIROS for simple reminders.

### 2. Multi-Agent Coordination

| Feature | Coordinator Mode | Our RunAgent |
|---------|------------------|--------------|
| **Orchestrator** | "Coordinator" Claude | Main agent + nucleus |
| **Workers** | `Agent` tool spawns workers | RunAgent with subagent_type |
| **Communication** | `SendMessage` to continue | Callback-based async |
| **Context** | Workers can't see coordinator chat | Full context passing |
| **Specialization** | Generic workers | Specialized (explorer, executor, reviewer, researcher) |
| **Verification** | Separate verification worker | Pre-merge code review built-in |

**Winner:** Tie. Coordinator has richer prompt engineering guidance; we have specialized subagents.

### 3. Memory & Knowledge

| Feature | Claude Code | Our Mementum |
|---------|-------------|--------------|
| **Storage** | `.claude/scheduled_tasks.json` | Git-based (`mementum/`) |
| **Persistence** | Session-scoped or disk | Git commits ( survives restarts) |
| **Knowledge** | AutoDream (memory consolidation) | Knowledge pages + memories |
| **Recall** | File-based lookup | Git log + semantic grep |
| **Synthesis** | Consolidation on idle | AI proposes → human approves |
| **Decay** | 7-day auto-expire | φ decay + weekly maintenance |

**Winner:** Our Mementum is more sophisticated and git-integrated.

### 4. Quality & Metrics

| Feature | Claude Code | Our System |
|---------|-------------|------------|
| **Telemetry** | Basic event logging | Eight Keys scoring |
| **Quality Threshold** | None | Grader 6/6 pass required |
| **Trend Analysis** | Frustration detection | Historical comparison (TSV) |
| **LLM Evaluation** | None | Analyzer + Grader + Comparator |

**Winner:** Our quality system is far more sophisticated.

### 5. Safety & Isolation

| Feature | Claude Code | Our System |
|---------|-------------|------------|
| **Isolation** | Process-level | Git worktree per experiment |
| **Branch Protection** | None | NEVER touches main, staging buffer |
| **Conflicts** | None | Auto-resolve (--theirs) |
| **Rollback** | Manual | Git-based recovery |
| **Multi-Machine** | Scheduler lock | Hostname in branch name |

**Winner:** Our git worktree isolation is superior for code changes.

---

## Patterns Worth Adopting from KAIROS

### 1. Thundering Herd Prevention (Jitter)

```typescript
// KAIROS pattern:
recurringFrac: 0.1      // 10% of interval
recurringCapMs: 15min   // Max jitter
oneShotMaxMs: 90s       // One-shot early lead
oneShotMinuteMod: 30    // Only jitter :00/:30

// Deterministic per-task: parseInt(taskId.slice(0,8), 16) / 0x1_0000_0000
```

**Recommendation:** Add jitter to our cron wrapper to avoid API spikes when multiple machines fire simultaneously.

```elisp
;; Implementation sketch:
(defun gptel-auto-workflow--compute-jitter (task-id interval-seconds)
  "Compute deterministic jitter delay for task scheduling."
  (let ((frac (/ (string-to-number (substring task-id 0 8) 16)
                 4294967296.0)))  ; 0x1_0000_0000
    (min (* frac 0.1 interval-seconds)
         900)))  ; 15 min cap
```

### 2. Scheduler Lock (Multi-Session Coordination)

```typescript
// KAIROS: Only one session fires file-backed tasks
tryAcquireSchedulerLock() → isOwner = true/false
// Lock file: .claude/scheduler.lock with sessionId + PID
```

**Recommendation:** Add lock mechanism for multi-machine scenarios.

```elisp
;; Implementation sketch:
(defvar gptel-auto-workflow--scheduler-lock-file
  "var/tmp/auto-workflow.lock")

(defun gptel-auto-workflow--acquire-lock ()
  "Try to acquire scheduler lock. Returns non-nil if acquired."
  (let ((lock-content (format "%s-%d" (system-name) (emacs-pid))))
    (condition-case nil
        (with-temp-file gptel-auto-workflow--scheduler-lock-file
          (insert lock-content))
      (file-already-exists nil))))
```

### 3. Missed Task Catch-Up

```typescript
// KAIROS: One-shot tasks missed while closed are surfaced on startup
findMissedTasks(tasks, nowMs) → prompt user to run or discard
```

**Recommendation:** Add to our cron wrapper for scheduled runs missed while Emacs was closed.

### 4. Session vs Durable Tasks

```typescript
// KAIROS distinction:
durable: false  → session-only, dies with process
durable: true   → .claude/scheduled_tasks.json, survives restart
```

**Recommendation:** Add session-scoped tasks for quick reminders without file persistence.

---

## What Claude Code Has That We Don't

| Feature | Status | Priority |
|---------|--------|----------|
| `/loop` skill (recurring prompts) | Not implemented | Medium |
| `CronCreate/CronDelete/CronList` tools | Not implemented | Medium |
| Scheduler lock for multi-session | Not implemented | Low |
| AutoDream memory consolidation | Partial (mementum weekly) | Low |
| Undercover mode (identity hiding) | Not needed | N/A |

---

## What We Have That Claude Code Doesn't

| Feature | Status | Advantage |
|---------|--------|-----------|
| Autonomous optimization pipeline | Implemented | Full LLM decision cycle |
| Eight Keys quality scoring | Implemented | Objective quality metrics |
| Git worktree isolation | Implemented | Safe experimentation |
| Staging branch buffer | Implemented | Human review gate |
| Mementum knowledge system | Implemented | Git-based persistence |
| Specialized subagents | Implemented | Better task separation |
| Pre-merge code review | Implemented | Built-in reviewer |
| Periodic researcher | Implemented | Pattern discovery |
| Multi-machine branch naming | Implemented | Conflict prevention |
| TSV experiment logging | Implemented | Historical analysis |

---

## Detailed Feature Comparison

### KAIROS Core Components

| Component | File | Purpose |
|-----------|------|---------|
| `CronCreateTool` | `tools/ScheduleCronTool/CronCreateTool.ts` | Create scheduled task |
| `CronDeleteTool` | `tools/ScheduleCronTool/CronDeleteTool.ts` | Cancel scheduled task |
| `CronListTool` | `tools/ScheduleCronTool/CronListTool.ts` | List scheduled tasks |
| `cronScheduler` | `utils/cronScheduler.ts` | Tick loop + fire handler |
| `cronTasks` | `utils/cronTasks.ts` | Task persistence + jitter |
| `/loop` skill | `skills/bundled/loop.ts` | User-facing recurring prompt |
| `coordinatorMode` | `coordinator/coordinatorMode.ts` | Multi-worker orchestration |

### Our Core Components

| Component | File | Purpose |
|-----------|------|---------|
| `gptel-auto-workflow.el` | Main workflow orchestration | 6-phase optimization cycle |
| `gptel-auto-workflow-strategic.el` | LLM target selection | Analyzer-driven decisions |
| `gptel-auto-workflow-projects.el` | Multi-project support | Project-level isolation |
| `gptel-tools-agent.el` | RunAgent tool | Subagent delegation |
| `gptel-benchmark-grade.el` | Quality validation | Eight Keys scoring |
| `mementum/*.el` | Memory system | Knowledge persistence |

---

## Implementation Recommendations

### Medium Priority: Add Scheduled Task System

Create `nucleus/skills/bundled/scheduler.el`:

```elisp
;;; nucleus/skills/bundled/scheduler.el --- Scheduled task execution

(defun nucleus-schedule-create (cron prompt recurring)
  "Create a scheduled task.
CRON: 5-field expression (local timezone)
PROMPT: Text to execute
RECURRING: t for recurring, nil for one-shot
Returns: task-id")

(defun nucleus-schedule-delete (task-id)
  "Cancel a scheduled task by ID.")

(defun nucleus-schedule-list ()
  "List all scheduled tasks.")

(defun nucleus-scheduler-start ()
  "Start the scheduler tick loop (1s interval).")

(defun nucleus-scheduler-stop ()
  "Stop the scheduler.")
```

### Low Priority: Add Jitter

Modify `scripts/run-auto-workflow-cron.sh`:

```bash
# Add deterministic jitter based on hostname hash
HOSTNAME_HASH=$(echo "$(hostname)" | md5sum | cut -c1-8)
JITTER_SECONDS=$((HOSTNAME_HASH % 900))  # 0-15 min
sleep $JITTER_SECONDS
```

### Already Superior: Keep Our Advantages

1. **Auto-workflow pipeline** - Keep LLM-driven optimization
2. **Eight Keys scoring** - Maintain quality metrics
3. **Git worktree isolation** - Keep safe experimentation
4. **Mementum system** - Maintain git-based knowledge
5. **Staging buffer** - Keep human review gate

---

## Coordinator Mode Deep Comparison

### Their Coordinator Architecture

```typescript
// Claude Code coordinator mode:
You: Coordinator Claude
  → Agent tool spawns workers
  → workers execute autonomously
  → SendMessage continues workers
  → TaskStop stops workers
  → Workers report back via <task-notification>

Worker capabilities:
  - Bash, Read, Edit tools
  - MCP tools from configured servers
  - Skills via Skill tool

Key guidance:
  - Workers can't see coordinator chat
  - Coordinator MUST synthesize findings before delegation
  - Never write "based on your findings" (lazy)
  - Include file paths, line numbers, error messages
```

### Our RunAgent Architecture

```elisp
;; Our RunAgent system:
Main agent
  → RunAgent spawns subagents
  → subagent_type: explore, general, reviewer, executor
  → Callback-based async continuation
  → TodoWrite for task tracking

Subagent capabilities:
  - All nucleus tools (filtered by type)
  - Full context passing via prompt
  - Specialized by task type

Key differences:
  - We have specialized subagents (explorer vs executor)
  - Callback-based vs notification-based
  - No explicit "synthesize" guidance (implicit in prompt)
```

### Coordinator Prompts Worth Adopting

Their coordinator system prompt has excellent guidance:

1. **Synthesize before delegate**: "Read findings. Identify the approach. Then write a prompt that proves you understood."
2. **Specific context**: "Include file paths, line numbers, error messages"
3. **Verification mindset**: "Prove the code works, don't just confirm it exists"
4. **Continue vs spawn decision**: "High overlap → continue. Low overlap → spawn fresh."

**Recommendation:** Add similar guidance to our RunAgent prompt.

---

## Summary

### Key Insight

**KAIROS ≠ Autonomous Optimization**

KAIROS is a **scheduled reminder system**. Our auto-workflow is a **full autonomous optimization pipeline**.

They serve different purposes:
- KAIROS: "Remind me to check PRs every 30 minutes"
- Our auto-workflow: "Find the best targets to optimize, experiment, validate, and merge"

### Action Items

| Action | Priority | Rationale |
|--------|----------|-----------|
| Add scheduled task system | Medium | User-facing feature |
| Add jitter to cron wrapper | Low | Thundering herd prevention |
| Add scheduler lock | Low | Multi-machine coordination |
| Add coordinator guidance | Low | Improve RunAgent prompts |
| Document our advantages | High | Already superior |

### Final Verdict

**For autonomous code optimization: Our system wins.**

**For scheduled reminders: KAIROS has a nice user-facing `/loop` skill.**

We should:
1. Keep and enhance our autonomous optimization pipeline
2. Consider adding a scheduled task skill for reminders
3. Adopt jitter pattern for multi-machine scenarios
4. Borrow coordinator prompt guidance for RunAgent

---

*Generated: 2026-04-02*
*Comparison: Claude Code CLI KAIROS vs Emacs Auto-Workflow*