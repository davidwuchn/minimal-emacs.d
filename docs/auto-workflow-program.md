# Auto-Workflow Program

> Human-editable objectives for autonomous overnight optimization.
> Edit this file to change what the agent works on.

## Current Baselines

From latest experiment runs (`var/tmp/experiments/2026-03-25/results.tsv`):

| Target | Eight Keys | Code Quality | Weakest Key | Status |
|--------|------------|--------------|-------------|--------|
| `gptel-ext-retry.el` | 0.40 | 0.50 → 1.00 | σ Specificity | Needs work |
| `gptel-ext-context.el` | (pending) | (pending) | - | New target |
| `gptel-tools-code.el` | (pending) | (pending) | - | New target |

**Note**: Code quality improved (0.50 → 1.00) from extracting error patterns into named constants, but Eight Keys score unchanged. Need mutations that affect signal patterns.

## Targets

Files to optimize (one per line, relative to project root):

```
lisp/modules/gptel-ext-retry.el
lisp/modules/gptel-ext-context.el
lisp/modules/gptel-tools-code.el
```

## Success Criteria

| Criterion | Threshold | Weight |
|-----------|-----------|--------|
| Eight Keys overall | >= 5% improvement | 50% |
| Code quality | >= 10% improvement | 30% |
| Tests pass | 100% | 20% |

**Combined Score** = 0.5 × Eight Keys + 0.5 × Code Quality

Decision: Keep if combined improves, discard if tie/decline.

## Constraints

### Immutable Files (never modify)

```
early-init.el
pre-early-init.el
lisp/eca-security.el
lisp/modules/gptel-ext-security.el
lisp/modules/gptel-ext-tool-confirm.el
lisp/modules/gptel-ext-tool-permits.el
lisp/modules/gptel-sandbox.el
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

- [ ] Performance (startup time, memory)
- [x] Code clarity (readability, maintainability)
- [x] Both equally weighted

## Mutation Strategy

Agent-driven: Read git history + optimization skills to generate hypotheses.

Allowed mutation types:
- [x] caching
- [x] lazy-init
- [x] simplification
- [ ] parallel-processing (experimental)

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

### Failed Patterns

| Pattern | Issue | Lesson |
|---------|-------|--------|
| No hypothesis stated | Grader 2/6 fail | Always state hypothesis first |
| Generic docstrings | No Eight Keys improvement | Need signal patterns in code |
| Error output | Executor failed to find file | Specify full paths |

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
| `gptel-ext-retry.el` | `retry.md` | 0.50 | caching, lazy-init, simplification |
| `gptel-ext-context.el` | `context.md` | 0.50 | caching, lazy-init, simplification |
| `gptel-tools-code.el` | `code.md` | 0.50 | caching, lazy-init, simplification |

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
1. **retry.el**: Add adaptive retry ordering based on historical success (φ Vitality)
2. **context.el**: Lazy-load context templates (λ Efficiency)
3. **code.el**: Cache parsed code structures (caching)

---

## Reference: Experiment Pipeline

```
gptel-auto-workflow-run-sync
  → worktree (optimize/{target}-{hostname}-exp{N})
  → analyzer (detect patterns)
  → executor (make changes)
  → grader (6/6 quality check)
  → benchmark (Eight Keys score)
  → code-quality (docstring coverage)
  → comparator (LLM decides keep/discard)
  → TSV log
  → push to optimize/* (NOT main)
```

**Safety**: All changes go to `optimize/*` branches. Human reviews before merging to main.