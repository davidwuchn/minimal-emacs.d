#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-auto-workflow}"
shift || true
case "$ACTION" in
    auto-workflow|stop) SERVER_NAME="${AUTO_WORKFLOW_EMACS_SERVER:-copilot-auto-workflow}" ;;
    research) SERVER_NAME="${AUTO_WORKFLOW_EMACS_SERVER:-copilot-researcher}" ;;
    *) SERVER_NAME="${AUTO_WORKFLOW_EMACS_SERVER:-copilot-auto-workflow}" ;;
esac
case "$ACTION" in
    mementum|instincts|evolution) SNAPSHOT_NAME="$ACTION" ;;
    *)
        case "$SERVER_NAME" in
            copilot-auto-workflow) SNAPSHOT_NAME="auto-workflow" ;;
            *) SNAPSHOT_NAME="$SERVER_NAME" ;;
        esac
        ;;
esac
STATUS_FILE="${AUTO_WORKFLOW_STATUS_FILE:-$DIR/var/tmp/cron/${SNAPSHOT_NAME}-status.sexp}"
DAEMON_LOG="$DIR/var/tmp/cron/${SERVER_NAME}.log"
MESSAGES_FILE="${AUTO_WORKFLOW_MESSAGES_FILE:-$DIR/var/tmp/cron/${SNAPSHOT_NAME}-messages-tail.txt}"
MESSAGES_CHARS="${AUTO_WORKFLOW_MESSAGES_CHARS:-16000}"
case "$ACTION" in
    mementum|instincts|evolution) SNAPSHOT_CACHE_NAME="$ACTION" ;;
    *) SNAPSHOT_CACHE_NAME="$SERVER_NAME" ;;
esac
SNAPSHOT_PATHS_FILE="${AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE:-$DIR/var/tmp/cron/${SNAPSHOT_CACHE_NAME}-snapshot-paths.txt}"
STALE_DAEMON_RECOVERED=0
PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=auto

lisp_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

refresh_messages_lisp() {
    MESSAGES_LISP="$(lisp_escape "$MESSAGES_FILE")"
}

save_cached_snapshot_paths() {
    local status_path="$1"
    local messages_path="$2"
    local cache_dir

    [ -n "$status_path" ] || return 1
    [ -n "$messages_path" ] || return 1

    cache_dir="$(dirname "$SNAPSHOT_PATHS_FILE")"
    mkdir -p "$cache_dir"
    printf '%s\n%s\n' "$status_path" "$messages_path" >"$SNAPSHOT_PATHS_FILE"
}

load_cached_snapshot_paths() {
    local cached_status
    local cached_messages

    [ -r "$SNAPSHOT_PATHS_FILE" ] || return 1
    {
        IFS= read -r cached_status || true
        IFS= read -r cached_messages || true
    } <"$SNAPSHOT_PATHS_FILE"
    [ -n "$cached_status" ] || return 1
    [ -n "$cached_messages" ] || return 1
    STATUS_FILE="$cached_status"
    MESSAGES_FILE="$cached_messages"
    return 0
}

resolve_emacsclient() {
    if command -v emacsclient >/dev/null 2>&1; then
        command -v emacsclient
        return
    fi
    if [ -x /opt/homebrew/bin/emacsclient ]; then
        echo /opt/homebrew/bin/emacsclient
        return
    fi
    if [ -x /usr/local/bin/emacsclient ]; then
        echo /usr/local/bin/emacsclient
        return
    fi
    return 1
}

resolve_emacs() {
    if command -v emacs >/dev/null 2>&1; then
        command -v emacs
        return
    fi
    if [ -x /opt/homebrew/bin/emacs ]; then
        echo /opt/homebrew/bin/emacs
        return
    fi
    if [ -x /usr/local/bin/emacs ]; then
        echo /usr/local/bin/emacs
        return
    fi
    if [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ]; then
        echo /Applications/Emacs.app/Contents/MacOS/Emacs
        return
    fi
    return 1
}

EMACSCLIENT="$(resolve_emacsclient)" || {
    echo "emacsclient not found" >&2
    exit 1
}

EMACS="$(resolve_emacs)" || {
    echo "emacs not found" >&2
    exit 1
}

ROOT_LISP=$(lisp_escape "$DIR")
mkdir -p "$DIR/var/tmp/cron" "$DIR/var/tmp/experiments"

path_exists_or_link() {
    [ -e "$1" ] || [ -L "$1" ]
}

resolve_worktree_common_root() {
    local common_dir

    common_dir="$(git -C "$DIR" rev-parse --git-common-dir 2>/dev/null | awk 'NF { print; exit }')" || return 1
    [ -n "$common_dir" ] || return 1
    case "$common_dir" in
        /*) ;;
        *) common_dir="$(cd "$DIR/$common_dir" 2>/dev/null && pwd)" || return 1 ;;
    esac
    dirname "$common_dir"
}

append_missing_submodule_path() {
    local path="$1"
    local existing

    [ -n "$path" ] || return 0

    if [ "${#missing[@]}" -gt 0 ]; then
        for existing in "${missing[@]}"; do
            [ "$existing" = "$path" ] && return 0
        done
    fi

    missing+=("$path")
}
hydrate_missing_worktree_submodules() {
    local missing=()
    local path
    local _key

    [ -f "$DIR/.gitmodules" ] || return 0

    while IFS= read -r path; do
        append_missing_submodule_path "$path"
    done < <(git -C "$DIR" submodule status 2>/dev/null | awk 'substr($1, 1, 1) == "-" { print $2 }')

    # Fresh detached worktrees can materialize tracked submodule directories as
    # empty folders before Git reports them as missing. Hydrate any configured
    # submodule whose checkout still lacks the usual `.git` entry.
    while read -r _key path; do
        if ! path_exists_or_link "$DIR/$path/.git"; then
            append_missing_submodule_path "$path"
        fi
    done < <(git config --file "$DIR/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null)

    [ "${#missing[@]}" -gt 0 ] || return 0

    git -C "$DIR" submodule sync -- "${missing[@]}" >/dev/null 2>&1 || true
    git -C "$DIR" submodule update --init --recursive -- "${missing[@]}"
}

seed_worker_daemon_shared_var() {
    local common_root shared_var target_var entry target source rel

    common_root="$(resolve_worktree_common_root)" || return 0
    [ "$common_root" = "$DIR" ] && return 0

    shared_var="$common_root/var"
    target_var="$DIR/var"
    [ -d "$shared_var/elpa" ] || return 0

    mkdir -p "$target_var/elpa"
    for source in "$shared_var"/elpa/*; do
        [ -e "$source" ] || continue
        target="$target_var/elpa/$(basename "$source")"
        if ! path_exists_or_link "$target"; then
            ln -s "$source" "$target"
        fi
    done

    for rel in package-quickstart.el tree-sitter; do
        source="$shared_var/$rel"
        target="$target_var/$rel"
        if [ -e "$source" ] && ! path_exists_or_link "$target"; then
            ln -s "$source" "$target"
        fi
    done
}

default_status() {
    printf '(:running nil :kept 0 :total 0 :phase "idle" :results "var/tmp/experiments/%s/results.tsv")\n' "$(date +%F)"
}

print_status() {
    if [ -s "$STATUS_FILE" ]; then
        cat "$STATUS_FILE"
    else
        default_status
    fi
}

print_messages_snapshot() {
    local reason="${1:-cached}"
    local daemon_unreachable="${2:-auto}"

    if [ -r "$MESSAGES_FILE" ]; then
        if [ "$daemon_unreachable" = "yes" ] ||
           { [ "$daemon_unreachable" = "auto" ] &&
             ! check_worker_daemon >/dev/null 2>&1; }; then
            printf '[auto-workflow] WARNING: showing %s cached Messages snapshot; worker daemon is not reachable.\n' "$reason"
            if [ -r "$STATUS_FILE" ]; then
                printf '[auto-workflow] Last status: '
                tr '\n' ' ' <"$STATUS_FILE"
                printf '\n'
            fi
            printf '\n'
        fi
        cat "$MESSAGES_FILE"
    fi
}

status_indicates_running() {
    [ -r "$STATUS_FILE" ] && grep -q ':running t' "$STATUS_FILE"
}

status_indicates_active_phase() {
    [ -r "$STATUS_FILE" ] && grep -Eq ':phase "(running|queued|selecting)"' "$STATUS_FILE"
}

status_looks_active() {
    status_indicates_running || status_indicates_active_phase
}

status_has_live_run_id() {
    [ -r "$STATUS_FILE" ] && grep -Eq ':run-id "[^"]+' "$STATUS_FILE"
}

snapshot_file_fresh() {
    local path="$1"
    local ttl="${2:-${AUTO_WORKFLOW_ACTIVE_SNAPSHOT_TTL:-45}}"
    [ -r "$path" ] || return 1
    python3 - "$path" "$ttl" <<'PY'
from pathlib import Path
import sys
import time

path = Path(sys.argv[1])
ttl = float(sys.argv[2])

if not path.exists():
    raise SystemExit(1)

age = time.time() - path.stat().st_mtime
raise SystemExit(0 if age <= ttl else 1)
PY
}

status_snapshot_fresh() {
    snapshot_file_fresh "$STATUS_FILE"
}

messages_snapshot_fresh() {
    snapshot_file_fresh "$MESSAGES_FILE"
}

active_snapshot_has_empty_messages_tail() {
    local status_dir messages_dir

    status_indicates_active_phase &&
        status_has_live_run_id &&
        [ -e "$MESSAGES_FILE" ] &&
        ! [ -s "$MESSAGES_FILE" ] || return 1

    status_dir="$(dirname "$STATUS_FILE")"
    messages_dir="$(dirname "$MESSAGES_FILE")"
    [ "$status_dir" = "$messages_dir" ]
}

active_snapshot_has_completion_marker() {
    status_looks_active || return 1
    [ -r "$MESSAGES_FILE" ] || return 1
    grep -Eq '\[[^]]+\] All projects processed:' "$MESSAGES_FILE"
}

clear_completed_running_status() {
    if active_snapshot_has_completion_marker; then
        rewrite_status_idle
    fi
}

snapshot_file_stale_for_recovery() {
    local path="$1"
    ! snapshot_file_fresh "$path" "${AUTO_WORKFLOW_STALE_DAEMON_TTL:-1800}"
}

stale_active_snapshot_recoverable() {
    status_indicates_running &&
        status_has_live_run_id &&
        snapshot_file_stale_for_recovery "$STATUS_FILE" &&
        snapshot_file_stale_for_recovery "$MESSAGES_FILE"
}

worker_daemon_pids() {
    ps -eo pid=,args= | awk -v bg="--bg-daemon=$SERVER_NAME" \
        -v d="--daemon=$SERVER_NAME" \
        -v fg="--fg-daemon=$SERVER_NAME" '
        $2 ~ /(^|\/)emacs/ && (index($0, bg) || index($0, d) || index($0, fg)) { print $1 }
    '
}

worker_daemon_pid() {
    worker_daemon_pids | head -1
}

clean_orphaned_sockets() {
    local uid
    uid="$(id -u)"
    # Never clean sockets if a daemon process is still alive for this server.
    # The daemon owns its socket; removing it from underneath breaks connectivity.
    if [ -n "$(worker_daemon_pids)" ]; then
        return 0
    fi
    for base in "${TMPDIR:-/tmp}" "/tmp"; do
        local socket_dir="$base/emacs$uid"
        if [ -S "$socket_dir/$SERVER_NAME" ]; then
            rm -f "$socket_dir/$SERVER_NAME"
        fi
    done
    local runtime_dir="${XDG_RUNTIME_DIR:-}"
    if [ -n "$runtime_dir" ] && [ -S "$runtime_dir/emacs/$SERVER_NAME" ]; then
        rm -f "$runtime_dir/emacs/$SERVER_NAME"
    fi
}

discard_stale_worker_daemon() {
    local pids
    local pid
    pids="$(worker_daemon_pids || true)"
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
        for _ in $(seq 1 30); do
            local any_alive=0
            for pid in $pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    any_alive=1
                    break
                fi
            done
            if [ "$any_alive" -eq 0 ]; then
                break
            fi
            sleep 0.2
        done
        for pid in $pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
    clean_orphaned_sockets
    STALE_DAEMON_RECOVERED=1
    rewrite_status_idle
}

daemon_socket_has_owner() {
    python3 - "$SERVER_NAME" <<'PY'
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

server_name = sys.argv[1]

def candidate_socket_paths(name):
    uid = os.getuid()
    candidates = []
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        candidates.append(Path(runtime_dir) / "emacs" / name)
    for base in filter(None, [os.environ.get("TMPDIR"), tempfile.gettempdir(), "/tmp"]):
        candidates.append(Path(base) / f"emacs{uid}" / name)
    deduped = []
    seen = set()
    for path in candidates:
        key = str(path)
        if key not in seen:
            deduped.append(path)
            seen.add(key)
    return deduped

socket_path = next((path for path in candidate_socket_paths(server_name) if path.exists()), None)
if socket_path is None:
    raise SystemExit(1)

lsof = shutil.which("lsof")
if not lsof:
    raise SystemExit(0)

try:
    probe = subprocess.run(
        [lsof, str(socket_path)],
        capture_output=True,
        text=True,
        timeout=2,
        check=False,
    )
except subprocess.TimeoutExpired:
    raise SystemExit(0)

raise SystemExit(0 if probe.returncode == 0 else 1)
PY
}

daemon_socket_owned_by_worker_daemon() {
    local daemon_pid

    daemon_pid="$(worker_daemon_pid || true)"
    [ -n "$daemon_pid" ] || return 1

    python3 - "$SERVER_NAME" "$daemon_pid" <<'PY'
from pathlib import Path
import os
import shutil
import subprocess
import sys
import tempfile

server_name = sys.argv[1]
daemon_pid = sys.argv[2]

def candidate_socket_paths(name):
    uid = os.getuid()
    candidates = []
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        candidates.append(Path(runtime_dir) / "emacs" / name)
    for base in filter(None, [os.environ.get("TMPDIR"), tempfile.gettempdir(), "/tmp"]):
        candidates.append(Path(base) / f"emacs{uid}" / name)
    deduped = []
    seen = set()
    for path in candidates:
        key = str(path)
        if key not in seen:
            deduped.append(path)
            seen.add(key)
    return deduped

socket_path = next((path for path in candidate_socket_paths(server_name) if path.exists()), None)
if socket_path is None:
    raise SystemExit(1)

lsof = shutil.which("lsof")
if not lsof:
    raise SystemExit(1)

try:
    probe = subprocess.run(
        [lsof, "-t", str(socket_path)],
        capture_output=True,
        text=True,
        timeout=2,
        check=False,
    )
except subprocess.TimeoutExpired:
    raise SystemExit(1)

owners = {line.strip() for line in probe.stdout.splitlines() if line.strip()}
raise SystemExit(0 if daemon_pid in owners else 1)
PY
}

status_can_use_persisted_active_snapshot() {
    local rc

    PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=auto

    status_indicates_active_phase || return 1
    status_has_live_run_id || return 1

    case "$ACTION" in
        messages)
            if messages_snapshot_fresh &&
               ! daemon_socket_owned_by_worker_daemon; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            ;;
        status)
            if status_snapshot_fresh &&
               ! daemon_socket_owned_by_worker_daemon; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            ;;
        *)
            if { status_snapshot_fresh || messages_snapshot_fresh; } &&
               ! daemon_socket_owned_by_worker_daemon; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            ;;
    esac

    case "$ACTION" in
        messages)
            if messages_snapshot_fresh && ! daemon_socket_has_owner; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            ;;
        status)
            if status_snapshot_fresh && ! daemon_socket_has_owner; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            ;;
        *)
            if { status_snapshot_fresh || messages_snapshot_fresh; } &&
               ! daemon_socket_has_owner; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            ;;
    esac

    if check_worker_daemon; then
        if daemon_reports_active_workflow; then
            case "$ACTION" in
                messages)
                    if messages_snapshot_fresh; then
                        PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=no
                        return 0
                    fi
                    return 1
                    ;;
                status)
                    if status_snapshot_fresh; then
                        PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=no
                        return 0
                    fi
                    return 1
                    ;;
                *)
                    if status_snapshot_fresh || messages_snapshot_fresh; then
                        PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=no
                        return 0
                    fi
                    return 1
                    ;;
            esac
        else
            rc=$?
            if [ "$rc" -eq 1 ]; then
                return 1
            elif [ "$rc" -eq 2 ]; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
        fi
    else
        rc=$?
        if [ "$rc" -eq 2 ]; then
            PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
            return 0
        fi
    fi

    case "$ACTION" in
        messages)
            if messages_snapshot_fresh || daemon_socket_has_owner; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            return 1
            ;;
        *)
            if status_snapshot_fresh || messages_snapshot_fresh || daemon_socket_has_owner; then
                PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE=yes
                return 0
            fi
            return 1
            ;;
    esac
}

rewrite_status_idle() {
    if [ ! -s "$STATUS_FILE" ]; then
        default_status >"$STATUS_FILE"
        return 0
    fi

    python3 - "$STATUS_FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r':running\s+t', ':running nil', text, count=1)
text = re.sub(r':phase\s+"[^"]*"', ':phase "idle"', text, count=1)
if not text.endswith("\n"):
    text += "\n"
path.write_text(text, encoding="utf-8")
PY
}

run_emacsclient_eval() {
    local elisp="$1"
    local timeout="${2:-10}"
    python3 - "$EMACSCLIENT" "$SERVER_NAME" "$elisp" "$timeout" <<'PY'
import subprocess
import os
import shutil
import sys
import tempfile
from pathlib import Path

emacsclient, server_name, elisp, timeout = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])

def server_socket_path():
    uid = os.getuid()
    candidates = []
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir:
        candidates.append(Path(runtime_dir) / "emacs" / server_name)
    for base in filter(None, [os.environ.get("TMPDIR"), tempfile.gettempdir(), "/tmp"]):
        candidates.append(Path(base) / f"emacs{uid}" / server_name)
    deduped = []
    seen = set()
    for path in candidates:
        key = str(path)
        if key in seen:
            continue
        deduped.append(path)
        seen.add(key)
    for path in deduped:
        if path.exists():
            return path
    return deduped[0]

def socket_has_owner():
    socket_path = server_socket_path()
    if not socket_path.exists():
        return False
    lsof = shutil.which("lsof")
    if not lsof:
        return True
    try:
        probe = subprocess.run(
            [lsof, str(socket_path)],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return True
    return probe.returncode == 0

try:
    proc = subprocess.Popen(
        [emacsclient, "-a", "false", "-s", server_name, "--eval", elisp],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
except OSError as err:
    sys.stderr.write(f"{err}\n")
    raise SystemExit(1)

try:
    stdout_text, stderr_text = proc.communicate(timeout=timeout)
except subprocess.TimeoutExpired as err:
    # Leave the client alive so the server can finish the request cleanly
    # instead of logging a broken server connection when the wrapper gives up.
    # The child must keep draining its stdout/stderr pipes after this wrapper
    # exits, otherwise the server sees a remote peer disconnect mid-request.
    if err.stdout:
        sys.stdout.write(err.stdout if isinstance(err.stdout, str) else err.stdout.decode())
    if err.stderr:
        sys.stderr.write(err.stderr if isinstance(err.stderr, str) else err.stderr.decode())
    if proc.poll() is None and hasattr(os, "fork"):
        try:
            reaper_pid = os.fork()
        except OSError:
            reaper_pid = -1
        if reaper_pid == 0:
            try:
                try:
                    os.setsid()
                except OSError:
                    pass
                devnull_fd = os.open(os.devnull, os.O_RDWR)
                try:
                    os.dup2(devnull_fd, 0)
                    os.dup2(devnull_fd, 1)
                    os.dup2(devnull_fd, 2)
                finally:
                    if devnull_fd > 2:
                        os.close(devnull_fd)
                try:
                    proc.communicate()
                except Exception:
                    pass
            finally:
                os._exit(0)
    raise SystemExit(124)

proc_stdout = stdout_text or ""
proc_stderr = stderr_text or ""
proc_returncode = proc.returncode

busy_markers = (
    "Server not responding; use Ctrl+C to break",
    "server did not reply",
)
stderr_text = proc_stderr
if proc_returncode != 0 and any(marker in stderr_text for marker in busy_markers):
    if proc_stdout:
        sys.stdout.write(proc_stdout)
    if proc_stderr:
        sys.stderr.write(proc_stderr)
    raise SystemExit(124)

if (proc_returncode != 0
        and "Connection refused" in stderr_text
        and socket_has_owner()):
    if proc_stdout:
        sys.stdout.write(proc_stdout)
    if proc_stderr:
        sys.stderr.write(proc_stderr)
    raise SystemExit(124)

sys.stdout.write(proc_stdout)
sys.stderr.write(proc_stderr)
raise SystemExit(proc_returncode)
PY
}

check_worker_daemon() {
    local first_rc rc
    if run_emacsclient_eval "t" 1 >/dev/null 2>&1; then
        return 0
    else
        first_rc=$?
    fi
    if run_emacsclient_eval "t" 3 >/dev/null 2>&1; then
        return 0
    else
        rc=$?
    fi
    if [ "$first_rc" -eq 124 ] || [ "$rc" -eq 124 ]; then
        return 2
    fi
    return 1
}

daemon_reports_active_workflow() {
    local body="(and (fboundp 'gptel-auto-workflow--status-plist)
                     (gptel-auto-workflow--status-plist))"
    local output
    local rc
    if output="$(run_emacsclient_eval "$(wrap_emacs_eval "$body")" 2 2>/dev/null)"; then
        if ! printf '%s' "$output" | grep -q ':phase '; then
            return 1
        fi
        if printf '%s' "$output" | grep -q ':running t'; then
            return 0
        fi
        if printf '%s' "$output" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"'; then
            return 1
        fi
        return 0
    else
        rc=$?
        if [ "$rc" -eq 124 ]; then
            return 2
        fi
        return 2
    fi
}

clear_stale_running_status() {
    if ! status_looks_active; then
        return 0
    fi

    local rc
    if check_worker_daemon; then
        rc=0
    else
        rc=$?
    fi

    # If daemon socket/process does not exist but status says running,
    # the daemon crashed.  Clear the stale status immediately so the next
    # cron run can start a fresh daemon.
    if [ "$rc" -eq 1 ] && ! [ -n "$(worker_daemon_pids)" ]; then
        rewrite_status_idle
        return 0
    fi

    if [ "$rc" -eq 0 ]; then
        if daemon_reports_active_workflow; then
            return 0
        else
            rc=$?
            if [ "$rc" -eq 1 ]; then
                rewrite_status_idle
            fi
        fi
        return 0
    fi

    if [ "$rc" -eq 1 ]; then
        rewrite_status_idle
    elif [ "$rc" -eq 2 ] && stale_active_snapshot_recoverable; then
        discard_stale_worker_daemon
    fi
    return 0
}

wrap_emacs_eval() {
    local body="$1"
    local env_elisp=""
    local ssh_auth_sock="${SSH_AUTH_SOCK:-}"
    local git_ssh_command="${GIT_SSH_COMMAND:-}"
    local status_file="$STATUS_FILE"
    local messages_file="$MESSAGES_FILE"

    case "$ACTION" in
        status|messages) ;;
        *)
            if [ -n "$status_file" ]; then
                env_elisp="$env_elisp (setenv \"AUTO_WORKFLOW_STATUS_FILE\" \"$(lisp_escape "$status_file")\")"
            fi

            if [ -n "$messages_file" ]; then
                env_elisp="$env_elisp (setenv \"AUTO_WORKFLOW_MESSAGES_FILE\" \"$(lisp_escape "$messages_file")\")"
            fi
            ;;
    esac

    if [ -n "$ssh_auth_sock" ]; then
        env_elisp="$env_elisp (setenv \"SSH_AUTH_SOCK\" \"$(lisp_escape "$ssh_auth_sock")\")"
    fi

    if [ -z "$git_ssh_command" ] && [ -n "$ssh_auth_sock" ]; then
        # Apple's built-in ssh supports UseKeychain/AddKeysToAgent extensions.
        # Homebrew OpenSSH (OpenSSL backend) does not. Detect and adapt.
        if [ "${SSH_FALLBACK:-0}" -eq 1 ] && [ -x /usr/bin/ssh ]; then
            git_ssh_command='/usr/bin/ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UseKeychain=yes -o AddKeysToAgent=yes'
        elif ssh -o UseKeychain=yes -V 2>/dev/null; then
            git_ssh_command='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o UseKeychain=yes -o AddKeysToAgent=yes'
        else
            git_ssh_command='ssh -o BatchMode=yes -o IdentitiesOnly=yes'
        fi
    fi

    if [ -n "$git_ssh_command" ]; then
        env_elisp="$env_elisp (setenv \"GIT_SSH_COMMAND\" \"$(lisp_escape "$git_ssh_command")\")"
    fi

    printf '(with-current-buffer (get-buffer-create "*copilot-auto-workflow-eval*")%s %s)' \
           "$env_elisp" "$body"
}

ensure_ssh_keys_loaded() {
    # Apple's built-in ssh auto-loads keys from Keychain via UseKeychain.
    # Homebrew OpenSSH needs keys explicitly added to the agent.
    if ssh -o UseKeychain=yes -V 2>/dev/null; then
        return 0  # Apple ssh handles this automatically
    fi

    [ -n "${SSH_AUTH_SOCK:-}" ] || return 0

    # Check if agent already has keys loaded
    if ssh-add -l >/dev/null 2>&1; then
        return 0
    fi

    # Try to add common key paths without prompting (BatchMode prevents interaction)
    local key_added=0
    for key in \
        "$HOME/.ssh/id_ed25519" \
        "$HOME/.ssh/id_ecdsa" \
        "$HOME/.ssh/id_rsa" \
        "$HOME/.ssh/github_ed25519"; do
        if [ -f "$key" ] && SSH_ASKPASS=false ssh-add "$key" </dev/null 2>/dev/null; then
            key_added=1
            break
        fi
    done

    if [ "$key_added" -eq 0 ]; then
        # Homebrew OpenSSH can't use macOS Keychain. Fall back to Apple's
        # built-in ssh for git operations if available.
        if [ -x /usr/bin/ssh ]; then
            echo "WARNING: No keys in ssh-agent. Falling back to Apple's built-in ssh for git." >&2
            SSH_FALLBACK=1
        else
            echo "WARNING: No SSH keys loaded in agent for Homebrew OpenSSH." >&2
            echo "  Run: ssh-add ~/.ssh/id_ed25519" >&2
            echo "  Or use Apple's built-in ssh: export PATH=/usr/bin:\$PATH" >&2
        fi
    fi
    return 0
}

workflow_action_elisp() {
    local action="$1"
    local dispatch

    case "$action" in
        auto-workflow) dispatch="(gptel-auto-workflow-queue-all-projects)" ;;
        research) dispatch="(gptel-auto-workflow-queue-all-research)" ;;
        mementum) dispatch="(progn (setq gptel-mementum-headless-auto-approve t) (gptel-auto-workflow-queue-all-mementum))" ;;
        instincts) dispatch="(gptel-auto-workflow-queue-all-instincts)" ;;
        evolution) dispatch="(when (fboundp 'gptel-auto-workflow-evolution-run-cycle) (gptel-auto-workflow-evolution-run-cycle))" ;;
        *) return 1 ;;
    esac

    printf '(let ((root (file-name-as-directory "%s"))) (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" root)) (when (fboundp (quote gptel-auto-workflow--activate-live-root)) (gptel-auto-workflow--activate-live-root root)) (when (fboundp (quote gptel-auto-workflow--reload-live-support)) (gptel-auto-workflow--reload-live-support root)) %s)' \
           "$ROOT_LISP" "$dispatch"
}

stop_action_elisp() {
    printf '(let ((root (file-name-as-directory "%s")))
              (let ((agent-file (expand-file-name "lisp/modules/gptel-tools-agent.el" root)))
                (when (file-readable-p agent-file)
                  (load-file agent-file)))
              (when (fboundp (quote gptel-auto-workflow--activate-live-root))
                (gptel-auto-workflow--activate-live-root root))
              (when (fboundp (quote gptel-auto-workflow-force-stop))
                (gptel-auto-workflow-force-stop))
              (if (fboundp (quote gptel-auto-workflow--status-plist))
                  (gptel-auto-workflow--status-plist)
                (quote (:running nil :kept 0 :total 0 :phase "idle" :run-id nil :results nil))))' \
           "$ROOT_LISP"
}

refresh_snapshot_paths_from_daemon() {
    local body
    local output
    local payload
    local daemon_status
    local daemon_messages
    local effective_status
    local effective_messages

    body='(if (and (fboundp '"'"'gptel-auto-workflow--status-file)
                   (fboundp '"'"'gptel-auto-workflow--messages-file))
              (format "%s\t%s"
                      (gptel-auto-workflow--status-file)
                      (gptel-auto-workflow--messages-file))
            "")'
    output="$(run_emacsclient_eval "$(wrap_emacs_eval "$body")" 2 2>/dev/null)" || return 1
    payload="$output"
    if [ "${payload#\"}" != "$payload" ] && [ "${payload%\"}" != "$payload" ]; then
        payload="${payload#\"}"
        payload="${payload%\"}"
    fi
    IFS=$'\t' read -r daemon_status daemon_messages <<<"$payload"
    [ -n "$daemon_status" ] || return 1
    [ -n "$daemon_messages" ] || return 1
    [ -d "$(dirname "$daemon_status")" ] || return 1
    [ -d "$(dirname "$daemon_messages")" ] || return 1

    effective_status="$daemon_status"
    effective_messages="$daemon_messages"
    if [ -n "${AUTO_WORKFLOW_STATUS_FILE:-}" ]; then
        effective_status="$STATUS_FILE"
    fi
    if [ -n "${AUTO_WORKFLOW_MESSAGES_FILE:-}" ]; then
        effective_messages="$MESSAGES_FILE"
    fi

    if [ -n "${AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE:-}" ] ||
       { [ -z "${AUTO_WORKFLOW_STATUS_FILE:-}" ] && [ -z "${AUTO_WORKFLOW_MESSAGES_FILE:-}" ]; }; then
        save_cached_snapshot_paths "$daemon_status" "$daemon_messages"
    fi

    STATUS_FILE="$effective_status"
    MESSAGES_FILE="$effective_messages"
    return 0
}

prime_snapshot_paths_for_action() {
    local default_status="$STATUS_FILE"
    local default_messages="$MESSAGES_FILE"
    local shared_status="$DIR/var/tmp/cron/auto-workflow-status.sexp"
    local shared_messages="$DIR/var/tmp/cron/auto-workflow-messages-tail.txt"

    if [ -n "${AUTO_WORKFLOW_STATUS_FILE:-}" ] || [ -n "${AUTO_WORKFLOW_MESSAGES_FILE:-}" ]; then
        # Nested callers (notably run-tests.sh during live workflow verification)
        # use temporary status/message files. Do not poison the shared cache
        # unless the caller also supplied a dedicated snapshot-path cache file.
        if [ -n "${AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE:-}" ]; then
            save_cached_snapshot_paths "$STATUS_FILE" "$MESSAGES_FILE" >/dev/null 2>&1 || true
        fi
    elif [ "$ACTION" = "status" ] || [ "$ACTION" = "messages" ]; then
        load_cached_snapshot_paths || true
        if [ "$default_status" != "$shared_status" ] &&
           [ "$STATUS_FILE" = "$shared_status" ] &&
           [ -r "$default_status" ]; then
            STATUS_FILE="$default_status"
        fi
        if [ "$default_messages" != "$shared_messages" ] &&
           [ "$MESSAGES_FILE" = "$shared_messages" ] &&
           [ -r "$default_messages" ]; then
            MESSAGES_FILE="$default_messages"
        fi
        save_cached_snapshot_paths "$STATUS_FILE" "$MESSAGES_FILE" >/dev/null 2>&1 || true
        if [ "$ACTION" = "messages" ] && [ ! -r "$MESSAGES_FILE" ]; then
            refresh_snapshot_paths_from_daemon >/dev/null 2>&1 || true
        fi
    else
        save_cached_snapshot_paths "$STATUS_FILE" "$MESSAGES_FILE" >/dev/null 2>&1 || true
    fi
    refresh_messages_lisp
}

prime_snapshot_paths_for_action

ensure_worker_daemon() {
    local rc
    if check_worker_daemon; then
        rc=0
    else
        rc=$?
    fi

    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    if [ "$rc" -eq 2 ]; then
        if [ "$STALE_DAEMON_RECOVERED" -eq 0 ]; then
            return 0
        fi
        rc=1
    fi
    
    # Kill any stale daemon process before starting a new one to avoid
    # socket conflicts from leftover processes.
    local stale_pids
    stale_pids="$(worker_daemon_pids || true)"
    if [ -n "$stale_pids" ]; then
        local pid_count
        pid_count="$(echo "$stale_pids" | wc -l | tr -d ' ')"
        if [ "$pid_count" -gt 1 ]; then
            echo "WARNING: Found $pid_count $SERVER_NAME daemons running. Killing all..." >&2
        else
            echo "Killing stale daemon: $SERVER_NAME (pid: $stale_pids)" >&2
        fi
        discard_stale_worker_daemon
        sleep 1
    fi
    
    # Always clean up orphaned sockets even if no stale PIDs found.
    # Daemons can crash without cleaning up their socket files.
    clean_orphaned_sockets
    
    # Ensure SSH keys are loaded in agent (needed by Homebrew OpenSSH)
    ensure_ssh_keys_loaded
    
    # Keep the dedicated workflow daemon truly headless and detached.  A forked
    # `--daemon' process has repeatedly disappeared mid-staging on this host
    # without leaving an Emacs backtrace.  Run the worker as a foreground daemon
    # in its own session instead: it still serves the named socket, but the OS
    # process is observable and not tied to the cron wrapper's shell lifetime.
    hydrate_missing_worktree_submodules
    seed_worker_daemon_shared_var
    # Disable native compilation for workflow daemon to avoid stale cache issues
    setsid env -u DISPLAY -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XAUTHORITY \
        EMACSNATIVELOADPATH= \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 \
        MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        "$EMACS" --init-directory="$DIR" --fg-daemon="$SERVER_NAME" >>"$DAEMON_LOG" 2>&1 &
    for _ in $(seq 1 50); do
        if check_worker_daemon; then
            rc=0
        else
            rc=$?
        fi

        if [ "$rc" -eq 0 ]; then
            return 0
        fi
        if [ "$rc" -eq 2 ]; then
            if [ "$STALE_DAEMON_RECOVERED" -eq 0 ]; then
                return 0
            fi
        fi
        sleep 0.2
    done
    echo "failed to start worker daemon: $SERVER_NAME" >&2
    tail -n 40 "$DAEMON_LOG" >&2 || true
    return 1
}

case "$ACTION" in
    auto-workflow)
        ELISP="$(workflow_action_elisp "auto-workflow")"
        ;;
    research)
        ELISP="$(workflow_action_elisp "research")"
        ;;
    mementum)
        ELISP="$(workflow_action_elisp "mementum")"
        ;;
    instincts)
        ELISP="$(workflow_action_elisp "instincts")"
        ;;
    evolution)
        ELISP="$(workflow_action_elisp "evolution")"
        ;;
    status)
        ELISP="(and (fboundp 'gptel-auto-workflow--status-plist)
                    (gptel-auto-workflow--status-plist))"
        ;;
    messages)
        ELISP="(let ((outfile \"$MESSAGES_LISP\")
                     (max-chars $MESSAGES_CHARS))
                 (with-current-buffer (get-buffer-create \"*Messages*\")
                   (write-region (max (point-min) (- (point-max) max-chars))
                                 (point-max)
                                 outfile nil 'silent))
                  outfile)"
        ;;
    stop)
        ELISP="$(stop_action_elisp)"
        ;;
    *)
        echo "Usage: $0 {auto-workflow|research|mementum|instincts|evolution|status|messages|stop}" >&2
        exit 2
        ;;
esac

EVAL_ELISP="$(wrap_emacs_eval "$ELISP")"

cd "$DIR"
if [ "$ACTION" = "status" ]; then
    clear_completed_running_status
    if active_snapshot_has_empty_messages_tail; then
        clear_stale_running_status
    fi
    # If daemon is running but doesn't report active workflow, clear stale status
    if check_worker_daemon && ! daemon_reports_active_workflow; then
        clear_stale_running_status
    fi
    if status_can_use_persisted_active_snapshot; then
        print_status
        exit 0
    fi
    if output="$(run_emacsclient_eval "$EVAL_ELISP" 5 2>/dev/null)" &&
       printf '%s' "$output" | grep -q ':phase '; then
        refresh_snapshot_paths_from_daemon >/dev/null 2>&1 || true
        printf '%s\n' "$output" >"$STATUS_FILE"
        printf '%s\n' "$output"
        exit 0
    fi
    clear_stale_running_status
    print_status
    exit 0
fi

if [ "$ACTION" = "messages" ]; then
    clear_completed_running_status
    if active_snapshot_has_empty_messages_tail; then
        clear_stale_running_status
    fi
    if ! check_worker_daemon; then
        rc=$?
        if [ -r "$MESSAGES_FILE" ]; then
            print_messages_snapshot fallback yes
            exit 0
        fi
        if [ "$rc" -eq 1 ]; then
            ensure_worker_daemon
        fi
    fi
    if run_emacsclient_eval "$EVAL_ELISP" 10 >/dev/null; then
        if [ -r "$MESSAGES_FILE" ]; then
            cat "$MESSAGES_FILE"
        fi
        exit 0
    fi
    rc=$?
    if status_can_use_persisted_active_snapshot && [ -r "$MESSAGES_FILE" ]; then
        print_messages_snapshot active "$PERSISTED_SNAPSHOT_DAEMON_UNREACHABLE"
        exit 0
    fi
    if [ -r "$MESSAGES_FILE" ]; then
        print_messages_snapshot stale yes
        exit 0
    fi
    exit $rc
fi

if [ "$ACTION" = "stop" ]; then
    if check_worker_daemon; then
        if output="$(run_emacsclient_eval "$EVAL_ELISP" 20 2>/dev/null)" &&
           printf '%s' "$output" | grep -q ':phase '; then
            refresh_snapshot_paths_from_daemon >/dev/null 2>&1 || true
            printf '%s\n' "$output" >"$STATUS_FILE"
            printf '%s\n' "$output"
            exit 0
        fi
        rc=$?
        if [ "$rc" -eq 124 ]; then
            echo "stop timed out waiting for worker daemon: $SERVER_NAME" >&2
            print_status
            exit 124
        fi
    fi
    clear_stale_running_status
    if status_looks_active; then
        rewrite_status_idle
    fi
    print_status
    exit 0
fi

clear_stale_running_status

if status_indicates_running; then
    echo "already-running"
    exit 0
fi

ensure_worker_daemon

if status_indicates_running; then
    echo "already-running"
    exit 0
fi

# Run workflow with crash recovery
MAX_RESTARTS=3
RESTART_COUNT=0
WORKFLOW_COMPLETED=0

while [ "$WORKFLOW_COMPLETED" -eq 0 ] && [ "$RESTART_COUNT" -lt "$MAX_RESTARTS" ]; do
    if run_emacsclient_eval "$EVAL_ELISP" 10; then
        WORKFLOW_COMPLETED=1
        exit 0
    fi
    
    rc=$?
    if [ "$rc" -eq 124 ] && status_indicates_running; then
        echo "already-running"
        exit 0
    fi
    
    # Check if daemon crashed
    if ! check_worker_daemon; then
        RESTART_COUNT=$((RESTART_COUNT + 1))
        echo "[auto-workflow] Daemon crashed during workflow (restart $RESTART_COUNT/$MAX_RESTARTS)" >&2
        
        # Clear stale state
        clear_stale_running_status
        
        # Kill any remaining stale processes
        discard_stale_worker_daemon
        sleep 2
        
        # Restart daemon
        ensure_worker_daemon
        sleep 5
        
        # Re-check
        if ! check_worker_daemon; then
            echo "[auto-workflow] Failed to restart daemon after crash" >&2
            exit 1
        fi
        
        echo "[auto-workflow] Daemon restarted, resuming workflow..." >&2
        # Continue loop to retry
    else
        # Daemon still alive but workflow failed for another reason
        echo "[auto-workflow] Workflow failed with rc=$rc (daemon still alive)" >&2
        exit "$rc"
    fi
done

if [ "$WORKFLOW_COMPLETED" -eq 0 ]; then
    echo "[auto-workflow] Workflow failed after $MAX_RESTARTS restart attempts" >&2
    exit 1
fi

exit 0
