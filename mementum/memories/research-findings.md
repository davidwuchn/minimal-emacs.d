---
name: research-strategies
description: External research insights digested by LLM. Feeds into directive hypotheses.
version: 3.0
updated: 2026-06-04T02:03
---

> Project: /home/davidwu/.emacs.d/
> Source: local + external synthesis

---

## Synthesized Research Digest — Turn 2

### Own Repos Deep Dive (53%)

**[deep-external] context-mode (TypeScript): Think-in-Code paradigm**
- LLM generates scripts (execute in sandbox), not READ files into context window
- Result: 98% context window reduction via output compression/filtering
- Session continuity via SQLite + FTS5 BM25 search (survives compaction)
- Hook-based routing enforcement across 16 platforms
- Priority-tiered snapshots → state restoration hierarchy

**[deep-external] zeroclaw (Rust): Security-First Agent Runtime**
- Provider-agnostic (30+ channels, ~20 LLM providers)
- SOP engine: event-triggered procedures with approval gates
- Cryptographic tool receipts: tamper-evident execution logging
- OS-level sandboxes (Landlock, Bubblewrap, Seatbelt)
- ACP: JSON-RPC over stdio for IDE/editor integration

**[deep-external] nullclaw (Zig): Minimal Footprint Architecture**
- 678 KB static binary, < 1 MB RAM, < 2ms startup
- 50+ providers, 19 channels — similar breadth to zeroclaw at 1/100 the size

**[deep-external] eca (Clojure): Editor-Agnostic Protocol (LSP-Inspired)**
- Protocol-based decoupling, multi-model/multi-subagent orchestration
- MCP resources integration, OpenTelemetry telemetry
- Similar to LangGraph's stateful multi-actor approach

**[deep-external] Ori-Mnemos (TypeScript): Recursive Memory Harness (RMH)**
- ACT-R cognitive architecture: dual-process theory (System 1/2)
- Recursive memory hierarchy: nested episodic + semantic layers
- Persistent agentic memory (survives context compaction via external storage)

### External Reference Patterns (15%)

**[deep-external] Top 2025 GitHub Agent Repos — Structural Patterns**
- n8n (160k★): Workflow automation + AI agents; bridges no-code with code flexibility
- Dify (120k★): Production-ready agentic workflows; prototype-to-production
- RAGFlow (70k★): RAG + agents; citation tracking; multi-step reasoning
- Claude Code (46k★): Terminal-native coding agent; on-device, codebase-aware
- Pathway (50k★): Rust-powered ETL → LLM pipelines; real-time streaming

**[deep-external] AgentNet (NeurIPS 2025): Decentralized Evolutionary Coordination**
- Privacy-preserving multi-agent coordination without central orchestrator
- Evolutionary selection of coordination strategies based on task type
- Contrast: zeroclaw uses centralized SOP; AgentNet shows distributed alternative

**[deep-external] Survey: Multi-Agent Collaboration Mechanisms (arXiv:2501.06322)**
- Framework: actors × types (cooperate/compete/coopetition) × structure × strategy × protocol
- Coopetition (cooperate + compete) largely unexplored — fertile ground
- Distributed structures emerging as trend vs. centralized orchestrators

### Key Non-Obvious Architectural Insights

1. **The Agent Harness Pattern** — All top agents: retrieval → memory → tools → orchestration → evaluation closed loop. context-mode has all 5; eca missing retrieval/evaluation; Ori-Mnemos focuses on memory only.

2. **"Think-in-Code" > "Read Everything"** — LLM generates scripts that execute in sandbox; results compressed. Maps directly to emacs --batch or script-mode execution.

3. **Spec-Driven Development (Spec Kit, 55k★)** — Treats specs as executable artifacts. Aligns with zeroclaw's SOP engine and eca's protocol design.

4. **Coopetition Uncharted** — Cooperation/competition well-explored; coopetition (agents that both collaborate and compete) mostly untapped. eca's multi-agent could benefit from role-competition patterns.

### Alignment with Previous Findings

- Provider-agnostic (zeroclaw, nullclaw, eca) confirmed by n8n/Dify multi-model support
- Security/sandboxing (zeroclaw) validated by Claude Code's "fully on-device" positioning
- Minimal footprint (nullclaw) aligns with Ollama's 150k★ local inference demand
- Tool receipts (zeroclaw) mirrors RAGFlow's citation tracking — auditability matters

### Gap Analysis (where own repos could improve)

| Component     | eca | context-mode | zeroclaw | Ori-Mnemos |
|---------------|-----|-------------|----------|------------|
| Retrieval     | ❌  | ✅ (BM25)   | ❌       | ❌         |
| Evaluation    | ❌  | ❌          | ❌       | ❌         |
| Multi-agent   | ✅  | ❌          | ✅ (ACP) | ❌         |
| Streaming     | ❌  | ❌          | ❌       | ❌         |
| Coopetition   | ❌  | ❌          | ❌       | ❌         |
| Spec-driven   | ❌  | ❌          | ✅ (SOP) | ❌         |
