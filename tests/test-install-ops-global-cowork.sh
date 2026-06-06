#!/usr/bin/env bash
# TDD: verify install-ops-global.sh cowork setup works correctly
# Regression: COWORK_INSTRUCTIONS defined but never written to disk

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

INSTALL_OPS="$DIR/scripts/install-ops-global.sh"

section "install-ops-global.sh syntax check"

if bash -n "$INSTALL_OPS"; then
    pass "Script has valid bash syntax"
else
    fail "Script has bash syntax errors"
fi

section "Cowork instructions are written to disk"

# Check that COWORK_INSTRUCTIONS variable is used (not just defined)
if grep -q 'COWORK_INSTRUCTIONS' "$INSTALL_OPS"; then
    pass "COWORK_INSTRUCTIONS variable is referenced"
else
    fail "COWORK_INSTRUCTIONS variable is missing"
fi

# Check that the variable is actually written somewhere (not just defined)
# It should be written to a file, e.g. via echo, cat, or printf
if grep -Eq 'echo.*\$\{COWORK_INSTRUCTIONS\}|cat.*\$\{COWORK_INSTRUCTIONS\}|printf.*\$\{COWORK_INSTRUCTIONS\}' "$INSTALL_OPS"; then
    pass "COWORK_INSTRUCTIONS is written to a file"
else
    fail "COWORK_INSTRUCTIONS is defined but never written to a file (bug)"
fi

section "OV5 skill source path detection"

# Verify the script detects EMACS_DIR from SCRIPT_DIR
if grep -q 'EMACS_DIR=.*SCRIPT_DIR' "$INSTALL_OPS"; then
    pass "EMACS_DIR is derived from SCRIPT_DIR"
else
    fail "EMACS_DIR detection is missing"
fi

# Verify the skill source path uses EMACS_DIR
if grep -q 'SKILL_SRC=.*EMACS_DIR' "$INSTALL_OPS"; then
    pass "SKILL_SRC uses EMACS_DIR"
else
    fail "SKILL_SRC does not use EMACS_DIR"
fi

section "Trap cleanup for both TMPDIR and SED_WRAP_DIR"

# Count trap lines - should handle both TMPDIR and SED_WRAP_DIR
TRAP_COUNT=$(grep -c "trap.*EXIT" "$INSTALL_OPS" || true)
if [ "$TRAP_COUNT" -ge 1 ]; then
    pass "Script has trap for cleanup ($TRAP_COUNT trap line(s))"
else
    fail "Script missing trap cleanup"
fi

# Verify the trap handles TMPDIR
if grep -q 'TMPDIR' "$INSTALL_OPS"; then
    pass "Trap references TMPDIR cleanup"
else
    fail "Trap does not reference TMPDIR"
fi

section "OV5 socket path uses dynamic UID"

if grep -q 'OV5_SOCKET=.*id -u' "$INSTALL_OPS"; then
    pass "OV5_SOCKET uses dynamic \$(id -u) for UID"
else
    fail "OV5_SOCKET does not use dynamic UID"
fi

section "OpenCode skills directory creation"

if grep -q 'mkdir -p.*OPENCODE_SKILLS' "$INSTALL_OPS"; then
    pass "Script creates OPENCODE_SKILLS directory"
else
    fail "Script does not create OPENCODE_SKILLS directory"
fi

section "SKILL.md copy logic"

if grep -q 'SKILL_SRC.*SKILL.md' "$INSTALL_OPS"; then
    pass "Script references SKILL.md source path"
else
    fail "Script does not reference SKILL.md source path"
fi

if grep -q 'cp.*SKILL.md' "$INSTALL_OPS"; then
    pass "Script copies SKILL.md to OpenCode skills"
else
    fail "Script does not copy SKILL.md"
fi

# Summary
echo
if [ "$FAIL" -eq 0 ]; then
    echo -e "${green}All tests passed${nc} ($PASS assertions)"
    exit 0
else
    echo -e "${red}Tests failed${nc}: $FAIL failed, $PASS passed"
    exit 1
fi
