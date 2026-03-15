# Org Mode Packages Guide

## Overview

This document lists the Org mode packages configured in your `minimal-emacs.d`, categorized by necessity.

## ✅ Core Packages (Installed)

These packages are already configured in `lisp/init-org.el`:

### Essential (Built-in)
| Package | Purpose | Status |
|---------|---------|--------|
| `org` | Core Org mode | ✅ Built-in |

### Highly Recommended (Installed)
| Package | Purpose | Status |
|---------|---------|--------|
| `org-bullets` | Pretty bullet points | ✅ Installed |
| `org-appear` | Reveal markup at cursor | ✅ Installed |
| `org-super-agenda` | Grouped agenda views | ✅ Installed |
| `org-roam` | Networked note-taking | ✅ Installed |
| `org-pomodoro` | Time management | ✅ Installed |
| `org-download` | Image handling | ✅ Installed |
| `org-modern` | Visual enhancements | ✅ Installed |

### Optional Enhancements (Installed)
| Package | Purpose | Status |
|---------|---------|--------|
| `ox-reveal` | Reveal.js presentations | ✅ Installed |
| `ox-gfm` | GitHub Flavored Markdown export | ✅ Installed |
| `ox-pandoc` | Multi-format export (PDF, DOCX, ePub) | ✅ Installed |
| `org-ql` | Powerful query language | ✅ Installed |
| `kirigami` | Unified folding interface | ✅ Installed |
| `org-transclusion` | Embed content from other files | ✅ Installed |

## 📦 Additional Recommended Packages (Optional)

These packages are **not installed** but may be useful depending on your workflow:

### Academic Writing
| Package | Purpose | Install |
|---------|---------|---------|
| `org-ref` | Citations, references, bibliographies | `(package-install 'org-ref)` |
| `org-noter` | PDF annotation with synced notes | `(package-install 'org-noter)` |
| `citar` | Citation management | `(package-install 'citar)` |
| `citar-org-roam` | Citar + Org-roam integration | `(package-install 'citar-org-roam)` |

### Productivity & GTD
| Package | Purpose | Install |
|---------|---------|---------|
| `org-gtd` | Getting Things Done workflow | `(package-install 'org-gtd)` |
| `org-habit` | Habit tracking (built-in) | `(require 'org-habit)` |
| `org-board` | Save web pages as Org | `(package-install 'org-board)` |
| `org-deft` | Quick notes with search | `(package-install 'org-deft)` |

### Navigation & Search
| Package | Purpose | Install |
|---------|---------|---------|
| `helm-org` | Helm integration for Org | `(package-install 'helm-org)` |
| `counsel-org` | Ivy/Counsel integration | `(package-install 'counsel-org)` |
| `org-sidebar` | Sidebar for Org-roam | `(package-install 'org-sidebar)` |

### Presentations
| Package | Purpose | Install |
|---------|---------|---------|
| `org-present` | Simple presentation mode | `(package-install 'org-present)` |
| `org-slides` | Alternative to ox-reveal | `(package-install 'org-slides)` |

### Other Utilities
| Package | Purpose | Install |
|---------|---------|---------|
| `org-journal` | Simple daily journaling | `(package-install 'org-journal)` |
| `org-contacts` | Contact management | `(package-install 'org-contacts)` |
| `org-mac-link` | macOS clipboard integration | `(package-install 'org-mac-link)` |
| `org-kanban` | Kanban board for Org | `(package-install 'org-kanban)` |
| `org-tidy` | Clean up Org files | `(package-install 'org-tidy)` |

## 🎯 Recommended by Workflow

### For Students/Researchers
```elisp
(use-package org-ref :ensure t)
(use-package org-noter :ensure t)
(use-package citar :ensure t)
(use-package citar-org-roam :ensure t)
```

### For Software Developers
```elisp
(use-package org-babel :ensure nil)  ; Built-in code execution
(use-package ob-rust :ensure t)      ; Rust code blocks
(use-package ob-python :ensure nil)  ; Python code blocks (built-in)
(use-package ob-shell :ensure nil)   ; Shell code blocks (built-in)
```

### For Writers
```elisp
(use-package ox-pandoc :ensure t)    ; Export to DOCX, ePub
(use-package org-board :ensure t)    ; Save web pages
(use-package org-transclusion :ensure t)  ; Embed content
```

### For Productivity Enthusiasts
```elisp
(use-package org-gtd :ensure t)      ; GTD workflow
(use-package org-habit :ensure nil)  ; Habit tracking (built-in)
(use-package org-kanban :ensure t)   ; Kanban boards
```

### For Note-Taking (Zettelkasten)
```elisp
(use-package org-roam :ensure t)     ; Already installed
(use-package org-roam-ui :ensure t)  ; Web UI for Org-roam
(use-package org-sidebar :ensure t)  ; Sidebar navigation
```

## ⚠️ Notes

1. **Less is More**: Start with the core packages and add more only when you need them
2. **Built-in Features**: Many features are already in Org mode (habits, clocking, archiving)
3. **Performance**: Too many packages can slow down Emacs startup
4. **Compatibility**: Some packages may conflict with each other

## 📊 Current Configuration Summary

Your `lisp/init-org.el` includes **15 Org packages**:
- 1 built-in (org)
- 7 highly recommended
- 6 optional enhancements
- 1 folding utility (kirigami)

This provides a **comprehensive but minimal** setup suitable for:
- ✅ Task management
- ✅ Note-taking
- ✅ Knowledge management (Zettelkasten)
- ✅ Time tracking
- ✅ Document export
- ✅ Presentations

## 🔧 How to Add More Packages

Add to `lisp/init-org.el`:

```elisp
(use-package package-name
  :ensure t
  :after org
  :config
  ;; Your configuration here
  )
```

Then restart Emacs or evaluate the buffer.

## 📚 Resources

- [Org Mode Manual](https://orgmode.org/manual/)
- [Org Mode Wiki](https://orgmode.org/worg/)
- [System Crafters Org Course](https://www.youtube.com/playlist?list=PL9kx2xYB0TdufTwvwpjJzKXzWqQbW1yq_)
- [Protesilaos Stavrou Org Videos](https://www.youtube.com/@protogitos)
