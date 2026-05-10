---
title: Experiment Insights - gptel-auto-workflow-strategic
status: active
category: knowledge
tags: [auto-workflow, experiments, gptel-auto-workflow-strategic]
insight-quality: 7.3/10
---

# Experiment Insights: gptel-auto-workflow-strategic

*Consolidated from 3 experiments (avg insight quality: 7.3/10).*

**Keep rate:** 0% (0 kept / 0 discarded / 0 failed / 0 timeout)

## Score Predictor

| Pattern | Predicts | Confidence |
|---------|----------|------------|
| Validation guard (proper-list-p, nil check) | KEEP | High |
| Bug fix + refactor combo | KEEP | High |
| Extract helper alone | DISCARD | Medium |
| catch/throw or complex flow | DISCARD | High |
| Common Lisp symbols (cw, file, plusp) | VALIDATION-FAILED | Very High |
| >50 lines changed | TIMEOUT/DISCARD | Medium |

