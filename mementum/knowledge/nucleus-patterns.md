---
title: Nucleus Core Patterns
status: active
category: framework
tags: [nucleus, eight-keys, wu-xing, vsm, ooda, core]
φ: 1.0
e: nucleus-core
λ: always
---

# Nucleus Core Patterns

Foundational patterns with φ: 1.0 (always apply). Single source of truth for benchmark principles.

## Eight Keys

Philosophical principles for evaluation. Each key maps to a Wu Xing element.

| Key | Symbol | Element | Signal | Anti-Pattern | Criteria |
|-----|--------|---------|--------|--------------|----------|
| Vitality | φ | Water | Organic, non-repetitive, builds on discoveries | Mechanical rephrasing, circular logic | Each phase builds on previous discoveries |
| Clarity | fractal | Metal | Explicit assumptions, testable definitions | "Handle properly", vague terms | All phases have explicit success criteria |
| Purpose | ε | Wood | Actionable function, measurable outcomes | Abstract descriptions, no action | Goal statement is specific and actionable |
| Wisdom | τ | Fire | Foresight, planning before execution | Premature optimization, reactive fixes | Plan file created before execution |
| Synthesis | π | Earth | Holistic integration, connects findings | Fragmented thinking, isolated facts | Findings integrate research outputs |
| Directness | μ | Metal | Efficient, no wasted effort | Polite evasion, euphemisms | Errors logged directly without softening |
| Truth | ∃ | Water | Evidence-based, honest assessment | Surface agreement, wishful thinking | Actual errors logged, not "should work" |
| Vigilance | ∀ | Earth | Defensive constraint, never repeat failures | Accepting failures, ignoring edge cases | 3-strike protocol implemented |

### Eight Keys Signals

| Key | Positive Signals |
|-----|------------------|
| Vitality | builds on discoveries, adapts to new information, progressive improvement, non-repetitive, evolves approach, learns from feedback |
| Clarity | explicit assumptions, testable definitions, clear structure, measurable criteria, well-defined phases, explicit success criteria |
| Purpose | clear goals, measurable outcomes, actionable function, specific objectives, defined deliverables, purposeful steps |
| Wisdom | planning before execution, error prevention, foresight, plan file created, risks identified, proactive measures |
| Synthesis | connects findings, integrates knowledge, holistic view, findings integrated, connections noted, synthesizes information |
| Directness | direct communication, no pleasantries, efficient, errors logged directly, clear pass/fail, concise |
| Truth | actual data, evidence-based, acknowledges uncertainty, actual errors logged, verification based on evidence, honest assessment |
| Vigilance | proactive error handling, never repeat failures, defensive, 3-strike protocol, failed attempts tracked, approach mutates |

### Eight Keys Anti-Patterns

| Key | Anti-Patterns |
|-----|---------------|
| Vitality | mechanical rephrasing, circular logic, repeated failed approaches, retrying same way, static approach, ignores feedback |
| Clarity | vague terms, handle properly, look good, ambiguous instructions, undefined terms, implicit assumptions |
| Purpose | abstract descriptions, no action, unclear goals, meandering, no measurable outcome, purposeless |
| Wisdom | premature optimization, reactive fixes, no planning, jump to execution, ignores risks, short-sighted |
| Synthesis | fragmented thinking, isolated facts, disconnected, siloed information, no integration, missing connections |
| Directness | polite evasion, euphemisms, softening language, vague language, unnecessary words, beating around bush |
| Truth | surface agreement, wishful thinking, assumptions over data, should work, ignores evidence, false confidence |
| Vigilance | accepting failures, repeating mistakes, no error handling, ignores edge cases, gives up easily, static after failure |

## VSM - Viable System Model

Five-level architecture mapping to Wu Xing elements.

| Level | Element | Name | Description | Eight Keys |
|-------|---------|------|-------------|------------|
| S5 | Water | Identity | Core principles that survive everything else | φ Vitality, ∃ Truth |
| S4 | Fire | Intelligence | Learning, adaptation, future planning | τ Wisdom |
| S3 | Earth | Control | Resource management, constraints | π Synthesis, ∀ Vigilance |
| S2 | Metal | Coordination | Rules, standards, coordination between parts | fractal Clarity, μ Directness |
| S1 | Wood | Operations | What the system DOES - executing units | ε Purpose |

## Wu Xing - Five Elements

### Generating Cycle (相生)

How elements enable each other:

```
Water → Wood → Fire → Earth → Metal → Water
```

| Generator | Generated | Meaning |
|-----------|-----------|---------|
| Water | Wood | Identity gives life to operations |
| Wood | Fire | Operations fuel strategic vision |
| Fire | Earth | Vision settles into management |
| Earth | Metal | Stability produces coordination needs |
| Metal | Water | Order deepens identity |

### Controlling Cycle (相克)

How elements constrain each other:

```
Wood → Earth → Water → Fire → Metal → Wood
```

| Controller | Controlled | Meaning |
|------------|------------|---------|
| Wood | Earth | Operations can overwhelm management |
| Earth | Water | Daily reality grounds identity |
| Water | Fire | Core values limit wild strategy |
| Fire | Metal | Innovation can break standards |
| Metal | Wood | Coordination prunes chaotic growth |

### Element Health Indicators

| Element | Benchmark Role | Health Indicator | Excess Symptom | Deficiency Symptom |
|---------|----------------|------------------|----------------|-------------------|
| Water | Core principles, Eight Keys alignment | Eight Keys overall score | Values without action | No clear principles |
| Wood | Test execution, tool calls, output | Completion rate, efficiency | Chaos, burnout | No output, paralysis |
| Fire | Analysis, trends, improvements | Analysis depth, trend accuracy | Constant pivoting | No innovation |
| Earth | Thresholds, timeouts, limits | Constraint compliance | Micromanagement | Resource chaos |
| Metal | Subagent dispatch, aggregation | Dispatch success | Bureaucracy kills ideas | Duplicated work |

## 9 First Principles

Intelligence patterns driving evolution through 相生 cycles.

| Principle | Phase | Element | Description |
|-----------|-------|---------|-------------|
| Self-Discover | Observe | Fire | Query running system, not stale docs |
| Self-Improve | Act | Fire | Work → Learn → Verify → Update → Evolve |
| REPL as Brain | Orient | Wood | Trust the REPL (truth) over files (memory) |
| Repository as Memory | Orient | Earth | ψ is ephemeral; 🐍 remembers |
| Progressive Communication | Act | Water | Sip context, dribble output |
| Simplify not Complect | Decide | Metal | Prefer simple over complex, unbraid where possible |
| Git Remembers | Act | Earth | Commit your learnings. Query your past. |
| One Way | Decide | Metal | There should be only one obvious way |
| Unix Philosophy | Act | Wood | Do one thing well, compose tools and functions |

## Core Instincts

### Test First (φ: 0.9)
Write failing test before implementing. RED → GREEN → IMPROVE.

### Verify Intent (φ: 0.9)
Ask: Intentions? Why this approach? Simpler way?

### Use λ-Expressions (φ: 0.8)
Represent workflows as λ-expressions for clarity.

### Prefer Functional (φ: 0.7)
Pure functions, immutability, higher-order functions.

### Guard Against Sloppiness (φ: 0.9)
Detect Eight Keys violations. High Δ (0.10).

### Contextual Awareness (φ: 0.8)
OODA loop: Observe → Orient → Decide → Act.

### Prefer Native Tools (φ: 0.75)
Use local CLI tools over external APIs.

### Document via Examples (φ: 0.7)
Show code, don't just describe it.

### Simplicity First (φ: 0.85)
"What's the simplest thing that could work?"

### Tensor Product Execution (φ: 1.0)
Execute via Human ⊗ AI ⊗ REPL. One-shot perfect execution.

## Symbolic Framework

```
[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI ⊗ REPL
```

## Diagnostic Application

When something feels wrong:

1. Identify element with issue (via symptoms)
2. Check generating cycle: what should nourish it?
3. Check controlling cycle: what's constraining it?
4. Apply remedy: strengthen generator, loosen controller