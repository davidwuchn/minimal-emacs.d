# Mementum State

> Last session: 2026-03-25

## Session Summary: Auto-Workflow Debugging

### Commits (11)

| Hash | Description |
|------|-------------|
| `ff20864` | λ Fix Eight Keys scoring: use actual code diff + commit message |
| `125298f` | λ Fix TSV logging: escape newlines/tabs |
| `f12accc` | 💡 Update TDD patterns with auto-workflow learnings |
| `15ea470` | ◈ Document auto-workflow branching rule |
| `d5f5700` | λ Fix auto-workflow: add working directory and target path to prompt |
| `a3f94d7` | λ Add gptel-auto-workflow-run-sync for cron |
| `0f0fa0b` | λ Remove auto-evolve, keep auto-workflow |
| `57ca7ce` | λ Add logging for auto-experiment agent output |
| `b153708` | λ Remove unused lite-executor agent |
| `2592957` | λ Fix auto-workflow: use executor agent + buffer-local timer state |
| `0af692a` | λ Fix auto-workflow: use lite-executor instead of code agent |

### Auto-Workflow Branching Rule (CRITICAL)

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

**Branch Format**: `optimize/{target-name}-{hostname}-exp{N}`

**Example**: `optimize/retry-imacpro.taila8bdd.ts.net-exp1`

**Flow**:
1. Auto-workflow creates worktree with optimize branch
2. Executor makes changes in worktree (isolated from main)
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main via PR

**Code Location**: `gptel-tools-agent.el:1134`
```elisp
(when gptel-auto-experiment-auto-push
  (magit-git-success "push" "origin" gptel-auto-workflow--current-branch))
```

**Why This Matters**:
- Prevents unreviewed AI changes on main
- Multiple machines can optimize same target without conflicts
- Human gate for quality control

### Eight Keys Scoring (FIXED 2026-03-25)

**Problem**: Eight Keys score rarely improved even when code quality improved.

**Root Causes**:
1. `plist-get` called on wrong structure (key-def instead of cdr key-def)
2. Inner quotes in signals/anti-patterns lists broke plist structure
3. Git diff --stat doesn't contain signal patterns

**Fixes**:
1. Fixed `plist-get` to use `(cdr key-def)` for proper plist access
2. Removed inner quotes from signal/anti-pattern definitions
3. Changed scoring input from `git diff --stat` to commit message + code diff

**Verified**: phi-vitality now scores 0.80 when patterns present (was always 0.50)

### Known Issue: Executor Model Doesn't Always Follow Instructions

**Problem**: `qwen3.5-plus` sometimes ignores the instruction to write "HYPOTHESIS:" at start.

**Impact**: Grader can't extract hypothesis → experiment discarded

**Example Output**:
```
✓ gptel-ext-retry.el: Enhanced fractal Clarity by adding explicit...
```

**Expected Output**:
```
HYPOTHESIS: Adding explicit sections will improve clarity.
✓ gptel-ext-retry.el: Enhanced fractal Clarity...
```

**Workaround**: Grader has fallback, but hypothesis detection fails.

**Possible Solutions**:
1. Switch to better model for executor (gpt-4o, claude)
2. Add stronger prompt emphasis
3. Post-process output to extract hypothesis from summary

### Issues Fixed

#### 1. Async/Sync Incompatibility (FIXED)

**Problem**: `gptel-auto-workflow-run` returns immediately when called via `emacsclient -e`

**Solution**: Added `gptel-auto-workflow-run-sync` using `accept-process-output` to keep event loop alive

#### 2. Executor Returns Nil/Error (FIXED)

**Root Cause**: Prompt didn't specify working directory or full target path

**Solution**: 
- Added "Working Directory" section to prompt
- Added "Target File (full path)" section to prompt
- Fixed `gptel-auto-workflow--project-root` to always return expanded path

**Verified**: Executor now successfully finds and edits target files

### How to Test Auto-Workflow

```elisp
;; Start daemon
emacs --daemon

;; Test single experiment (interactive)
emacsclient -e "
(let ((gptel-auto-workflow-targets '(\"lisp/modules/gptel-ext-retry.el\"))
      (gptel-auto-experiment-max-per-target 1))
  (gptel-auto-workflow-run-sync))"

;; Check results
cat var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv
```

### Verified Working

```
grader/* tests: 52/52 ✓
executor agent: loaded ✓ (via assistant/agents/executor.md)
gptel backend: DashScope (coding.dashscope.aliyuncs.com)
```

## Suggested Hypothesis (from skill)
(Populated by metabolize after each night)

## Hypothesis Templates
- Add caching to {component} to reduce redundant {operation}
- Cache {result} to avoid recomputing {input}
- Memoize {function} for {scenario}
- Lazy initialize {resource} to defer {cost} until needed
- Defer {initialization} to first {usage}
- Wrap {variable} in lazy-{pattern} for on-demand init
- Simplify {logic} by removing {redundancy}
- Merge {path-a} and {path-b} into unified {path}
- Remove {unused} to reduce complexity
```

### Bugs Fixed

1. **Non-greedy regex issue**: `.+?` doesn't work well with newlines in Emacs regex
   - Solution: Use position-based substring extraction
2. **Program.md parsing**: `forward-line 2` wasn't enough to reach code block
   - Solution: Use `re-search-forward` to find ` ``` ` marker
3. **Mutations regex**: `[^ ]+` captured newlines
   - Solution: Use `[a-z-]+` for mutation names

### Tests Added

```
grader/eight-keys-weakest-excludes-overall         ✓
grader/eight-keys-weakest-returns-sorted           ✓
grader/eight-keys-weakest-with-signals-returns-list ✓
grader/format-weakest-keys-produces-string         ✓
grader/extract-mutation-templates-returns-list     ✓
```

---

## λ Summary

```
λ fix. Skills loaded but never used → now injected into prompt
λ fix. Non-greedy regex replaced with position-based extraction
λ fix. Program.md targets now load correctly
λ target. Weakest Eight Keys guide hypothesis generation
λ template. 9 mutation templates extracted from 3 skills
λ test. 5 new tests for weakest/template functions
λ verify. Full prompt includes templates + suggested hypothesis
```

---

## Previous Session: Autonomous Research Agent Complete

### Commits (36)

| Hash | Description |
|------|-------------|
| `ca00465` | Autonomous Research Agent knowledge page |
| `a1cece4` | 74/74 tests, timeout memory |
| `77aad9e` | Experiment timeout handling memory |
| `0e7bf41` | Experiment timeout default tests |
| `98447af` | Final session summary with 30 commits |
| `49b0adf` | Comparator integrated into decision |
| `c99b3ae` | Decision uses comparator subagent |
| `baf136a` | Executor, reviewer, explorer, registry tests |
| `fac41c7` | Docs updated |
| `e14f837` | 68/68 tests |
| `3678b79` | Analyzer, comparator, workflow tests |
| ... | (see git log for full list) |

### Pipeline Verified

```
worktree → analyzer → executor → grader → benchmark → code-quality → comparator → decide
```

### Subagents Integrated

| Subagent | Function | Used In |
|----------|----------|---------|
| analyzer | `gptel-benchmark-analyze` | `gptel-auto-experiment-analyze` |
| grader | `gptel-benchmark-grade` | `gptel-auto-experiment-grade` |
| comparator | `gptel-benchmark-compare` | `gptel-auto-experiment-decide` |

### Test Status

```
grader/*               42/42 ✓
retry/*                32/32 ✓
Combined (grader+retry): 74/74 ✓
Full suite: 1056/1138 (test isolation issues)
```

### Knowledge Created

- `mementum/knowledge/autonomous-research-agent.md`
- `mementum/knowledge/tdd-patterns.md`
- `mementum/memories/experiment-timeout-handling.md`
- `mementum/memories/llm-degradation-detection.md`
- `mementum/memories/surgical-edits-nested-code.md`

### Cleaned Up

- Removed stale worktree: `optimize/retry-exp4`
- Deleted orphaned branches: `optimize/agent-exp1`, `optimize/retry-exp2`, `optimize/retry-exp4`

### Production Ready

```bash
# Install cron
./scripts/install-cron.sh

# Run manually
emacsclient -e '(gptel-auto-workflow-run)'

# View results
cat var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv

# Check logs
tail -f var/tmp/cron/auto-workflow.log
```

---

## λ Summary

```
λ complete. 36 commits, 74/74 tests, 3 subagents integrated
λ pipeline. worktree → analyzer → executor → grader → benchmark → code-quality → comparator → decide
λ decision. 70% grader + 30% code quality
λ detect. forbidden + missing_expected = degradation
λ clean. stale worktrees and branches removed
```
| `c99b3ae` | Decision uses comparator subagent when available |
| `baf136a` | Executor, reviewer, explorer, registry tests |
| `fac41c7` | Docs updated: code quality, decision logic, LLM degradation |
| `e14f837` | 68/68 tests with subagent integration |
| `3678b79` | Analyzer, comparator, workflow integration tests |
| `1a8f8be` | 61/61 tests verified |
| `2c0f8c8` | Summarize function tests |
| `e1cabdf` | Should-stop logic tests |
| `eb7b557` | TDD patterns knowledge page |
| `143f14c` | Complete session with TSV format and cron |
| `b3466ed` | 55/55 tests verified |
| `7d4f9df` | TSV log includes code_quality |
| `bf9f544` | Final session summary |
| `ce020a0` | Hypothesis extraction tests |
| `ad07e85` | 49/49 tests verified |
| `e4aef98` | Surgical-edits-nested-code memory |
| `b3a90b2` | Autonomous research agent complete |
| `974d33b` | Experiment workflow uses code quality |
| `108eba8` | Decision logic documented |
| `6131631` | Decision logic factors code quality |
| `70a84a1` | Session summary with test fixes |
| `1a69411` | Fix test isolation issues |
| `19e4077` | test-isolation-issue memory |
| `156f08d` | Fix vc-git-root batch mode |
| `117d4b3` | llm-degradation-detection memory |
| `065a0c0` | LLM degradation detection |
| `241b706` | TDD: code quality scoring |
| `781d368` | Restore balanced parens |
| `02bfa32` | Autonomous workflow verified working |

### Full Pipeline Working

```
gptel-auto-workflow-run
  → worktree ✓
  → analyzer (patterns) ✓
  → executor ✓
  → grader ✓
  → benchmark ✓
  → code-quality ✓
  → comparator ✓
  → decide ✓ (70% grader + 30% quality)
  → TSV log ✓ (with code_quality column)
```

### Subagent Integration

| Subagent | Function | Used In | Tested |
|----------|----------|---------|--------|
| grader | `gptel-benchmark-grade` | `gptel-auto-experiment-grade` | ✓ |
| analyzer | `gptel-benchmark-analyze` | `gptel-auto-experiment-analyze` | ✓ |
| comparator | `gptel-benchmark-compare` | `gptel-auto-experiment-decide` | ✓ |
| executor | `gptel-benchmark-execute` | (future) | ✓ |
| reviewer | `gptel-benchmark-review` | (future) | ✓ |
| explorer | `gptel-benchmark-explore` | (future) | ✓ |

### New Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark--code-quality-score` | Docstring coverage (0.0-1.0) |
| `gptel-benchmark--detect-llm-degradation` | Detect off-topic/repetition |
| `gptel-auto-experiment--code-quality-score` | Integration with auto-experiment |

### Test Status

```
grader/*               42/42 ✓
retry/*                32/32 ✓
Combined (grader+retry): 74/74 ✓
Full suite: 1056/1136 (test isolation issues remain)
```

### TSV Output Format

```
experiment_id  target  hypothesis  score_before  score_after  code_quality  delta  decision  ...
```

### Cron Schedule

```
2 AM  daily   - gptel-auto-workflow-run
4 AM  weekly  - gptel-mementum-weekly-job
5 AM  weekly  - gptel-benchmark-instincts-weekly-job
```

### Docs Updated

- `docs/auto-workflow.md` - decision logic, code quality, LLM degradation
- `INTRO.md` - pipeline overview, features table

---

## λ Summary

```
λ complete. autonomous research agent pipeline working
λ integrate. analyzer + grader + comparator subagents
λ improve. decision = 70% grader + 30% quality
λ detect. forbidden + missing_expected = degradation
λ learn. surgical edits > large replacements
λ verify. 72/72 tests pass
λ document. docs updated with all changes
```
gptel-auto-workflow-run
  → worktree ✓
  → executor subagent ✓
  → grader subagent ✓
  → benchmark ✓
  → code-quality score ✓
  → decision ✓ (70% grader + 30% quality)
  → TSV log ✓ (with code_quality column)
```

### New Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark--code-quality-score` | Docstring coverage (0.0-1.0) |
| `gptel-benchmark--detect-llm-degradation` | Detect off-topic/repetition |
| `gptel-auto-experiment--code-quality-score` | Integration with auto-experiment |

### Test Status

```
grader/*               40/40 ✓
retry/*                32/32 ✓
Combined (grader+retry): 72/72 ✓
Full suite: 1048/1136 (test isolation issues remain)
```

### Subagent Integration

| Subagent | Function | Used In | Tested |
|----------|----------|---------|--------|
| grader | `gptel-benchmark-grade` | `gptel-auto-experiment-grade` | ✓ |
| analyzer | `gptel-benchmark-analyze` | `gptel-auto-experiment-analyze` | ✓ |
| comparator | `gptel-benchmark-compare` | `gptel-auto-experiment-decide` | ✓ |
| executor | `gptel-benchmark-execute` | (future) | ✓ |
| reviewer | `gptel-benchmark-review` | (future) | ✓ |
| explorer | `gptel-benchmark-explore` | (future) | ✓ |

### Workflow Functions

| Function | Purpose | Tested |
|----------|---------|--------|
| `gptel-auto-experiment-analyze` | Pattern analysis | ✓ |
| `gptel-auto-experiment-grade` | Quality grading | ✓ |
| `gptel-auto-experiment-decide` | Keep/discard decision | ✓ |
| `gptel-auto-experiment-should-stop-p` | Stop condition | ✓ |
| `gptel-auto-experiment--extract-hypothesis` | Parse hypothesis | ✓ |
| `gptel-auto-experiment--summarize` | Truncate text | ✓ |

### TSV Output Format

```
experiment_id	target	hypothesis	score_before	score_after	code_quality	delta	decision	duration	...
```

### Cron Schedule

```
2 AM  daily   - gptel-auto-workflow-run
4 AM  weekly  - gptel-mementum-weekly-job
5 AM  weekly  - gptel-benchmark-instincts-weekly-job
```

---

## λ Summary

```
λ complete. autonomous research agent pipeline working
λ improve. decision = 70% grader + 30% quality
λ detect. forbidden + missing_expected = degradation
λ learn. surgical edits > large replacements
λ verify. 55/55 tests pass
λ log. code_quality in TSV output
```
gptel-auto-workflow-run
  → worktree ✓
  → executor subagent ✓
  → grader subagent ✓
  → benchmark ✓
  → code-quality score ✓
  → decision ✓ (70% grader + 30% quality)
  → TSV log ✓
```

### New Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark--code-quality-score` | Docstring coverage (0.0-1.0) |
| `gptel-benchmark--detect-llm-degradation` | Detect off-topic/repetition |
| `gptel-auto-experiment--code-quality-score` | Integration with auto-experiment |

### Test Status

```
grader/*               23/23 ✓
retry/*                32/32 ✓
Combined (grader+retry): 55/55 ✓
Full suite: 1048/1113 (test isolation issues remain)
```

### Key Patterns Learned

1. **Surgical edits** - minimal changes preserve structure in nested code
2. **TDD** - test failures reveal logic gaps
3. **Decision logic** - 70% grader + 30% quality rewards docstrings

---

## λ Summary

```
λ complete. autonomous research agent pipeline working
λ improve. decision = 70% grader + 30% quality
λ detect. forbidden + missing_expected = degradation
λ learn. surgical edits > large replacements
λ verify. 51/51 tests pass
```