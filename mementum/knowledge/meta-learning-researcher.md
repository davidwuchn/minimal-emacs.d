# Meta-Learning Researcher Architecture

## Status: active
## Updated: 2026-05-08
## Category: knowledge
## Tags: [meta-learning, researcher, self-evolution, auto-workflow]
## Related: mementum/knowledge/self-evolution.md, assistant/skills/researcher-prompt/SKILL.md

---

## Problem Statement

The external researcher subagent has a static prompt. It doesn't learn from:
- Which research topics led to kept experiments
- Which external sources produced actionable insights
- Which techniques worked vs. failed when implemented

**Goal:** Make the researcher self-evolve by correlating its outputs with experiment outcomes.

---

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Data Sources   │────▶│  Analysis Engine │────▶│  Skill Updater  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │                        │
         ▼                       ▼                        ▼
  ┌─────────────┐       ┌──────────────┐        ┌──────────────┐
  │ Git History │       │ Topic        │        │ Dynamic      │
  │ (870+ exp)  │       │ Performance  │        │ RESEARCHER.md│
  └─────────────┘       │ Rankings     │        └──────────────┘
  ┌─────────────┐       └──────────────┘               │
  │ Mementum    │              │                        ▼
  │ Memories    │              │                 ┌──────────────┐
  └─────────────┘              │                 │ Researcher   │
  ┌─────────────┐              │                 │ Subagent     │
  │ Results TSV │              │                 └──────────────┘
  │ (structured)│              │                        │
  └─────────────┘              ▼                        ▼
                        ┌──────────────┐        ┌──────────────┐
                        │ Feedback     │◄───────│ Experiments  │
                        │ Loop         │        │ (kept/discard)│
                        └──────────────┘        └──────────────┘
```

---

## Data Sources

### 1. Git History (Temporal)

Extract from `git log`:
- Experiment branch names: `optimize/<target>-<host>-<hash>-exp<N>`
- Merge commits (kept): `Merge optimize/... for verification`
- Abandoned branches (discarded): branches never merged
- Research-related commits: commits with researcher findings

**Format:**
```json
{
  "experiment_id": "cache-neopi5-r122426z53f9-exp1",
  "target": "gptel-ext-context-cache.el",
  "decision": "kept",
  "branch_hash": "r122426z53f9",
  "research_context": ["caching", "performance", "memoization"],
  "techniques_attempted": ["helper-extraction", "nil-guard"],
  "score_before": 0.40,
  "score_after": 0.41,
  "quality_delta": 0.03
}
```

### 2. Mementum Memories (Semantic)

Research-related memories tagged with:
- `research:` prefix in memory slug
- `insight-` prefix for successful patterns
- Content mentioning external sources

**Extraction:**
```bash
git grep -l "research\|external\|source\|technique" mementum/memories/
```

**Format:**
```json
{
  "memory_slug": "insight-researcher-all-forks",
  "date": "2026-05-08",
  "source_type": "repo-discovery",
  "techniques": ["gh-repo-list", "categorization"],
  "downstream_impact": {
    "experiments_enabled": 5,
    "experiments_kept": 2
  }
}
```

### 3. Results TSV (Ground Truth)

Structured experiment data:
```
experiment_id target hypothesis score_before score_after code_quality delta decision duration ...
```

**Correlatable fields:**
- `hypothesis` → contains research-inspired keywords
- `decision` → ground truth (kept/discarded)
- `score_after` → outcome quality
- `target` → which module was improved

---

## Analysis Engine

### Module 1: Topic Performance Analyzer

**Input:** Git history + Results TSV
**Output:** Topic → Performance mapping

```python
def analyze_topic_performance(experiments, lookback_days=30):
    """
    Returns:
    {
      "validation-guard": {
        "total": 45,
        "kept": 18,
        "success_rate": 0.40,
        "avg_quality_improvement": 0.08,
        "top_targets": ["gptel-sandbox.el", "gptel-agent-loop.el"]
      },
      "helper-extraction": {
        "total": 32,
        "kept": 5,
        "success_rate": 0.16,
        "avg_quality_improvement": 0.02,
        "top_targets": ["gptel-ext-context-cache.el"]
      }
    }
    """
```

**Keyword extraction from hypotheses:**
- Action verbs: Add, Fix, Remove, Prevent, Handle, Check, Validate, Ensure, Improve, Optimize, Refactor, Extract
- Target concepts: guard, validation, nil, callback, buffer, overlay, timer, cache, helper, error
- Technique patterns: `proper-list-p`, `listp`, `bound-and-true-p`, `consp`, `functionp`

### Module 2: Source Effectiveness Tracker

**Input:** Mementum memories + Research findings
**Output:** Source → Effectiveness mapping

```python
def analyze_source_effectiveness(memories, experiments):
    """
    Returns:
    {
      "github-davidwuchn-gptel": {
        "mentions": 12,
        "experiments_from_research": 8,
        "kept": 3,
        "success_rate": 0.375
      },
      "arxiv-meta-learning": {
        "mentions": 3,
        "experiments_from_research": 2,
        "kept": 0,
        "success_rate": 0.0
      }
    }
    """
```

### Module 3: Temporal Pattern Detector

**Input:** Time-series of experiments
**Output:** Trending topics, diminishing returns

```python
def detect_temporal_patterns(experiments):
    """
    Returns:
    {
      "emerging": ["buffer-live-p", "cleanup-overlay"],  # Recent high success
      "mature": ["nil-guard", "proper-list-p"],          # Consistent but saturated
      "declining": ["helper-extraction"],                # Recent low success
      "unexplored": ["async-process", "tree-sitter"]     # High potential, few attempts
    }
    """
```

---

## Skill Evolution

### Dynamic Prompt Sections

The researcher skill template has these variable sections:

```markdown
## Current Research Performance

- Overall research effectiveness: {{research-effectiveness}}%
- Topics ranked by downstream success:

{{topic-performance}}

## Mission

Search external sources for actionable techniques related to:
{{priority-topics}}

## Priority Projects to Monitor

{{project-priorities}}

## Anti-patterns (avoid)

{{avoid-patterns}}
```

### Generation Rules

1. **topic-performance**: Sort topics by `success_rate * avg_quality_improvement`
2. **priority-topics**: Include top 3 topics + 1 emerging + 1 unexplored
3. **project-priorities**: Weight projects by downstream keep rate
4. **avoid-patterns**: Include techniques with <10% success rate

---

## Trigger System

### Trigger 1: Pre-Research (Lightweight)

**When:** Before each research cycle
**What:** Read `research-topics.json` cache, update prompt variables
**Cost:** O(1) file read

### Trigger 2: Post-Batch (Full Analysis)

**When:** After N experiments complete (N=50 default)
**What:** Run full analysis pipeline, regenerate JSON, update skill
**Cost:** O(experiments) parsing

### Trigger 3: Threshold Alert

**When:** Keep rate drops below threshold (current: 14%)
**What:** Emergency re-analysis, shift topic priorities
**Cost:** Full analysis + skill rewrite

### Trigger 4: Research Memory Ingestion

**When:** New research memory created (`mementum-record-research`)
**What:** Incrementally update source-effectiveness.json
**Cost:** O(1) append

---

## Data Persistence

### File Structure

```
assistant/skills/researcher-prompt/
├── SKILL.md                          # Template with variables
├── scripts/
│   ├── evolve_researcher.py          # Main evolution script
│   └── analyze_research_outcomes.py  # Analysis engine
├── data/
│   ├── topic-performance.json        # Topic → stats
│   ├── source-effectiveness.json     # Source → stats
│   ├── technique-frequency.json      # Technique → stats
│   └── research-effectiveness.cache  # Quick-load cache
└── references/
    └── research-topics-history.tsv   # Time series
```

### JSON Schemas

**topic-performance.json:**
```json
{
  "version": "2026-05-08T20:32:00",
  "lookback_days": 30,
  "topics": {
    "validation-guard": {
      "total_experiments": 45,
      "kept": 18,
      "success_rate": 0.40,
      "avg_quality_delta": 0.08,
      "first_seen": "2026-04-01",
      "last_seen": "2026-05-08",
      "trend": "stable",
      "top_targets": ["gptel-sandbox.el", "gptel-agent-loop.el"],
      "related_sources": ["github-davidwuchn-gptel", "internal-pattern"]
    }
  }
}
```

**source-effectiveness.json:**
```json
{
  "version": "2026-05-08T20:32:00",
  "sources": {
    "github-davidwuchn-gptel": {
      "source_type": "github",
      "url": "https://github.com/davidwuchn/gptel",
      "mentions": 12,
      "techniques_suggested": ["async-callback", "backend-fallback"],
      "experiments_enabled": 8,
      "experiments_kept": 3,
      "success_rate": 0.375,
      "last_research_date": "2026-05-08"
    }
  }
}
```

---

## Implementation Plan

### Phase 1: Data Collection (Day 1)

1. **Create `analyze_research_outcomes.py`**
   - Parse all results.tsv files in `var/tmp/experiments/`
   - Extract keywords from hypotheses using NLP/tokenization
   - Correlate with git history (branch names, merge status)
   - Read mementum memories for research context

2. **Create data directory structure**
   - `assistant/skills/researcher-prompt/data/`
   - Initialize empty JSON files with schemas

3. **Backfill historical data**
   - Process all 870 experiments
   - Generate initial topic-performance.json
   - Generate initial source-effectiveness.json

### Phase 2: Analysis Engine (Day 2)

1. **Implement topic extraction**
   - Keyword matching from hypothesis text
   - Technique pattern detection (regex for known patterns)
   - Target module association

2. **Implement performance scoring**
   - Success rate per topic
   - Quality improvement per topic
   - Trend detection (improving/declining/stable)

3. **Implement source tracking**
   - Parse research memories for source URLs
   - Link sources to downstream experiments
   - Calculate source effectiveness

### Phase 3: Skill Evolution (Day 3)

1. **Rewrite `evolve_researcher.py`**
   - Load analysis JSON files
   - Generate dynamic markdown sections
   - Update SKILL.md template variables
   - Preserve human-edited sections

2. **Add variable substitution to elisp loader**
   - `gptel-auto-workflow--load-researcher-skill` reads JSON
   - Substitutes `{{variables}}` with live data
   - Caches for performance

3. **Create `gptel-auto-workflow--update-researcher-priorities`**
   - Elisp function called before research
   - Runs Python script if cache stale
   - Updates prompt with current priorities

### Phase 4: Integration (Day 4)

1. **Hook into research cycle**
   - Call update function before `gptel-auto-workflow--build-research-prompt`
   - Pass topic-performance to prompt builder

2. **Add to auto-workflow cron**
   - Run full analysis weekly (Sunday 03:00)
   - Run lightweight update before each research cycle

3. **Add verification tests**
   - Test JSON schema validity
   - Test skill generation produces valid markdown
   - Test variable substitution in elisp

### Phase 5: Feedback Loop (Day 5+)

1. **Measure impact**
   - Compare keep rate: research-enabled vs. non-research experiments
   - Track topic distribution over time
   - Monitor for topic saturation

2. **A/B test topic prioritization**
   - Randomly swap topic order for 10% of experiments
   - Measure if prioritized topics produce better outcomes

3. **Self-correcting thresholds**
   - Auto-adjust topic inclusion threshold based on success
   - Retire topics with <5% success after 20 attempts
   - Promote emerging topics with >30% success

---

## Questions Answered

### Q1: What data format should the meta-learning analysis produce?

**A:** Three JSON files:
1. `topic-performance.json` — Topic-level statistics with trends
2. `source-effectiveness.json` — Source-level effectiveness metrics
3. `technique-frequency.json` — Technique occurrence and success rates

Plus a rendered `RESEARCHER.md` with substituted variables.

### Q2: How should the researcher skill be updated?

**A:** Template variable substitution:
- SKILL.md contains `{{variable}}` placeholders
- Python analysis engine generates JSON data
- Elisp loader reads JSON and substitutes variables before building prompt
- Humans can still edit static sections; variables are dynamic

### Q3: What triggers the self-evolution?

**A:** Four triggers:
1. **Pre-research** (lightweight, O(1)) — read cache
2. **Post-batch** (full analysis, O(N)) — after 50 experiments
3. **Threshold alert** (emergency) — keep rate < 14%
4. **Memory ingestion** (incremental) — new research memory created

---

## Success Metrics

| Metric | Baseline | Target |
|--------|----------|--------|
| Research-enabled keep rate | 16% | 20% |
| Topic prioritization accuracy | — | 70% |
| Source effectiveness correlation | — | r > 0.5 |
| Time to adapt to new patterns | — | < 7 days |

---

## λ Principle

```
λ meta-learn(x).  research → experiment → measure → evolve → research
                  | ¬static_prompt(x) | dynamic(x) ∝ outcome(y)
                  | topic_priority ≡ success_rate * quality_gain
                  | source_quality ≡ downstream_kept / total_enabled
```

---

## Implementation Results

### Deployed: 2026-05-08

**Files Created:**
1. `assistant/skills/researcher-prompt/scripts/analyze_research_outcomes.py`
   - Parses all results.tsv files (870 experiments)
   - Extracts topics from hypotheses using keyword matching
   - Correlates with git history and mementum memories
   - Generates topic-performance.json, source-effectiveness.json, temporal-patterns.json

2. `assistant/skills/researcher-prompt/scripts/evolve_researcher.py`
   - Reads analysis JSON files
   - Generates dynamic SKILL.md with prioritized topics
   - Formats topic performance as markdown table
   - Identifies anti-patterns from low-success topics

3. `assistant/skills/researcher-prompt/data/`
   - `topic-performance.json` — 10 topics analyzed
   - `source-effectiveness.json` — 1 source tracked
   - `temporal-patterns.json` — Pattern classifications

**Elisp Integration:**
4. `gptel-auto-workflow--load-researcher-meta-learning()` — Reads JSON cache
5. `gptel-auto-workflow--substitute-researcher-variables()` — Replaces {{variables}} in skill template
6. `gptel-auto-workflow--format-topic-performance()` — Formats topics as markdown table
7. `gptel-auto-workflow--trigger-researcher-meta-learning()` — Four trigger types
8. `gptel-auto-workflow--maybe-trigger-researcher-evolution()` — Periodic check

**Key Findings from 870 Experiments:**
- **nil-safety**: 28.3% success (15/53) — TOP TOPIC
- **validation-guard**: 18.6% success (85/456)
- **performance**: 17.8% success (24/135)
- **helper-extraction**: 9.3% success (7/75) — ANTI-PATTERN
- **async**: 7.1% success (9/126) — ANTI-PATTERN
- **cleanup**: 5.9% success (3/51) — ANTI-PATTERN

**Updated SKILL.md:**
- Version bumped to 2.0
- Dynamic topic priorities based on actual success rates
- Anti-patterns section now data-driven
- Project priorities ranked by downstream success

---

## Next Steps

1. ✅ DONE: Implement `analyze_research_outcomes.py`
2. ✅ DONE: Backfill 870 experiments into topic-performance.json
3. ✅ DONE: Rewrite `evolve_researcher.py` with full analysis
4. ✅ DONE: Update elisp loader for variable substitution
5. 🔄 NEXT: Run A/B test for 100 experiments
6. 🔄 NEXT: Measure improvement in research-enabled keep rate
7. 🔄 NEXT: Add more source patterns (YouTube, arXiv, Reddit)
8. 🔄 NEXT: Implement incremental JSON updates for memory ingestion trigger
