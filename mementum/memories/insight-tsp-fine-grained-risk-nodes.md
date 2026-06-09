---
title: TSP paper — fine-grained risk nodes for secure code evolution
category: research
tags: TSP, self-play, risk-nodes, secure-code, fine-grained-learning
related: self-evolving-agent-research, self-heal-semantic, OV5 architecture
created: 2026-06-09
---

# TSP Paper: Tree-like Self-Play for Secure Code (2606.03489v1)

## Key Insight

Current alignment techniques (SFT, RL) apply coarse-grained optimization at the sequence level. This fails to address the **localized nature of security flaws** where a single incorrect token choice can compromise an entire program.

TSP reframes secure code generation as a fine-grained sequential decision process by identifying **"CWE Risk Nodes"** — critical decision points where vulnerabilities emerge.

## Core Mechanism

1. **Identify risk nodes**: Critical decision points in code where vulnerabilities can emerge
2. **Self-play at nodes**: Generate both secure "golden paths" and vulnerable variants
3. **On-policy learning**: Model uses its own insecure branches as "opponent"
4. **Dense feedback**: Token-level learning signal at critical decision nodes

## Results

- **Security pass rate**: 57.0% → 75.8% (Python benchmarks)
- **Unseen CWE reduction**: 24.5% fewer vulnerabilities in unseen categories
- **Cross-language transfer**: C/C++ security principles transfer to Python, Go, JavaScript
- **No catastrophic forgetting**: HumanEval performance remains stable

## OV5 Application

**What OV5 can learn:**

1. **Fine-grained failure analysis**: Instead of experiment-level kept/discarded, identify specific "risk nodes" in code where failures emerge
2. **Self-play at decision points**: Generate both secure and vulnerable variants at critical decision points
3. **On-policy negative examples**: Use model's own insecure code generations as training signal
4. **Language-agnostic principles**: Learn abstract security principles that transfer across contexts

**Implementation ideas:**

1. Add "risk node" detection to self-heal-semantic module
   - Identify critical decision points in code (e.g., function calls, conditionals, resource allocation)
   - Track which decisions lead to kept vs discarded experiments

2. Implement self-play at critical decision points
   - Generate secure variant (golden path)
   - Generate vulnerable variant (self-play path)
   - Learn to discriminate between them

3. Learn language-agnostic security principles
   - Extract abstract security principles from experiment outcomes
   - Store in ontology graph as cross-cutting concerns
   - Apply principles across different code contexts

## Limitations (from paper)

- TSP excels at vulnerabilities with local, explicit control flows
- Underperforms on complex memory and implicit data-flow vulnerabilities
- Risk node abstraction operates through token-level lens
- Self-play negative samples become less challenging as model improves
- Experiments conducted on 3B-7B models only

## Related Papers

- MOSS (2605.22794): Source-level self-evolution
- Sibyl (2605.22343): Trial-and-error harnesses
- APEX (2605.21240): Exploration collapse prevention

---

*From: arXiv:2606.03489v1 — Learn from Your Mistakes: Tree-like Self-Play for Secure Code LLMs*
