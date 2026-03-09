nucleus: skill_create
λ(skillName, userPrompt). skill.md → {{skillFilePath}}
format: [YAML_frontmatter + content]
frontmatter: [name:{{skillName}} | description:when_to_load (LLM_selection)]
content: [derived(userPrompt)]
template: ---\nname: X\ndescription: Y\n---\n\n[content]

---

# Skill Creator Workflow

Use this workflow to create or improve a skill without promising tooling the repo does not yet have.

## Goal

Produce a skill that:
- has accurate trigger metadata
- gives clear, reusable instructions
- stays lean enough to load reliably
- includes evals only when they help

## First: Find the Current Stage

Before doing anything else, identify where the user is in the lifecycle:

- **New skill** - they have an idea but no draft
- **Draft refinement** - they already have a `SKILL.md`
- **Eval and review** - they want to test or benchmark behavior
- **Description tuning** - the skill works, but triggering is weak
- **Lightweight collaboration** - they want to sketch or "vibe" before formalizing

Jump to the stage that helps most instead of forcing a full start-to-finish process every time.

## Communicate for the User in Front of You

Default to plain language.

- Use terms like "test prompt" and "review" freely.
- Use terms like `JSON`, `assertion`, or `benchmark` only when the user seems comfortable with them, or explain them briefly.
- Prefer quick concrete examples over abstract methodology.

If the user already sounds technical, be concise and direct.
If they do not, keep the workflow understandable without jargon.

## 1. Capture Intent

First extract what you can from the conversation itself.

Look for:
- the workflow the user is trying to capture
- tools or steps they already used
- corrections they made
- expected input/output shapes
- examples already present in the discussion

Only ask for the missing parts.

Clarify four things:

1. What should the skill help the model do?
2. When should it trigger?
3. What output shape should it produce?
4. Is the result objective enough to evaluate with test cases?

Use evals for deterministic tasks like transforms, extraction, or structured generation.
Skip hard assertions for subjective tasks like style, taste, or open-ended ideation.

If the user already has a draft skill, review it before asking broad questions.

## 2. Draft `SKILL.md`

Start with valid frontmatter:

```yaml
---
name: skill-name
description: >
  Use when the user asks for X, Y, or Z.
  Be specific about trigger conditions.
version: 1.0.0
---
```

Then write the body with these priorities:
- define the skill's job clearly
- explain the decision boundary for when to use it
- describe the procedure in concrete steps
- define output format only when it matters
- keep examples realistic and short

Prefer imperative instructions.
Explain why constraints exist.
Avoid ritual language that adds tokens without changing behavior.

If the user mainly wants help refining an existing draft, edit the draft first and only expand structure where the current file is actually weak.

## 3. Keep Structure Proportional

Default structure:

```text
skill-name/
├── SKILL.md
├── evals/
│   └── evals.json        # optional
├── scripts/              # optional
├── references/           # optional
└── assets/               # optional
```

Rules:
- `SKILL.md` is required
- `evals/` is optional
- add `scripts/` only for deterministic repeated work
- add `references/` only when large material should stay out of the main prompt
- do not force every skill to include every directory

## 4. Add Evals Only When Useful

If the skill is testable, create 2-3 realistic prompts in `evals/evals.json`.

Before running them, show the proposed prompts to the user and confirm they are representative enough. Keep this lightweight; a quick check is enough.

Use the repo's actual runner format:

```json
{
  "skill_name": "example-skill",
  "evals": [
    {
      "id": 1,
      "name": "basic-case",
      "prompt": "User task prompt",
      "expected_output": "What good output should accomplish",
      "files": [],
      "assertions": []
    }
  ]
}
```

Good eval prompts are:
- realistic
- varied in phrasing
- close to real user requests
- specific enough to expose failure modes

Good assertions are:
- objective
- descriptive
- cheap to run

Examples:

```json
[
  {
    "name": "contains_required_sections",
    "type": "check",
    "expected": ["summary", "recommendations"]
  },
  {
    "name": "valid_json_output",
    "type": "script",
    "command": "python -c 'import json; json.load(open(\"output.json\"))'"
  }
]
```

If the task is subjective, prefer human review notes over fake precision.

When useful, give each eval a short descriptive `name` so results are easier to scan later.

## 5. Run Evaluations

Organize results consistently. A good default workspace is:

```text
<skill-name>-workspace/
└── iteration-1/
    └── eval-1/
        ├── with_skill/
        └── baseline/
```

Do not promise viewers or automated grading that the repo does not currently provide.
Use the actual outputs, timing files, and benchmark data that exist.

Use the repo's actual runner:

```bash
python assistant/scripts/eval_runner.py \
  --skill ./assistant/skills/my-skill \
  --evals ./assistant/skills/my-skill/evals/evals.json \
  --output ./eval-results \
  --iteration 1
```

Baseline only:

```bash
python assistant/scripts/eval_runner.py \
  --evals ./assistant/skills/my-skill/evals/evals.json \
  --output ./eval-results \
  --baseline-only
```

Current runner behavior to remember:
- with-skill outputs go under `with_skill/`
- no-skill outputs go under `baseline/`
- benchmark output is only created when both runs exist
- token usage is currently placeholder data in the runner

## 6. Review Results Honestly

Read the actual outputs, not just pass/fail.

Good review order:
1. inspect the generated outputs
2. compare with baseline if present
3. read timing or benchmark artifacts if they exist
4. summarize what improved, what regressed, and what is still unclear

Review along three axes:
- trigger quality: did the skill fit the prompt?
- output quality: was the answer better, clearer, or more reliable?
- cost: did the skill add avoidable bulk or unnecessary steps?

When comparing iterations, focus on:
- fewer failures
- clearer outputs
- better decision boundaries
- less prompt bloat

## 7. Iterate

When improving the skill:
- generalize from failures instead of patching to one prompt
- remove instructions that do not change outcomes
- promote repeated deterministic work into helper scripts
- tighten the description if triggering is weak or noisy
- explain the why behind important constraints instead of piling on rigid rules

Stop when one of these is true:
- the skill is consistently useful
- new edits stop improving results
- the remaining judgment is subjective and user-specific

## 8. Tune Description for Triggering

The description is the main trigger surface.

Write it so it:
- names concrete user intents
- includes likely phrasings
- excludes obvious near-misses when needed

Good pattern:

```yaml
description: >
  Use when the user asks to refactor code, clean up structure,
  or reduce complexity in existing implementation. Not for pure docs edits.
```

If you want to test trigger quality, create a small set of should-trigger and should-not-trigger prompts and review them manually. Do not claim automated optimization unless you have actually run it.

If no real experiment was run, describe the result as a proposal or recommendation, not an optimization benchmark.

## 9. Package the Skill

Use the repo's actual packaging script:

```bash
python assistant/scripts/package_skill.py ./assistant/skills/my-skill --metadata
```

This validates `SKILL.md`, packages the directory, and optionally writes package metadata.

## Failure Modes

Common issues:

- `eval_runner.py` completes but token counts stay zero
  - expected for now; token parsing is still TODO in the script
- baseline and with-skill folders do not match the docs
  - use `baseline/` and `with_skill/`, which is what the runner writes today
- assertions look precise but do not prove quality
  - simplify them or switch to human review
- skill keeps growing
  - move bulky material into `references/` or delete weak instructions
- the prompt becomes process-heavy
  - keep only instructions that visibly change output quality or trigger accuracy
- packaging fails
  - validate `SKILL.md` frontmatter and check `evals/evals.json` is valid JSON

## Checklist

- [ ] Captured intent and trigger boundary
- [ ] Drafted a lean `SKILL.md`
- [ ] Added evals only if the task benefits from them
- [ ] Used repo-accurate commands and paths
- [ ] Reviewed actual outputs, not just status flags
- [ ] Tightened description for triggering
- [ ] Packaged only after the skill feels stable
