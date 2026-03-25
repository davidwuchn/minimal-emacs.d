# Parallel Auto-Workflow: macOS + Pi5

## Overview

Two machines run auto-workflow simultaneously:
- **macOS** (imacpro.taila8bdd.ts.net) - Main development
- **Pi5** (pi5) - Headless overnight workhorse

## How It Works

```
┌─────────────────┐     ┌─────────────────┐
│     macOS       │     │      Pi5        │
│  (imacpro)      │     │   (pi5)         │
├─────────────────┤     ├─────────────────┤
│ 1:00, 5:00 AM   │     │ 3:00, 11:00 PM  │
│                 │     │                 │
│ optimize/*-     │     │ optimize/*-     │
│   imacpro-*     │     │   pi5-*         │
└────────┬────────┘     └────────┬────────┘
         │                       │
         └───────────┬───────────┘
                     ▼
              ┌─────────────┐
              │   staging   │
              │   (merges)  │
              └──────┬──────┘
                     ▼
              ┌─────────────┐
              │    main     │
              │  (human)    │
              └─────────────┘
```

## Schedule (Staggered to Avoid Git Conflicts)

| Time | Machine | Reason |
|------|---------|--------|
| 11:00 PM | Pi5 | Before sleep |
| 1:00 AM | macOS | Deep night |
| 3:00 AM | Pi5 | Deep night |
| 5:00 AM | macOS | Early morning |

**8 runs per day total** (4 each machine)

## Pi5 Setup

### 1. Clone Repository

```bash
# On Pi5
git clone git@onepi5:davidwuchn/minimal-emacs.d.git ~/.emacs.d
cd ~/.emacs.d
```

### 2. Install Emacs

```bash
# Debian
sudo apt install emacs
```

### 3. Setup Cron

```bash
# Copy cron config
crontab cron.d/auto-workflow-pi5
```

### 4. Start Daemon

```bash
emacs --daemon
```

## Configuration

### macOS: `cron.d/auto-workflow`
```
# 1:00, 5:00 AM
0 1,5 * * * emacsclient -a '' -e '...'
```

### Pi5: `cron.d/auto-workflow-pi5`
```
# 11:00 PM, 3:00 AM
0 23,3 * * * emacsclient -a '' -e '...'
```

## Branch Naming

Branches include hostname, no collisions:

```
macOS: optimize/retry-imacpro.taila8bdd.ts.net-exp1
Pi5:   optimize/retry-pi5-exp1
```

## Merging

Both push to `staging`:
```bash
git push origin staging --force-with-lease
```

If conflict, last writer wins. Human reviews before merging to `main`.

## Monitoring

```bash
# macOS
./scripts/run-auto-workflow.sh status

# Pi5 (remote)
ssh pi5 'cd ~/.emacs.d && ./scripts/run-auto-workflow.sh status'
```

## Benefits

- **2x throughput**: 8 runs/day instead of 4
- **24/7 coverage**: Runs around the clock
- **No conflicts**: Hostname in branch names
- **Efficient**: Pi5 handles overnight work