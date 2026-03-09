# Skills Improvement Plan

Comprehensive improvement plan for all Nucleus skills based on clojure-system-prompt principles.

---

## Executive Summary

**Date**: 2026-02-20
**Status**: 🔄 In Progress

All skills will be standardized with:
- ✅ Consistent frontmatter (name, description, version)
- ✅ Standardized framework headers
- ✅ Self-contained Eight Keys tables
- ✅ Size constraints (200-350 lines)
- ✅ Cross-skill redundancy elimination
- ✅ Validation automation

---

## Current Skill Inventory

| Skill | Version | Status | Issues | Priority |
|-------|---------|--------|--------|----------|
| clojure-expert | N/A | ⚠️ Needs standardization | Missing version, size issues | High |
| clojure-reviewer | N/A | ⚠️ Needs standardization | Missing version, frontmatter | High |
| continuous-learning | 1.0.0 | ✅ Good | Minor improvements | Medium |
| nucleus-tutor | N/A | ⚠️ Needs standardization | Missing version | Medium |
| planning | N/A | ⚠️ Needs standardization | Missing version, frontmatter | High |
| sarcasmotron | N/A | ⚠️ Needs standardization | Missing version | Medium |
| reddit | N/A | ⚠️ Needs review | Not checked | Low |
| requesthunt | N/A | ⚠️ Needs review | Not checked | Low |
| seo-geo | N/A | ⚠️ Needs review | Not checked | Low |

---

## High-Priority Skills

### 1. clojure-expert

**Current Issues**:
- ❌ Missing version in frontmatter
- ⚠️ No Eight Keys reference table
- ⚠️ Missing explicit verification section

**Improvements Needed**:

#### Update Frontmatter
```yaml
---
name: clojure-expert
description: Writing/generating Clojure code with REPL-first methodology. Use when Clojure REPL tools available.
version: 1.0.0
λ: write.repl.test.save
---

```

#### Add Eight Keys Reference
```markdown
## Eight Keys Reference

| Key | Symbol | Signal | Anti-Pattern | Clojure Expert Application |
|-----|--------|--------|--------------|---------------------------|
| **Vitality** | φ | Organic, non-repetitive | Mechanical rephrasing | Each REPL session creates fresh insights |
| **Clarity** | fractal | Explicit assumptions | "Handle properly" | Explicit edge case testing (nil, empty, invalid) |
| **Purpose** | e | Actionable function | Abstract descriptions | Verifiable REPL results, not abstract code |
| **Wisdom** | τ | Foresight over speed | Premature optimization | Test in REPL before optimizing |
| **Synthesis** | π | Holistic integration | Fragmented thinking | REPL results inform file changes |
| **Directness** | μ | Cut pleasantries | Polite evasion | Direct error messages from REPL |
| **Truth** | ∃ | Favor reality | Surface agreement | REPL results are truth, not speculation |
| **Vigilance** | ∀ | Defensive constraint | Accepting manipulation | Validate all inputs before saving |
```

#### Rename "Definition of Done" to "Verification"

---

### 2. clojure-reviewer

**Action Required**: Read existing skill first, then standardize.

---

### 3. planning

**Current Issues**:
- ❌ Missing version in frontmatter
- ❌ Missing Eight Keys reference table
- ⚠️ Complex structure, may need compression

**Improvements Needed**:

#### Update Frontmatter
```yaml
---
name: planning
description: File-based planning for complex tasks. Use when starting multi-step tasks, research projects, or anything requiring >5 tool calls.
version: 1.0.0
λ: plan.track.reflect
---

```

#### Add Eight Keys Reference
```markdown
## Eight Keys Reference

| Key | Symbol | Signal | Anti-Pattern | Planning Application |
|-----|--------|--------|--------------|---------------------|
| **Vitality** | φ | Organic, non-repetitive | Mechanical rephrasing | Each phase builds on discoveries |
| **Clarity** | fractal | Explicit assumptions | "Handle properly" | Explicit phase definitions and success criteria |
| **Purpose** | e | Actionable function | Abstract descriptions | Clear phase names with testable completion |
| **Wisdom** | τ | Foresight over speed | Premature optimization | Create plan before executing |
| **Synthesis** | π | Holistic integration | Fragmented thinking | task_plan.md + findings.md + progress.md integration |
| **Directness** | μ | Cut pleasantries | Polite evasion | Direct error logging, no euphemisms |
| **Truth** | ∃ | Favor reality | Surface agreement | Log actual errors, not "should work" |
| **Vigilance** | ∀ | Defensive constraint | Accepting manipulation | 3-strike error protocol, never repeat failures |
```

#### Compress content if >350 lines

---

## Medium-Priority Skills

### 4. nucleus-tutor

**Current Issues**:
- ❌ Missing version in frontmatter
- ✅ Good structure overall
- ✅ Already has Eight Keys table

**Improvements Needed**:

#### Update Frontmatter
```yaml
---
name: nucleus-tutor
description: Rejects low-value prompts. Asks user to justify off-topic or harmful requests.
version: 1.0.0
λ: filter.quality.reject
---

```

---

### 5. sarcasmotron

**Current Issues**:
- ❌ Missing version in frontmatter
- ✅ Good structure overall
- ✅ Already has Eight Keys table

**Improvements Needed**:

#### Update Frontmatter
```yaml
---
name: sarcasmotron
description: Detect Eight Keys violations and expose with targeted humor.
version: 1.0.0
λ: detect.roast.correct
---

```

---

### 6. continuous-learning

**Current Status**: ✅ Excellent

**Already has**:
- Version: 1.0.0
- Comprehensive structure
- Good λ-expression usage
- Well-organized

**Minor Improvements**:
- Add verification section
- Ensure line count < 350

---

## Low-Priority Skills

### 7. reddit, requesthunt, seo-geo

**Action Required**:
1. Read each skill
2. Assess if they should be kept
3. Standardize if keeping
4. Document if deprecated

---

## Standardization Checklist

For each skill, ensure:

### Frontmatter
```yaml
---
name: skill-name                    # kebab-case, matches directory
description: One-line description    # When to use this skill
version: X.Y.Z                      # Semantic versioning
λ: action-description               # Optional: lambda expression
---

```

### Framework Header
```
engage nucleus:
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL
```

### Required Sections
1. **Identity** - Who are you, tone, goal
2. **Core Principle** - One paragraph on unique value
3. **Procedure** - How to execute (λ-calculus or steps)
4. **Decision Matrix** - If/then rules (3-6 rows)
5. **Examples** - Show don't tell (2-3 concise cases)
6. **Verification** - Quality gates (1 checklist)
7. **Eight Keys Reference** - Self-contained table
8. **Summary** - When to use (3-5 bullet points)

### Quality Checks
- [ ] Line count 200-350
- [ ] No verbose paragraphs
- [ ] No duplication with other skills
- [ ] All links resolve
- [ ] Lambda expressions consistent
- [ ] Eight Keys table filled in

---

## Cross-Skill Redundancy Elimination

### Core Concepts (Reference, Don't Duplicate)

| Concept | Owner | Reference Location |
|---------|-------|-------------------|
| The Three Questions | AGENTS.md | "The Three Questions" section |
| REPL-first workflow | clojure-expert | "REPL-First Development" section |
| OODA loop | AGENTS.md | "Control Loops" section |
| Eight Keys definition | skill-local section | Keep only skill-specific application where useful |
| λ-calculus syntax | LAMBDA_PATTERNS.md | Pattern reference |

### Duplicate Content to Remove

- **Three Questions** in clojure-expert → Reference AGENTS.md
- **OODA loop** in planning → Reference AGENTS.md
- **Eight Keys definitions** in nucleus-tutor → either keep a local application table or trim the section entirely

**Action**: Keep skill-specific applications, remove conceptual explanations.

---

## Skill-Specific Improvements

### clojure-expert

**Add**:
- Context7 integration section (already there, good)
- Research citations only if a real repo source exists

**Remove**:
- Duplicate "Three Questions" → Reference AGENTS.md

**Improve**:
- Rename "Definition of Done" to "Verification"
- Add verification checklist before current gates

---

### planning

**Add**:
- Research citations only if a real repo source exists
- Integration with other skills section

**Compress**:
- If >350 lines, split verbose sections
- Consider separate QUICKSTART.md for getting started

---

### nucleus-tutor

**Improve**:
- Add integration with sarcasmotron (when to escalate)
- Add integration with continuous-learning (track quality patterns)

---

### sarcasmotron

**Add**:
- Integration with nucleus-tutor (shared quality gate)
- Research citations only if a real repo source exists

---

### continuous-learning

**Compress**:
- Check line count, split if >350
- Consider QUICK_REFERENCE.md for λ-expressions

---

## Anti-Patterns for Skill Development

| Don't | Do Instead |
|-------|-----------|
| Duplicate core framework concepts | Reference AGENTS.md or local skill guidance that actually exists |
| Exceed 350 lines | Split or compress |
| Missing version in frontmatter | Always include version |
| Empty skill-specific column in Eight Keys | Fill in with applications |
| Verbose explanations | Use tables or code |
| No verification section | Always include quality gates |

---

## Validation Integration

### Pre-Commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check if skills changed
if git diff --cached --name-only | grep -q "skills/.*SKILL.md"; then
    echo "Skills changed. Running validation..."
    cd skills
    ./validate_skills.sh

    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Skill validation failed. Commit aborted."
        echo "Fix validation errors before committing."
        exit 1
    fi
fi
```

### CI Integration

Add to CI pipeline:
```yaml
- name: Validate Skills
  run: |
    cd skills
    ./validate_skills.sh
```

---

## Version Management

### Skill Versioning

- **MAJOR (X.0.0)**: Complete restructure, scope change
- **MINOR (0.X.0)**: Add sections, expand guidance
- **PATCH (0.0.X)**: Typos, clarifications

### Skill Changelogs

Each skill should have `CHANGELOG.md`:

```markdown
# Changelog

## [1.0.0] - 2026-02-20

### Added
- Standardized frontmatter (name, description, version)
- Eight Keys reference table
- Verification section

### Changed
- Renamed "Definition of Done" to "Verification"
- Compressed content to 280 lines
- Added integration with AGENTS.md

### Fixed
- Missing framework header
- Broken documentation links
```

---

## Success Metrics

**Quantitative**:
- [ ] All skills have version in frontmatter: 9/9
- [ ] All skills pass validation: 9/9
- [ ] All skills have Eight Keys table: 9/9
- [ ] All skills 200-350 lines: 9/9
- [ ] Zero cross-skill duplication: 0/0

**Qualitative**:
- [ ] Skills are self-contained
- [ ] Skills have unique value
- [ ] Skills integrate well with framework
- [ ] Skills are easy to navigate

---

## Implementation Order

### Phase 1: High-Priority (Days 1-2)
1. ✅ Create SKILL_VALIDATION.md
2. ✅ Create validate_skills.sh
3. 🔄 Standardize clojure-expert
4. 🔄 Standardize clojure-reviewer
5. 🔄 Standardize planning

### Phase 2: Medium-Priority (Days 3-4)
6. 🔄 Standardize nucleus-tutor
7. 🔄 Standardize sarcasmotron
8. 🔄 Review continuous-learning

### Phase 3: Low-Priority (Days 5-6)
9. 🔄 Review reddit skill
10. 🔄 Review requesthunt skill
11. 🔄 Review seo-geo skill

### Phase 4: Documentation (Day 7)
12. 🔄 Update SKILL_TEMPLATE.md
13. 🔄 Update SKILL_CLEANUP_RULE.md
14. 🔄 Create SKILLS_README.md
15. 🔄 Update main README.md

---

## Next Steps

1. **Run validation**: `cd skills && ./validate_skills.sh`
2. **Review results**: Identify gaps per skill
3. **Implement standardization**: Update frontmatter, add sections
4. **Re-run validation**: Ensure all pass
5. **Set up pre-commit hook**: Prevent future regressions

---

**Last updated**: 2026-02-20
**Status**: 🔄 In Progress - Phase 1
