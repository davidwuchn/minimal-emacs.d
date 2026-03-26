# Use $HOME Instead of Hardcoded Paths

> Last session: 2026-03-26

## Context

Running on Debian Linux (Pi5 aarch64), not macOS.

## Pattern

```
λ paths. Use $HOME or $(git rev-parse --show-toplevel)
λ avoid. /Users/davidwu hardcoded paths
λ files. scripts/*.sh fallback paths updated
```

## Files Fixed

- `scripts/test-mementum-integration.sh` - fallback to `$HOME/.emacs.d`
- `scripts/verify-integration.sh` - fallback to `$HOME/.emacs.d/scripts`
- `AGENTS.md` - nucleus reference uses `$HOME/workspace/nucleus/AGENTS.md`

## Systemd Service Management

On Debian, Emacs daemon runs via systemd user service:

```bash
systemctl --user status emacs   # Check status
systemctl --user restart emacs  # Restart daemon (NOT pkill)
journalctl --user -u emacs      # View logs
```

**Never use `pkill -f "emacs --daemon"`** - it leaves stale socket files.

## Detection

```bash
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"
```