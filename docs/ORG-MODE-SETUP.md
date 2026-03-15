# Org Mode Setup Guide

## Overview

Your Org mode configuration has been set up with comprehensive features for:
- Task management (TODO, scheduling, deadlines)
- Note-taking (capture templates, org-roam)
- Time management (pomodoro)
- Knowledge management (networked notes)

## Directory Structure

```
~/org/
├── agenda.org          # Tasks and scheduled items
├── notes.org           # General notes and meetings
├── projects.org        # Project tracking
├── journal.org         # Daily journal entries
├── roam/               # Org-roam networked notes
│   └── daily/          # Daily notes
├── images/             # Images attached to notes
└── README.org          # Quick reference guide
```

## Key Bindings

### Global Org Commands

| Key     | Command              | Description                    |
|---------|---------------------|--------------------------------|
| `C-c a` | `org-agenda`        | Open agenda view               |
| `C-c c` | `org-capture`       | Quick capture (task/note/etc)  |
| `C-c l` | `org-store-link`    | Store link to current location |
| `C-c o` | `org-open-at-point` | Open link at cursor            |

### Org Roam (Networked Notes)

| Key     | Command                          | Description              |
|---------|----------------------------------|--------------------------|
| `C-c n l` | `org-roam-buffer-toggle`       | Toggle roam buffer       |
| `C-c n f` | `org-roam-node-find`           | Find or create node      |
| `C-c n g` | `org-roam-graph`               | View knowledge graph     |
| `C-c n i` | `org-roam-node-insert`         | Insert link to node      |
| `C-c n c` | `org-roam-capture`             | Capture new node         |
| `C-c n j` | `org-roam-dailies-capture-today` | Today's daily note     |

### Org Mode Commands

| Key       | Command              | Description                    |
|-----------|---------------------|--------------------------------|
| `TAB`     | `org-cycle`         | Fold/unfold subtree            |
| `S-TAB`   | `org-global-cycle`  | Cycle entire buffer            |
| `C-c C-t` | `org-todo`          | Cycle todo state               |
| `C-c C-s` | `org-schedule`      | Set schedule date              |
| `C-c C-d` | `org-deadline`      | Set deadline                   |
| `C-c .`   | `org-time-stamp`    | Insert timestamp               |
| `C-c C-w` | `org-refile`        | Refile to another location     |
| `C-c P`   | `org-pomodoro`      | Start pomodoro timer           |
| `C-c ,`   | `org-priority`      | Set priority (A/B/C)           |
| `C-c C-q` | `org-set-tags`      | Set tags                       |

## Capture Templates

Press `C-c c` then choose:

| Key | Type     | Location              | Description              |
|-----|----------|-----------------------|--------------------------|
| `t` | Todo     | agenda.org/Tasks      | New task                 |
| `n` | Note     | notes.org/Notes       | General note             |
| `j` | Journal  | journal.org           | Daily journal entry      |
| `m` | Meeting  | notes.org/Meetings    | Meeting notes            |
| `p` | Project  | projects.org/Projects | New project              |

## Todo Workflow

Your TODO keywords are configured as:

```
TODO → INPROGRESS → WAITING → DONE | CANCELLED
PROJECT → COMPLETED
MEETING → HELD
```

Colors:
- 🔴 TODO (red)
- 🟢 INPROGRESS (teal)
- 🟡 WAITING (yellow)
- ✅ DONE (green, strikethrough)
- ❌ CANCELLED (gray, strikethrough)

## Agenda Views

The agenda (`C-c a`) shows tasks grouped by:

1. 🔴 Today - Scheduled for today
2. 🟡 Overdue - Past deadline/schedule
3. 🟢 Next - NEXT tasks
4. 🔵 In Progress - Currently working on
5. 🟣 High Priority - Priority A
6. 🟠 Medium Priority - Priority B
7. ⚪ Low Priority - Priority C
8. 📋 Projects - Project items
9. ⏳ Waiting - Waiting on others
10. 📝 Tasks - All TODO items

## Getting Started

### 1. Capture Your First Task

```
C-c c t  →  Type task description  →  C-c C-c to save
```

### 2. View Your Agenda

```
C-c a  →  Press 'd' for daily agenda
```

### 3. Create a Note

```
C-c c n  →  Type note  →  C-c C-c to save
```

### 4. Start Using Org-Roam

```
C-c n j  →  Create today's daily note
C-c n f  →  Find or create a new note
```

### 5. Start a Pomodoro Session

```
C-c P  →  Start 25-minute focus timer
```

## Tips

1. **Quick Capture**: Use `C-c c` to quickly capture thoughts without leaving your current context
2. **Daily Review**: Start each day with `C-c a` to review your agenda
3. **Link Notes**: Use `C-c n i` to link related notes together
4. **Refile Tasks**: Use `C-c C-w` to move tasks between files
5. **Search**: Use `C-c a s` to search across all agenda files
6. **Priorities**: Use `C-c ,` to set A (high), B (medium), or C (low) priority
7. **Tags**: Use `C-c C-q` to add tags for better organization

## Sample Workflow

### Morning Routine
1. `C-c a` - Review today's agenda
2. `C-c n j` - Create daily journal entry
3. Pick a task and start pomodoro: `C-c P`

### During the Day
1. Capture new tasks: `C-c c t`
2. Take notes in meetings: `C-c c m`
3. Link related ideas: `C-c n i`

### Evening Review
1. Mark completed tasks: Navigate to task, `C-c C-t` to DONE
2. Review journal entry
3. Plan tomorrow's tasks

## Configuration File

All Org mode settings are in `lisp/init-org.el`. You can customize:
- Todo keywords and colors
- Capture templates
- Agenda file locations
- Export settings

## Next Steps

1. Explore `~/org/README.org` for a quick reference
2. Try the capture templates (`C-c c`)
3. Set up Org-roam backlinks for networked thought
4. Customize capture templates in `lisp/init-org.el`
5. Explore org-super-agenda views with `C-c a`

## Troubleshooting

**Org-roam not syncing?**
```
M-x org-roam-db-sync
```

**Agenda not showing files?**
Check `org-agenda-files` variable in `lisp/init-org.el`

**Images not displaying?**
Ensure `org-download-image-dir` exists: `~/org/images/`
