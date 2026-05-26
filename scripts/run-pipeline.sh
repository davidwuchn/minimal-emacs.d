#!/usr/bin/env bash
# Pipeline: Research → Digestion → Auto-Workflow
# Ensures research findings are digested before auto-workflow runs.
# Includes verification that findings feed into directive skill.

set -euo pipefail

# Prevent C stack overflow in deeply nested subagent calls
ulimit -s 65532 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DIR/scripts/run-auto-workflow-cron.sh"
LOG_DIR="$DIR/var/tmp/cron"
PIPELINE_LOG="$LOG_DIR/pipeline.log"
LOCK_FILE="$LOG_DIR/pipeline.lock"
MAX_WAIT_RESEARCH="${MAX_WAIT_RESEARCH:-900}"   # 15 minutes
MAX_WAIT_EVOLUTION="${MAX_WAIT_EVOLUTION:-900}" # 15 minutes
MAX_WAIT_WORKFLOW="${MAX_WAIT_WORKFLOW:-14400}" # 4 hours
POLL_INTERVAL="${POLL_INTERVAL:-30}"
PIPELINE_SMOKE_ONLY="${PIPELINE_SMOKE_ONLY:-no}"

# Quota-aware scheduling: when MiniMax is exhausted, run less frequently
QUOTA_RESET_FILE="$DIR/var/tmp/quota-reset-timestamp"

# Research output files
FINDINGS_FILE="$DIR/var/tmp/research-findings.md"
INTERNAL_FILE="$DIR/var/tmp/internal-research.md"
SKIP_IF_QUOTA_EXHAUSTED="${SKIP_IF_QUOTA_EXHAUSTED:-no}"

mkdir -p "$LOG_DIR"

log() {
    local line

    line="[pipeline $(date '+%H:%M:%S')] $*"
    printf '%s\n' "$line"
}

# Prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log "Pipeline already running (PID $lock_pid), skipping"
        exit 0
    fi
fi

# ─── Rotate oversized logs to prevent unbounded growth ───
log_rotate "$PIPELINE_LOG"
log_rotate "$LOG_DIR/ov5-researcher.log"
log_rotate "$LOG_DIR/ov5-auto-workflow.log"

wait_for_idle() {
    local action="$1"
    local max_wait="${2:-900}"
    local socket_name="${3:-ov5-auto-workflow}"
    local elapsed=0
    local daemon_was_seen=0
    local min_start_wait="${4:-60}"

    log "Waiting for $action to complete (max ${max_wait}s)..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        if [ "$socket_name" = "ov5-auto-workflow" ]; then
            local status
            status="$($SCRIPT status 2>/dev/null || true)"
            if printf '%s' "$status" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"|:running nil'; then
                # Verify experiments were actually produced (not just idle between cycles)
                if find "$DIR/var/tmp/experiments" -name "results.tsv" -newer "$PIPELINE_LOG" 2>/dev/null | grep -q .; then
                    log "$action completed after ${elapsed}s (experiments produced)"
                    return 0
                fi
                # Still idle but no experiments yet — daemon might be between cycles
                if [ "$elapsed" -gt 300 ]; then
                    log "$action completed after ${elapsed}s (no experiments after 5min idle, daemon likely done)"
                    return 0
                fi
            fi
            daemon_was_seen=1
        elif [ "$socket_name" = "ov5-researcher" ]; then
            # Researcher daemon is persistent; wait for findings file instead
            if [ -f "$FINDINGS_FILE" ] && [ "$(wc -c < "$FINDINGS_FILE" 2>/dev/null || echo 0)" -gt 100 ]; then
                if findings_mtime="$(stat -f %m "$FINDINGS_FILE" 2>/dev/null)"; then
                    :
                elif findings_mtime="$(stat -c %Y "$FINDINGS_FILE" 2>/dev/null)"; then
                    :
                else
                    findings_mtime=0
                fi
                if [ "$findings_mtime" -ge "$PIPELINE_START_TIME" ]; then
                    log "$action completed after ${elapsed}s (findings file ready)"
                    return 0
                fi
            fi
            # Check if researcher daemon reports phase complete/idle
            if [ "$daemon_was_seen" -eq 1 ]; then
                local phase
                phase="$(emacsclient --socket-name="ov5-researcher" \
                    --eval '(if (and (boundp (quote gptel-auto-workflow--stats)) gptel-auto-workflow--stats) (plist-get gptel-auto-workflow--stats :phase) "unknown")' 2>/dev/null || echo "unknown")"
                phase="${phase//\"/}"
                if [ "$phase" = "complete" ] || [ "$phase" = "idle" ]; then
                    log "$action daemon phase=$phase after ${elapsed}s"
                    return 0
                fi
            fi
            # Actually check if researcher daemon is alive
            if emacsclient --socket-name="ov5-researcher" --eval 't' >/dev/null 2>&1; then
                daemon_was_seen=1
            elif [ "$daemon_was_seen" -eq 1 ]; then
                log "WARNING: $action daemon stopped after ${elapsed}s without findings"
                return 1
            fi
            if [ "$elapsed" -ge "$min_start_wait" ] && [ "$daemon_was_seen" -eq 0 ]; then
                log "WARNING: $action daemon was not observed within ${elapsed}s"
                return 1
            fi
        elif ! emacsclient --socket-name="$socket_name" --eval 't' >/dev/null 2>&1; then
            if [ "$daemon_was_seen" -eq 1 ]; then
                log "$action daemon stopped after ${elapsed}s (socket closed)"
                return 0
            fi
            if [ "$elapsed" -ge "$min_start_wait" ]; then
                log "WARNING: $action daemon was not observed within ${elapsed}s"
                return 1
            fi
        else
            daemon_was_seen=1
            local phase
            phase="$(emacsclient --socket-name="$socket_name" \
                --eval '(if (and (boundp (quote gptel-auto-workflow--stats)) gptel-auto-workflow--stats) (plist-get gptel-auto-workflow--stats :phase) "unknown")' 2>/dev/null || echo "unknown")"
            phase="${phase//\"/}"
            if [ "$phase" = "idle" ] || [ "$phase" = "complete" ]; then
                log "$action completed after ${elapsed}s"
                return 0
            fi
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    log "WARNING: $action did not complete within ${max_wait}s"
    return 1
}

run_self_evolution() {
    local label="$1"
    local evolution_output

    log "=== $label ==="

    evolution_output="$(AUTO_WORKFLOW_ACTION_TIMEOUT="$MAX_WAIT_EVOLUTION" \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        timeout "$MAX_WAIT_EVOLUTION" "$SCRIPT" evolution 2>&1 || true)"
    printf '%s\n' "$evolution_output" >> "$PIPELINE_LOG"
    if printf '%s' "$evolution_output" | grep -q "already-running"; then
        log "Self-evolution skipped (already running)"
    elif printf '%s' "$evolution_output" | grep -q "throttled"; then
        log "Self-evolution skipped (throttled)"
    elif printf '%s' "$evolution_output" | grep -q "converged"; then
        log "Self-evolution skipped (converged)"
    elif printf '%s' "$evolution_output" | grep -q "discard"; then
        log "Self-evolution skipped (discard)"
    elif printf '%s' "$evolution_output" | grep -q "first"; then
        log "Self-evolution skipped (first run / establishing baseline)"
    elif printf '%s' "$evolution_output" | grep -q "keep"; then
        log "Self-evolution completed (kept improvements)"
    elif printf '%s' "$evolution_output" | grep -q "Insufficient new data"; then
        log "Self-evolution skipped (insufficient new data)"
    elif printf '%s' "$evolution_output" | grep -q "Self-evolution cycle complete"; then
        log "Self-evolution completed (research: $RESEARCH_QUALITY)"
    else
        log "WARNING: self-evolution command had issues, but continuing pipeline"
        # Non-fatal: evolution failure shouldn't stop experiments
    fi
}

write_research_fallback() {
    local reason="$1"

    mkdir -p "$(dirname "$FINDINGS_FILE")"
    cat > "$FINDINGS_FILE" <<EOF
# Research Findings

> Updated: $(date '+%Y-%m-%d %H:%M')
> Source type: local-fallback
> Reason: $reason

## Local Research Fallback

The dedicated researcher daemon did not produce fresh external findings. Use this local context rather than running auto-workflow with no research signal:

- Preserve the feedback loop: every experiment row must include a non-none research hash so AutoTTS can link outcomes back to the research trace.
- Treat missing research files as a pipeline defect, not a successful empty research run.
- Prefer structured, machine-parseable research outputs with source, technique, apply-to-us, and verification fields.
- Guard daemon orchestration boundaries: if a researcher daemon disappears after being observed, fail fast and fall back instead of waiting until the global timeout.
- Prioritize changes that make self-evolution observable through results.tsv metadata, research traces, and controller decisions.

EOF
    cat > "$INTERNAL_FILE" <<EOF
# Internal Code Analysis

> Updated: $(date '+%Y-%m-%d %H:%M')
> Source type: local-fallback

The pipeline generated fallback research because the researcher daemon did not produce fresh findings. This is still useful input for self-evolution: focus on daemon lifecycle, result metadata, trace outcome linking, and pipeline validation.

EOF
    if [ "$RESEARCH_QUALITY" = "none" ] || [ "$RESEARCH_QUALITY" = "failed" ]; then
        RESEARCH_QUALITY="internal"
    fi
    log "Generated local research fallback after: $reason"
}

# Kill all ov5- daemon processes by PID (not socket — socket may be orphaned).
# Uses pgrep on daemon name suffix (appears after \012 newline in macOS --bg-daemon).
# Rotate a log file if it exceeds max size (default 100KB).
# Keeps at most 3 rotated copies: .1 (newest), .2, .3 (oldest).
log_rotate() {
    local f="$1" max="${2:-102400}"
    [ -f "$f" ] || return
    local size
    size=$(wc -c < "$f")
    [ "$size" -lt "$max" ] && return
    [ -f "${f}.3" ] && rm -f "${f}.3"
    [ -f "${f}.2" ] && mv "${f}.2" "${f}.3" 2>/dev/null || true
    [ -f "${f}.1" ] && mv "${f}.1" "${f}.2" 2>/dev/null || true
    mv "$f" "${f}.1"
    : > "$f"
    echo "[pipeline $(date '+%H:%M:%S')] Rotated $(basename "$f") (${size}B → .1)"
}

kill_ov5_daemons() {
    local pids label="$1"
    pids=$(pgrep -f "ov5-(auto-workflow|researcher)" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        local count=$(echo "$pids" | wc -l | tr -d ' ')
        log "Killing $count daemon(s) by PID${label:+ ($label)}"
        echo "$pids" | xargs kill -9 2>/dev/null || true
        sleep 2
        # Verify all are dead
        local remaining=$(pgrep -f "ov5-(auto-workflow|researcher)" 2>/dev/null || true)
        if [ -n "$remaining" ]; then
            local still=$(echo "$remaining" | wc -l | tr -d ' ')
            log "WARNING: $still daemon(s) still alive after SIGKILL — retrying"
            echo "$remaining" | xargs kill -9 2>/dev/null || true
            sleep 2
        fi
    fi
}

verify_research_feedback_loop() {
    local results_file="$1"
    local data_rows linked_rows

    if [ "$RESEARCH_QUALITY" != "external" ]; then
        return 0
    fi
    if [ ! -f "$results_file" ]; then
        return 0
    fi

    data_rows=$(awk 'NR > 1 { count++ } END { print count + 0 }' "$results_file")
    if [ "$data_rows" -eq 0 ]; then
        log "WARNING: No experiment rows found to validate research feedback loop"
        return 0
    fi

    linked_rows=$(awk 'BEGIN { FS = sprintf("%c", 9) } NR > 1 && $22 != "" && $22 != "none" { count++ } END { print count + 0 }' "$results_file")
    if [ "$linked_rows" -eq 0 ]; then
        log "WARNING: Research feedback loop broken: 0/${data_rows} experiment rows have a research hash"
        return 1
    fi

    log "Research feedback loop: ${linked_rows}/${data_rows} experiment rows linked to research"
}

# ─── Clear stale byte-compiled files to force source reload ───
find "$DIR/lisp/modules" -name "*.elc" -delete 2>/dev/null || true
find "$DIR/var/eln-cache" -name "*.eln" -delete -maxdepth 3 2>/dev/null || true
log "Cleared stale .elc + .eln files from lisp/modules/"

# ─── Force-kill all stale Emacs daemons ───
# NOTE: macOS --bg-daemon embeds \012 (newline) in args, so pgrep patterns
# like "emacs.*ov5" fail because . doesn't match the newline. Instead match
# on the daemon name suffix which appears after the newline.
STALE_PIDS=$(pgrep -f "ov5-(auto-workflow|researcher)" 2>/dev/null || true)
if [ -n "$STALE_PIDS" ]; then
    STALE_COUNT=$(echo "$STALE_PIDS" | wc -l | tr -d ' ')
    log "Killing $STALE_COUNT stale daemon process(es)..."
    echo "$STALE_PIDS" | xargs kill -9 2>/dev/null || true
    sleep 3
fi
# Also clean any leftover --fg-daemon / --bg-daemon emacs processes
# Match on the daemon flag which appears before the newline
STALE_BG=$(pgrep -f "bg-daemon" 2>/dev/null || true)
if [ -n "$STALE_BG" ]; then
    STALE_BG_COUNT=$(echo "$STALE_BG" | wc -l | tr -d ' ')
    log "Killing $STALE_BG_COUNT leftover fg/bg-daemon process(es)..."
    echo "$STALE_BG" | xargs kill -9 2>/dev/null || true
    sleep 2
fi
# Clean stale sockets from ALL candidate directories
# Linux: /tmp/emacsUID/; macOS: $TMPDIR/emacsUID/ or /tmp/emacsUID/
clean_stale_socket() {
    local name="$1" sock=""
    for base in "${TMPDIR:-}" /tmp "${XDG_RUNTIME_DIR:-}"; do
        [ -n "$base" ] || continue
        sock="$base/emacs$(id -u)/$name"
        if [ -S "$sock" ] || [ -e "$sock" ]; then
            rm -f "$sock" 2>/dev/null || true
            log "Cleared stale socket: $sock"
        fi
    done
}
clean_stale_socket "server"
clean_stale_socket "ov5-auto-workflow"
clean_stale_socket "ov5-researcher"

# ─── Stop any existing daemons to ensure fresh code is loaded ───
log "Stopping any existing daemons to load latest code..."
kill_ov5_daemons "pre-cleanup"
# Also try socket-based stop as fallback (handles edge cases)
"$SCRIPT" stop >/dev/null 2>&1 || true
AUTO_WORKFLOW_EMACS_SERVER=ov5-researcher "$SCRIPT" stop >/dev/null 2>&1 || true
# Force-remove stale staging worktree so auto-workflow recreates from latest main
rm -rf "$DIR/var/tmp/experiments/staging-verify" 2>/dev/null || true
rm -rf "$DIR/var/tmp/experiments/optimize" 2>/dev/null || true
log "Cleaned stale staging + experiment worktrees"
sleep 2

# ─── Clear stale findings to ensure fresh research ───
rm -f "$FINDINGS_FILE" "$INTERNAL_FILE"
log "Cleared stale findings files"

# Capture start time AFTER clearing stale files so mtime check is reliable
PIPELINE_START_TIME="$(date +%s)"

# Verify findings were produced
RESEARCH_QUALITY="none"

# ─── Step 0: Researcher fetches files on demand (no batch prefetch) ───
log "=== Step 0: Researcher will fetch specific files on demand via gh CLI ==="

# ─── Step 1: Research ───
log "=== Step 1: Research ==="
# The cron script's research action starts daemon, queues job, and returns.
# The researcher daemon auto-processes the job and then shuts down.
# We just need to wait for it to complete.
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
    "$SCRIPT" research >> "$PIPELINE_LOG" 2>&1 || true
# Researcher daemon startup can take 90-120s (emacs init + package loading).
# Use min_start_wait=120 to give it enough time before giving up.
if ! wait_for_idle "research" "$MAX_WAIT_RESEARCH" "ov5-researcher" 180; then
    log "Research still in progress after timeout — continuing with partial findings"
    # Do NOT kill the daemon — let it keep working for next cycle
fi

if [ -f "$FINDINGS_FILE" ]; then
    findings_size=$(wc -c < "$FINDINGS_FILE")
    log "Research findings: ${findings_size} bytes"

    has_external=0
    if grep -q "https\?://" "$FINDINGS_FILE" 2>/dev/null || \
        grep -q "## .*Technique" "$FINDINGS_FILE" 2>/dev/null; then
        has_external=1
    elif grep -q "webfetch\|WebFetch\|WebSearch\|Hunting external" "$DIR/var/tmp/cron/ov5-researcher.log" 2>/dev/null; then
        has_external=1
    fi
    if [ "$has_external" = "1" ]; then
        log "  ✓ External research content detected"
        RESEARCH_QUALITY="external"
    elif grep -q "Source type: local-fallback" "$FINDINGS_FILE" 2>/dev/null; then
        log "  ⚠ Local fallback research generated"
        RESEARCH_QUALITY="internal"
    elif [ "$findings_size" -gt 200 ]; then
        log "  ⚠ Findings file present but may lack external content"
        RESEARCH_QUALITY="unknown"
    else
        log "  ✗ Findings file too small, research may have failed"
        RESEARCH_QUALITY="failed"
    fi
else
    log "WARNING: No findings file found at $FINDINGS_FILE"
    write_research_fallback "research findings file missing after wait"
    RESEARCH_QUALITY="internal"
fi

# Check internal research (local code patterns)
if [ -f "$INTERNAL_FILE" ]; then
    internal_size=$(wc -c < "$INTERNAL_FILE")
    log "Internal research: ${internal_size} bytes"
    if [ "$internal_size" -gt 100 ]; then
        log "  ✓ Internal code analysis available"
        if [ "$RESEARCH_QUALITY" = "none" ] || [ "$RESEARCH_QUALITY" = "failed" ]; then
            RESEARCH_QUALITY="internal"
        fi
    fi
fi

# ─── Step 2: Verify pipeline integration (file-based checks) ───
log "=== Step 2: Verify Pipeline Integration ==="
HAS_RESEARCH=0

if [ -f "$FINDINGS_FILE" ]; then
    SIZE=$(wc -c < "$FINDINGS_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 100 ]; then
        log "  ✓ Findings file: $SIZE bytes"
        HAS_RESEARCH=1
    else
        log "  ⚠ Findings file too small: $SIZE bytes"
    fi
else
    log "  ⚠ Findings file missing"
fi

if [ -f "$INTERNAL_FILE" ]; then
    SIZE=$(wc -c < "$INTERNAL_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 100 ]; then
        log "  ✓ Internal research file: $SIZE bytes"
        HAS_RESEARCH=1
    fi
fi

DIRECTIVE_FILE="$DIR/assistant/skills/auto-workflow/DIRECTIVE.md"
if [ -f "$DIRECTIVE_FILE" ]; then
    log "  ✓ Directive skill exists"
else
    log "  ⚠ Directive skill file not found"
fi

if [ -f "$FINDINGS_FILE" ]; then
    if FINDINGS_MTIME=$(stat -f %m "$FINDINGS_FILE" 2>/dev/null); then
        :
    elif FINDINGS_MTIME=$(stat -c %Y "$FINDINGS_FILE" 2>/dev/null); then
        :
    else
        FINDINGS_MTIME=0
    fi
    FINDINGS_AGE=$(( $(date +%s) - FINDINGS_MTIME ))
    if [ "$FINDINGS_AGE" -lt 86400 ]; then
        log "  ✓ Findings are recent ($(( FINDINGS_AGE / 3600 ))h old)"
    else
        log "  ⚠ Findings are stale ($(( FINDINGS_AGE / 3600 ))h old)"
    fi
fi

# Report research quality and continue (non-fatal)
case "$RESEARCH_QUALITY" in
    external)
        log "Pipeline integration: External research available ✓"
        ;;
    internal)
        log "Pipeline integration: Internal research only (no external) ⚠"
        ;;
    unknown)
        log "Pipeline integration: Research file present but content unclear ⚠"
        ;;
    failed|none)
        log "Pipeline integration: No research available ⚠"
        ;;
esac

# Pipeline continues regardless - self-evolution can work with local data
if [ "$HAS_RESEARCH" -eq 0 ]; then
    log "WARNING: No research data available. Self-evolution will use local patterns only."
fi

# ─── Step 3: Self-Evolution (digest findings/results into skills) ───
if [ "${PIPELINE_SKIP_PRE_EVOLUTION:-no}" != "yes" ]; then
    # Pass research quality info to evolution context
    export PIPELINE_RESEARCH_QUALITY="$RESEARCH_QUALITY"
    export PIPELINE_FINDINGS_FILE="$FINDINGS_FILE"
    export PIPELINE_INTERNAL_FILE="$INTERNAL_FILE"
    run_self_evolution "Step 3: Self-Evolution (pre-workflow)"
    # Verify cross-subsystem state was persisted
    STATE_FILE="$DIR/var/tmp/cross-subsystem-state.json"
    if [ -f "$STATE_FILE" ]; then
        state_size=$(wc -c < "$STATE_FILE")
        if [ "$state_size" -gt 10 ]; then
            log "  ✓ cross-subsystem-state.json: $state_size bytes"
        else
            log "  ⚠ cross-subsystem-state.json too small: $state_size bytes"
        fi
    else
        log "  ⚠ cross-subsystem-state.json not created — next cycle starts with amnesia"
    fi
    # Restart daemon to pick up any evolved code changes
    log "Restarting daemon to load evolved code..."
    # Kill by PID first (socket may be orphaned), then fallback to socket stop
    kill_ov5_daemons "evolution-restart"
    "$SCRIPT" stop >/dev/null 2>&1 || true
    # Clean stale sockets from ALL candidate directories (macOS: $TMPDIR, Linux: /tmp).
    # After the daemon is killed, a stale socket prevents new daemon startup.
    clean_ov5_sockets() {
        for base in "${TMPDIR:-}" /tmp "${XDG_RUNTIME_DIR:-}"; do
            [ -n "$base" ] || continue
            for sock_name in ov5-auto-workflow ov5-researcher; do
                local sock_path="$base/emacs$(id -u)/$sock_name"
                rm -f "$sock_path" 2>/dev/null || true
                [ "$base" = "${XDG_RUNTIME_DIR:-}" ] && rm -f "$base/emacs/$sock_name" 2>/dev/null || true
            done
        done
    }
    clean_ov5_sockets
    unset -f clean_ov5_sockets
    sleep 2
else
    log "=== Step 3: Skipped (PIPELINE_SKIP_PRE_EVOLUTION=yes) ==="
fi

# ─── Step 4: Auto-Workflow (uses digested findings via directive) ───
log "=== Step 4: Auto-Workflow ==="
if [ "$PIPELINE_SMOKE_ONLY" = "yes" ]; then
    log "PIPELINE_SMOKE_ONLY=yes; skipping auto-workflow batch queue"
    exit 0
fi
# Stop researcher daemon so it doesn't hold the cron-job lock
# Kill by PID first (socket may be orphaned from evolution restart socket cleanup)
kill_ov5_daemons "pre-workflow"
AUTO_WORKFLOW_EMACS_SERVER=ov5-researcher "$SCRIPT" stop >/dev/null 2>&1 || true
sleep 2
# Queue the workflow job (daemon will be started if not running)
# Retry if evolution is still running (returns "already-running")
for retry in 0 1 2 3 4; do
    auto_workflow_output="$(AUTO_WORKFLOW_ACTION_TIMEOUT="$MAX_WAIT_WORKFLOW" \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        timeout "$MAX_WAIT_WORKFLOW" \
        "$SCRIPT" auto-workflow 2>&1)"
    printf '%s\n' "$auto_workflow_output" >> "$PIPELINE_LOG"
    if printf '%s' "$auto_workflow_output" | grep -q "already-running"; then
        log "Auto-workflow already running, retry $((retry+1))/5 in 30s..."
        sleep 30
    else
        break
    fi
done
wait_for_idle "auto-workflow" "$MAX_WAIT_WORKFLOW" "ov5-auto-workflow" || :

# Verify auto-workflow actually completed (not timed out)
workflow_status="$($SCRIPT status 2>/dev/null || true)"
if printf '%s' "$workflow_status" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"'; then
    log "Auto-workflow completed successfully"
elif printf '%s' "$workflow_status" | grep -Eq ':phase "running"'; then
    log "WARNING: Auto-workflow still running after timeout; may need more time"
fi

# ─── Step 5: Self-Evolution (digest fresh workflow results) ───
if printf '%s' "$workflow_status" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"'; then
    run_self_evolution "Step 5: Self-Evolution (post-workflow)"
else
    log "Skipping post-workflow self-evolution because auto-workflow did not complete"
fi

# ─── Step 6: Report results ───
log "=== Pipeline Complete ==="
RESULTS_PATTERN="$DIR/var/tmp/experiments/$(date +%F)*/results.tsv"
if compgen -G "$RESULTS_PATTERN" >/dev/null; then
    latest_result=$(ls -t $RESULTS_PATTERN | head -1)
    result_count=$(wc -l < "$latest_result")
    log "Results: $latest_result ($((result_count - 1)) experiments)"
    verify_research_feedback_loop "$latest_result" || true
else
    log "No results file found for today"
fi

exit 0
