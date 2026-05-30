# AI Agent Auto-Workflow: Local Gaps vs External Patterns

## What's Implemented (Local)
- Transient error detection (`my/gptel--transient-error-p`)
- Fallback chains with backend reordering
- Exponential backoff retry logic
- Backend demotion on failure

## External Patterns NOT YET in Local Codebase

### Critical Gaps
1. **Circuit breaker** — only backend demotion exists; missing proper 3-state (closed/open/half-open) breaker
2. **Error classification taxonomy** — only transient/non-transient; missing semantic errors, resource errors, auth errors
3. **Graceful degradation ladder** — not implemented
4. **Checkpoint & resume** — not implemented for multi-step agent loops
5. **Self-evolving memory architecture** — referenced in arXiv surveys, not in codebase
6. **Skill-augmented evolution** — agent learns/chains skills dynamically
7. **MCP (Model Context Protocol) integration** — tool augmentation pattern not yet wired in

### Relevant Sources
- arXiv: self-evolving agents survey (taxonomy section)
- MetaAgent paper: tool meta-learning
- Mike Olson: Emacs AI setup patterns
- gptel + mcp.el: MCP integration

## Priority Actions
1. Implement 3-state circuit breaker for gptel backends
2. Build error taxonomy beyond transient/non-transient
3. Add graceful degradation ladder (local model → cached → apology)
4. Add checkpoint/resume for agent loops
