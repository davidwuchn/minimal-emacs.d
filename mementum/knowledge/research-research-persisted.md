<!--
Synthesis verification:
- Confidence: 40%
- Sources: 37 memories
- Warnings: No code examples or concrete references, Very short content (29 lines)
- Auto-approved: yes (flagged)
--->

The user wants me to synthesize the memories into a knowledge page about "research-research-persisted". Let me analyze the content:

This is a collection of "Research" entries from an auto-workflow system that does research for an Emacs-based AI agent system. The key themes I can extract:

1. **Research pipeline architecture** - The auto-workflow researcher pattern with strategy, targets, outcome, findings hash
2. **Own repos priority** - davidwuchn/* repos (nucleus, mementum, gptel, zeroclaw, context-mode, eca, etc.)
3. **External sources** - Anthropic, Azure, DSPy, Reflexion, mcp.el, claude-code.el, etc.
4. **Common failure modes** - "research findings file missing after wait" (local-fallback), low keep rates
5. **Key patterns discovered**:
   - Judge boundaries for LLM verification
   - Recovery ladder (retry→repair→replan→degrade→escalate)
   - Human governance (AI proposes, human approves, AI commits)
   - Mementum three-tier memory (state/memories/knowledge)
   - Nucleus attention magnets (mathematical symbols)
   - gptel FSM pause/resume
   - MCP integration
   - Tool use with structured function specs
   - Reflexion-style verbal self-reflection
   - Circuit breakers, fallback chains
   - Skills system (procedural memory)
   - Doo
6. **Magent-style durable child-agent jobs** - status enums, runtime state separation
7. **Prompt compiler/prose bidirectional** - EDN statecharts + lambda notation
8. **Verification gates** - self-rewriting, BDD, strategy gating
9. **Speculative verifier for streaming** - run judge in parallel
10. **Circuit breaker pattern** - CLOSED/OPEN/HALF_OPEN
11. **Context compression** - 98% reduction via sandboxing

Let me build a comprehensive knowledge page synthesizing this into actionable patterns.