# auto workflow mementum

## Purpose

Bridges auto-workflow experiments with the mementum memory system. Writes atomic
memories (💡, ✅, ❌, 🔄, 🎯, 🔬) per experiment result, deduplicates via SHA-256
hashing, synthesizes recent memories into `auto-workflow-evolution.md` knowledge
pages with git-backed change-type and target-file success rates, and injects
synthesized knowledge into executor/analyzer prompts via a cache layer.

## File Stats

- **Lines**: 455
- **Path**: `lisp/modules/gptel-auto-workflow-mementum.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-auto-workflow--mementum-slug` | 60 | Generate URL-safe slug from text (max 80 chars) |
| `gptel-auto-workflow--mementum-write-memory` | 110 | Write deduplicated memory file with frontmatter; supersedes older matching memories |
| `gptel-auto-workflow--mementum-record-experiment` | 163 | Record a kept experiment to mementum as a ✅ memory |
| `gptel-auto-workflow--mementum-record-research` | 185 | Record research findings as a 🔬 memory with strategy hash |
| `gptel-auto-workflow--mementum-read-memories` | 231 | Read memories from the last N days |
| `gptel-auto-workflow--mementum-supersede-memory` | 269 | Mark old memory as superseded by a new one via `valid-until` frontmatter |
| `gptel-auto-workflow--mementum-synthesize-knowledge` | 302 | Synthesize recent memories into `auto-workflow-evolution.md` knowledge page |
| `gptel-auto-workflow--mementum-get-knowledge-for-prompt` | 408 | Get synthesized knowledge for prompt injection (with cache) |
| `gptel-auto-workflow-mementum-weekly-job` | 446 | Weekly batch synthesis job (callable from cron or timer) |

## Dependencies

- `cl-lib`, `subr-x`
- `gptel-auto-workflow-evolution` (hypothesis categorization)
- `gptel-auto-workflow-memory-schema` (schema extraction)
- `gptel-auto-workflow-git-learning` (git stats computation)
- `gptel-tools-agent-base` (worktree root)

## Integration Points

- **Experiment recording**: Called by the experiment loop when a result is kept
- **Research recording**: Called by the research phase after findings are digested
- **Prompt injection**: `gptel-auto-workflow--mementum-get-knowledge-for-prompt` feeds evolution patterns into executor prompts
- **Weekly batch**: `gptel-auto-workflow-mementum-weekly-job` runs synthesis from cron/timer
- **Knowledge cache**: Invalidation via `gptel-auto-workflow--knowledge-cache-invalidate` after synthesis

## See Also

- [auto workflow evolution](gptel-auto-workflow-evolution.md)
- [tools agent prompt build](gptel-tools-agent-prompt-build.md)
- [tools agent base](gptel-tools-agent-base.md)