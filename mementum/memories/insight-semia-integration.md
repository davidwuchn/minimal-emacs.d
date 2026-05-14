**Target:** Semia integration (security audit for AI agent skills)
**Decision:** Integrate as Layer 2 in skill-governance cycle using `uv tool install semia-audit`
**Score:** 9/10

## What we learned

Semia (`berabuddies/semia`, Apache-2.0, Python 3.11+) statically analyzes agent SKILL.md files for security threats: shell commands, network access, secret reads, tool invocations. Reads as data — never executes.

Key integration parameters:
- Install: `uv tool install semia-audit` (provides `semia` CLI)
- Scan: `semia scan <skill-dir> --offline-baseline --out <run-dir>`
- `--offline-baseline` skips LLM synthesize → pure static analysis, no API calls
- Output: report.md (human), report.json (machine), detection_result.json (findings)
- 0 findings on researcher-prompt skill

## Integration plan

Added as Layer 2 in `skill-governance-run-cycle`:
1. Layer 1: skills-refiner (hygiene — existing)
2. Layer 2: Semia (security — NEW, `--offline-baseline`)
3. Layer 3: A/B testing (existing)
4. Layer 4: Activation tracing (existing)

Implementation in `skill-governance.el`: Elisp calls `semia scan` via `shell-command-to-string`, parses JSON, stores findings in `var/tmp/skill-governance/semia/`.

## Lesson

Semia was discovered by explicitly searching for security audit tools after seeing our governance module lacked threat detection. Integrating external tools via `uv tool install` keeps dependencies isolated while providing CLI access from Elisp.
