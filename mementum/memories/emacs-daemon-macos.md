---
title: Emacs daemon setup on macOS
date: 2026-03-30
---

# Emacs Daemon Management on macOS

## Key Learnings

### Launch Agent vs Manual Management
- **Use `launchctl` for production/auto-start**: Native macOS process management, auto-starts on login, handles crashes with KeepAlive
- **Use manual commands for development**: Better error feedback during config testing and troubleshooting
- **Hybrid approach recommended**: launchctl for auto-start, manual for debugging

### Theme Loading Issue
- **Problem**: Daemon runs headless, doesn't load GUI themes automatically
- **Solution**: Use `after-make-frame-functions` hook to load theme when GUI frames are created
- **Configuration**: Remove conflicting `(server-start)` from init files when using daemon mode

### Process Conflicts
- **GUI Emacs vs Daemon**: Running both creates separate servers; emacsclient connects to whichever starts first
- **Resolution**: Choose one approach - either GUI Emacs with server, or headless daemon with emacsclient frames
- **Best practice**: Use daemon + emacsclient -c for fastest startup and consistent theming

### Verification Commands
```bash
# Check daemon status
pgrep -f "Emacs.*--daemon"

# Test client connection  
emacsclient -e "(+ 1 1)"

# View daemon logs
tail /tmp/emacs-daemon.log

# Manage via launchctl
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
```

### Oh-My-Zsh Integration
- Emacs aliases (`emacs`, `eframe`, `te`) work correctly with daemon
- They connect to existing daemon rather than starting new instances
- No configuration changes needed for oh-my-zsh emacs plugin