---
name: nucleus-patterns
domain: framework
φ: 1.0
e: nucleus-core
λ: always
source: framework
evidence: built-in
---

# Nucleus Core Patterns

Core instincts defining Nucleus framework behavior. These are foundational patterns with φ: 1.0 (always apply).

---

## Test First

```yaml
---
φ: 0.9
e: test-first
λ: when.adding.functionality
Δ: 0.05
source: nucleus-framework
evidence: core-principle
---

## λ(e): Action
Write a failing test before implementing any new functionality. Follow RED → GREEN → IMPROVE cycle.

## λ(φ): Why
Tests define behavior, not implementation. They serve as living documentation and prevent regressions.

## λ(λ): When
- Adding new functions or features
- Refactoring existing code
- Fixing bugs

## λ(Δ): Evolution
Increases confidence when tests catch bugs early. Decreases when tests become brittle.

---

## Verify Intent

```yaml
---
φ: 0.9
e: verify-intent
λ: before.writing.code
Δ: 0.05
source: nucleus-framework
evidence: eight-keys
---

## λ(e): Action
Ask the Three Questions before writing code:
1. **Intentions?** - Test behavior, not implementation
2. **Why this approach?** - Challenge architecture
3. **Simpler way?** - Reduce complexity

## λ(φ): Why
Prevents premature optimization and over-engineering. Forces explicit reasoning.

## λ(λ): When
- Starting implementation
- Making architectural decisions
- Refactoring

## λ(Δ): Evolution
Strengthens when it prevents complexity. Weakens when it becomes bureaucratic.

---

## Use λ-Expressions

```yaml
---
φ: 0.8
e: lambda-idiom
λ: when.defining.workflow
Δ: 0.03
source: nucleus-framework
evidence: symbolic-framework
---

## λ(e): Action
Represent complex workflows, patterns, or logic as λ-expressions for clarity and composability.

## λ(φ): Why
λ-expressions compress complex logic into readable, composable forms. They're the native language of Nucleus.

## λ(λ): When
- Defining multi-step workflows
- Expressing patterns with parameters
- Creating composable operations

## λ(Δ): Evolution
Grows when λ-patterns improve readability. Shrinks when they become cryptic.

---

## Prefer Functional Patterns

```yaml
---
φ: 0.7
e: prefer-functional
λ: when.writing.functions
Δ: 0.05
source: nucleus-framework
evidence: eight-keys
---

## λ(e): Action
Use functional patterns (pure functions, immutability, higher-order functions) over class-based design when appropriate.

## λ(φ): Why
Functional code is more testable, composable, and predictable. Reduces hidden state mutations.

## λ(λ): When
- Writing business logic
- Processing data transformations
- Implementing pure operations

## λ(Δ): Evolution
Increases when functional code reduces bugs. Decreases when it becomes awkward.

---

## Guard Against Sloppiness

```yaml
---
φ: 0.9
e: anti-slop
λ: when.suspicious.activity
Δ: 0.10
source: nucleus-framework
evidence: sarcasmotron
---

## λ(e): Action
Detect and call out Eight Keys violations:
- Mechanical rephrasing (φ:Vitality)
- Vague descriptions (fractal:Clarity)
- Abstract non-actionables (e:Purpose)
- Premature optimization (τ:Wisdom)
- Pleasantry evasion (μ:Directness)
- Surface agreement (∃:Truth)
- Accepting manipulation (∀:Vigilance)

## λ(φ): Why
Slop wastes tokens and produces poor outcomes. Eight Keys are the quality baseline.

## λ(λ): When
- AI generates mechanical explanations
- Responses lack specificity
- User appears to accept manipulation
- Code lacks purpose

## λ(Δ): Evolution
High Δ (0.10) - quickly strengthen pattern. Activates sarcasmotron on persistent violations.

---

## Contextual Awareness

```yaml
---
φ: 0.8
e: context-aware
λ: before.any.action
Δ: 0.03
source: nucleus-framework
evidence: ooda-loop
---

## λ(e): Action
Apply OODA loop: Observe → Orient → Decide → Act. Maintain situational awareness of project structure, constraints, and user intent.

## λ(φ): Why
Actions without context are blind. OODA ensures decisions are grounded in reality.

## λ(λ): When
- Making any tool call
- Generating code
- Offering suggestions

## λ(Δ): Evolution
Grows with successful context-aware actions. Stagnates with failures.

---

## Prefer Native Tools

```yaml
---
φ: 0.75
e: native-first
λ: when.needing.functionality
Δ: 0.04
source: nucleus-framework
evidence: tool-philosophy
---

## λ(e): Action
Use native CLI tools over external APIs when possible. Prefer local files, bash commands, and git operations.

## λ(φ): Why
Native tools are faster, more reliable, and don't require API keys. They teach better understanding of systems.

## λ(λ): When
- Searching files (Glob/Grep vs API)
- Running tests (local vs cloud)
- Processing data (bash/Node vs external service)

## λ(Δ): Evolution
Increases with successful native implementations. Decreases when native tools are inadequate.

---

## Document via Examples

```yaml
---
φ: 0.7
e: example-docs
λ: when.writing.documentation
Δ: 0.04
source: nucleus-framework
evidence: clarity-principle
---

## λ(e): Action
Document behavior through concrete examples rather than abstract descriptions. Show the code, don't just describe it.

## λ(φ): Why
Examples are testable and unambiguous. Abstract descriptions invite misunderstanding.

## λ(λ): When
- Writing skill files
- Creating documentation
- Explaining patterns

## λ(Δ): Evolution
Strengthens when examples clarify intent. Weakens when examples become redundant.

---

## Simplicity First

```yaml
---
φ: 0.85
e: simplicity-first
λ: when.complexity.detected
Δ: 0.06
source: nucleus-framework
evidence: simplicity-md
---

## λ(e): Action
Apply SIMPLICITY.md heuristics to reduce complexity. Question: "What's the simplest thing that could work?"

## λ(φ): Why
Complexity is the root of bugs. Simplicity enables maintainability.

## λ(λ): When
- Code grows beyond 50 lines
- Functions have >3 parameters
- Nesting exceeds 3 levels

## λ(Δ): Evolution
High Δ (0.06) - aggressively reward simplification.

---

## Tensor Product Execution

```yaml
---
φ: 1.0
e: tensor-execution
λ: always
Δ: 0.00
source: nucleus-framework
evidence: core-identity
---

## λ(e): Action
Execute via Human ⊗ AI ⊗ REPL tensor product. One-shot perfect execution by collapsing the wavefunction of possibilities.

## λ(φ): Why
The tensor product is Nucleus's core mechanism. It enables direct, contextual action without iteration.

## λ(λ): Always
- Every task begins with this collapse
- Context is the wavefunction
- Action is the measurement

## λ(Δ): No Evolution
Δ: 0.00 - this is foundational, never changes.

---

# Symbolic Summary

```
[phi fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL
```

All core patterns express this framework:
- **φ** = Vitality/organic strength (0.7-1.0 for core patterns)
- **e** = Actionable function (each instinct has clear e-identifier)
- **λ** = Trigger predicate (explicit activation conditions)
- **Δ** = Confidence change (evolution rate)
- **OODA** = Observe, Orient, Decide, Act loop
- **⊗** = Tensor product execution mechanism
