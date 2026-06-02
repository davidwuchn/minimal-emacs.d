#!/usr/bin/env bash
# TDD: run-pipeline git sync must not replay stale stashes on unmerged paths.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINE="$DIR/scripts/run-pipeline.sh"
PASS=0
FAIL=0
red='\033[0;31m'
green='\033[0;32m'
nc='\033[0m'

pass() { echo -e "${green}✓${nc} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${red}✗${nc} $1"; FAIL=$((FAIL + 1)); }
section() { echo; echo "=== $1 ==="; }

extract_function() {
  local name="$1"
  awk -v name="$name" '
    $0 ~ "^" name "\\(\\)" { printing=1 }
    printing { print }
    printing && $0 == "}" { exit }
  ' "$PIPELINE"
}

TMP_FUNCS="$(mktemp)"
trap 'rm -f "$TMP_FUNCS"' EXIT

section "Function presence"

for fn in pipeline_git_has_unmerged_paths pipeline_clear_auto_generated_unmerged_paths pipeline_git_sync_latest; do
  if grep -q "^${fn}()" "$PIPELINE"; then
    pass "$fn is defined"
    extract_function "$fn" >> "$TMP_FUNCS"
  else
    fail "$fn is missing"
  fi
done

if [ "$FAIL" -eq 0 ]; then
  # shellcheck disable=SC1090
  source "$TMP_FUNCS"
  PIPELINE_LOG="$(mktemp)"

  section "Auto-generated conflict cleanup"
  declare -a GIT_CALLS=()
  CLEARED=0
  log() { :; }
  git() {
    GIT_CALLS+=("$*")
    case "$*" in
      *"diff --name-only --diff-filter=U"*)
        if [ "$CLEARED" -eq 0 ]; then
          printf 'mementum/knowledge/backend-comparison.md\nassistant/skills/researcher-prompt/data/strategy-guidance.json\n'
        fi
        return 0
        ;;
      *"checkout HEAD -- mementum/knowledge/ assistant/skills/ assistant/strategies/"*)
        CLEARED=1
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  if pipeline_clear_auto_generated_unmerged_paths; then
    pass "auto-generated unmerged paths are clearable"
  else
    fail "auto-generated unmerged paths should be clearable"
  fi
  if printf '%s\n' "${GIT_CALLS[@]}" | grep -q 'checkout HEAD -- mementum/knowledge/ assistant/skills/ assistant/strategies/'; then
    pass "cleanup checks out auto-generated dirs"
  else
    fail "cleanup did not check out auto-generated dirs"
  fi

  section "No stale stash pop after stash failure"
  GIT_CALLS=()
  git() {
    GIT_CALLS+=("$*")
    case "$*" in
      *"diff --name-only --diff-filter=U"*) return 0 ;;
      *"stash push"*) printf 'error: cannot stash unmerged paths\n'; return 1 ;;
      *"stash pop"*) return 0 ;;
      *) return 0 ;;
    esac
  }
  pipeline_git_sync_latest "test sync" "test-stash"
  if printf '%s\n' "${GIT_CALLS[@]}" | grep -q 'stash pop'; then
    fail "stash pop ran even though stash push failed"
  else
    pass "stash pop skipped when stash push failed"
  fi
fi

section "Syntax"
if bash -n "$PIPELINE" 2>/dev/null; then
  pass "run-pipeline.sh syntax OK"
else
  fail "run-pipeline.sh syntax error"
fi

echo
echo "=== Summary: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
