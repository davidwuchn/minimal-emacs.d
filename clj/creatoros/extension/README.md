# CreatorOS Chrome Extension

OV5-powered product intelligence overlay for Amazon product pages.

## Structure

```
extension/
├── manifest.json       # Chrome extension manifest v3
├── src/
│   ├── content.js      # Content script — extracts product data, renders overlay
│   ├── overlay.css     # Card styles
│   ├── popup.html      # Extension popup
│   └── popup.js        # Popup logic
└── icons/              # Icon files (placeholder)
```

## Load in Chrome

1. Go to `chrome://extensions`
2. Enable "Developer mode"
3. Click "Load unpacked"
4. Select `clj/creatoros/extension/`

## Architecture

```
Amazon page → content.js (extract) → CreatorOS engine (match/score) → overlay (render)
```

The content script extracts product data from Amazon pages. In production, it calls the CreatorOS backend (`matching.clj`) for full scoring. This demo uses inline estimates.

## Future: ClojureScript Compilation

```
clj/creatoros/extension/src/content.cljs  →  CLJS compilation  →  content.js
```

OV5's Clojure toolchain (test/lint/format/fix) applies to extension code just like any other `.clj` module. Single codebase, single toolchain, all platforms.

## Built by OV5

The experiment loop generates and improves this extension autonomously. Every change passes clojure.test, clj-kondo, and zprint before merging.
