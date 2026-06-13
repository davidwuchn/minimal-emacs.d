## Insight

OV5 should not promote semantic fixes on loadability alone.

The right handoff is:
1. structural checks (`check-parens` + `load-file`)
2. targeted ERT selector for the touched file
3. copy back to the live tree only if the gate passes

This keeps self-heal fast for known files while still stopping bad fixes before they reach `main`.
