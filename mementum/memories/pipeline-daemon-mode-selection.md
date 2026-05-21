# ❌ Pipeline Daemon Mode Selection

tags: daemon, pipe-blocking, soft-requires, force-push

## Context
Three rounds of force-push ping-pong between `--daemon` and `--fg-daemon` in scripts/run-auto-workflow-cron.sh. Each side claimed their choice fixed socket conflicts or pipe blocking. Neither was the root cause. The experiment promotion pipeline kept force-pushing whichever version was on the branch that passed verification, creating a tug-of-war.

## What We Tested (TDD)
- `--daemon`: forked daemon, standard Emacs mode. Daemon alive >120s with workflow running. 171/171 tests.
- `--fg-daemon`: foreground daemon, doesn't fork. Same pipe-block behavior. Also works.
- `--bg-daemon`: appears in ps output for some Emacs versions; pgrep kept for backward compat.

## Actual Root Causes (verified)
1. **Socket conflicts**: NOT daemon mode. Script's crash detection: emacsclient timeout → false crash → spawns duplicate daemon without killing old one → socket conflict.
2. **Self-pipe blocking**: NOT daemon mode. Orphaned gptel curl processes block fd 7 after async HTTP calls. Zombie reaper (60s) + sentinel >=0 deferral handle this regardless of mode.
3. **Daemon startup crash**: NOT daemon mode. Hard `(require 'gptel)` crashes during deferred init-ai loading (race: init-ai loads at 0.5s, workflow may reach gptel before that). Soft requires fix this.

## Selected Solution
`--daemon` — standard Emacs daemon mode. Forks properly. The script's own comment warned `--fg-daemon` causes blocking pipe_read. Real defenses: zombie reaper + sentinel >=0 deferral + soft requires.

## Decision Communicated
171/171 TDD pass. Pipeline running on `--daemon` with soft requires in both base.el and gptel-tools-agent.el. Consistent pgrep patterns. mementum memory stored for future sessions.

## Updated Files
- scripts/run-auto-workflow-cron.sh: --fg-daemon → --daemon + pgrep patterns + updated comment
- scripts/watchdog-daemon.sh: --fg-daemon → --daemon + backward-compat kill pattern
- lisp/modules/gptel-tools-agent-base.el: hard → soft requires (condition-case)
- lisp/modules/gptel-tools-agent.el: hard → soft requires (condition-case)
