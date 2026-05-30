## Task-Type Diversity Gap Pattern

The auto-workflow system tracks task-type diversity per target via `gptel-auto-experiment--format-task-type-diversity` and `gptel-auto-experiment--get-task-type-stats`. These classify experiments by hypothesis keywords into: refactoring, bug-fix, performance, feature, validation.

**Key finding:** When experiments use hypotheses that don't match any keyword pattern (e.g., 'default'), they are invisible to diversity tracking. This can make diversity appear zero when experiments ARE happening but are unclassified.

**Implications:**
- The controller should bias experiment selection toward underexplored types when counts show zeros
- Early-stage targets naturally have zero diversity — that's expected, not a failure
- The 5 task types cover most code changes. If a target truly has no experiments across them, the researcher should propose specific candidates per type
- 'default' experiments should either be rare or indicate a missing task-type category

**Remediation:** When the researcher reports diversity=0, the controller should explicitly generate experiment proposals in at least 2 underexplored categories for the next cycle.
