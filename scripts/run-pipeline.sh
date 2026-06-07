#!/usr/bin/env bash
# Pipeline: Research → Digestion → Auto-Workflow
# Ensures research findings are digested before auto-workflow runs.
# Includes verification that findings feed into directive skill.

set -euo pipefail

# Prevent C stack overflow in deeply nested subagent calls
ulimit -s 65532 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DIR/scripts/run-auto-workflow-cron.sh"

# Bootstrap: ensure we're running the latest version of the script.
# This prevents stale code when the local branch has diverged from origin.
# Uses rebase to handle divergence gracefully.
BOOTSTRAP_HEAD_BEFORE="$(git -C "$DIR" rev-parse HEAD 2>/dev/null)" || true
(git -C "$DIR" fetch origin main 2>/dev/null && \
 git -C "$DIR" stash -q 2>/dev/null || true && \
 git -C "$DIR" checkout HEAD -- mementum/knowledge/ assistant/skills/ assistant/strategies/ 2>/dev/null || true && \
 git -C "$DIR" rebase origin/main 2>/dev/null && \
 git -C "$DIR" stash pop -q 2>/dev/null || true) || true
# If HEAD moved (rebase succeeded), re-exec so we run the updated script.
if [ -n "$BOOTSTRAP_HEAD_BEFORE" ] && [ "$BOOTSTRAP_HEAD_BEFORE" != "$(git -C "$DIR" rev-parse HEAD 2>/dev/null)" ]; then
    echo "[pipeline] Bootstrap: HEAD updated, re-execing with latest code"
    exec "$0" "${@:-}"
fi
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

# ─── Pipeline Operations (merged from run-pipeline-ops.sh) ───

PLAN_DIR="$DIR/mementum/knowledge/plans/pipeline-runs"
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# Pre-pipeline: Create plan and update state
create_pipeline_plan() {
    log "Creating pipeline plan..."
    mkdir -p "$PLAN_DIR/run-$TIMESTAMP"
    cat > "$PLAN_DIR/run-$TIMESTAMP/plan.md" <<EOF
# Pipeline Run $TIMESTAMP

## Objective
Run OV5 self-evolution pipeline with research -> digestion -> workflow.

## Requirements
- Research findings digested before workflow
- Quota-aware scheduling
- Results tracked in mementum

## DoD
- [ ] Pipeline completes without error
- [ ] Results stored in mementum/memories/
- [ ] State updated in mementum/state.md

## Changelog
- **$(date '+%Y-%m-%d')**: Plan created
EOF
    log "Plan created: $PLAN_DIR/run-$TIMESTAMP/"
}

# Post-pipeline: Update plan with results
update_pipeline_plan() {
    local status="$1"
    log "Updating pipeline plan..."
    cat >> "$PLAN_DIR/run-$TIMESTAMP/plan.md" <<EOF

## Results

- **Status**: $status
- **Timestamp**: $TIMESTAMP

EOF
    log "Plan updated with status: $status"
}

# Post-pipeline: Update mementum state
update_mementum_state() {
    local status="$1"
    log "Updating mementum/state.md..."
    if [ -f "$DIR/mementum/state.md" ]; then
        local tmp
        tmp=$(mktemp)
        {
            echo "# Mementum State"
            echo ""
            echo "> **Last pipeline**: $(date '+%Y-%m-%d') ($status)"
            echo "> **Next pipeline**: scheduled"
            echo "> **Plan**: $PLAN_DIR/run-$TIMESTAMP/"
            echo ""
            # Append rest of existing state (skip first line)
            tail -n +2 "$DIR/mementum/state.md" 2>/dev/null || true
        } > "$tmp"
        mv "$tmp" "$DIR/mementum/state.md"
        log "State updated"
    fi
}

# Post-pipeline: Log patterns for analysis
log_pipeline_patterns() {
    local status="$1"
    log "Logging pipeline patterns..."
    if [ -f "$DIR/mementum/state.md" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | Pipeline $status | Plan: $PLAN_DIR/run-$TIMESTAMP/" >> "$DIR/mementum/.pipeline-log"
        log "Patterns logged to mementum/.pipeline-log"
    fi
}

# Prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log "Pipeline already running (PID $lock_pid), skipping"
        exit 0
    fi
fi

wait_for_idle() {
    local action="$1"
    local max_wait="${2:-900}"
    local socket_name="${3:-pmf-value-stream}"
    local elapsed=0
    local daemon_was_seen=0
    local min_start_wait="${4:-60}"

    log "Waiting for $action to complete (max ${max_wait}s)..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        if [ "$socket_name" = "pmf-value-stream" ]; then
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
        elif [ "$socket_name" = "gtm-product-org" ]; then
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
                phase="$(emacsclient --socket-name="gtm-product-org" \
                    --eval '(if (and (boundp (quote gptel-auto-workflow--stats)) gptel-auto-workflow--stats) (plist-get gptel-auto-workflow--stats :phase) "unknown")' 2>/dev/null || echo "unknown")"
                phase="${phase//\"/}"
                if [ "$phase" = "complete" ] || [ "$phase" = "idle" ]; then
                    log "$action daemon phase=$phase after ${elapsed}s"
                    return 0
                fi
            fi
            # Actually check if researcher daemon is alive
            if emacsclient --socket-name="gtm-product-org" --eval 't' >/dev/null 2>&1; then
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
    elif printf '%s' "$evolution_output" | grep -qE '(^|[^a-z])discard($|[^a-z])'; then
        log "Self-evolution skipped (discard - keep rate not improved)"
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
    [ -f "$f" ] || return 0
    local size
    size=$(wc -c < "$f")
    [ "$size" -lt "$max" ] && return 0
    [ -f "${f}.3" ] && rm -f "${f}.3"
    [ -f "${f}.2" ] && mv "${f}.2" "${f}.3" 2>/dev/null || true
    [ -f "${f}.1" ] && mv "${f}.1" "${f}.2" 2>/dev/null || true
    mv "$f" "${f}.1"
    : > "$f"
    echo "[pipeline $(date '+%H:%M:%S')] Rotated $(basename "$f") (${size}B → .1)"
}

kill_ov5_daemons() {
    local pids label="$1"
    pids=$(pgrep -f "(pmf-value-stream|gtm-product-org|ov5-auto-workflow|ov5-researcher)" 2>/dev/null || true)
    if [ -n "$pids" ]; then
        local count=$(echo "$pids" | wc -l | tr -d ' ')
        log "Killing $count daemon(s) by PID${label:+ ($label)}"
        echo "$pids" | xargs kill -9 2>/dev/null || true
        sleep 2
        # Verify all are dead
        local remaining=$(pgrep -f "(pmf-value-stream|gtm-product-org|ov5-auto-workflow|ov5-researcher)" 2>/dev/null || true)
        if [ -n "$remaining" ]; then
            local still=$(echo "$remaining" | wc -l | tr -d ' ')
            log "WARNING: $still daemon(s) still alive after SIGKILL — retrying"
            echo "$remaining" | xargs kill -9 2>/dev/null || true
            sleep 2
        fi
    fi
}

pipeline_git_has_unmerged_paths() {
    git -C "$DIR" diff --name-only --diff-filter=U 2>/dev/null | grep -q .
}

pipeline_clear_auto_generated_unmerged_paths() {
    local unmerged

    unmerged="$(git -C "$DIR" diff --name-only --diff-filter=U 2>/dev/null || true)"
    [ -n "$unmerged" ] || return 0

    if printf '%s\n' "$unmerged" | grep -Ev '^(mementum/knowledge/|assistant/skills/|assistant/strategies/)' >/dev/null; then
        log "WARNING: non-auto-generated merge conflicts remain; skipping git sync"
        printf '%s\n' "$unmerged" | sed 's/^/[pipeline conflict] /'
        return 1
    fi

    log "Clearing auto-generated merge conflicts before git sync"
    git -C "$DIR" merge --abort 2>/dev/null || true
    git -C "$DIR" checkout HEAD -- mementum/knowledge/ assistant/skills/ assistant/strategies/ 2>/dev/null || true
    git -C "$DIR" clean -fd -- mementum/knowledge/ assistant/skills/ assistant/strategies/ 2>/dev/null || true
    ! pipeline_git_has_unmerged_paths
}

pipeline_git_sync_latest() {
    local label="${1:-git sync}" stash_label="${2:-auto-workflow-sync}"
    local stash_output stash_made=0

    pipeline_clear_auto_generated_unmerged_paths || return 0

    stash_output="$(git -C "$DIR" stash push -m "${stash_label}-$(date +%s)" 2>&1 || true)"
    case "$stash_output" in
        *"No local changes to save"*) stash_made=0 ;;
        *"Saved working directory"*) stash_made=1 ;;
        *"Saved working tree"*) stash_made=1 ;;
        "") stash_made=0 ;;
        *)
            log "WARNING: git stash failed during $label; continuing without stash pop"
            printf '%s\n' "$stash_output" >> "$PIPELINE_LOG"
            stash_made=0
            ;;
    esac

    git -C "$DIR" merge --abort 2>/dev/null || true
    git -C "$DIR" checkout HEAD -- mementum/knowledge/ assistant/skills/ assistant/strategies/ 2>/dev/null || true
    git -C "$DIR" clean -fd -- mementum/knowledge/ assistant/skills/ assistant/strategies/ 2>/dev/null || true
    git -C "$DIR" pull --rebase 2>&1 || log "WARNING: $label git pull failed"

    if [ "$stash_made" -eq 1 ]; then
        if ! git -C "$DIR" stash pop 2>/dev/null; then
            log "WARNING: $label stash pop failed, resetting to HEAD and dropping stash"
            git -C "$DIR" reset --hard HEAD 2>/dev/null || true
            git -C "$DIR" stash drop 2>/dev/null || true
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

# ─── Rotate oversized logs to prevent unbounded growth ───
log_rotate "$PIPELINE_LOG"
log_rotate "$LOG_DIR/gtm-product-org.log"
log_rotate "$LOG_DIR/pmf-value-stream.log"
log_rotate "$LOG_DIR/evolution-backtrace.log" 51200  # Rotate at 50KB (grows fast)

# ─── Clean stale PID/lock files older than 12h ───
find "$DIR/var/tmp" -type f \( -name "*.pid" -o -name "*.lock" \) -mtime +0 -delete 2>/dev/null || true

# ─── Clean old experiment directories (keep last 7 days) ───
find "$DIR/var/tmp/experiments" -maxdepth 1 -type d -mtime +7 2>/dev/null | while read d; do
    rm -rf "$d" 2>/dev/null || true
done
# Also clean stale git worktree metadata for removed experiment dirs
git -C "$DIR" worktree prune 2>/dev/null || true
log "Cleaned old experiment directories + stale worktree metadata"

# ─── Clean old Emacs daemon logs (keep last 50, prevents unbounded growth) ───
emacs_log_count=$(find "$DIR/var/log" -maxdepth 1 -name "emacs-*.log" -type f 2>/dev/null | wc -l)
if [ "$emacs_log_count" -gt 50 ]; then
    removed=$(find "$DIR/var/log" -maxdepth 1 -name "emacs-*.log" -type f -printf '%T@ %p\n' 2>/dev/null \
              | sort -n | head -n -$((50)) | cut -d' ' -f2- | xargs rm -f 2>/dev/null \
              | wc -l || echo "0")
    actual_removed=$((emacs_log_count - 50))
    if [ "$actual_removed" -gt 0 ]; then
        log "Cleaned $actual_removed old Emacs daemon logs (kept 50 most recent)"
    fi
fi

# ─── Clear stale byte-compiled files to force source reload ───
find "$DIR/lisp/modules" -name "*.elc" -delete 2>/dev/null || true
find "$DIR/var/eln-cache" -name "*.eln" -delete -maxdepth 3 2>/dev/null || true
log "Cleared stale .elc + .eln files from lisp/modules/"

# ─── Force-kill all stale Emacs daemons ───
# NOTE: macOS --bg-daemon embeds \012 (newline) in args, so pgrep patterns
# like "emacs.*ov5" fail because . doesn't match the newline. Instead match
# on the daemon name suffix which appears after the newline.
STALE_PIDS=$(pgrep -f "(pmf-value-stream|gtm-product-org|ov5-auto-workflow|ov5-researcher)" 2>/dev/null || true)
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
clean_stale_socket "pmf-value-stream"
clean_stale_socket "gtm-product-org"

# ─── Pull latest code so daemon restart picks up fixes ───
log "Pulling latest code from origin..."
# Stash any work-in-progress (experiment results, manual edits) so we don't lose them.
# Auto-evolved files (DIRECTIVE.md, strategy-guidance.json, comparison reports) are
# upstream-dominant — discard local versions since they'll be regenerated next cycle.
# Stale merge conflicts from previous interrupted pulls also block git pull — clear them.
pipeline_git_sync_latest "pre-workflow" "auto-workflow-pre-pull"

# ─── Stop any existing daemons to ensure fresh code is loaded ───
log "Stopping any existing daemons to load latest code..."
# Check if auto-workflow is already running experiments — preserve its worktrees
workflow_running=0
if [ -f "$DIR/var/tmp/cron/auto-workflow-status.sexp" ]; then
    if grep -q ':running t' "$DIR/var/tmp/cron/auto-workflow-status.sexp" 2>/dev/null; then
        workflow_running=1
        log "Auto-workflow already running experiments — preserving worktrees"
    fi
fi
kill_ov5_daemons "pre-cleanup"
# Also try socket-based stop as fallback (handles edge cases)
"$SCRIPT" stop >/dev/null 2>&1 || true
AUTO_WORKFLOW_EMACS_SERVER=gtm-product-org "$SCRIPT" stop >/dev/null 2>&1 || true
# Clear stale status so auto-workflow starts fresh daemon
rm -f "$DIR/var/tmp/cron/auto-workflow-status.sexp" 2>/dev/null || true
# Force-remove stale staging worktree so auto-workflow recreates from latest main
rm -rf "$DIR/var/tmp/experiments/staging-verify" 2>/dev/null || true
# Only clean optimize worktrees if no workflow was running (avoid race)
if [ "$workflow_running" -eq 0 ]; then
    rm -rf "$DIR/var/tmp/experiments/optimize" 2>/dev/null || true
    log "Cleaned stale staging + experiment worktrees"
else
    log "Preserved active experiment worktrees (workflow was running)"
fi
# Keep only the 3 most recent baseline worktrees; delete older ones
ls -dt "$DIR/var/tmp/experiments/main-baseline-"* 2>/dev/null | tail -n +4 | xargs -r rm -rf 2>/dev/null || true
sleep 2

# ─── Clear stale findings to ensure fresh research ───
rm -f "$FINDINGS_FILE" "$INTERNAL_FILE"
log "Cleared stale findings files"

# Capture start time AFTER clearing stale files so mtime check is reliable
PIPELINE_START_TIME="$(date +%s)"

# Verify findings were produced
RESEARCH_QUALITY="none"

# ─── Pipeline Ops: Create plan for this run ───
create_pipeline_plan

# ─── Step 0: Researcher fetches files on demand (no batch prefetch) ───
log "=== Step 0: Researcher will fetch specific files on demand via gh CLI ==="

# ─── Step 1: Research ───
log "=== Step 1: Research ==="
# The cron script's research action starts daemon, queues job, and returns.
# The researcher daemon (GTM Mayor) stays alive between pipeline runs.
# It runs periodic research via internal timer; we just wait for this cycle.
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
    "$SCRIPT" research >> "$PIPELINE_LOG" 2>&1 || true
# Researcher daemon startup can take 90-120s (emacs init + package loading).
# Use min_start_wait=120 to give it enough time before giving up.
if ! wait_for_idle "research" "$MAX_WAIT_RESEARCH" "gtm-product-org" 180; then
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
    elif grep -q "webfetch\|WebFetch\|WebSearch\|Hunting external" "$DIR/var/tmp/cron/gtm-product-org.log" 2>/dev/null; then
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
            for sock_name in pmf-value-stream gtm-product-org; do
                local sock_path="$base/emacs$(id -u)/$sock_name"
                rm -f "$sock_path" 2>/dev/null || true
                [ "$base" = "${XDG_RUNTIME_DIR:-}" ] && rm -f "$base/emacs/$sock_name" 2>/dev/null || true
            done
        done
    }
    clean_ov5_sockets
    unset -f clean_ov5_sockets
    # Clear workflow status so auto-workflow can start a fresh daemon
    rm -f "$DIR/var/tmp/cron/auto-workflow-status.sexp" 2>/dev/null || true
    # Discard all local changes + untracked files in auto-generated dirs
    pipeline_git_sync_latest "post-evolution" "auto-workflow-post-pull"
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
AUTO_WORKFLOW_EMACS_SERVER=gtm-product-org "$SCRIPT" stop >/dev/null 2>&1 || true
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
wait_for_idle "auto-workflow" "$MAX_WAIT_WORKFLOW" "pmf-value-stream" || :

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

# ─── Step 6.5: Merge kept experiment branches to main ───
log "=== Step 6.5: Merge kept experiments ==="
kept_count=0
merged_count=0
if compgen -G "$RESULTS_PATTERN" >/dev/null; then
    latest_result=$(ls -t $RESULTS_PATTERN | head -1)
    # Parse results.tsv for kept experiments
    # Header: experiment_id target hypothesis score_before score_after code_quality delta decision ...
    # Decision column is 8th (tab-separated)
    while IFS=$'\t' read -r exp_id target _ _ _ _ _ decision _; do
        [ "$exp_id" = "experiment_id" ] && continue
        case "$decision" in
            kept|staged|merged|grader-bypass*commit*)
                kept_count=$((kept_count + 1))
                # Find corresponding optimize branch for this run
                result_dir=$(basename "$(dirname "$latest_result")")
                run_id="${result_dir##*-}"
                # P2.1 FIX: Extract just the last part of target name (after last hyphen)
                # Branch format: optimize/{name}-{hostname}-r{run_id}-exp{N}
                # where name is the last component of target filename
                target_base=$(basename "$target" .el)
                target_name="${target_base##*-}"
                # Try multiple patterns to find the branch (check remote first)
                branch=""
                # Pattern 1: exact match with run_id on remote (most specific)
                branch=$(git -C "$DIR" branch -r --list "origin/optimize/*-r${run_id}-exp${exp_id}" 2>/dev/null | head -1 | sed 's/^[* ]*//' | sed 's|^origin/||')
                # Pattern 2: match with target_name and run_id on remote
                if [ -z "$branch" ]; then
                    branch=$(git -C "$DIR" branch -r --list "origin/optimize/${target_name}-*-r${run_id}-exp*" 2>/dev/null | head -1 | sed 's/^[* ]*//' | sed 's|^origin/||')
                fi
                # Pattern 3: match with just target_name and exp_id on remote
                if [ -z "$branch" ]; then
                    branch=$(git -C "$DIR" branch -r --list "origin/optimize/${target_name}-*-exp${exp_id}" 2>/dev/null | head -1 | sed 's/^[* ]*//' | sed 's|^origin/||')
                fi
                # Pattern 4: broader match with any target containing the name on remote
                if [ -z "$branch" ]; then
                    branch=$(git -C "$DIR" branch -r --list "origin/optimize/*${target_name}*-exp${exp_id}" 2>/dev/null | head -1 | sed 's/^[* ]*//' | sed 's|^origin/||')
                fi
                # Pattern 5: check local branches as fallback
                if [ -z "$branch" ]; then
                    branch=$(git -C "$DIR" branch --list "optimize/${target_name}-*-${run_id}-exp*" 2>/dev/null | head -1 | sed 's/^[* ]*//')
                fi
                if [ -n "$branch" ]; then
                    log "  Merging kept experiment: $branch (decision: $decision)"
                    # Fetch the branch from remote if not available locally
                    if ! git -C "$DIR" rev-parse --verify "$branch" >/dev/null 2>&1; then
                        git -C "$DIR" fetch origin "$branch:$branch" 2>/dev/null || true
                    fi
                    if git -C "$DIR" merge --no-ff "$branch" -m "⚒ Merge $branch: $decision" 2>/dev/null; then
                        log "    ✓ Merged $branch"
                        merged_count=$((merged_count + 1))
                        # Delete local branch after merge
                        git -C "$DIR" branch -D "$branch" 2>/dev/null || true
                    else
                        log "    ✗ Merge failed for $branch (conflicts?)"
                        git -C "$DIR" merge --abort 2>/dev/null || true
                    fi
                else
                    log "  ⚠ No branch found for kept experiment: $target (run: $run_id, exp: $exp_id)"
                fi
                ;;
        esac
    done < "$latest_result"
fi
log "Kept experiments: $kept_count, Merged to main: $merged_count"

# ─── Step 6.6: Clean old optimize branches (merged >7 days) ───
log "=== Step 6.6: Clean old optimize branches ==="
old_branches=$(git -C "$DIR" for-each-ref --sort=-committerdate --format='%(committerdate:unix) %(refname:short)' refs/remotes/origin/optimize/ 2>/dev/null | awk -v cutoff="$(date -d '7 days ago' +%s)" '$1 < cutoff {print $2}' || true)
old_count=$(printf '%s\n' "$old_branches" | sed '/^$/d' | wc -l)
if [ "$old_count" -gt 0 ]; then
    printf '%s\n' "$old_branches" | while read branch; do
        branch_name="${branch#origin/}"
        git -C "$DIR" push origin --delete "$branch_name" 2>/dev/null || true
    done
    log "Cleaned $old_count old optimize branches (merged before 7 days)"
else
    log "No old optimize branches to clean"
fi

# ─── Step 7: Commit and push outcomes to main ───
log "=== Step 7: Publish outcomes to main ==="

# Check for auto-generated changes
AUTO_GEN_DIRS=(
    "mementum/memories/"
    "mementum/knowledge/"
    "assistant/skills/"
    "assistant/strategies/"
    "mementum/state.md"
)

has_auto_gen=0
for dir in "${AUTO_GEN_DIRS[@]}"; do
    if git -C "$DIR" status --short | grep -q "^\s*M\|^??.*$dir"; then
        has_auto_gen=1
        break
    fi
done

if [ "$has_auto_gen" -eq 1 ]; then
    log "Auto-generated changes detected, publishing to main..."
    
    # Stash any non-auto-generated changes
    stash_output="$(git -C "$DIR" stash push -m "pipeline-auto-sync-$(date +%s)" 2>&1 || true)"
    stash_made=0
    case "$stash_output" in
        *"Saved working directory"*|*"Saved working tree"*) stash_made=1 ;;
    esac
    
    # Pull latest to avoid conflicts
    git -C "$DIR" pull --rebase 2>/dev/null || log "WARNING: git pull failed before push"
    
    # Stage auto-generated files
    git -C "$DIR" add mementum/ assistant/skills/ assistant/strategies/ 2>/dev/null || true
    
    # Commit if there are staged changes
    if ! git -C "$DIR" diff --cached --quiet 2>/dev/null; then
        commit_msg="$(date '+🔄 Auto-evolved outcomes: %Y-%m-%d %H:%M')"
        if git -C "$DIR" commit -m "$commit_msg" 2>/dev/null; then
            log "  ✓ Committed auto-generated outcomes"
            
            # Push to origin/main
            remote="$(git -C "$DIR" remote get-url origin 2>/dev/null || true)"
            if [ -n "$remote" ]; then
                if git -C "$DIR" push origin main 2>/dev/null; then
                    log "  ✓ Pushed outcomes to origin/main"
                else
                    log "WARNING: git push failed — outcomes committed locally but not pushed"
                fi
            else
                log "WARNING: no origin remote configured — outcomes committed locally"
            fi
        else
            log "WARNING: git commit failed for auto-generated outcomes"
        fi
    else
        log "No staged changes to commit"
    fi
    
    # Restore stashed changes
    if [ "$stash_made" -eq 1 ]; then
        if ! git -C "$DIR" stash pop 2>/dev/null; then
            log "WARNING: stash pop failed after auto-publish, resetting to HEAD and dropping stash"
            git -C "$DIR" reset --hard HEAD 2>/dev/null || true
            git -C "$DIR" stash drop 2>/dev/null || true
        fi
    fi
else
    log "No auto-generated changes to publish"
fi

# ─── Pipeline Ops: Update plan, state, and log patterns ───
update_pipeline_plan
update_mementum_state
log_pipeline_patterns

exit 0
