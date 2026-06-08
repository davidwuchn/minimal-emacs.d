<!--
Synthesis verification:
- Confidence: 24%
- Sources: 29 memories
- Warnings: No code examples or concrete references, Content does not mention topic 'insight-proposal-strategy-harness'
- Auto-approved: yes (flagged)
--->

Let me analyze the memories and synthesize them into a comprehensive knowledge page about the strategy-harness component and its recurring failure patterns.

Key patterns I see:
1. All insights relate to the `strategy-harness` component
2. All have "recurring failures" as the pattern
3. All are "tentative" status with "high" risk
4. Validation rates are very low (0.01-0.08)
5. Confidence varies: 0.60 or 0.80
6. Two categories of failures: staging-* and lisp/modules/*
7. Timestamps: 2026-06-07 14:12 and 20:21-20:22

Staging failures:
- staging-verification (60%, val 0.02)
- staging-scope (70%, val 0.03)
- staging-review (80%, val 0.08)
- staging-push (70%, val 0.02)
- staging-merge (70%, val 0.03)
- staging-config (80%, val 0.04)

Module failures (Lisp):
- treesit-agent-tools-workspace.el (80%, val 0.04)
- gptel-tools-agent-strategy-harness.el (60%, val 0.02)
- gptel-tools-agent-runtime.el (80%, val 0.05)
- gptel-tools-agent-prompt-build.el (80%, val 0.03)
- gptel-tools-agent-experiment-core.el (80%, val 0.07)
- gptel-tools-agent-error.el (80%, val 0.03)
- gptel-tools-agent.el (80%, val 0.03)
- gptel-tools-agent-benchmark.el (80%, val 0.04)
- gptel-ext-tool-confirm.el (80%, val 0.04)
- gptel-ext-backend-registry.el (60%, val 0.02)
- gptel-benchmark-subagent.el (80%, val 0.05)
- gptel-benchmark-principles.el (60%, val 0.02)
- gptel-benchmark-core.el (60%, val 0.02)
- gptel-auto-workflow-strategic.el (80%, val 0.05)
- gptel-auto-workflow-research-cache.el (60%, val 0.02)
- gptel-auto-workflow-projects.el (80%, val 0.05)
- gptel-auto-workflow-production-metrics.el (80%, val 0.05)
- gptel-auto-workflow-production.el (80%, val 0.05)
- gptel-auto-workflow-ontology-strategy.el (80%, val 0.07)
- gptel-auto-workflow-ontology-router.el (80%, val 0.03)
- gptel-auto-workflow-mementum.el (60%, val 0.01)
- gptel-auto-workflow-evolution.el (80%, val 0.03)
- gptel-auto-workflow-bare-path-diagnostic.el (60%, val 0.01)

Let me group the modules by subsystem:
- gptel-tools-agent-* : core agent tools
- gptel-ext-* : extensions
- gptel-benchmark-* : benchmarking
- gptel-auto-workflow-* : workflow automation

Now let me write the full knowledge page.