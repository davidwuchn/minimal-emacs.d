# Reusing Benchmark System for AutoTTS-Style Evolution

## Insight

We already have a sophisticated benchmark infrastructure. Instead of building AutoTTS from scratch, **reuse the benchmark system as the AutoTTS evaluation engine**.

## What We Already Have

### Benchmark Infrastructure
- `gptel-benchmark-call-subagent` — Calls subagents with timeout/retries
- `gptel-auto-experiment-run` — Runs single experiments with scoring
- TSV results tracking — Records all experiments with metrics
- Eight Keys scoring — Evaluates output quality
- Strategy evaluation — Tests different prompt-building strategies

### How It Maps to AutoTTS

| AutoTTS Component | Our Benchmark Equivalent |
|---|---|
| **Replay Store** | Experiment TSVs (`var/tmp/experiments/*/results.tsv`) |
| **Trace Collection** | Subagent call logging (already in benchmark) |
| **Offline Evaluation** | Re-run experiment with different strategy, compare TSV |
| **Controller** | Prompt-building strategy (already have strategy harness) |
| **Metrics** | Eight Keys scores, keep rates, token counts |
| **Evolution Loop** | `meta-harness-proposer` + strategy evolution |

## Implementation: Research as Benchmark

### Step 1: Treat Research as Experiment

Each research session IS an experiment:
```
Experiment ID: research-20260513-064500
Target: "external-research"
Hypothesis: "Search {topic} with strategy {name}"
Backend: researcher subagent
Strategy: own-repos-first | deep-external | etc.
```

### Step 2: Score Research Output

Use Eight Keys to score research quality:
- **φ Vitality**: Does research find novel ideas? (not rehashed)
- **ε Purpose**: Does it address our actual pain points?
- **τ Wisdom**: Are sources credible and relevant?
- **π Synthesis**: Is output structured and actionable?
- **μ Directness**: Is it concise, not bloated?
- **∃ Truth**: Are URLs real and accessible?
- **∀ Vigilance**: Does it avoid generic advice?

### Step 3: Benchmark Different Strategies

Run N research sessions with different strategies:
```
Session 1: own-repos-first → Score: 0.7, Tokens: 3000
Session 2: deep-external → Score: 0.5, Tokens: 8000
Session 3: quick-own-only → Score: 0.4, Tokens: 1500
```

### Step 4: AutoTTS Controller = Best Strategy

The "controller" IS the strategy with best score/tokens ratio.
No need for separate Python controller — use existing strategy harness.

## Implementation Plan

### 1. Create `research-strategy` Experiment Type

Add to `gptel-tools-agent-prompt-build.el`:
```elisp
(defun gptel-auto-experiment-build-research-prompt (strategy topic)
  "Build prompt for research experiment with STRATEGY on TOPIC."
  (format "Research topic: %s\nStrategy: %s\n..." topic strategy))
```

### 2. Add Research to Benchmark Pipeline

In `run-pipeline.sh`:
```bash
# Instead of just running researcher, benchmark it
for strategy in own-repos-first deep-external quick-own-only; do
    run_research_benchmark "$strategy" "$topic"
done
# Pick best strategy based on results
```

### 3. Score Research with Eight Keys

Create `research-grader` skill:
```markdown
Grade research output on:
1. Novelty (not in our codebase already)
2. Actionability (specific techniques, not vague)
3. Source quality (credible, relevant)
4. Conciseness (no fluff)
5. Applicability (to Emacs Lisp)
```

### 4. Strategy Evolution = Benchmark Comparison

After N research sessions:
```python
# Compare strategies like we compare prompt-builders
results = load_research_results()
for strategy in ['own-repos-first', 'deep-external']:
    sessions = [r for r in results if r.strategy == strategy]
    score = avg(s.eight_keys_score for s in sessions)
    tokens = avg(s.tokens for s in sessions)
    efficiency = score / tokens
    
# Pick strategy with best efficiency
best = max(strategies, key=lambda s: s.efficiency)
```

### 5. Unified Evolution Hook

Replace separate AutoTTS + self-evolution with single benchmark evolution:
```elisp
(defun gptel-auto-workflow--unified-evolution ()
  "Run unified evolution using benchmark infrastructure."
  ;; 1. Load recent research experiments (from TSV)
  ;; 2. Score them with Eight Keys
  ;; 3. Compare strategies
  ;; 4. Evolve best strategy
  ;; 5. Update researcher prompt
  )
```

## Advantages

1. **Reuse existing code** — No new Python scripts needed
2. **Consistent metrics** — Eight Keys scores work for research too
3. **Proven infrastructure** — Benchmark system already handles timeouts, retries, scoring
4. **Simpler architecture** — One evolution loop, not two
5. **Better integration** — Research strategy evolution uses same pipeline as code evolution

## Files to Modify

1. `lisp/modules/gptel-benchmark-subagent.el` — Add researcher to benchmarkable agents
2. `lisp/modules/gptel-tools-agent-prompt-build.el` — Add research strategy prompt builder
3. `assistant/skills/researcher-prompt/SKILL.md` — Add strategy performance section
4. `scripts/run-pipeline.sh` — Add research benchmarking step

## Verification

After implementation:
```
Pipeline runs researcher with strategy A → scores it
Pipeline runs researcher with strategy B → scores it
Compares: A = 0.7 @ 3000 tokens, B = 0.5 @ 8000 tokens
Evolution: Pick A, update prompt
Next run: Uses strategy A
```
