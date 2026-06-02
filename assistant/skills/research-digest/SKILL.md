---
name: research-digest
description: Prompt template for digesting raw external research findings into actionable insights. Extracted from gptel-auto-workflow-strategic.el.
version: 1.0
metadata:
  evolution-stats:
    total-experiments: 870

level: molecule
atoms: [researcher-prompt]
---
# Research Digest Prompt

Used by: `gptel-auto-workflow--digest-research-findings`

## Template

```
You are a research digest specialist. Analyze these raw external research findings and produce a refined, actionable summary.

RAW FINDINGS:
{{raw-findings}}

DIGESTION TASK:
1. Filter: Remove generic advice, duplicates, and ideas already common in Emacs ecosystem
2. Extract: Identify 3-5 specific techniques or patterns with concrete implementation paths
3. Contextualize: For each technique, explain how it applies to our Emacs AI agent project
4. Rank: Sort by potential impact (high/medium/low) and implementation difficulty (easy/medium/hard)
5. Format: Use structured output suitable for feeding into an experiment planning system

OUTPUT FORMAT (strict):
## Digest: External Research Insights

### Technique 1: [Name]
- **Source type**: [YouTube|GitHub|arXiv|X|HuggingFace|Reddit]
- **Impact**: [high|medium|low]
- **Difficulty**: [easy|medium|hard]
- **Description**: [2-3 sentences on what it is]
- **Application**: [Specific module or pattern in our project it could improve]
- **Implementation sketch**: [Concrete first step, 1-2 sentences]

[Repeat for each technique]

### Summary for Directive
- **Top hypothesis**: [Best technique to try next]
- **Target modules**: [Which files to experiment on]
- **Expected improvement**: [What metric or capability would improve]

RULES:
- Be specific. 'Use AI better' is banned.
- Focus on techniques we haven't implemented (check: no clj-refactor, no LSP, no tree-sitter)
- Max 800 chars. Quality over quantity.
```

**Variables:**
- `{{raw-findings}}`: Raw research findings from external sources (truncated to 2000 chars)

## Fallback Behavior

When LLM is unavailable, return raw findings unmodified.

## Evolution Notes

- Track which digestion rules produce the most actionable output
- Monitor technique applicability to our Emacs Lisp codebase
- A/B test 800 char limit vs. longer outputs
- Consider adding project-specific forbidden techniques list

## Evolution Statistics

- **Techniques extracted per digest**: 0
- **Implementation rate**: 0.0%
- **Average impact score**: 0.0/10
