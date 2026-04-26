#!/usr/bin/env bash

# run-tests.sh - Unified test runner for Emacs.d
#
# Usage:
#   ./scripts/run-tests.sh              # Run all tests
#   ./scripts/run-tests.sh unit         # Run ERT unit tests only
#   ./scripts/run-tests.sh e2e          # Run E2E tests only
#   ./scripts/run-tests.sh cron         # Run cron installation tests only
#   ./scripts/run-tests.sh workflow     # Run auto-workflow tests only
#   ./scripts/run-tests.sh all          # Run everything
#
# Returns 0 if all tests pass, 1 if any fail.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.bash"

SUBCOMMAND="${1:-all}"

touch_minutes_ago() {
    local minutes="$1"
    local path="$2"

    python3 - "$minutes" "$path" <<'PY'
import os
import sys
import time

minutes = float(sys.argv[1])
path = sys.argv[2]
stamp = time.time() - (minutes * 60.0)
os.utime(path, (stamp, stamp))
PY
}

# ═══════════════════════════════════════════════════════════════════════════
# ERT Unit Tests
# ═══════════════════════════════════════════════════════════════════════════

run_unit_tests() {
    local PATTERN="${1:-t}"
    local status_file
    local messages_file
    local snapshot_paths_file
    local runtime_dir
    local workflow_server
    local ert_status=0
    
    section "Unit Tests (ERT)"
    
    echo "Running ERT tests (pattern: $PATTERN)..."
    echo ""

    status_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-test-status.XXXXXX")" || {
        fail "Failed to create isolated workflow status file"
        return 1
    }
    messages_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-test-messages.XXXXXX")" || {
        rm -f "$status_file"
        fail "Failed to create isolated workflow messages file"
        return 1
    }
    snapshot_paths_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-test-snapshot-paths.XXXXXX")" || {
        rm -f "$status_file" "$messages_file"
        fail "Failed to create isolated workflow snapshot cache file"
        return 1
    }
    runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/auto-workflow-test-runtime.XXXXXX")" || {
        rm -f "$status_file" "$messages_file" "$snapshot_paths_file"
        fail "Failed to create isolated workflow runtime directory"
        return 1
    }
    chmod 700 "$runtime_dir"
    workflow_server="copilot-auto-workflow-test-$(basename "$runtime_dir")"
    
    local output
    set +e
    output=$(AUTO_WORKFLOW_STATUS_FILE="$status_file" \
        AUTO_WORKFLOW_MESSAGES_FILE="$messages_file" \
        AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE="$snapshot_paths_file" \
        AUTO_WORKFLOW_EMACS_SERVER="$workflow_server" \
        XDG_RUNTIME_DIR="$runtime_dir" \
        TMPDIR="$runtime_dir" \
        emacs --batch -Q \
        -L "$DIR" \
        -L "$DIR/lisp" \
        -L "$DIR/lisp/modules" \
        -L "$DIR/packages/gptel" \
        -L "$DIR/packages/gptel-agent" \
        -L "$DIR/tests" \
        -l ert \
        --eval "(setq load-prefer-newer t)" \
        --eval "(advice-add (quote startup-redirect-eln-cache) :override (lambda (dir) (push (expand-file-name (file-name-as-directory dir) user-emacs-directory) native-comp-eln-load-path)))" \
        --eval "(when (and (boundp 'native-comp-enable-subr-trampolines) native-comp-enable-subr-trampolines (fboundp 'comp-subr-trampoline-install) (fboundp 'subr-primitive-p)) (mapc (lambda (fn) (and (fboundp fn) (subr-primitive-p (symbol-function fn)) (comp-subr-trampoline-install fn))) (quote (file-exists-p file-executable-p call-process kill-buffer message directory-files require featurep process-list process-name system-name))))" \
        $(find tests -name "test-*.el" -exec echo "-l {}" \;) \
        --eval "(ert-run-tests-batch-and-exit \"$PATTERN\")" 2>&1)
    ert_status=$?
    set -e
    rm -f "$status_file" "$messages_file" "$snapshot_paths_file"
    rm -rf "$runtime_dir"
    
    grep -E "FAILED|unexpected|0 unexpected" <<< "$output" | head -30
    if [ -z "$(grep -E "FAILED|unexpected" <<< "$output")" ]; then
        echo "$output" | tail -5
    fi
    
    if [ "$ert_status" -eq 0 ] && grep -q "0 unexpected" <<< "$output" && ! grep -q "^Aborted:" <<< "$output"; then
        pass "All ERT tests passed"
        return 0
    else
        if grep -q "^Aborted:" <<< "$output"; then
            fail "ERT run aborted"
        else
            fail "Some ERT tests failed"
        fi
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Auto-Workflow E2E Tests
# ═══════════════════════════════════════════════════════════════════════════

run_e2e_tests() {
    local RUNNER="$DIR/scripts/run-auto-workflow-cron.sh"
    local complete_status_file=""
    local complete_messages_file=""
    local complete_runtime_dir=""
    local complete_server=""
    local complete_daemon_log=""
    local live_messages_status_file=""
    local live_messages_file=""
    local live_messages_runtime_dir=""
    local live_messages_server=""
    local daemon_ready=0
    local status_output=""
    
    section "Auto-Workflow E2E"
    
    # Prerequisites
    echo "Checking prerequisites..."
    if [ ! -x "$RUNNER" ]; then
        fail "wrapper missing or not executable: $RUNNER"
        return 1
    fi
    pass "wrapper exists: $RUNNER"
    
    EMACSCLIENT="$(resolve_emacsclient)" || {
        fail "emacsclient not found"
        return 1
    }
    pass "emacsclient is resolvable"
    
    # Wrapper status
    echo ""
    echo "Checking wrapper status..."
    if "$RUNNER" status | grep -q ':phase'; then
        pass "wrapper returns a workflow status snapshot"
    else
        fail "wrapper status did not return workflow data"
        return 1
    fi
    
    # Required modules
    echo ""
    echo "Checking required modules..."
    for module in gptel-tools-agent.el gptel-auto-workflow-projects.el gptel-auto-workflow-strategic.el; do
        if [ -f "$DIR/lisp/modules/$module" ]; then
            pass "$module exists"
        else
            fail "$module missing"
            return 1
        fi
    done

    # Daemon truth should override stale persisted running snapshots
    echo ""
    echo "Checking daemon completion recovery..."
    complete_status_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-complete-status.XXXXXX")" || {
        fail "Failed to create complete-state status file"
        return 1
    }
    complete_messages_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-complete-messages.XXXXXX")" || {
        rm -f "$complete_status_file"
        fail "Failed to create complete-state messages file"
        return 1
    }
    complete_runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/aw-comp.XXXXXX")" || {
        rm -f "$complete_status_file" "$complete_messages_file"
        fail "Failed to create complete-state runtime dir"
        return 1
    }
    complete_daemon_log="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-complete-daemon.XXXXXX")" || {
        rm -f "$complete_status_file" "$complete_messages_file"
        rm -rf "$complete_runtime_dir"
        fail "Failed to create complete-state daemon log"
        return 1
    }
    chmod 700 "$complete_runtime_dir"
    complete_server="aw-complete-$$"

    printf '%s\n' '(:running t :kept 0 :total 5 :phase "running" :run-id "stale-complete" :results "var/tmp/experiments/stale-complete/results.tsv")' >"$complete_status_file"
    printf '%s\n' '[auto-workflow] stale running snapshot' >"$complete_messages_file"
    touch_minutes_ago 2 "$complete_status_file"

    env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XAUTHORITY \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        XDG_RUNTIME_DIR="$complete_runtime_dir" \
        emacs --init-directory="$DIR" --bg-daemon="$complete_server" >"$complete_daemon_log" 2>&1 || true

    for _ in $(seq 1 100); do
        if env XDG_RUNTIME_DIR="$complete_runtime_dir" \
           emacsclient -a false -s "$complete_server" --eval "t" >/dev/null 2>&1; then
            daemon_ready=1
            break
        fi
        sleep 0.2
    done

    if [ "$daemon_ready" -ne 1 ]; then
        tail -n 80 "$complete_daemon_log" >&2 || true
        emacsclient -a false -s "$complete_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
        rm -f "$complete_status_file" "$complete_messages_file" "$complete_daemon_log"
        rm -rf "$complete_runtime_dir"
        fail "Test daemon did not start"
        return 1
    fi

    env XDG_RUNTIME_DIR="$complete_runtime_dir" \
        emacsclient -a false -s "$complete_server" --eval \
        "(progn
           (load-file \"$DIR/lisp/modules/gptel-tools-agent.el\")
           (setq gptel-auto-workflow--stats '(:phase \"complete\" :total 5 :kept 0)
                 gptel-auto-workflow--running nil
                 gptel-auto-workflow--run-id nil
                 gptel-auto-workflow--current-target nil
                 gptel-auto-workflow--current-project nil)
           t)" >/dev/null 2>&1 || {
        emacsclient -a false -s "$complete_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
        rm -f "$complete_status_file" "$complete_messages_file" "$complete_daemon_log"
        rm -rf "$complete_runtime_dir"
        fail "Failed to seed daemon with completed workflow state"
        return 1
    }

    if ! status_output=$(AUTO_WORKFLOW_STATUS_FILE="$complete_status_file" \
        AUTO_WORKFLOW_MESSAGES_FILE="$complete_messages_file" \
        AUTO_WORKFLOW_EMACS_SERVER="$complete_server" \
        XDG_RUNTIME_DIR="$complete_runtime_dir" \
        AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
        "$RUNNER" status); then
        env XDG_RUNTIME_DIR="$complete_runtime_dir" \
            emacsclient -a false -s "$complete_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
        rm -f "$complete_status_file" "$complete_messages_file" "$complete_daemon_log"
        rm -rf "$complete_runtime_dir"
        fail "wrapper status failed while checking daemon completion recovery"
        return 1
    fi

    env XDG_RUNTIME_DIR="$complete_runtime_dir" \
        emacsclient -a false -s "$complete_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true

    if grep -q ':phase "complete"' <<< "$status_output" &&
       grep -q ':phase "complete"' "$complete_status_file" &&
       ! grep -q ':running t' "$complete_status_file"; then
        pass "wrapper rewrites stale running snapshot from daemon completion"
    else
        rm -f "$complete_status_file" "$complete_messages_file" "$complete_daemon_log"
        rm -rf "$complete_runtime_dir"
        fail "wrapper kept stale running snapshot after daemon completion"
        return 1
    fi

    rm -f "$complete_status_file" "$complete_messages_file" "$complete_daemon_log"
    rm -rf "$complete_runtime_dir"

    echo ""
    echo "Checking live messages refresh..."
    live_messages_status_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-live-status.XXXXXX")" || {
        fail "Failed to create live-messages status file"
        return 1
    }
    live_messages_file="$(mktemp "${TMPDIR:-/tmp}/auto-workflow-live-messages.XXXXXX")" || {
        rm -f "$live_messages_status_file"
        fail "Failed to create live-messages file"
        return 1
    }
    live_messages_runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/aw-live.XXXXXX")" || {
        rm -f "$live_messages_status_file" "$live_messages_file"
        fail "Failed to create live-messages runtime dir"
        return 1
    }
    chmod 700 "$live_messages_runtime_dir"
    live_messages_server="aw-live-msg-$$"

    printf '%s\n' '(:running t :kept 0 :total 3 :phase "running" :run-id "live-messages" :results "var/tmp/experiments/live-messages/results.tsv")' >"$live_messages_status_file"
    printf '%s\n' '[auto-workflow] stale persisted tail' >"$live_messages_file"
    touch_minutes_ago 2 "$live_messages_file"

    daemon_ready=0
    env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XAUTHORITY \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
        emacs --init-directory="$DIR" --bg-daemon="$live_messages_server" >/dev/null 2>&1 || true

    for _ in $(seq 1 100); do
        if env XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
           emacsclient -a false -s "$live_messages_server" --eval "t" >/dev/null 2>&1; then
            daemon_ready=1
            break
        fi
        sleep 0.2
    done

    if [ "$daemon_ready" -ne 1 ]; then
        env XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
            emacsclient -a false -s "$live_messages_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
        rm -f "$live_messages_status_file" "$live_messages_file"
        rm -rf "$live_messages_runtime_dir"
        fail "Live-messages test daemon did not start"
        return 1
    fi

    env XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
        emacsclient -a false -s "$live_messages_server" --eval \
        "(progn
           (load-file \"$DIR/lisp/modules/gptel-tools-agent.el\")
           (setq gptel-auto-workflow--stats '(:phase \"running\" :total 3 :kept 0)
                 gptel-auto-workflow--running t
                 gptel-auto-workflow--run-id \"live-messages\"
                 gptel-auto-workflow--current-target \"lisp/modules/gptel-agent-loop.el\")
           (with-current-buffer (get-buffer-create \"*Messages*\")
             (let ((inhibit-read-only t))
               (goto-char (point-max))
               (insert \"[auto-workflow] live daemon message sentinel\\n\")))
           t)" >/dev/null 2>&1 || {
        env XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
            emacsclient -a false -s "$live_messages_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
        rm -f "$live_messages_status_file" "$live_messages_file"
        rm -rf "$live_messages_runtime_dir"
        fail "Failed to seed daemon with live messages state"
        return 1
    }

    if status_output=$(AUTO_WORKFLOW_STATUS_FILE="$live_messages_status_file" \
        AUTO_WORKFLOW_MESSAGES_FILE="$live_messages_file" \
        AUTO_WORKFLOW_EMACS_SERVER="$live_messages_server" \
        XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
        AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL=45 \
        "$RUNNER" messages) &&
       grep -q 'live daemon message sentinel' <<< "$status_output" &&
       grep -q 'live daemon message sentinel' "$live_messages_file" &&
       ! grep -q 'stale persisted tail' "$live_messages_file"; then
        pass "wrapper refreshes stale messages from active daemon"
    else
        env XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
            emacsclient -a false -s "$live_messages_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
        rm -f "$live_messages_status_file" "$live_messages_file"
        rm -rf "$live_messages_runtime_dir"
        fail "wrapper kept stale messages while daemon was active"
        return 1
    fi

    env XDG_RUNTIME_DIR="$live_messages_runtime_dir" \
        emacsclient -a false -s "$live_messages_server" --eval "(kill-emacs)" >/dev/null 2>&1 || true
    rm -f "$live_messages_status_file" "$live_messages_file"
    rm -rf "$live_messages_runtime_dir"
    
    # Cron configuration
    echo ""
    echo "Checking cron configuration..."
    if crontab -l 2>/dev/null | grep -Eq '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow'; then
        pass "Auto-workflow cron job installed"
    else
        fail "Wrapper-based auto-workflow cron job not found"
        return 1
    fi
    
    # Required directories
    echo ""
    echo "Checking required directories..."
    for dir in var/tmp/cron var/tmp/experiments; do
        if [ -d "$DIR/$dir" ]; then
            pass "$dir exists"
        else
            mkdir -p "$DIR/$dir"
            pass "$dir created"
        fi
    done
    
    # Batch bootstrap
    echo ""
    echo "Testing batch module loading..."
    if run_batch_bootstrap >/dev/null 2>&1; then
        pass "auto-workflow modules load successfully in batch mode"
    else
        fail "Failed to load auto-workflow modules in batch mode"
        return 1
    fi
    
    # Entrypoints
    echo ""
    echo "Checking workflow entrypoints..."
    if "$RUNNER" status | grep -q ':phase'; then
        pass "wrapper status remains responsive"
    else
        fail "wrapper status did not return workflow data"
        return 1
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Cron Installation Tests
# ═══════════════════════════════════════════════════════════════════════════

run_cron_tests() {
    local CRON_FILE="$DIR/cron.d/auto-workflow"
    local RUNNER="$DIR/scripts/run-auto-workflow-cron.sh"
    local INSTALLER="$DIR/scripts/install-cron.sh"
    local LOGDIR="$DIR/var/tmp/cron"
    local RENDERED
    local FAKE_ROOT
    local FAKE_BIN
    local FAKE_CRONTAB
    
    section "Cron Installation"
    
    # Cron template
    if [ -f "$CRON_FILE" ]; then
        pass "Crontab template exists: $CRON_FILE"
    else
        fail "Crontab template missing: $CRON_FILE"
        return 1
    fi
    
    if grep -q 'SHELL=/bin/bash' "$CRON_FILE"; then
        pass "SHELL=/bin/bash is set"
    else
        fail "SHELL not set to /bin/bash"
    fi
    
    if grep -q 'run-auto-workflow-cron.sh auto-workflow' "$CRON_FILE"; then
        pass "Template uses wrapper for auto-workflow"
    else
        fail "Template does not use wrapper for auto-workflow"
    fi
    
    # Rendered crontab
    RENDERED=$(mktemp)
    FAKE_ROOT=$(mktemp -d)
    FAKE_BIN="$FAKE_ROOT/bin"
    FAKE_CRONTAB="$FAKE_ROOT/crontab.txt"
    trap 'rm -f "${RENDERED:-}"; rm -rf "${FAKE_ROOT:-}"' RETURN
    "$INSTALLER" --render > "$RENDERED"
    
    if grep -Eq '^[0-9*@]' "$RENDERED"; then
        pass "Rendered crontab contains active schedules"
    else
        fail "Rendered crontab has no active schedules"
        rm -f "$RENDERED"
        return 1
    fi

    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/crontab" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

store="${FAKE_CRONTAB_STORE:?}"

case "${1:-}" in
    -l)
        [ -f "$store" ] || exit 1
        cat "$store"
        ;;
    "")
        cat > "$store"
        ;;
    *)
        cat "$1" > "$store"
        ;;
esac
EOF
    chmod +x "$FAKE_BIN/crontab"
    printf '30 2 * * * /usr/bin/true\n' > "$FAKE_CRONTAB"

    PATH="$FAKE_BIN:$PATH" FAKE_CRONTAB_STORE="$FAKE_CRONTAB" "$INSTALLER" install >/dev/null
    PATH="$FAKE_BIN:$PATH" FAKE_CRONTAB_STORE="$FAKE_CRONTAB" "$INSTALLER" install >/dev/null

    if grep -q '^30 2 \* \* \* /usr/bin/true$' "$FAKE_CRONTAB" &&
       grep -Eq '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow' "$FAKE_CRONTAB" &&
       [ "$(grep -c '^# >>> minimal-emacs\.d auto-workflow >>>$' "$FAKE_CRONTAB")" -eq 1 ]; then
        pass "Installer merges workflow block idempotently"
    else
        fail "Installer did not merge workflow block correctly"
        return 1
    fi
    
    if crontab -l >/dev/null 2>&1; then
        pass "User crontab is installed"
    else
        skip "No user crontab installed"
    fi
    
    # Log directory
    if [ -d "$LOGDIR" ]; then
        pass "Log directory exists: $LOGDIR"
    else
        fail "Log directory missing: $LOGDIR"
    fi
    
    # Cron daemon
    if systemctl is-active --quiet cron 2>/dev/null; then
        pass "Cron daemon is running (systemd)"
    elif service cron status >/dev/null 2>&1; then
        pass "Cron daemon is running (service)"
    elif pgrep -x "cron" >/dev/null; then
        pass "Cron daemon is running (pgrep)"
    else
        fail "Cron daemon is NOT running"
    fi
    
    # Log writability
    local TEST_LOG="$LOGDIR/test-write-$$.log"
    if touch "$TEST_LOG" 2>/dev/null; then
        pass "Can create log files in $LOGDIR"
        rm -f "$TEST_LOG"
    else
        fail "Cannot create log files in $LOGDIR"
    fi
    
    rm -f "$RENDERED"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Auto-Workflow Tests
# ═══════════════════════════════════════════════════════════════════════════

run_workflow_tests() {
    local ORIGINAL_BRANCH
    ORIGINAL_BRANCH=$(git branch --show-current)
    
    section "Auto-Workflow"
    
    # Emacs server
    echo "Checking Emacs server..."
    if emacsclient --eval "t" >/dev/null 2>&1; then
        pass "Emacs server is running"
    else
        fail "Emacs server not running"
        return 1
    fi
    
    # Function exists
    echo "Checking function..."
    if emacsclient --eval "(fboundp 'gptel-auto-workflow-run-async)" 2>/dev/null | grep -q "t"; then
        pass "gptel-auto-workflow-run-async is defined"
    else
        skip "gptel-auto-workflow-run-async is NOT defined (may not be loaded)"
    fi
    
    # Git configuration
    if git rev-parse --git-dir >/dev/null 2>&1; then
        pass "In git repository"
    else
        fail "Not in git repository"
        return 1
    fi
    
    if [ -n "$ORIGINAL_BRANCH" ]; then
        pass "Current branch: $ORIGINAL_BRANCH"
    else
        fail "Could not detect current branch"
    fi
    
    # Verify script
    local VERIFY_SCRIPT="$DIR/scripts/verify-nucleus.sh"
    if [ -x "$VERIFY_SCRIPT" ]; then
        pass "Verify script exists and is executable"
    else
        skip "Verify script not found or not executable"
    fi
    
    # Target files
    echo "Checking target files..."
    for target in "gptel-ext-retry.el" "gptel-ext-context.el" "gptel-tools-code.el"; do
        if [ -f "$DIR/lisp/modules/$target" ]; then
            pass "Target exists: $target"
        else
            fail "Target missing: $target"
        fi
    done
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

reset_counters
FAILED=0

case "$SUBCOMMAND" in
    unit|u)
        run_unit_tests || FAILED=1
        ;;
    e2e|e)
        run_e2e_tests || FAILED=1
        ;;
    cron|c)
        run_cron_tests || FAILED=1
        ;;
    workflow|w)
        run_workflow_tests || FAILED=1
        ;;
    all|a)
        run_unit_tests || FAILED=1
        echo ""
        run_e2e_tests || FAILED=1
        echo ""
        run_cron_tests || FAILED=1
        echo ""
        run_workflow_tests || FAILED=1
        ;;
    *)
        echo "Usage: $0 {unit|e2e|cron|workflow|all}"
        echo ""
        echo "  unit, u      - ERT unit tests only"
        echo "  e2e, e       - Auto-workflow E2E tests only"
        echo "  cron, c      - Cron installation tests only"
        echo "  workflow, w  - Auto-workflow tests only"
        echo "  all, a       - Run all tests (default)"
        exit 1
        ;;
esac

echo ""
print_summary

if [ "$FAIL" -gt 0 ] || [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
