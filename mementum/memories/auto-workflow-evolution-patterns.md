# Auto-Workflow Evolution: Key Patterns from External Research

## 1. Schema-Based Tool Filtering (Efrit/steveyegge)
Dynamic tool schema filtering based on execution phase. Remove planning tools once planning is done; prioritize execution tools during execution. Implemented as `efrit-do--get-tools-for-state()` which filters schema before each API call. **Actionable**: Add `gptel-programmatic--filter-schema` that takes tool schema + state plist → filtered schema.

## 2. Circuit Breaker — Same-Tool Repetition Detection (Efrit)
Two-tier defense: (1) schema filtering (gentle), (2) circuit breaker (emergency shutdown). Tracks both total tool calls AND same-tool repetitions (default: max 30 total, max 3 same). **Actionable**: Extend `max-tool-calls` to also track same-tool repetition count, not just total.

## 3. Five-Layer Gatekeeper for Safe Evolution (Geneclaw)
Layers: (1) Tool registry, (2) Capability verification, (3) Risk assessment, (4) Permission checks, (5) Execution sandbox. GEP (Geneclaw Evolution Protocol): Observe→Diagnose→Propose→Gate→Apply. **Actionable**: Our auto-workflow needs explicit "gate" function before tool mutation — check risk level, require confirmation for high-risk mutations.

## 4. Layered Error Handling (Fast.io patterns)
Exponential backoff with jitter, circuit breaker pattern, output validation with self-correction, state checkpointing before risky operations, file locking for concurrent operations, webhook-based recovery, observability/audit logging. **Actionable**: Add `gptel-try–cacti-compatible` with exponential backoff and state checkpointing before each tool mutation.

## 5. Self-Distillation (EvolveR)
Offline: mine successful trajectories → distill into strategic principles. Online: retrieve relevant principles at runtime to guide behavior. **Actionable**: Our system could track successful workflow patterns → write to `auto-workflow-principles.el` → retrieve relevant principles before tool mutations.

## 6. Safe Tool Evolution (Verifiably Safe Tool Use paper)
STPA hazard analysis for tool capabilities, MCP capability labels, Information Flow Control (IFC) for tool access. **Actionable**: Add capability labels to our tool definitions, implement IFC-like restrictions (no read tools after write tools without explicit gate).

## 7. Four-Stage Agent Evolution (Arxiv Survey)
Stage 1: Training-time (RLHF), Stage 2: Prompt-time (system prompts), Stage 3: Memory-time (context management), Stage 4: Tool-time (tool creation/modification). Our auto-workflow operates at Stage 4. **Actionable**: Build evolution stages into `auto-workflow-evolve` — each stage has different risk profile and gate requirements.

## 8. Clanker — Emacs Agentic Programming (github.com/jlizhao/clanker)
gptel-based agent with 10 tool categories, spectator mode (pause/resume/skip/cancel), 3-tier testing (unit/simulation/integration). **Actionable**: Consider spectator mode for our auto-workflow — ability to pause evolution and review proposed changes before applying.

## Priority Implementation Order
1. Same-tool repetition detection in circuit breaker (low-risk, high-value)
2. Schema-based tool filtering by phase (medium-risk, high-value)  
3. Gate function before tool mutations (critical for safety)
4. State checkpointing before mutations (medium-effort, high-value)
5. Self-distillation from successful trajectories (long-term, high-value)
