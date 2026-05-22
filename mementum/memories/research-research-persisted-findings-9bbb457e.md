# Research: 2026-05-22 10:29

**Strategy:** persisted-findings
**Findings hash:** 9bbb457e1e0ddd347fecd8b40cbf8246031ea0ca
**Targets:** lisp/modules/gptel-tools-agent-runtime.el, lisp/modules/gptel-tools-memory.el, staging-merge, lisp/modules/gptel-ext-fsm.el, lisp/modules/gptel-ext-tool-permits.el, lisp/modules/gptel-ext-abort.el
**Outcome:** 9/39 kept (23%)

**Raw Findings:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-22 07:01

Researcher result for task: External research turn 1/3

I'll research the priority repositories systematically, starting with own repos as directed. Let me fetch the key repos to extract novel patterns.Now let me check Tier 2 repos for novel patterns:Let me check Tier 3 and Tier 4 repos:Let me search for any recent research on key patterns found:Now let me synthesize all findings into actionable patterns for the Emacs AI agent system:

## External Sources — Priority Repos Analysis

### Tier 1: Directly Applicable (Emacs Lisp + AI agents)

**[deep-external] 1. efrit — Circuit Breaker + Checkpoint/Restore Pattern**
- **Source**: https://github.com/davidwuchn/efrit
- **Technique**: Circuit breaker monitors failure rates per provider, transitions through CLOSED→OPEN→HALF-OPEN states to prevent cascading failures. Checkpoint/restore stores state snapshots before risky operations.
- **Emacs application**: Implement `gptel-circuit-breaker` defcustom tracking `(failure-count success-count last-failure provider)` triples. On 5 consecutive failures, open circuit. Auto-restore from `~/.emacs.d/.gptel/checkpoints/` on crash.

**[deep-external] 2. efrit — Tool Receipts for Audit Trail**
- **Source**: https://github.com/davidwuchn/efrit (35+ tools with security controls)
- **Technique**: Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.
- **Emacs application**: Implement `gptel-tool-log` using sqlite.el. Record `(tool-executed tool-name input-hash output-hash timestamp duration success)` for replay and compliance audit.

**[deep-external] 3. nucleus — Lambda Notation + Mathematical Attention Magnets**
- **Source**: https://github.com/davidwuchn/nucleus
- **Technique**: Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Primes formal reasoning patterns.
- **Emacs application**: Add nucleus-style preamble to `gptel-system-prompt`. Use EDN statecharts for `gptel-auto-workflow` states: `{:phase :planning :actions [...]}`.

**[deep-external] 4. context-mode — Think-in-Code Paradigm**
- **Source**: https://github.com/davidwuchn/context-mode
- **Technique**: Instead of dumping raw file reads (700KB), execute analysis script that returns only result (3.6KB). 98% context reduction via sandbox tools.
- **Emacs application**: Implement `gptel-sandbox-execute` that runs analysis scripts in isolated subprocess, returns only structured result. Prevents LLM from becoming data processor.

**[deep-external] 5. context-mode — Session Continuity via FTS5**
- **Source**: https://github.com/davidwuchn/context-mode
- **Technique**: Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search—not dumps raw data.
- **Emacs application**: Implement `gptel-session-db` using sqlite.el. Track `(session-id timestamp event-type data)` for continuity across compaction events.

**[deep-external] 6. mementum — Feed-Forward Memory Protocol**
- **Source**: https://github.com/davidwuchn/mementum
- **Technique**: Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.
- **Emacs application**: Implement `gptel-memory-synthesize` reading `mementum/state.md` on session start. Create knowledge pages for successful experiment patterns with human approval workflow.

### Tier 2: Agent Architecture Patterns

**[deep-external] 7. gastown — Beads Ledger for Work Tracking**
- **Source**: https://github.com/davidwuchn/gastown
- **Technique**: Work state persisted as immutable beads (git commits) with typed metadata (task, status, agent-id). Scales to 20-30 agents via git-backed hooks.
- **Emacs application**: Implement `gptel-work-bead` creating git commits with structured metadata for tasks. Enables recovery and a
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-M34c4d.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /home/davidwu/.emacs.d/
> Updated: 2026-05-22 07:01

Researcher result for task: External research turn 1/3

I'll research the priority repositories systematically, starting with own repos as directed. Let me fetch the key repos to extract novel patterns.Now let me check Tier 2 repos for novel patterns:Let me check Tier 3 and Tier 4 repos:Let me search for any recent research on key patterns found:Now let me synthesize all findings into actionable patterns for the Emacs AI agent system:

## External Sources — Priority Repos Analysis

### Tier 1: Directly Applicable (Emacs Lisp + AI agents)

**[deep-external] 1. efrit — Circuit Breaker + Checkpoint/Restore Pattern**
- **Source**: https://github.com/davidwuchn/efrit
- **Technique**: Circuit breaker monitors failure rates per provider, transitions through CLOSED→OPEN→HALF-OPEN states to prevent cascading failures. Checkpoint/restore stores state snapshots before risky operations.
- **Emacs application**: Implement `gptel-circuit-breaker` defcustom tracking `(failure-count success-count last-failure provider)` triples. On 5 consecutive failures, open circuit. Auto-restore from `~/.emacs.d/.gptel/checkpoints/` on crash.

**[deep-external] 2. efrit — Tool Receipts for Audit Trail**
- **Source**: https://github.com/davidwuchn/efrit (35+ tools with security controls)
- **Technique**: Every tool execution generates structured metadata: `(input-hash output-hash timestamp duration tool-name)`. Shell commands have allowed/forbidden pattern matching.
- **Emacs application**: Implement `gptel-tool-log` using sqlite.el. Record `(tool-executed tool-name input-hash output-hash timestamp duration success)` for replay and compliance audit.

**[deep-external] 3. nucleus — Lambda Notation + Mathematical Attention Magnets**
- **Source**: https://github.com/davidwuchn/nucleus
- **Technique**: Greek letters and math symbols as compressed prompt preamble: `λ engage(nucleus). [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Primes formal reasoning patterns.
- **Emacs application**: Add nucleus-style preamble to `gptel-system-prompt`. Use EDN statecharts for `gptel-auto-workflow` states: `{:phase :planning :actions [...]}`.

**[deep-external] 4. context-mode — Think-in-Code Paradigm**
- **Source**: https://github.com/davidwuchn/context-mode
- **Technique**: Instead of dumping raw file reads (700KB), execute analysis script that returns only result (3.6KB). 98% context reduction via sandbox tools.
- **Emacs application**: Implement `gptel-sandbox-execute` that runs analysis scripts in isolated subprocess, returns only structured result. Prevents LLM from becoming data processor.

**[deep-external] 5. context-mode — Session Continuity via FTS5**
- **Source**: https://github.com/davidwuchn/context-mode
- **Technique**: Every edit, git op, task, error tracked in SQLite with FTS5. When context compacts, retrieves only relevant events via BM25 search—not dumps raw data.
- **Emacs application**: Implement `gptel-session-db` using sqlite.el. Track `(session-id timestamp event-type data)` for continuity across compaction events.

**[deep-external] 6. mementum — Feed-Forward Memory Protocol**
- **Source**: https://github.com/davidwuchn/mementum
- **Technique**: Three storage types (working memory/state.md, memories <200 words, synthesized knowledge). Human governance: AI proposes, human approves, AI commits.
- **Emacs application**: Implement `gptel-memory-synthesize` reading `mementum/state.md` on session start. Create knowledge pages for successful experiment patterns with human approval workflow.

### Tier 2: Agent Architecture Patterns

**[deep-external] 7. gastown — Beads Ledger for Work Tracking**
- **Source**: https://github.com/davidwuchn/gastown
- **Technique**: Work state persisted as immutable beads (git commits) with typed metadata (task, status, agent-id). Scales to 20-30 agents via git-backed hooks.
- **Emacs application**: Implement `gptel-work-bead` creating git commits with structured metadata for tasks. Enables recovery and a
...[Result too large, truncated. Full result saved to: /home/davidwu/.emacs.d/tmp/gptel-subagent-result-M34c4d.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
