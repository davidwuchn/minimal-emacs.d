#!/usr/bin/env bash
# TDD: verify install-ops-global.sh model updates use cross-platform perl
# Regression: BSD sed wrapper was needed because install.sh uses GNU sed
# features. Switching to perl -pi -e makes the script cross-platform
# without a wrapper.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
red='\033[0;31m'; green='\033[0;32m'; nc='\033[0m'
pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

INSTALL_OPS="$DIR/scripts/install-ops-global.sh"

section "update_model uses cross-platform perl (not sed)"

# Verify the model update line uses perl -pi -e (cross-platform).
# Quoting varies, so check the essential tokens: perl -pi -e + model:.*|model:
if grep -Eq "perl -pi -e.*model:.*\|model:" "$INSTALL_OPS"; then
    pass "update_model uses perl -pi -e for cross-platform replacement"
else
    fail "update_model does not use perl -pi -e (relying on BSD sed wrapper?)"
fi

# The old BSD sed compatibility wrapper should be removed when we use perl
if grep -q 'SEDWRAP\|SED_WRAP_DIR\|sed-wrapper' "$INSTALL_OPS"; then
    fail "BSD sed wrapper still present (should be removed when using perl)"
else
    pass "BSD sed wrapper removed (perl handles cross-platform)"
fi

section "Primary agent model insert uses perl (not GNU sed 'a' command)"

# The primary agents block used GNU sed '/pat/a\text' to append after match.
# With perl, we use a simple conditional print.
if grep -q "perl -i -pe.*description" "$INSTALL_OPS"; then
    pass "Primary agent update uses perl -i -pe with description regex"
else
    fail "Primary agent update does not use perl (relying on GNU sed 'a' command?)"
fi

section "Functional check: perl model update works in practice"

TMPDIR_TEST="$(mktemp -d)"
trap "rm -rf $TMPDIR_TEST" EXIT
SAMPLE="$TMPDIR_TEST/agent.md"
cat > "$SAMPLE" <<'EOF'
---
description: A test agent
model: some-provider/old-model
---
body
EOF

# Run the perl command that update_model should use
perl -pi -e 's|^model:.*|model: some-provider/kimi-k2.6|' "$SAMPLE"

if grep -q "^model: some-provider/kimi-k2.6" "$SAMPLE"; then
    pass "perl -pi -e correctly replaces model line"
else
    fail "perl -pi -e did not replace model line"
fi

if grep -q "^description: A test agent" "$SAMPLE"; then
    pass "perl -pi -e preserves other lines (description)"
else
    fail "perl -pi -e broke other lines"
fi

section "Functional check: perl primary-agent insert works in practice"

SAMPLE2="$TMPDIR_TEST/agent2.md"
cat > "$SAMPLE2" <<'EOF'
---
description: A test agent
---
body
EOF

# Insert model after description, removing any existing model line
perl -i -pe 'if (/^model:/) { $_ = ""; } elsif (/^description:/) { $_ = $_ . "model: some-provider/kimi-k2.6\n"; }' "$SAMPLE2"

if grep -q "^model: some-provider/kimi-k2.6" "$SAMPLE2"; then
    pass "perl inserts model after description"
else
    fail "perl did not insert model after description"
fi
if grep -q "^description: A test agent$" "$SAMPLE2"; then
    pass "description line preserved verbatim"
else
    fail "description line was modified"
fi
if ! grep -q "^model: " "$SAMPLE2" | grep -v kimi >/dev/null; then
    :  # Only one model line expected
fi
MODEL_COUNT=$(grep -c "^model: " "$SAMPLE2")
if [ "$MODEL_COUNT" -eq 1 ]; then
    pass "exactly one model line in output (idempotent)"
else
    fail "expected 1 model line, got $MODEL_COUNT"
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
