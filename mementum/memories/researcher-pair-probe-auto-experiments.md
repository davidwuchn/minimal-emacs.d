# ✅ Researcher Pair-Probe Auto-Queue as Experiments

tags: researcher, pair-probe, experiments, auto-queue, research-executor

## Context
The researcher generates structured [pair-probe] HA/HB blocks with Elisp code proposals in findings, but these were only logged as markdown — never executed as experiments.

## Solution
1. `queue-research-pair-probes`: parses [pair-probe] blocks from research-findings.md, extracts hypothesis+code, stores under :research-probes in hints plist
2. `inject-queued-targets`: reads both :cluster-queued and :research-probes from hints, appends unique targets to selection list. Wired into both analyzer and static paths.

## Researcher Self-Evolution
The researcher now uses all 4 Ouroboros subsystems:
- AutoTTS: {{strategy-guidance}} from controller evolution
- AutoGo: {{research-champion}} from champion league
- Ontology: {{ontology-gaps}} from knowledge gaps
- Allium: {{current-bottlenecks}} from experiment analysis

7 template variables feed live data into the researcher prompt.
