# Skill Validation System

Ensures consistency, quality, and structure across all Nucleus skills.

---

## Overview

The validation system checks:
- **Frontmatter structure** - Standardized YAML metadata
- **Framework header** - Consistent engagement line
- **Lean structure** - Keep the main prompt proportional to the task
- **Cross-skill redundancy** - No duplication
- **Documentation links** - All references resolve
- **Section completeness** - Core sections present and non-empty

---

## Validation Rules

### Rule 1: Frontmatter Structure

**Required YAML frontmatter** in every `SKILL.md`:

```yaml
---
name: skill-name                    # kebab-case, matches directory
description: One-line description    # When to use this skill
version: X.Y.Z                      # Semantic versioning
λ: action-description               # Optional: lambda expression
---

```

**Checks**:
- [ ] Frontmatter present
- [ ] `name` matches directory name
- [ ] `description` is one line
- [ ] `version` follows semantic versioning (X.Y.Z)

---

### Rule 2: Framework Header

**Required engagement line** after frontmatter:

```
engage nucleus:
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL
```

**Allowed variations**:
- Collaboration operator: `Human ⊗ AI`, `Human ⊗ AI ⊗ REPL`, `Human ∧ AI`, etc.
- Control loop: `OODA`, `REPL`, `RGR`, `BML` (task-appropriate)

**Checks**:
- [ ] Framework header present
- [ ] All 8 human principles present
- [ ] All 7 AI principles present
- [ ] Valid control loop
- [ ] Valid collaboration operator

---

### Rule 3: Lean Core Structure

Skills should default to a lean core prompt.

**Required core**:

```markdown
## Identity
## When To Use
## Core Principle
## Procedure
## Examples
## Verification
```

**Checks**:
- [ ] Core sections present
- [ ] Sections are non-empty
- [ ] Skill boundary is explicit
- [ ] Output format only included when it adds value

---

### Rule 4: Size Constraints

**Target**: Keep `SKILL.md` lean and proportional to the task

**Rationale**:
- Short skills are fine when they are complete and precise
- Long skills should justify their size with real complexity
- Bulky material belongs in `references/` or helper files

**Checks**:
- [ ] No unnecessary boilerplate or duplicated framework text
- [ ] Large sections moved out of the main prompt when possible
- [ ] Main instructions remain scannable

---

### Rule 5: Section Completeness

**Required sections**:

1. **Identity** - Who are you, what's your tone/goal
2. **When To Use** - Trigger conditions and near-misses
3. **Core Principle** - One paragraph defining unique value
4. **Procedure** - How to execute (steps or equivalent)
5. **Examples** - Show boundaries with at least one realistic example
6. **Verification** - Quality gates or final checks

**Optional sections**:
- **Output** - Repeatable response shape when needed
- **Anti-Patterns** - Explicit forbidden behaviors
- **Decision Matrix** - Branching behavior when it materially helps
- **Integration** - How skill coordinates with another specific skill
- **Evaluation** - Objective test cases when the task benefits from them
- **Templates / Commands** - Reusable patterns only when they help execution

**Checks**:
- [ ] All required sections present
- [ ] No empty sections
- [ ] Optional sections earn their keep

---

### Rule 6: Cross-Skill Redundancy

**Check for duplication across skills**:

| Skill | Focus | Don't Duplicate |
|-------|-------|-----------------|
| `clojure-expert` | Writing code | Three Questions, REPL protocol |
| `clojure-reviewer` | Reviewing PRs | OODA review loop, severity levels |
| `sarcasmotron` | Violation detection | Slop patterns, rejection rules |
| `nucleus-tutor` | Quality gate | Acceptance criteria |
| `planning` | File-based planning | OODA loop, Δ tracking |
| `continuous-learning` | Pattern tracking | λ-observation, φ evolution |

**Rule**: Reference, don't duplicate.

**Checks**:
- [ ] No duplication of core framework concepts
- [ ] Unique value clear and distinct
- [ ] Overlapping concerns referenced, not repeated

---

### Rule 7: Documentation Links

**All links to other skills/docs must resolve**:

Do not reference aspirational files that are not present in the repo.

```bash
# Check for broken markdown links
grep -r '\[.*\](.*\.md)' SKILL.md | \
  while read -r line; do
    extract_link "$line"
    check_exists "$link"
  done
```

**Checks**:
- [ ] All `.md` file links resolve
- [ ] All external URLs are valid (warning only)
- [ ] No circular references

---

### Rule 8: Lambda Expression Consistency

**If using λ-expressions, follow this format**:

```clojure
λ(input).action ⟺ [
  step_one(input),
  step_two(result),
  step_three(result),
  output(result)
]
```

**Checks**:
- [ ] Lambda expressions use `λ` symbol
- [ ] Arrow operator `⟺` or `→` used correctly
- [ ] Steps are executable
- [ ] Output clearly defined

---

## Running Validation

### Manual Validation

```bash
# Validate single skill
cd skills/skill-name
validate_skill.sh SKILL.md

# Validate all skills
cd skills
validate_all_skills.sh
```

### Automated Validation Script

**Create `skills/validate_skills.sh`**:

```bash
#!/bin/bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/skills"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() { echo -e "${GREEN}✓${NC} $1"; ((PASS_COUNT++)); }
check_fail() { echo -e "${RED}✗${NC} $1"; ((FAIL_COUNT++)); }
check_warn() { echo -e "${YELLOW}⚠${NC} $1"; ((WARN_COUNT++)); }

echo "========================================"
echo "Nucleus Skills Validation"
echo "========================================"
echo ""

for skill_dir in */; do
    if [ "$skill_dir" = "_" ] || [ "$skill_dir" = "examples/" ]; then
        continue
    fi

    skill="${skill_dir%/}"
    skill_file="$skill_dir/SKILL.md"

    if [ ! -f "$skill_file" ]; then
        check_fail "$skill: SKILL.md not found"
        continue
    fi

    echo "Checking $skill..."

    # Rule 1: Frontmatter
    if grep -q "^---$" "$skill_file" | head -1; then
        check_pass "$skill: Frontmatter present"
    else
        check_fail "$skill: Frontmatter missing"
    fi

    # Rule 2: Name matches directory
    name=$(grep "^name:" "$skill_file" | cut -d: -f2 | xargs)
    if [ "$name" = "$skill" ]; then
        check_pass "$skill: Name matches directory"
    else
        check_warn "$skill: Name ($name) != directory ($skill)"
    fi

    # Rule 3: Framework header
    if grep -q "engage nucleus:" "$skill_file"; then
        check_pass "$skill: Framework header present"
    else
        check_fail "$skill: Framework header missing"
    fi

    # Rule 4: Eight Keys table
    if grep -q "## Eight Keys Reference" "$skill_file"; then
        check_pass "$skill: Eight Keys section present"
    else
        check_fail "$skill: Eight Keys section missing"
    fi

    # Rule 5: Line count
    lines=$(wc -l < "$skill_file")
    if [ "$lines" -ge 150 ] && [ "$lines" -le 350 ]; then
        check_pass "$skill: Line count $lines (within range)"
    elif [ "$lines" -lt 150 ]; then
        check_warn "$skill: Line count $lines (below 150, may be incomplete)"
    else
        check_warn "$skill: Line count $lines (above 350, may be verbose)"
    fi

    # Rule 6: Required sections
    required_sections=("Identity" "Core Principle" "Procedure" "Examples" "Verification")
    for section in "${required_sections[@]}"; do
        if grep -q "^## $section" "$skill_file"; then
            : # pass
        else
            check_warn "$skill: Section '$section' missing"
        fi
    done

    echo ""
done

echo "========================================"
echo "Validation Summary"
echo "========================================"
echo -e "${GREEN}Passed:${NC} $PASS_COUNT"
echo -e "${YELLOW}Warnings:${NC} $WARN_COUNT"
echo -e "${RED}Failed:${NC} $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Validation failed${NC}"
    exit 1
fi
```

---

## Skill Scoring System

**Score skills on 0-100 scale**:

| Criterion | Max Score | Weight |
|-----------|-----------|--------|
| Frontmatter completeness | 15 | 15% |
| Framework header | 10 | 10% |
| Lean structure | 15 | 15% |
| Section completeness | 20 | 20% |
| Prompt proportionality | 10 | 10% |
| Unique value (no redundancy) | 15 | 15% |
| Documentation quality | 15 | 15% |
| **Total** | **100** | **100%** |

**Grade thresholds**:
- **90-100**: Excellent ✅
- **80-89**: Good ⚠️
- **70-79**: Needs improvement ⚠️
- **< 70**: Failing ❌

---

## Improvement Checklist

Before finalizing a skill:

### Structure
- [ ] Frontmatter complete (name, description, version)
- [ ] Framework header present
- [ ] All required sections present
- [ ] Main prompt stays lean

### Content
- [ ] Identity clear (who are you, tone, goal)
- [ ] Trigger boundary explicit
- [ ] Core principle concise (1 paragraph)
- [ ] Procedure executable (λ-calculus or steps)
- [ ] Examples concise and realistic
- [ ] Verification gates (1 checklist)
- [ ] Optional sections only where they help

### Quality
- [ ] No verbosity (remove fluff paragraphs)
- [ ] No duplication (reference instead)
- [ ] Cross-skill redundancy checked
- [ ] Documentation links resolve
- [ ] Lambda expressions consistent

### Framework Integration
- [ ] Collaborates with other skills
- [ ] Nucleus symbols used correctly
- [ ] Framework header task-appropriate

---

## Pre-Commit Hook for Skills

Add `.git/hooks/skill-pre-commit`:

```bash
#!/bin/bash

# Validate skills if SKILL.md files changed
if git diff --cached --name-only | grep -q "SKILL.md"; then
    echo "Skills changed. Running validation..."
    ./skills/validate_skills.sh

    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Skill validation failed. Commit aborted."
        echo "Fix validation errors before committing."
        exit 1
    fi
fi
```

Make executable:
```bash
chmod +x .git/hooks/skill-pre-commit
```

---

## Skill Versioning

**Follow semantic versioning**:

- **MAJOR (X.0.0)**: Complete restructure, scope change, removal
- **MINOR (0.X.0)**: Add sections, expand guidance, new examples
- **PATCH (0.0.X)**: Typos, clarifications, formatting

**Update CHANGELOG.md** in skill directory:

```markdown
# Changelog

## [1.0.0] - 2026-02-20

### Added
- Initial skill definition
- Core procedure and verification gates
- Eight Keys reference

## [0.9.0] - 2026-02-19

### Changed
- Improved examples
- Added decision matrix
```

---

## Status Matrix

| Skill | Version | Status | Last Validated |
|-------|---------|--------|----------------|
| clojure-expert | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| clojure-reviewer | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| continuous-learning | 1.0.0 | ✅ Excellent | 2026-02-20 |
| nucleus-tutor | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| planning | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| sarcasmotron | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| reddit | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| requesthunt | 0.1.0 | ⚠️ Needs review | 2026-02-20 |
| seo-geo | 0.1.0 | ⚠️ Needs review | 2026-02-20 |

---

**Last updated**: 2026-02-20
