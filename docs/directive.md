# Auto-Workflow Program

> LLM decides targets and strategies. We gather context and execute.
> Philosophy: LLM = Brain, We = Eyes + Hands

## Architecture

```
Target Selection (LLM decides):
1. We gather: git history, file sizes, TODOs, test results
2. LLM decides: which 3 files to optimize tonight
3. We execute: run experiments on LLM's choices

Decision Points (all LLM):
- Which targets? → Analyzer
- What mutations? → Analyzer + Executor
- Quality OK? → Grader
- Keep or discard? → Comparator (requires correctness-fix + strong-grade for ties)
```

**Static targets below are fallback only.** Primary: LLM strategic selection.

## Current Baselines

From latest experiment runs (updated 2026-04-16):

| Target | Eight Keys | Code Quality | Weakest Key | Status |
|--------|------------|--------------|-------------|--------|
| `gptel-tools-agent.el` | 0.40→0.75 | 0.50→0.93 | σ Specificity | Active |
| `gptel-agent-loop.el` | 0.50→0.88 | 0.50→0.92 | μ Directness | Active |
| `gptel-ext-context-cache.el` | 0.50→0.92 | 0.50→0.90 | τ Wisdom | Active |
| `gptel-sandbox.el` | 0.50→0.90 | 0.50→0.85 | π Synthesis | Active |
| `gptel-benchmark-core.el` | 0.40→0.80 | 0.50→0.93 | σ Specificity | Active |

**Note**: Backend fallback chain now includes moonshot/kimi-k2.6 as first fallback after MiniMax.

## Targets

Files to optimize (one per line, relative to project root):

```
lisp/modules/gptel-tools-agent.el
lisp/modules/gptel-agent-loop.el
lisp/modules/gptel-ext-context-cache.el
lisp/modules/gptel-sandbox.el
lisp/modules/gptel-benchmark-core.el
```

## Success Criteria

| Criterion | Threshold | Weight |
|-----------|-----------|--------|
| Eight Keys overall | >= 5% improvement | 50% |
| Code quality | >= 10% improvement | 30% |
| Tests pass | 100% | 20% |

**Combined Score** = 0.5 × Eight Keys + 0.5 × Code Quality

**Decision Gate**:
- Keep if combined score improves
- Tie: Keep ONLY if combined score improves AND quality gain >= threshold (default 0.05)
- Discard if decline or tie without sufficient quality gain

## Constraints

### Immutable Files (never modify)

```
early-init.el
pre-early-init.el
lisp/eca-security.el
lisp/modules/gptel-ext-security.el
lisp/modules/gptel-ext-tool-confirm.el
lisp/modules/gptel-ext-tool-permits.el
eca/**
mementum/**
var/elpa/**
```

### Time Budget

| Setting | Value |
|---------|-------|
| Per experiment | 15 minutes |
| Max per target | 10 experiments |
| Stop if no improvement after | 3 consecutive |

### Optimization Focus

- [x] Performance (startup time, memory)
- [x] Code clarity (readability, maintainability)
- [x] Both equally weighted

## Backend Fallback Chain

When MiniMax hits rate limits (429), auto-workflow automatically fails over:

| Order | Backend | Model | Purpose |
|-------|---------|-------|---------|
| 1 | **MiniMax** | `minimax-m2.7-highspeed` | Primary workhorse |
| 2 | **moonshot** | `kimi-k2.6` | First fallback |
| 3 | **DashScope** | `qwen3.6-plus` | Second fallback |
| 4 | **DeepSeek** | `deepseek-reasoner` | Third fallback |
| 5 | **CF-Gateway** | `@cf/moonshotai/kimi-k2.6` | Fourth fallback |
| 6 | **Gemini** | `gemini-3.1-pro-preview` | Last resort |

## Mutation Strategy

**LLM decides** based on target analysis. We don't prescribe.

The analyzer examines each target and recommends:
- Which mutation type fits best
- What hypothesis to test
- Expected improvement areas

Mutation skills in `mementum/knowledge/mutations/`:
- `caching.md` - Memoize, cache results
- `lazy-init.md` - Defer initialization
- `simplification.md` - Remove redundancy

LLM chooses based on code patterns, not our presets.

## Priority Focus

Each experiment targets the weakest Eight Keys. Include signal phrases in commits.

**See**: `mementum/knowledge/eight-keys-signals.md` for full signal phrase reference.

| Key | Weakest Score | Signal Phrases to Include |
|-----|---------------|---------------------------|
| Clarity | **0.40** | "explicit assumptions", "testable definitions" |
| φ Vitality | 0.50 | "builds on discoveries", "adapts to new information" |
| ε Purpose | - | "clear goals", "measurable outcomes" |
| τ Wisdom | - | "risks identified", "error prevention" |
| π Synthesis | - | "connects findings", "integrates knowledge" |
| μ Directness | - | Direct statements, no hedging |
| ∃ Truth | - | "evidence-based", "actual data" |
| ∀ Vigilance | - | "edge cases handled", "input validation" |

**Current Focus**: Clarity (0.40) - add `;; ASSUMPTION:` and `;; BEHAVIOR:` comments.

## What Works (from experiments)

### Successful Patterns

| Pattern | Example | Effect |
|---------|---------|--------|
| Extract constants | `my/gptel--transient-error-patterns` | Code quality +0.50 |
| Add docstrings | PRECONDITIONS, BEHAVIOR sections | Grader 6/6 pass |
| Named patterns | `my/gptel--rate-limit-patterns` | Testability |
| Nil guards | `(or value default)` patterns | Stability +0.10 |
| Helper extraction | DRY repeated logic | Clarity +0.20 |

### Failed Patterns

| Pattern | Issue | Lesson |
|---------|-------|--------|
| No hypothesis stated | Grader 2/6 fail | Always state hypothesis first |
| Generic docstrings | No Eight Keys improvement | Need signal patterns in code |
| Error output | Executor failed to find file | Specify full paths |
| Over-engineering | Complexity penalty | Keep changes minimal |

### Hypothesis Templates

From `mementum/knowledge/mutations/*.md`:

```
"Add caching to {component} to reduce redundant {operation}"
"Cache {result} to avoid recomputing {input}"
"Memoize {function} for {scenario}"
"Lazy initialize {resource} to defer {cost} until needed"
"Simplify {logic} by removing {redundancy}"
```

### Commit Message Template (includes signals)

```
✓ {file}: {brief description}

HYPOTHESIS: {what} will improve {key} because {why}.

SIGNALS:
- {signal phrase}: {how applied}
- {signal phrase}: {how applied}

EVIDENCE: Tests pass, {metrics}
```

**Example**:
```
✓ retry.el: Extract error patterns into constants

HYPOTHESIS: Named constants will improve Clarity by making
assumptions explicit and definitions testable.

SIGNALS:
- explicit assumptions: Error patterns now named
- testable definitions: Can grep for constants

EVIDENCE: Tests pass, byte-compile clean
```

## Target-Specific Skills

Each target has an optimization skill in `mementum/knowledge/optimization-skills/`:

| Target | Skill File | φ Baseline | Mutation Skills |
|--------|------------|------------|-----------------|
| `gptel-tools-agent.el` | `tools-agent.md` | 0.50 | caching, simplification, nil-guards |
| `gptel-agent-loop.el` | `agent-loop.md` | 0.50 | caching, lazy-init, simplification |
| `gptel-ext-context-cache.el` | `context-cache.md` | 0.50 | caching, simplification |
| `gptel-sandbox.el` | `sandbox.md` | 0.50 | simplification, nil-guards |
| `gptel-benchmark-core.el` | `benchmark-core.md` | 0.50 | caching, simplification |

Mutation skills provide hypothesis templates. These are injected into experiment prompts.

## Morning Review

### 1. Check Results

```bash
cat var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv | column -t -s $'\t'
```

Look for:
- `decision: kept` - experiments that improved combined score
- `code_quality: 1.00` - good docstring coverage
- `delta: +0.XX` - Eight Keys improvement

### 2. Review Kept Experiments

```bash
git branch -r 'origin/optimize/*'
git log origin/optimize/retry-$(hostname)-expN --oneline
```

### 3. Merge or Discard

```bash
# If satisfied, merge
git checkout main
git merge --squash origin/optimize/retry-$(hostname)-expN
git commit -m "✓ {description}"

# If not, delete
git push origin --delete optimize/retry-$(hostname)-expN
```

### 4. Update Skills

After merge, update `mementum/knowledge/optimization-skills/{target}.md`:

```markdown
## Successful Mutations

| Mutation | Success Rate | Avg Delta | Best Hypothesis |
|----------|-------------|-----------|-----------------|
| simplification | 1/1 | +0.10 | Extract constants |
```

### 5. Adjust Program

- Add new targets
- Remove targets that plateaued
- Adjust mutation weights based on success rates

## Next Night's Hypothesis

(Populated by metabolize after each night)

Current suggestions:
1. **gptel-tools-agent.el**: Extract repeated validation logic into helpers (μ Directness)
2. **gptel-agent-loop.el**: Cache continuation state to avoid recomputation (λ Efficiency)
3. **gptel-sandbox.el**: Simplify form parsing with better EOF handling (π Synthesis)

---

## Reference: Experiment Pipeline

```
gptel-auto-workflow-run-async
  → worktree (optimize/{target}-{hostname}-exp{N})
  → analyzer (detect patterns)
  → executor (make changes)
  → grader (6/6 quality check)
  → benchmark (Eight Keys score)
  → code-quality (docstring coverage)
  → reviewer (checks for blockers, max 2 retries)
  → comparator (LLM decides keep/discard)
  → TSV log
  → push to optimize/* (NOT main)
```

**Safety**: All changes go to `optimize/*` branches. Human reviews before merging to main.
