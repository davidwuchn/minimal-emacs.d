# Parallel Auto-Workflow: macOS + Pi5

## Overview

Two machines run auto-workflow simultaneously:
- **macOS** (imacpro.taila8bdd.ts.net) - Main development
- **Pi5** (pi5) - Headless overnight workhorse

## How It Works

```
┌─────────────────┐     ┌─────────────────┐
│     macOS       │     │      Pi5        │
│  (daylight)     │     │   (24/7)        │
├─────────────────┤     ├─────────────────┤
│ 10AM, 2PM, 6PM  │     │ 11PM,3AM,7AM   │
│                 │     │ 11AM,3PM,7PM    │
│ 3 runs/day      │     │ 6 runs/day      │
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

## Schedule (Pi5 Heavy, macOS Daylight)

| Time | Machine | Reason |
|------|---------|--------|
| 11:00 PM | Pi5 | Night |
| 3:00 AM | Pi5 | Deep night |
| 7:00 AM | Pi5 | Early morning |
| 10:00 AM | macOS | Daylight |
| 11:00 AM | Pi5 | Mid-day |
| 2:00 PM | macOS | Daylight |
| 3:00 PM | Pi5 | Afternoon |
| 6:00 PM | macOS | Evening |
| 7:00 PM | Pi5 | Night |

**Pi5: 6 runs/day | macOS: 3 runs/day | Total: 9 runs/day**

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
# Daylight hours only: 10:00 AM, 2:00 PM, 6:00 PM
0 10,14,18 * * * emacsclient -a '' -e '...'
```

### Pi5: `cron.d/auto-workflow-pi5`
```
# 24/7 heavy usage: 11PM, 3AM, 7AM, 11AM, 3PM, 7PM
0 23,3,7,11,15,19 * * * emacsclient -a '' -e '...'
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

- **9 runs/day**: 6 (Pi5) + 3 (macOS)
- **Pi5 24/7**: Headless workhorse, always running
- **macOS daylight**: Only when you're actively using it
- **No conflicts**: Hostname in branch names
- **Efficient**: Maximize both subscriptions