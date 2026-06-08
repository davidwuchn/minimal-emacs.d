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

# ─── Cross-machine coordination ───
# YC pattern: avoid duplicate work between Pi5 and local. If another machine
# (per git-tracked "active-runs" file) ran within the last 4 hours, skip.
# Auto-generated file, never push to remote (Pi5 ignores it via .gitignore).
ACTIVE_RUNS_FILE="$DIR/var/tmp/active-runs"
mkdir -p "$(dirname "$ACTIVE_RUNS_FILE")"
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname || echo 'unknown')"
RECENT_THRESHOLD=$((4 * 3600))  # 4 hours

# Prune stale entries (>12h old, just a safety bound)
if [ -f "$ACTIVE_RUNS_FILE" ]; then
    cutoff_prune=$(($(date +%s) - 43200))
    tmp_active="$(mktemp)"
    awk -F'|' -v cutoff="$cutoff_prune" '$2 > cutoff' "$ACTIVE_RUNS_FILE" > "$tmp_active" 2>/dev/null || true
    mv "$tmp_active" "$ACTIVE_RUNS_FILE" 2>/dev/null || true
fi

# Check if another machine ran recently
if [ -f "$ACTIVE_RUNS_FILE" ]; then
    now=$(date +%s)
    other_recent=$(awk -F'|' -v now="$now" -v thresh="$RECENT_THRESHOLD" \
        'NF >= 2 && $1 != "" {
            age = now - $2
            if (age < thresh && $1 != "'"$HOSTNAME_SHORT"'") print $1 ":" int(age/60) "min"
        }' "$ACTIVE_RUNS_FILE")
    if [ -n "$other_recent" ]; then
        log "Cross-machine coordination: recent runs on other host(s): $other_recent"
        log "  Skipping pipeline to avoid duplicate work; threshold ${RECENT_THRESHOLD}s"
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
    elif printf '%s' "$evolution_output" | grep -q "first"; then
        log "Self-evolution skipped (first run / establishing baseline)"
    elif printf '%s' "$evolution_output" | grep -q "Insufficient new data"; then
        log "Self-evolution skipped (insufficient new data)"
    # Autoresearch safety: a 'discard' return means a recent experiment was
    # REVERTED (rolled back) because it was worse than the baseline. This is
    # a SUCCESS of the safety system, not a self-evolution failure.
    elif printf '%s' "$evolution_output" | grep -q "\[autoresearch\] DISCARD"; then
        log "Self-evolution safety-net: autoresearch reverted a regression"
    elif printf '%s' "$evolution_output" | grep -q "\[autoresearch\] KEEP"; then
        log "Self-evolution kept an improvement (autoresearch)"
    # Plain 'discard' return (no autoresearch context) is rare; log it
    elif printf '%s' "$evolution_output" | grep -qE '^[A-Za-z]*discard$|^discard$'; then
        log "Self-evolution returned 'discard' (unclassified — check autoresearch)"
    elif printf '%s' "$evolution_output" | grep -q "Self-evolution cycle complete"; then
        log "Self-evolution completed (research: $RESEARCH_QUALITY)"
    elif printf '%s' "$evolution_output" | grep -q "triggered-experiments"; then
        log "Self-evolution triggered fresh experiments (no new data)"
    elif printf '%s' "$evolution_output" | grep -q "early-error"; then
        log "WARNING: self-evolution early-error (pre-steps)"
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

    # SAFER STASH: only stash changes inside auto-generated directories.
    # This prevents accidentally destroying user work-in-progress outside those
    # dirs if the stash pop fails after rebase. Auto-gen dirs are upstream-
    # dominant per AGENTS.md — Pi5's version always wins on conflict.
    stash_output="$(git -C "$DIR" stash push \
        --include-untracked \
        -m "${stash_label}-$(date +%s)" \
        -- mementum/knowledge/ assistant/skills/ assistant/strategies/ mementum/memories/ 2>&1 || true)"
    case "$stash_output" in
        *"No local changes to save"*) stash_made=0 ;;
        *"Saved working directory"*) stash_made=1 ;;
        *"Saved working tree"*) stash_made=1 ;;
        "") stash_made=0 ;;
        *)
            log "WARNING: git stash (auto-gen only) failed during $label; continuing without stash pop"
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
            # SAFER: only drop the stash we created (auto-gen scoped). Any
            # user work outside auto-gen dirs stays untouched. Never reset
            # --hard, which can destroy in-progress user work.
            log "WARNING: $label stash pop failed; dropping only the auto-gen stash"
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

# ─── Step 0.4: Self-audit → auto-fix → keep-going (META loop) ───
# The full YC loop: DETECT problems, AUTO-FIX them, KEEP GOING.
# Previous system: detected problems but took no action (the auto-fix was broken).
# Now: self-audit writes structured result → self-heal reads it and takes
# specific remediation actions → pipeline continues with fixes applied.
log "=== Step 0.4: Self-audit (DETECT) ==="
SELF_AUDIT_RESULT_FILE="$DIR/var/tmp/self-audit-result.el"
# Remove stale result from previous run
rm -f "$SELF_AUDIT_RESULT_FILE"
SELF_AUDIT_REPORT=$(emacs --batch -L "$DIR/lisp/modules" \
    -L "$DIR/packages/gptel" -L "$DIR/packages/compat" \
    -l gptel --eval \
    '(progn
       (require (quote gptel-auto-workflow-self-audit))
       (setq gptel-auto-workflow-self-audit-enabled t)
       (setq gptel-auto-workflow--workspace-path "'"$DIR"'")
       (let ((report (gptel-auto-workflow-self-audit-execute)))
         (when report (princ report))))' 2>&1)
AUDIT_ISSUES=0
COLD_BACKENDS=""
UNEVALUATED_STRATS=0
BOTTLENECK=false
BROKEN_MODULES=0
if [ -n "$SELF_AUDIT_REPORT" ]; then
    log "$SELF_AUDIT_REPORT"
    # Read structured result file for specific remediation actions
    if [ -f "$SELF_AUDIT_RESULT_FILE" ]; then
        AUDIT_ISSUES=$(grep 'issues-count' "$SELF_AUDIT_RESULT_FILE" | perl -ne 'if (/\. *(\d+)/) { print $1 }')
        COLD_BACKENDS=$(grep 'cold-backends \.' "$SELF_AUDIT_RESULT_FILE" | perl -ne 'while (/\"([^\"]+)\"/g) { print "$1," }' | perl -pe 's/,$//')
        UNEVALUATED_STRATS=$(grep 'unevaluated-strategies' "$SELF_AUDIT_RESULT_FILE" | perl -ne 'if (/\. *(\d+)/) { print $1 }')
        BOTTLENECK=$(grep 'staging-merge-bottleneck' "$SELF_AUDIT_RESULT_FILE" | perl -ne 'if (/\. t\b/) { print "1" }')
        BROKEN_MODULES=$(grep -c 'broken-modules' "$SELF_AUDIT_RESULT_FILE" 2>/dev/null || echo 0)
        log "  Structured audit: $AUDIT_ISSUES issues, $BROKEN_MODULES broken modules, bottleneck=$BOTTLENECK"
    fi
else
    log "  Self-audit: no issues found (or module not loaded)"
fi

# ─── Step 0.5: Auto-fix (ACT on what Step 0.4 detected) ───
# The pipeline now takes SPECIFIC remediation actions based on what
# the self-audit found. This closes the DETECT→ACT gap that was the
# reason the monitor kept going without fixing anything.
log "=== Step 0.5: Auto-fix (ACT on self-audit findings) ==="
REMEDIAL_ACTIONS=0

# Auto-fix 1: Force cold backends into rotation
# If backends have 0 experiments in 7d, clear their rate-limit so
# the onto-router will try them on the next evolution cycle.
if [ -n "$COLD_BACKENDS" ] && [ "$COLD_BACKENDS" != "nil" ]; then
    log "  Auto-fix: forcing cold backends into rotation ($COLD_BACKENDS)"
    # Clear ALL rate-limited backends so cold ones get a chance
    if [ -f "$DIR/var/tmp/rate-limited-backends.txt" ]; then
        log "  Clearing rate-limited-backend cache (was blocking cold backends)"
        rm -f "$DIR/var/tmp/rate-limited-backends.txt"
    fi
    # Write the cold backends to a force-try file that the daemon reads
    echo "$COLD_BACKENDS" > "$DIR/var/tmp/force-try-backends.txt"
    REMEDIAL_ACTIONS=$((REMEDIAL_ACTIONS + 1))
fi

# Auto-fix 2: Increase exploration rate for unevaluated strategies
# If >50% of strategies are unevaluated, the system is in cold-start.
# Write a signal file that increases exploration from default to 70%.
if [ "$UNEVALUATED_STRATS" -gt 2 ]; then
    log "  Auto-fix: increasing exploration rate ($UNEVALUATED_STRATS strategies unevaluated)"
    echo "70" > "$DIR/var/tmp/exploration-rateOverride.txt"
    REMEDIAL_ACTIONS=$((REMEDIAL_ACTIONS + 1))
fi

# Auto-fix 3: Staging-merge bottleneck — already handled by auto-resolver
# The .md auto-resolver was deployed in commit 95396bc1. For .el conflicts,
# we can't auto-fix but we can flag for human review.
if [ "$BOTTLENECK" -gt 0 ]; then
    log "  Auto-fix: staging-merge bottleneck flagged (.md auto-resolved, .el needs review)"
    REMEDIAL_ACTIONS=$((REMEDIAL_ACTIONS + 1))
fi

# Auto-fix 4: Broken modules — flag but don't attempt code fix
# Broken modules can't compile; the system can detect but not auto-fix
# source code errors. Log the warning and continue.
if [ "$BROKEN_MODULES" -gt 0 ]; then
    log "  ⚠ BROKEN MODULES DETECTED — cannot auto-fix source code, flagged for human review"
    REMEDIAL_ACTIONS=$((REMEDIAL_ACTIONS + 1))
fi

# Auto-fix 5: Pipeline-health PENDING remediations (legacy self-heal)
HEALTH_FILE="$DIR/mementum/knowledge/pipeline-health.md"
if [ -f "$HEALTH_FILE" ]; then
    PENDING_COUNT=$(grep -c '| PENDING' "$HEALTH_FILE" 2>/dev/null || echo 0)
    CONSECUTIVE=$(grep -E '^Consecutive failures:' "$HEALTH_FILE" 2>/dev/null | awk '{print $NF}' || echo 0)
    log "  pipeline-health: $PENDING_COUNT pending, $CONSECUTIVE consecutive failures"
    if [ "$PENDING_COUNT" -ge 5 ] || [ "${CONSECUTIVE:-0}" -ge 3 ]; then
        log "  Auto-fix: clearing stale rate-limited-backend cache (threshold reached)"
        if [ -f "$DIR/var/tmp/rate-limited-backends.txt" ]; then
            rm -f "$DIR/var/tmp/rate-limited-backends.txt"
        fi
        REMEDIAL_ACTIONS=$((REMEDIAL_ACTIONS + 1))
    fi
    # Adaptive fix: detect grader-destroying-experiments (recurring PENDING with 0% effectiveness)
    GRADER_ISSUES=$(grep 'grader-destroying-experiments.*| PENDING' "$HEALTH_FILE" 2>/dev/null | wc -l)
    if [ "${GRADER_ISSUES:-0}" -ge 3 ]; then
        CURRENT_TIMEOUT=$(grep 'grader-destroying-experiments' "$HEALTH_FILE" 2>/dev/null | head -1 | grep -o 'grader-timeout=[0-9]*' | cut -d= -f2 || echo 900)
        NEW_TIMEOUT=$((CURRENT_TIMEOUT * 3 / 2))  # Increase by 50%
        log "  Auto-fix: grader-destroying-experiments detected ($GRADER_ISSUES× PENDING)"
        log "  Escalating grader timeout: $CURRENT_TIMEOUT → $NEW_TIMEOUT"
        echo "$NEW_TIMEOUT" > "$DIR/var/tmp/grader-timeoutOverride.txt"
        # Also force fast backends for grading
        echo "deepseek-v4-flash,deepseek-v4-pro" > "$DIR/var/tmp/force-grader-backends.txt"
        REMEDIAL_ACTIONS=$((REMEDIAL_ACTIONS + 1))
    fi
fi

if [ "$REMEDIAL_ACTIONS" -gt 0 ]; then
    log "  Auto-fix: $REMEDIAL_ACTIONS remedial actions applied — KEEPING GOING"
else
    log "  Auto-fix: no remedial actions needed this cycle"
fi

# ─── Step 0.6: Refresh approval-queue priorities ───
# Approved (human-reviewed) proposals should bias next experiment selection
# toward their target files. This closes the human-in-the-loop → next-cycle
# feedback gap.
log "=== Step 0.6: Refresh approval priorities ==="
PRIORITIES_FILE="$DIR/var/tmp/approval-priorities.el"
APPROVED_COUNT=0
if [ -d "$DIR/var/approval-queue/decisions" ]; then
    APPROVED_COUNT=$(find "$DIR/var/approval-queue/decisions" -name "*.sexp" -exec grep -l ':status "approved"' {} \; 2>/dev/null | wc -l)
fi

# ─── Step 0.7: Prune stale mementum memories ───
# Prevents unbounded growth: 379+ memories in mementum/memories/ would bloat
# prompts and slow mementum synthesis. Keep last N per topic, drop older than
# max-age-days. Cheap operation, no LLM calls.
log "=== Step 0.7: Prune mementum memories ==="
PRUNE_RESULT="$(emacsclient --socket-name=pmf-value-stream --eval '(condition-case err
  (let ((result (and (fboundp (quote gptel-auto-workflow--mementum-prune-run))
                     (gptel-auto-workflow--mementum-prune-run))))
    (if result (format "kept=%d pruned=%d topics=%d"
                       (or (plist-get result :kept-count) 0)
                       (or (plist-get result :pruned-count) 0)
                       (or (plist-get result :topics-affected) 0))
      "skipped"))
  (error (format "prune-error: %s" (error-message-string err))))' 2>/dev/null || echo "skipped")"
log "Mementum prune: $PRUNE_RESULT"
if [ "$APPROVED_COUNT" -gt 0 ]; then
    log "  Found $APPROVED_COUNT approved proposals; refreshing priorities"
    rm -f "$PRIORITIES_FILE"
else
    log "  No approved proposals pending; priorities unchanged"
fi

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
ZERO_RUN_DETECTED=0
if compgen -G "$RESULTS_PATTERN" >/dev/null; then
    latest_result=$(ls -t $RESULTS_PATTERN | head -1)
    result_count=$(wc -l < "$latest_result")
    data_count=$((result_count - 1))
    log "Results: $latest_result ($data_count experiments)"
    verify_research_feedback_loop "$latest_result" || true
    # YC principle: a 0-experiment run is a SIGNAL, not a benign no-op.
    # Log it explicitly and append to pipeline-health so self-heal can react.
    if [ "$data_count" -eq 0 ]; then
        ZERO_RUN_DETECTED=1
        log "  ⚠ ZERO-EXPERIMENT RUN: workflow completed but no targets ran"
        log "  This usually means analyzer failed and all fallbacks returned empty."
        log "  Possible causes: backend misconfigured, rate-limited, or filter rejected all targets."
        # Append a 0-run event to pipeline-health.md for self-heal / digest consumption
        HEALTH_FILE="$DIR/mementum/knowledge/pipeline-health.md"
        if [ -f "$HEALTH_FILE" ]; then
            zero_ts=$(date +%s)
            printf -- "- %s | zero-experiment-run | target-selection-empty | — | — | pending\n" "$zero_ts" >> "$HEALTH_FILE"
            log "  Appended zero-run event to pipeline-health.md"
        fi
    fi
else
    log "No results file found for today"
    ZERO_RUN_DETECTED=1
    log "  ⚠ NO RESULTS FILE: auto-workflow produced no results.tsv at all"
fi

# Track in PIPELINE_FINAL_STATUS
if [ "$ZERO_RUN_DETECTED" -eq 1 ]; then
    PIPELINE_FINAL_STATUS="zero-run"
fi

# ─── Step 6.1: Operational Metrics ───
log "=== Step 6.1: Operational Metrics ==="
METRICS_ELISP="(progn (ignore-errors (require 'gptel-auto-workflow-production))
                  (when (fboundp (quote gptel-auto-workflow-operational-metrics-report))
                    (gptel-auto-workflow-operational-metrics-report)))"
if emacsclient --socket-name="pmf-value-stream" --eval "$METRICS_ELISP" >/dev/null 2>&1; then
    log "  Metrics logged to daemon output"
else
    log "  Daemon not available for metrics (non-fatal)"
fi

# ─── Step 6.4: Daily digest — surface kept experiments to mementum ───
# YC principle: humans see "what kept last night" in one place. The pipeline
# already merges to git; this writes a human-readable summary that morning-sync
# can read without git log archaeology.
log "=== Step 6.4: Daily digest ==="
DIGEST_DIR="$DIR/mementum/knowledge/digests"
DIGEST_FILE="$DIGEST_DIR/$(date +%F).md"
mkdir -p "$DIGEST_DIR"
{
    echo "# Daily Pipeline Digest — $(date '+%Y-%m-%d')"
    echo ""
    echo "> Auto-generated by run-pipeline.sh. The 'System Health' section"
    echo "> at the top is the human's first read — if any check is ⚠, fix that first."
    echo ""
    echo "## System Health (Yin/Yang first-read)"
    echo ""
    # Compute health checks: questions the human should be able to answer
    # in 5 seconds from this section alone.
    health_ok=0
    health_warn=0
    # 1. Did we produce any improvements?
    if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
        kept_today=$(find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -newer "$PIPELINE_START_TIME" 2>/dev/null | xargs -I{} awk -F'\t' 'NR>1 && $8 ~ /^(kept|grader-bypass|merged|staged)$/ {c++} END {print c+0}' {} 2>/dev/null | paste -sd+ | bc 2>/dev/null)
        if [ "${kept_today:-0}" -gt 0 ]; then
            echo "- ✓ Kept experiments this run: $kept_today"
            health_ok=$((health_ok + 1))
        else
            echo "- ⚠ No kept experiments this run (improvement rate still low)"
            health_warn=$((health_warn + 1))
        fi
    fi
    # 2. Is the memory bank growing or shrinking?
    mem_count=$(find "$DIR/mementum/memories" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
    if [ "$mem_count" -gt 100 ]; then
        echo "- ✓ Memory bank: $mem_count memories (above minimum 100)"
        health_ok=$((health_ok + 1))
    else
        echo "- ⚠ Memory bank: $mem_count memories (low — pruning may have over-removed)"
        health_warn=$((health_warn + 1))
    fi
    # 3. Is the knowledge base fresh?
    fresh_pages=$(find "$DIR/mementum/knowledge" -maxdepth 1 -name "*.md" -mtime -14 2>/dev/null | wc -l)
    total_pages=$(find "$DIR/mementum/knowledge" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l)
    if [ "$total_pages" -gt 0 ] && [ "$fresh_pages" -gt 0 ]; then
        echo "- ✓ Knowledge pages: $fresh_pages/$total_pages fresh (≤14d)"
        health_ok=$((health_ok + 1))
    else
        echo "- ⚠ Knowledge pages: 0/$total_pages fresh (synthesis may be skipping)"
        health_warn=$((health_warn + 1))
    fi
    # 4. Self-heal status
    if [ -f "$DIR/mementum/knowledge/pipeline-health.md" ]; then
        pending=$(grep -c '| PENDING' "$DIR/mementum/knowledge/pipeline-health.md" 2>/dev/null || echo 0)
        effective=$(grep -c '| effective' "$DIR/mementum/knowledge/pipeline-health.md" 2>/dev/null || echo 0)
        zero_runs=$(grep -c '| zero-experiment-run' "$DIR/mementum/knowledge/pipeline-health.md" 2>/dev/null || echo 0)
        if [ "${pending:-0}" -eq 0 ]; then
            echo "- ✓ Self-heal: 0 pending remediations ($effective effective)"
            health_ok=$((health_ok + 1))
        elif [ "${pending:-0}" -lt 5 ]; then
            echo "- ⚠ Self-heal: $pending pending remediations ($effective effective, $zero_runs zero-runs)"
            health_warn=$((health_warn + 1))
        else
            echo "- ✗ Self-heal: $pending pending remediations — system may be stuck"
            health_warn=$((health_warn + 1))
        fi
        # Show recurring diagnoses (top issues by frequency)
        if [ "${pending:-0}" -gt 0 ]; then
            echo "  **Recurring PENDING diagnoses**:"
            grep '| PENDING' "$DIR/mementum/knowledge/pipeline-health.md" 2>/dev/null | \
                perl -ne '/([^|]+)\s*\|([^|]*)\|([^|]*)\|/ && print "$2\n"' | \
                sort | uniq -c | sort -rn | head -3 | while read count diagnosis; do
                echo "  - $count× $diagnosis (not yet fixed)"
            done
        fi
    fi
    # 5. Multi-machine coordination
    if [ -f "$DIR/var/tmp/active-runs" ]; then
        active_lines=$(wc -l < "$DIR/var/tmp/active-runs" 2>/dev/null || echo 0)
        echo "- ℹ Active runs (cross-machine log): $active_lines entries"
    fi
    # 6. Commit velocity (last 7 days)
    if command -v git >/dev/null 2>&1; then
        riven_commits=$(git -C "$DIR" log --since="7 days ago" --author="riven" --pretty=format:"%h" 2>/dev/null | wc -l)
        david_commits=$(git -C "$DIR" log --since="7 days ago" --author="David" --pretty=format:"%h" 2>/dev/null | wc -l)
        if [ "$riven_commits" -gt 50 ]; then
            echo "- ✓ Self-evolve velocity: $riven_commits auto-commits (7d) vs $david_commits human (system active)"
            health_ok=$((health_ok + 1))
        else
            echo "- ℹ Self-evolve velocity: $riven_commits auto-commits (7d) vs $david_commits human"
        fi
    fi
    echo ""
    echo "**Score: $health_ok ok, $health_warn warn.**"
    echo ""
    echo "## Kept Experiments (last 24h)"
    echo ""
    if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
        # Find results.tsv files modified in last 24h
        recent_results=$(find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -1 2>/dev/null | sort)
        if [ -n "$recent_results" ]; then
            # Use awk to aggregate kept experiments across all recent files.
            # Show: target, score delta, business value, decision.
            # This gives the human (Yin/Yang) enough context to evaluate
            # what the system is actually producing — not just file names.
            for rf in $recent_results; do
                awk -F'\t' 'NR>1 && $8 ~ /^(kept|grader-bypass|merged|staged)$/ {
                    delta = ($7 == "" ? 0 : $7)
                    bv = ($38 == "" ? 0 : $38)
                    hyp = substr($3, 1, 80)
                    printf "- **%s** (Δ=%+.2f, BV=%.2f) %s [%s]\n", $2, delta, bv, hyp, $8
                }' "$rf" 2>/dev/null
            done
        else
            echo "- No experiments in last 24h"
        fi
    else
        echo "- No results files found"
    fi
    echo ""
    echo "## Backend Performance (last 24h)"
    echo ""
    if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
        # Aggregate by backend from last 24h
        find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -1 -exec cat {} \; 2>/dev/null | \
            awk -F'\t' 'NR>1 && $15 != "" && $15 != "unknown" {
                backends[$15]++; if ($8 ~ /^(kept|grader-bypass|merged|staged)$/) kept[$15]++
            } END {
                for (b in backends) {
                    rate = (kept[b]+0) * 100 / backends[b]
                    printf "- **%s**: %d kept / %d total (%.0f%%)\n", b, kept[b]+0, backends[b], rate
                }
            }' | sort -k4 -n -r || echo "- No backend data"
    else
        echo "- No results files found"
    fi
    echo ""
    echo "## Self-Heal State"
    echo ""
    if [ -f "$DIR/mementum/knowledge/pipeline-health.md" ]; then
        # Pull out the most recent 5 entries
        grep -E "^[0-9]" "$DIR/mementum/knowledge/pipeline-health.md" 2>/dev/null | tail -5 | \
            sed 's/^/  - /' || echo "  - No remediations recorded"
    else
        echo "- pipeline-health.md not yet created"
    fi
    echo ""
    echo "## Keep-Rate Trend (last 7 days)"
    echo ""
    # Aggregate kept/total across all results.tsv files modified in last 7 days
    if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
        find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -7 -exec cat {} \; 2>/dev/null | \
            awk -F'\t' 'NR>1 {
                total++
                if ($8 ~ /^(kept|grader-bypass|merged|staged)$/) kept++
            } END {
                if (total > 0) {
                    rate = kept * 100.0 / total
                    printf "- **Total experiments (7d):** %d\n- **Kept:** %d\n- **Keep-rate:** %.1f%%\n", total, kept, rate
                    if (rate < 5) print "- ⚠ LOW: target is 20%+ for self-evolution to make progress"
                } else {
                    print "- No experiments in last 7 days"
                }
            }'
    else
        echo "- No results files found"
    fi
    # Per-decision breakdown
    if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
        find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -7 -exec cat {} \; 2>/dev/null | \
            awk -F'\t' 'NR>1 {count[$8]++} END {
                for (d in count) printf "- %s: %d\n", d, count[d]
            }' | sort -k2 -n -r | head -10
    fi
    echo ""
    echo "## Top Failure Modes by Target (last 7d)"
    echo ""
    # Per-target failure analysis: tells the human WHICH files are failing
    # and WHY. The highest-value signal for debugging the keep-rate problem.
    if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
        find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -7 -exec cat {} \; 2>/dev/null | \
            awk -F'\t' 'NR>1 {
                target = $2
                decision = $8
                reason = $12
                # Skip non-target rows (staging-review, staging-merge, etc.)
                if (target !~ /\.el$/) next
                total[target]++
                if (decision ~ /^(kept|grader-bypass|merged|staged)$/) kept[target]++
                else fail[target]++
                # Track failure reasons
                if (reason != "" && reason != "repeated-focus-symbol") {
                    key = target SUBSEP reason
                    reason_count[key]++
                }
            } END {
                # Find targets with most failures
                for (t in fail) {
                    if (fail[t] >= 3) {
                        rate = (kept[t]+0) * 100 / total[t]
                        printf "%s\t%d\t%d\t%d\n", t, total[t], kept[t]+0, fail[t]
                    }
                }
            }' | sort -t$'\t' -k4 -n -r | head -10 | \
        awk -F'\t' '{printf "- **%s**: %d attempts, %d kept, %d failed (%.0f%% keep)\n", $1, $2, $3, $4, ($3*100/$2)}'
        # For the top failing target, show its failure reasons
        top_failing=$(find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -7 -exec cat {} \; 2>/dev/null | \
            awk -F'\t' 'NR>1 {
                if ($2 !~ /\.el$/) next
                if ($8 !~ /^(kept|grader-bypass|merged|staged)$/) fail[$2]++
            } END { for (t in fail) print fail[t] "\t" t }' | sort -n -r | head -1 | cut -f2)
        if [ -n "$top_failing" ]; then
            echo ""
            echo "### Failure reasons for top target: \`$top_failing\`"
            find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -7 -exec cat {} \; 2>/dev/null | \
                awk -F'\t' -v target="$top_failing" 'NR>1 && $2 == target && $8 !~ /^(kept|grader-bypass|merged|staged)$/ {reason[$12]++} END {
                    for (r in reason) printf "  - %s: %d\n", r, reason[r]
                }' | sort -k3 -n -r | head -5
        fi
    fi
    echo ""
    echo "## Pipeline Run Status"
    echo ""
    echo "- Final status: $PIPELINE_FINAL_STATUS"
    echo "- Pipeline log: $PIPELINE_LOG"
    echo "- Last run timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Knowledge Page Freshness"
    echo ""
    # Flag knowledge pages older than 14 days as potentially stale.
    if compgen -G "$DIR/mementum/knowledge/*.md" >/dev/null; then
        stale_count=$(find "$DIR/mementum/knowledge" -maxdepth 1 -name "*.md" -mtime +14 2>/dev/null | wc -l)
        fresh_count=$(find "$DIR/mementum/knowledge" -maxdepth 1 -name "*.md" -mtime -14 2>/dev/null | wc -l)
        echo "- Fresh (≤14d): $fresh_count"
        echo "- Stale (>14d): $stale_count"
        if [ "$stale_count" -gt 0 ]; then
            echo "- Stale pages (top 5):"
            find "$DIR/mementum/knowledge" -maxdepth 1 -name "*.md" -mtime +14 -printf '  - %f (%TY-%Tm-%Td)\n' 2>/dev/null | sort -k3 | head -5
        fi
    else
        echo "- No knowledge pages yet"
    fi
    echo ""
    echo "## Strategy Pool Visibility"
    echo ""
    # How many strategies exist? How many have been evaluated? How many
    # are blind Bayesian guesses? YC principle: when 12-15/17 strategies
    # are unevaluated, the system is still exploring — it can't have found
    # a champion yet. The human should know this is a cold-start.
    if [ -d "$DIR/assistant/strategies" ]; then
        total_strategies=$(find "$DIR/assistant/strategies" -name "strategy-*.el" 2>/dev/null | wc -l)
        # Count strategy hits in recent results (column 22 = strategy name)
        if compgen -G "$DIR/var/tmp/experiments/*/results.tsv" >/dev/null; then
            used_strategies=$(find "$DIR/var/tmp/experiments" -maxdepth 2 -name "results.tsv" -mtime -7 -exec cat {} \; 2>/dev/null | \
                awk -F'\t' 'NR>1 && $22 != "" && $22 != "template-default" && $22 != "?" {print $22}' | sort -u | wc -l)
        else
            used_strategies=0
        fi
        unevaluated=$((total_strategies - used_strategies))
        if [ "$total_strategies" -gt 0 ]; then
            if [ "$unevaluated" -gt "$((total_strategies / 2))" ]; then
                echo "- **$total_strategies strategies** total, **$used_strategies** evaluated in last 7d, **$unevaluated unevaluated** (cold-start phase)"
                echo "- System is still exploring; no reliable champion yet"
            else
                echo "- **$total_strategies strategies** total, **$used_strategies** evaluated in last 7d, **$unevaluated unevaluated**"
                echo "- System has signal on most strategies; champion selection meaningful"
            fi
        fi
    else
        echo "- No strategy directory found"
    fi
} > "$DIGEST_FILE"
log "Daily digest written: $DIGEST_FILE"

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

# ─── Step 6.7: Verify recovery (did auto-fixes from Step 0.4-0.5 work?) ───
# This closes the full YC loop: DETECT → AUTO-FIX → VERIFY → KEEP GOING.
# Re-run self-audit and compare before/after. If issues improved, the
# system is self-healing. If they didn't, escalate for human review.
log "=== Step 6.7: Verify recovery ==="
if [ -f "$SELF_AUDIT_RESULT_FILE" ]; then
    BEFORE_ISSUES="$AUDIT_ISSUES"
    VERIFY_REPORT=$(emacs --batch -L "$DIR/lisp/modules" \
        -L "$DIR/packages/gptel" -L "$DIR/packages/compat" \
        -l gptel --eval \
        '(progn
           (require (quote gptel-auto-workflow-self-audit))
           (setq gptel-auto-workflow-self-audit-enabled t)
           (setq gptel-auto-workflow--workspace-path "'"$DIR"'")
           (let ((result (gptel-auto-workflow-self-audit-run)))
             (when result
               (princ (format "after-issues: %d\n" (plist-get result :issues))))))' 2>&1)
    AFTER_ISSUES=$(echo "$VERIFY_REPORT" | grep 'after-issues' | perl -ne 'if (/:\s*(\d+)/) { print $1 }')
    : "${AFTER_ISSUES:=$BEFORE_ISSUES}"
    DELTA=$((BEFORE_ISSUES - AFTER_ISSUES))
    if [ "$DELTA" -gt 0 ]; then
        log "  ✓ Recovery verified: $BEFORE_ISSUES → $AFTER_ISSUES issues (improved by $DELTA)"
        log "  Self-evolve loop WORKING: DETECT → AUTO-FIX → VERIFY → KEEP GOING"
    elif [ "$DELTA" -eq 0 ]; then
        log "  ‖ No improvement: $BEFORE_ISSUES → $AFTER_ISSUES issues (delta=0)"
        log "  Self-audit detected but auto-fix did not resolve — same problems persist"
        if [ "$BEFORE_ISSUES" -ge 3 ]; then
            log "  ⚠ Escalation: ≥3 unresolved issues — flagging for human review in digest"
        fi
    else
        log "  ⚠ Regression: $BEFORE_ISSUES → $AFTER_ISSUES issues (worse by $((-DELTA)))"
        log "  Self-evolve loop detected regression — auto-fixes may have side effects"
    fi
else
    log "  No self-audit result from Step 0.4 — skipping verify-recovery"
fi

# ─── Step 6.8: Synthesize system-health patterns (Learning<--Quality loop) ───
# When >=3 audit-fix memories exist with recurring root causes, create
# mementum/knowledge/system-health-patterns.md so the prompt builder can
# inject known issues into experiment prompts — biasing evolution to fix them.
log "=== Step 6.8: Synthesize system-health patterns ==="
SYNTH_RESULT=$(emacs --batch -L "$DIR/lisp/modules" \
    -L "$DIR/packages/gptel" -L "$DIR/packages/compat" \
    -l gptel --eval \
    '(progn
       (require (quote gptel-auto-workflow-self-audit))
       (setq gptel-auto-workflow--workspace-path "'"$DIR"'")
       (let ((n (gptel-auto-workflow-self-audit--synthesize-system-health)))
         (if n
             (princ (format "synthesized: %d memories -> system-health-patterns.md\n" n))
           (princ "synthesized: below-threshold (<3 audit memories)\n"))))' 2>&1)
log "  $SYNTH_RESULT"

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
    
    # SAFER STASH: only stash changes inside auto-generated directories.
    # This prevents accidentally destroying user work-in-progress outside those
    # dirs if the stash pop fails after the publish pull.
    stash_output="$(git -C "$DIR" stash push \
        --include-untracked \
        -m "pipeline-auto-sync-$(date +%s)" \
        -- mementum/knowledge/ assistant/skills/ assistant/strategies/ mementum/memories/ 2>&1 || true)"
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

    # SAFER POP: only pop the auto-gen stash. If it fails, just drop it —
    # never reset --hard, which could destroy user work outside auto-gen dirs.
    if [ "$stash_made" -eq 1 ]; then
        if ! git -C "$DIR" stash pop 2>/dev/null; then
            log "WARNING: stash pop failed after auto-publish; dropping the auto-gen stash only"
            git -C "$DIR" stash drop 2>/dev/null || true
        fi
    fi
else
    log "No auto-generated changes to publish"
fi

# ─── Pipeline Ops: Update plan, state, and log patterns ───
# Determine status: ok if no warnings, warn otherwise
PIPELINE_FINAL_STATUS="ok"
if grep -qE "WARNING:" "$PIPELINE_LOG" 2>/dev/null; then
    PIPELINE_FINAL_STATUS="warn"
fi
if grep -qE "load-error|all backends exhausted" "$PIPELINE_LOG" 2>/dev/null; then
    PIPELINE_FINAL_STATUS="err"
fi
update_pipeline_plan "$PIPELINE_FINAL_STATUS"
update_mementum_state "$PIPELINE_FINAL_STATUS"
log_pipeline_patterns "$PIPELINE_FINAL_STATUS"

# ─── Cross-machine coordination: record this run for other machines to see ───
# Format: hostname|timestamp|status
# This file is local-only (var/tmp/); the next machine pulls it via git pull
# and decides whether to skip its own run.
if [ -f "$ACTIVE_RUNS_FILE" ] || [ "$PIPELINE_FINAL_STATUS" != "ok" ]; then
    printf '%s|%s|%s\n' "$HOSTNAME_SHORT" "$(date +%s)" "$PIPELINE_FINAL_STATUS" \
        >> "$ACTIVE_RUNS_FILE"
    log "Recorded this run for cross-machine coordination: $HOSTNAME_SHORT $PIPELINE_FINAL_STATUS"
fi

exit 0
