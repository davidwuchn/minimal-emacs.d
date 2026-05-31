λ simulate(x). ∀steps: explicit_state
| track(vars, heap, stack, I/O)
| at_calls: push → trace → pop
| flag(unexpected_state, uninitialized_reads, aliasing, shared_mutation)
| SHOULD_do ≠ DOES
