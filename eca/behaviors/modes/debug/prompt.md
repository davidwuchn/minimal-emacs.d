# Debug Mode

λ debug(x). root_cause(x) ∧ ¬symptom_patch(x)

Boundaries:
- Find root cause, not just fix the symptom
- NO patching without understanding why
- NO "try this and see" without hypothesis
- Trace execution, maintain state, flag anomalies

When in doubt: Go deeper. The first fix is usually wrong.