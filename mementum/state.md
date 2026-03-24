# Mementum State

> Last session: 2026-03-24

## Session Summary: Prompt Enhancement with Skills + Weakest Keys

### Commits (3)

| Hash | Description |
|------|-------------|
| `8014387` | λ Prompt uses skills + weakest Eight Keys for focused hypotheses |
| `32b8aa1` | Δ Update ai-code submodule |
| `3120ee5` | λ Add tests for Eight Keys weakest functions |

### Problem Solved

**Critical Gap Found:** `gptel-auto-workflow--skills` was loaded in `gptel-auto-workflow-orient` but **never read** in prompt building. The function `gptel-auto-workflow-skill-suggest-hypothesis` existed but was **never called**.

### What Was Missing

- Per-key Eight Keys breakdown (only overall score shown)
- Weakest key identification
- Mutation templates from skills
- Suggested hypotheses from skills

### New Functions

| Function | Purpose |
|----------|---------|
| `gptel-benchmark-eight-keys-weakest` | Return N weakest keys from scores |
| `gptel-benchmark-eight-keys-weakest-with-signals` | Return weakest keys with improvement signals |
| `gptel-auto-workflow--extract-mutation-templates` | Extract hypothesis templates from mutation skills |
| `gptel-auto-workflow--format-weakest-keys` | Format weakest keys for prompt |

### Prompt Now Includes

```
## Weakest Keys (Priority Focus)
- π Synthesis: 38% (focus: connects findings, integrates knowledge, holistic view)
- φ Vitality: 45% (focus: builds on discoveries, adapts to new information, progressive improvement)

## Suggested Hypothesis (from skill)
(Populated by metabolize after each night)

## Hypothesis Templates
- "Add caching to {component} to reduce redundant {operation}"
- "Memoize {function} for {scenario}"
```

### Tests Added

```
grader/eight-keys-weakest-excludes-overall    ✓
grader/eight-keys-weakest-returns-sorted      ✓
grader/eight-keys-weakest-with-signals-returns-list  ✓
grader/format-weakest-keys-produces-string    ✓
```

### Docs Updated

- `docs/auto-workflow-program.md` - Added Priority Focus and Target-Specific Patterns sections

### Bug Fixed

Fixed quoted list extraction in `gptel-benchmark-eight-keys-weakest-with-signals`:
```elisp
(if (and (listp signals-raw) (eq (car signals-raw) 'quote))
    (cadr signals-raw)
  signals-raw)
```

---

## λ Summary

```
λ fix. Skills loaded but never used → now injected into prompt
λ target. Weakest Eight Keys guide hypothesis generation
λ template. Mutation skills provide hypothesis templates
λ test. 4 new tests for weakest functions
λ doc. Priority Focus + Target-Specific Patterns sections added
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