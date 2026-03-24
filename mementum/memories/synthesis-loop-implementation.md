💡 synthesis-loop-implementation

## Problem
`gptel-mementum-weekly-job` detected synthesis candidates (≥3 memories) but only logged count. No actual synthesis happened.

## Solution
Wired `gptel-mementum-check-synthesis-candidates` → `gptel-mementum-synthesize-candidate` with human approval gate.

## Key Functions
- `gptel-mementum-synthesize-candidate`: Preview buffer + y-or-n-p → create knowledge
- `gptel-mementum-synthesis-run`: M-x interactive command

## λ termination
```
synthesis ≡ AI | approval ≡ human | human ≡ termination_condition
```

Human gate prevents noise accumulation in knowledge/.