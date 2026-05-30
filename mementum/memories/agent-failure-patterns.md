# Agent Failure Patterns & Recovery

## External Research
- **MetaAgent (arXiv 2508.00271)**: Self-evolving agent using tool meta-learning. Generates help requests for knowledge gaps, self-reflects, verifies answers, distills into concise texts. Builds in-house tools + persistent knowledge base.
- **Error Recovery Patterns**: Circuit breaker, graceful degradation, checkpoint/resume, structured logging, input/output validation.
- **agent-shell (Emacs)**: ACP protocol for native Emacs LLM agents.

## Local Analysis
- **Top failure modules**: evolution, strategic, prompt-build, ontology-router
- **Existing patterns**: Retry mechanisms in codebase
- **Strategic module**: Has fallback mechanisms

## Action Items
- Apply nil-safety patterns to high-failure modules
- Add validation guards at module boundaries
- Consider circuit breaker for API failures
- Explore MetaAgent's self-reflection + distillation for agent evolution