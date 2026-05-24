#!/bin/bash
# Hot-start: boot daemon, hot-reload, then trigger run
BASEDIR="/home/davidwu/.emacs.d"
SOCKET="ov5-auto-workflow"

# Step 1: Start daemon via cron
"$BASEDIR/scripts/run-auto-workflow-cron.sh" auto-workflow &
DAEMON_PID=$!

# Step 2: Wait for socket
for i in $(seq 1 60); do
  if [ -S "/run/user/1000/emacs/$SOCKET" ]; then
    break
  fi
  sleep 1
done

if [ ! -S "/run/user/1000/emacs/$SOCKET" ]; then
  echo "ERROR: Daemon socket never appeared"
  exit 1
fi

# Step 3: Wait for daemon to fully initialize (modules loaded)
sleep 30

# Step 4: Hot-reload + reset + trigger
emacsclient -s "$SOCKET" --eval "
(progn
  (defvar async nil)
  (defvar process nil)
  (defvar monitoring nil)
  (defvar state nil)
  (load-file \"lisp/modules/gptel-auto-workflow-projects.el\")
  (load-file \"lisp/modules/gptel-tools-agent-main.el\")
  (setq gptel-auto-workflow--cron-job-running nil
        gptel-auto-workflow--running nil)
  (gptel-auto-workflow--queue-cron-job \"auto-workflow\"
    (lambda (cb) (gptel-auto-workflow-run-all-projects cb))
    t)
  \"hot-started\")"

echo "Hot-start sequence complete"
