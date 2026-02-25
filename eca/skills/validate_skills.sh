#!/bin/bash
# Nucleus Skills Validator - Check consistency across all skills

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/skills"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_COUNT++))
}

echo "========================================"
echo "Nucleus Skills Validation"
echo "========================================"
echo ""

# Count total skills
SKILL_COUNT=0
VALID_SKILLS=0

for skill_dir in */; do
    # Skip special directories
    if [[ "$skill_dir" =~ ^(_|examples|templates|scripts|instincts) ]]; then
        continue
    fi

    skill="${skill_dir%/}"
    skill_file="$skill_dir/SKILL.md"

    # Skip if no SKILL.md
    if [ ! -f "$skill_file" ]; then
        check_warn "$skill: SKILL.md not found"
        continue
    fi

    ((SKILL_COUNT++))
    echo -e "${BLUE}$skill${NC}"
    VALID_SKILLS=$((VALID_SKILLS + 1))

    # Rule 1: Frontmatter present
    if grep -q "^---$" "$skill_file" 2>/dev/null; then
        check_pass "  Frontmatter present"
    else
        check_fail "  Frontmatter missing"
    fi

    # Rule 2: Name matches directory
    name=$(grep "^name:" "$skill_file" 2>/dev/null | cut -d: -f2 | xargs || echo "")
    if [ -n "$name" ] && [ "$name" = "$skill" ]; then
        check_pass "  Name matches directory ($name)"
    else
        check_warn "  Name ($name) != directory ($skill)"
    fi

    # Rule 3: Description present
    if grep -q "^description:" "$skill_file"; then
        description=$(grep "^description:" "$skill_file" | cut -d: -f2- | xargs)
        if [ -n "$description" ]; then
            check_pass "  Description present: $description"
        else
            check_warn "  Description empty"
        fi
    else
        check_fail "  Description missing"
    fi

    # Rule 4: Version present
    if grep -q "^version:" "$skill_file"; then
        version=$(grep "^version:" "$skill_file" | cut -d: -f2 | xargs)
        if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            check_pass "  Version valid: $version"
        else
            check_warn "  Version format invalid: $version (expected X.Y.Z)"
        fi
    else
        check_warn "  Version missing (expected X.Y.Z)"
    fi

    # Rule 5: Framework header present
    if grep -q "engage nucleus:" "$skill_file"; then
        check_pass "  Framework header present"

        # Check for required symbols
        framework=$(grep -A 2 "engage nucleus:" "$skill_file" | head -3)
        missing_symbols=0

        # Human principles
        for symbol in "phi" "fractal" "euler" "tao" "pi" "mu"; do
            if ! echo "$framework" | grep -q "$symbol"; then
                ((missing_symbols++))
            fi
        done

        # AI principles
        for symbol in "Δ" "λ" "∞/0"; do
            if ! echo "$framework" | grep -q "$symbol"; then
                ((missing_symbols++))
            fi
        done

        if [ $missing_symbols -eq 0 ]; then
            check_pass "  All required symbols present"
        else
            check_warn "  Missing $missing_symbols required symbols"
        fi
    else
        check_fail "  Framework header missing"
    fi

    # Rule 6: Eight Keys section
    if grep -q "## Eight Keys Reference" "$skill_file"; then
        check_pass "  Eight Keys section present"

        # Check table has all 8 keys
        eight_keys_count=$(grep -A 20 "## Eight Keys Reference" "$skill_file" | grep -c "^\| \*\*" || echo 0)
        if [ "$eight_keys_count" -ge 8 ]; then
            check_pass "  Eight Keys table complete ($eight_keys_count keys)"
        else
            check_warn "  Eight Keys table incomplete ($eight_keys_count/8 keys)"
        fi
    else
        check_fail "  Eight Keys section missing"
    fi

    # Rule 7: Required sections
    required_sections=("Identity" "Core Principle" "Procedure" "Examples")
    missing_sections=0
    for section in "${required_sections[@]}"; do
        if ! grep -q "^## $section" "$skill_file"; then
            ((missing_sections++))
        fi
    done

    if [ $missing_sections -eq 0 ]; then
        check_pass "  All required sections present"
    else
        check_warn "  Missing $missing_sections required sections"
    fi

    # Rule 8: Line count
    lines=$(wc -l < "$skill_file" | xargs)
    if [ "$lines" -ge 150 ] && [ "$lines" -le 350 ]; then
        check_pass "  Line count optimal: $lines"
    elif [ "$lines" -lt 150 ]; then
        check_warn "  Line count low: $lines (may be incomplete, target 200-350)"
    else
        check_warn "  Line count high: $lines (may be verbose, target 200-350)"
    fi

    # Rule 9: Verification section
    if grep -q "^## Verification" "$skill_file" || grep -q "^## Definition of Done" "$skill_file"; then
        check_pass "  Verification/quality gates present"
    else
        check_warn "  Verification section missing"
    fi

    echo ""
done

echo "========================================"
echo "Validation Summary"
echo "========================================"
echo -e "Skills checked: ${BLUE}$VALID_SKILLS${NC}"
echo -e "${GREEN}Passed:${NC} $PASS_COUNT"
echo -e "${YELLOW}Warnings:${NC} $WARN_COUNT"
echo -e "${RED}Failed:${NC} $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    if [ $WARN_COUNT -eq 0 ]; then
        echo -e "${GREEN}✓ All skills validated successfully${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ All skills passed with warnings${NC}"
        exit 0
    fi
else
    echo -e "${RED}✗ Validation failed${NC}"
    exit 1
fi
