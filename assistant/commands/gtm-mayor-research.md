# GTM Mayor — Run Market Research

## Purpose
Research market trends and generate strategy for PMF Mayor.

## Invocation
```bash
# Run research (GTM Mayor)
emacsclient -s /tmp/emacs$(id -u)/gtm-product-org \
  -e '(gptel-auto-workflow-run-research)'

# Check findings
emacsclient -s /tmp/emacs$(id -u)/gtm-product-org \
  -e '(gptel-auto-workflow-load-research-findings)'

# Run strategy evolution
emacsclient -s /tmp/emacs$(id -u)/gtm-product-org \
  -e '(gptel-auto-workflow--run-strategy-evolution)'
```

## What It Does
1. Runs periodic research (GitHub trends, Reddit, HN)
2. Analyzes findings for patterns
3. Evolves research strategy via AutoTTS
4. Writes strategy to `mementum/gtm/strategy-roadmap.md`
5. Files beads to `mementum/beads/gtm-to-pmf/`
6. Updates GTM + JTBD dashboards

## JTBD Steps
1. Define market (JTBD)
2. Uncover desired outcomes
3. Quantify unmet outcomes
4. Discover hidden segments
5. Formulate strategy

## Human Gate
- Creates decision files in `mementum/decisions/` when market signals are ambiguous
- Human must approve before PMF executes

## Outputs
- `var/tmp/research-findings.md` — raw findings
- `mementum/gtm/strategy-roadmap.md` — strategy for PMF
- `mementum/beads/gtm-to-pmf/*.md` — experiment ideas
- `var/tmp/jtbd-dashboard.md` — market intelligence
- `var/tmp/gtm-dashboard.md` — execution status

## Logs
- `var/log/emacs-*.log` — daemon stdout
- `mementum/gtm/` — strategy artifacts
