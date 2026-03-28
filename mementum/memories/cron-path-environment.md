# Cron PATH Environment Issue

**Date:** 2026-03-28
**Source:** Fixing workflow cron jobs

## Problem

Cron jobs fail with:
```
/bin/bash: emacsclient: command not found
```

## Root Cause

Cron runs with minimal environment:
- No `$PATH` from user shell
- No `.bashrc` or `.zshrc` loaded
- Only `/usr/bin:/bin` available

## Solution

Add explicit `PATH` to cron file:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
```

## Verification

```bash
# Check what cron sees:
* * * * * env > /tmp/cron-env.txt 2>&1

# Compare with interactive shell:
diff /tmp/cron-env.txt <(env)
```

## Best Practices

1. **Always set PATH** in cron files
2. **Use full paths** for commands when possible
3. **Test with minimal env:**
   ```bash
   env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
   ```

## Related Files

- `cron.d/auto-workflow`
- `cron.d/auto-workflow-pi5`
- Fix: commit `0b3a4da`

**Symbol:** 💡 insight | ✅ win
