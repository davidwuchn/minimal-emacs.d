---
name: benchmark-llm-prompts
description: LLM prompt templates for benchmark improvement suggestions, results analysis, and knowledge synthesis. Extracted from gptel-benchmark-llm.el.
version: 1.0
evolve-script: evolve_llm_prompts.py
metadata:
  evolution-stats:
    total-experiments: 870

level: atom
---
# Benchmark LLM Prompts

Prompt templates used by the benchmark system when calling LLM backends for improvement generation.

## Improvement Suggestions Prompt

Used by: `gptel-benchmark--make-improvement-prompt`

```
You are an AI benchmark improvement system using Wu Xing principles.

Analyze the following anti-patterns detected in {{type}} {{name}} and suggest specific improvements.

## Anti-Patterns (相克)
{{anti-patterns}}

## Wu Xing Framework
- Wood (Operations): Action, execution
- Fire (Intelligence): Learning, adaptation
- Earth (Control): Constraints, resources
- Metal (Coordination): Structure, protocols
- Water (Identity): Purpose, direction

For each anti-pattern:
1. Identify the affected element
2. Apply the controlling element (相克 remedy)
3. Suggest a specific, actionable improvement

Format your response as JSON:
```json
{
  "improvements": [
    {"element": "wood", "action": "specific action", "rationale": "why this helps"}
  ]
}
```
```

**Variables:**
- `{{type}}`: 'skill' or 'workflow'
- `{{name}}`: Name of the skill/workflow
- `{{anti-patterns}}`: List of detected anti-patterns with element and symptom

## Results Analysis Prompt

Used by: `gptel-benchmark--make-analysis-prompt`

```
Analyze these benchmark results for {{type}} {{name}}:

{{results}}

Provide:
1. Overall assessment
2. Key strengths
3. Areas for improvement
4. Recommended focus areas

Be concise and specific.
```

**Variables:**
- `{{type}}`: 'skill' or 'workflow'
- `{{name}}`: Name of the skill/workflow
- `{{results}}`: Benchmark results data

## Knowledge Synthesis Prompt

Used by: `gptel-benchmark--make-synthesis-prompt`

```
Synthesize the following memories into a knowledge page.

TOPIC: {{topic}}

REQUIREMENTS:
1. Minimum 50 lines of actual content
2. Concrete examples (code, tables, commands)
3. Actionable patterns (not just descriptions)
4. Cross-references to related topics
5. Return the full markdown page directly in your final response

IMPORTANT:
- Return the complete knowledge page inline, not a summary
- Do not describe what you would write; write the page itself
- Start with frontmatter and include the full document body

OUTPUT FORMAT:
---
title: [Title]
status: active
category: knowledge
tags: [tag1, tag2]
---

# [Title]

## [Section 1]

[Content with examples]

## [Section 2]

[Content with patterns]

## Related

- [Related topics]

---

MEMORIES TO SYNTHESIZE:

{{memories}}

---

Generate the complete knowledge page now. Start with the frontmatter and include ALL content. Do not truncate or summarize.
```

**Variables:**
- `{{topic}}`: Topic name for the knowledge page
- `{{memories}}`: List of memories to synthesize

## Fallback Suggestion Mappings

When LLM is unavailable, use these element-to-action mappings:

| Element | Action | Rationale |
|---------|--------|-----------|
| Wood | Reduce step count, simplify operations | Addresses {{pattern}} anti-pattern |
| Fire | Focus on one task at a time | Addresses {{pattern}} anti-pattern |
| Earth | Relax constraints, allow flexibility | Addresses {{pattern}} anti-pattern |
| Metal | Adapt protocols to context | Addresses {{pattern}} anti-pattern |
| Water | Clarify purpose and direction | Addresses {{pattern}} anti-pattern |

## Usage

```elisp
;; Load prompt template
(let ((skill (gptel-auto-workflow--load-skill-content "benchmark-llm-prompts")))
  (when skill
    ;; Extract specific prompt section
    (if (string-match "## Improvement Suggestions Prompt\\(.*?\\)## " skill)
        (match-string 1 skill))))
```

## Evolution Notes

- Track which prompt variations produce better JSON parsing rates
- Monitor anti-pattern detection accuracy per element
- A/B test synthesis prompt length vs. output quality

## Evolution Statistics

- **improvement_suggestions**: 0/0 successful
- **results_analysis**: 0/0 successful
- **knowledge_synthesis**: 0/0 successful
