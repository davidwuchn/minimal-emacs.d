---
type: planning
entity: plan
plan: opencode-skill-evolution
status: done
created: 2026-06-11
updated: 2026-06-11
---

# Plan: opencode-skill-evolution

## Objective

Build an eval harness that lets OV5 (the Emacs-based self-improving pipeline) evolve opencode CLI agent skills (brepl, daemon-repl, ov5) through A/B experiments — testing whether skill variants actually change agent behavior, grading compliance, and promoting winners.

## Motivation

OV5 already evolves internal Emacs agent skills (researcher prompt, strategy prompts) but cannot evolve opencode skills because:

1. **No opencode executor** — OV5's eval loop byte-compiles Elisp files; it doesn't launch an opencode agent
2. **No behavioral grader** — OV5 grades code output (byte-compile pass/fail), not instruction-following (did the agent use heredoc? `-a false`?)
3. **No skill injection** — the existing `skill-eval-run-ab` never actually loads the skill variant into the treatment arm
4. **No task corpus** — no controlled tasks that should trigger specific skill behaviors
5. **No variant generation/promotion** — no mechanism to write candidate skill files and promote the winner

The 3 opencode skills (brepl, daemon-repl, ov5) live in `assistant/skills/` and are symlinked to `.opencode/skills/`. OV5 can already *audit* them (Semia, canary). This plan adds the *evolution* capability.

## Requirements

### Functional

- [ ] OV5 can run an A/B experiment comparing two SKILL.md variants on a controlled opencode task
- [ ] The eval harness launches `opencode` CLI in an isolated worktree with the skill loaded
- [ ] Behavioral assertions grade whether the agent followed the skill's instructions (not just "did the task")
- [ ] Results are persisted in a format OV5's existing champion-league can consume
- [ ] Winner variants are promoted to `assistant/skills/{skill}/SKILL.md` (canonical location)
- [ ] Skill graph tracks opencode-platform results separately from Emacs-platform results

### Non-Functional

- [ ] Each eval run completes in <5 minutes (opencode agent + grading)
- [ ] No external dependencies beyond what's already installed (opencode, emacs, git)
- [ ] Results are human-readable (JSON + markdown report)
- [ ] The harness is safe: runs in isolated worktrees, never touches `main` directly

## Scope

### In Scope

- New Elisp module: `gptel-auto-workflow-skill-eval-opencode.el` — opencode-specific executor + grader
- Task corpus: `var/tmp/skill-eval-opencode/tasks/` — YAML task definitions with assertions
- Integration with existing `gptel-auto-workflow--skill-governance-run-cycle`
- Fix existing bugs in skill-governance (missing hook, broken JSON serialization)
- Variant generation: LLM-assisted SKILL.md variant writer
- Promotion pipeline: winner → `assistant/skills/{skill}/SKILL.md`

### Out of Scope

- Changing opencode itself (we use it as-is)
- Evolving skills for platforms other than opencode
- Building a UI/dashboard for skill eval results
- Modifying the skill graph data model (just tag results with `:platform "opencode"`)

## Definition of Done

- [ ] `gptel-auto-workflow-skill-eval-opencode.el` loaded and byte-compile clean
- [ ] At least 3 task corpus entries (one per skill: brepl, daemon-repl, ov5)
- [ ] A/B experiment runs end-to-end: baseline vs variant → graded result → persisted
- [ ] Winner promotion writes to `assistant/skills/{skill}/SKILL.md`
- [ ] Existing ERT tests still pass (no regressions)
- [ ] Pi5 picks up the new module on next cron cycle without error

## Testing Strategy

- [ ] Unit tests for assertion checker (pure function: transcript + assertions → pass/fail)
- [ ] Integration test: mock opencode run (capture output from a known-good task)
- [ ] E2E test: run a real opencode eval with a trivial task, verify result persistence
- [ ] Regression: `make test` passes (all 3485+ ERT tests)

## Phases

| Phase | Title | Scope | Status |
|-------|-------|-------|--------|
| 1 | Task corpus + assertion engine | [Detail](phases/phase-1.md) | pending |
| 2 | Opencode executor + A/B runner | [Detail](phases/phase-2.md) | pending |
| 3 | Variant generation + promotion pipeline | [Detail](phases/phase-3.md) | pending |
| 4 | Integration with OV5 governance cycle | [Detail](phases/phase-4.md) | pending |

## Risks & Open Questions

| Risk/Question | Impact | Mitigation/Answer |
|---------------|--------|-------------------|
| opencode CLI may not have a programmatic "run single task and exit" mode | High — blocks executor | Check opencode CLI flags; may need `opencode --non-interactive --task "..."` or similar. Fallback: use Bash tool from opencode's own agent. |
| opencode agent behavior is non-deterministic (LLM) | Medium — A/B noise | Use multiple runs per arm (N=3), require effect-size > 0.3 (matching existing threshold) |
| Skill variants may be identical in effect for trivial tasks | Low — false indeterminate | Task corpus must exercise the specific instruction being varied (e.g., heredoc vs no-heredoc) |
| Pi5 cron may run experiments while we're developing | Low — conflicts | Feature-flag the new cycle (`gptel-auto-workflow-opencode-eval-enabled`) |

## Changelog

### 2026-06-11

- Plan created
