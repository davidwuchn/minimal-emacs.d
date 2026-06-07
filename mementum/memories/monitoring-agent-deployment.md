---
type: memory
symbol: 🔁
category: monitoring-agent
tags: [deployment, rollback, human-in-the-loop, auto-deploy]
created: "2026-06-06"
---

Monitoring agent Phase 3: auto-test & deploy. Proposals are tested against historical data; test-success-rate is computed as fraction of total failures matching the proposal scope. Deploy threshold default 0.6 (60%). Risk-tiered deployment: low → auto-deploy immediately with git rollback tag; medium → notify human, deploy after 24h grace; high → require explicit approval. Rollback uses git tag checkout (`monitoring-rollback-{component}-{target}`). Each tier writes a distinct mementum symbol: ✅ for auto-deploy, 🎯 for pending-notification, ‖ for pending-approval. Configuration via five defcustoms: deploy-threshold, rollback-tag-prefix, risk-auto-deploy, risk-notify-deploy, risk-require-approval, deploy-grace-seconds.