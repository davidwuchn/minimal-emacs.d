# tools agent prompt build

## Purpose

Prompt construction, logging, and knowledge caching for the auto-workflow
executor. Builds experiment prompts with KIBC-M axis tagging (15 axes across 4
tiers), prompt structure scoring (verbum + nucleus pattern), nucleus
compiler/decompiler for prose ↔ EDN round-trip forging, Allium v3 behavioral
spec distilling/checking/decompiling, LLM-powered OWL/SHACL serialization,
section A/B testing for prompt optimization, agent skills loading (agentskills.io
compliant with variant selection), and a knowledge cache layer for self-evolution
data injection.

## File Stats

- **Lines**: 3912
- **Path**: `lisp/modules/gptel-tools-agent-prompt-build.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-auto-workflow--knowledge-cache-get` | 99 | Get cached knowledge if fresh (< 1 hour) |
| `gptel-auto-workflow--knowledge-cache-set` | 112 | Cache knowledge with current timestamp |
| `gptel-auto-workflow--knowledge-cache-invalidate` | 116 | Invalidate cache for key or all keys |
| `gptel-auto-workflow--adapt-prompt-compression` | 167 | Adjust compression based on token efficiency skill |
| `gptel-auto-experiment--prompt-structure-score` | 180 | Score prompt structure quality (0.0-1.0) |
| `gptel-auto-experiment--kibcm-axis` | 238 | Classify hypothesis into KIBC-M axis |
| `gptel-auto-experiment--forge-fixed-point` | 251 | Deterministic fixed-point refinement of prompts |
| `gptel-auto-experiment--compile-score` | 269 | Audit prompt via nucleus COMPILER.md |
| `gptel-auto-experiment--forge-lambda-fixed-point` | 327 | Nucleus compile↔decompile round-trip forging |
| `gptel-auto-experiment--allium-distill` | 439 | Distill prose to Allium v3 behavioral spec |
| `gptel-auto-experiment--allium-check` | 456 | Check Allium spec for issues |
| `gptel-auto-experiment--research-for-prompt` | 578 | Optimize research findings for LLM prompt injection |
| `gptel-auto-experiment--owl-generate` | 661 | Generate OWL/Turtle from ontology plist via LLM |
| `gptel-auto-experiment--shacl-generate` | 708 | Generate SHACL shapes from ontology plist via LLM |
| `gptel-auto-workflow--select-ab-test-sections` | 775 | Select prompt sections based on A/B test data |
| `gptel-auto-workflow--load-skill` | 918 | Load skill with variant selection and champion league |
| `gptel-auto-workflow--refresh-variant-axis-champions` | 852 | Populate per-axis variant champions from TSV |

## Dependencies

- `cl-lib`, `seq`, `subr-x`
- `gptel-ext-backend-registry` (optional)
- `gptel-auto-workflow-knowledge-reasoning` (dialectic lens, EDN, forge)
- `gptel-tools-agent-strategy-harness` (strategy evaluation)
- `gptel-tools-agent-base` (worktree root, results paths)
- `gptel-tools-agent-benchmark` (Eight Keys, project root)
- `gptel-tools-agent-prompt-analyze` (inspection thrash, large target focus)
- `gptel-agent-tools` (skill file reading)

## Integration Points

- **Executor prompt building**: `gptel-auto-experiment-build-prompt` is the main entry point
- **Strategy harness**: `gptel-auto-experiment-build-prompt-with-strategy` uses evolved strategies
- **Knowledge injection**: Research findings, self-evolution data, topic knowledge fed into prompts
- **Allium pipeline**: Research findings → distill → check → inject into prompts
- **Section A/B testing**: Tracks which prompt sections correlate with experiment success
- **Skill loading**: Agentskills.io compliant with progressive disclosure and variant champions

## See Also

- [auto workflow knowledge reasoning](gptel-auto-workflow-knowledge-reasoning.md)
- [tools agent strategy harness](gptel-tools-agent-strategy-harness.md)
- [tools agent experiment core](gptel-tools-agent-experiment-core.md)
- [tools agent benchmark](gptel-tools-agent-benchmark.md)