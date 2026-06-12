---
title: SkillOpt vs OV5 Skill Self-Evolution Gaps
φ: 0.80
e: skillopt-ov5-gap-analysis
λ: when.skill.evolution.research
Δ: 0.30
evidence: 3
sources:
  - Microsoft SkillOpt (https://github.com/microsoft/SkillOpt)
  - SkillOpt paper arXiv:2605.23904
  - OV5 skill graph / governance / eval-opencode modules
---

💡 SkillOpt is the closest published end-to-end skill optimizer. It treats a skill document as trainable state and runs rollout → reflect → aggregate → select → update → validation gate, plus epoch-boundary slow update and meta skill. SkillOpt-Sleep adds nightly offline consolidation from real session transcripts.

**Where OV5 is ahead:**
- Multi-surface skill discovery (assistant/, .opencode/, global, .agents/)
- Ontology-driven skill routing
- Git-based mementum persistence across sessions
- Source-level self-heal in addition to text-level skill evolution
- Human-gated promotion queue

**Where OV5 should borrow from SkillOpt:**
1. Strict held-out validation gate for skill promotions (real task performance, not assertion patterns)
2. Bounded edit budget / learning-rate scheduler per cycle
3. Rejected-edit buffer to avoid re-proposing bad mutations
4. Protected slow-update guidance region inside canonical skills
5. SkillOpt-Sleep style nightly cycle: harvest transcripts → replay recurring tasks → gate → stage for adoption
6. Multi-rollout contrastive reflection (high vs low scoring attempts of same task)
7. Multi-objective reward: accuracy ↑, tokens ↓, latency ↓
8. Separate optimizer/target models for cost-effective evolution

**Full comparison:** see `mementum/knowledge/self-evolving-agent-research.md` section 5.
