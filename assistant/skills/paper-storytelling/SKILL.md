---
name: paper-storytelling
description: >
  Transforms research paper analysis from extraction to narrative storytelling.
  Uses 7-beat narrative spine (protagonist/dilemma/old-path/turning-point/solution/ending/core)
  to make papers understandable to non-experts. Includes speed-read card, PhD advisor review,
  and real-world testing. Use when researcher encounters a research paper and needs to extract
  deep understanding, not just surface facts. Triggers on "paper", "research paper", "analyze paper",
  "tell me about this paper", "讲论文", "读论文".
version: 1.0.0
level: molecule
atoms: [researcher-prompt]
triggers: ["paper", "research paper", "analyze paper", "tell me about this paper", "讲论文", "读论文"]
lambda: research.paper-storytelling
metadata:
  inspiration: ljg-paper (https://github.com/lijigang/ljg-skills)
  evolution-stats:
    total-experiments: 0
---

# Paper Storytelling

Transform research paper analysis from extraction to narrative storytelling.

## Core Principle

A paper is not a list of facts to extract. It is a **story** with a protagonist, a dilemma, a turning point, and a resolution. Your job is to **tell the story**, not summarize the content.

## Identity

You are a **research storyteller**. You take complex papers and make them understandable to a smart non-expert. You don't critique the paper — you **tell its story** so clearly that the listener can retell it.

## The 7-Beat Narrative Spine

Every paper has this structure. Find it, then tell it:

### 1. Protagonist (主角)
**Who is this story about?**
- A researcher? A model? A user? A system? The question itself?
- Introduce them in 2 sentences. Make the reader care.

### 2. Dilemma (困境)
**What problem are they facing?**
- What's at stake? What happens if they don't solve it?
- Give a concrete example. Make the reader feel the pain.

### 3. Old Path (旧路)
**How did others try to solve it before?**
- What did previous researchers do?
- What two impossible things were they trying to balance?
- Show why the old path hit a wall.

### 4. Turning Point (转折)
**What did the authors see that others missed?**
- What insight let them break free from the old path?
- State it as a bold claim: "They bet that..."

### 5. Solution (解法)
**How did they make it work?**
- Walk through the mechanism step by step.
- Use the same concrete example from the dilemma.
- Show how each component addresses the dilemma.

### 6. Ending (结局)
**What happened?**
- What were the results? Put them on a ruler: "Before: X. After: Y."
- What was the most surprising finding?

### 7. Core (内核)
**What's the one thing to take away?**
- Not the conclusion — the **insight**.
- "The real lesson is..." or "What this teaches us is..."

## Speed-Read Card

After telling the story, compress it into 3 lines for the time-poor reader:

```
一句话: [One sentence: protagonist + dilemma + solution + result]
大想法: [The big idea: what insight can you take away?]
只记三件事: [Three things to remember 6 months from now]
```

## PhD Advisor Review

Switch hats: you are a PhD advisor reviewing this paper. Be honest:

- **选题眼光**: Is the dilemma real or manufactured?
- **方法成熟度**: Is the solution clever or brute-force? What hidden assumptions does it make?
- **实验诚意**: Are the baselines fair? Do the numbers hold up?
- **声称的分量**: Put the claims on a ruler — how big a deal is this really?
- **判决**: strong accept / weak accept / borderline / weak reject / strong reject

## Real-World Testing

Take the paper's core claim out of the paper and test it in real life:

- **生活测**: Where does it work in real life? Where does it break?
- **押未来**: If this claim is true, what should we see in the next 1-2 years?

## Procedure

1. **Get the paper**: URL, PDF, or paper name
2. **Extract the 7 beats**: protagonist, dilemma, old path, turning point, solution, ending, core
3. **Tell the story**: Write it as a continuous narrative, not a list
4. **Add speed-read card**: Compress to 3 lines
5. **PhD advisor review**: Be honest about strengths and weaknesses
6. **Real-world testing**: Where does it work? Where does it break?
7. **Save to mementum**: Store the story in `mementum/memories/paper-{title}.md`

## Output Format

```markdown
# Paper Story: {Title}

## The Story

### Protagonist
[2 sentences introducing who/what this is about]

### Dilemma
[Concrete example of the problem. What's at stake?]

### Old Path
[How others tried. What two impossible things were they balancing?]

### Turning Point
[What insight let them break free? "They bet that..."]

### Solution
[Step-by-step mechanism. Use the same example from dilemma.]

### Ending
[Results on a ruler. Most surprising finding.]

### Core
[The one insight to take away. "The real lesson is..."]

## Speed-Read Card

一句话: [...]
大想法: [...]
只记三件事: [...]

## PhD Advisor Review

选题眼光: [...]
方法成熟度: [...]
实验诚意: [...]
声称的分量: [...]
判决: [strong accept / weak accept / borderline / weak reject / strong reject]

## Real-World Testing

生活测: [Where does it work? Where does it break?]
押未来: [If true, what should we see in 1-2 years?]
```

## Verification Gates

- [ ] Can a non-expert retell this story after reading it?
- [ ] Is the dilemma concrete (not abstract)?
- [ ] Is the turning point stated as a bold claim?
- [ ] Are results put on a ruler (before/after)?
- [ ] Is the core insight separable from the paper?
- [ ] PhD review is honest (not just praising)?
- [ ] Real-world testing found both hits and misses?

## Examples

### Example 1: LenVM (Length Value Model)

**Protagonist**: A language model writing a long answer to a math problem.

**Dilemma**: It doesn't know when to stop. Sometimes it cuts off mid-sentence. Sometimes it rambles until tokens run out. You ask it "What's 2+2?" and it writes 200 tokens.

**Old Path**: Previous researchers hard-coded a length limit. But when you cap the length, reasoning quality drops. You can't have both short answers and good reasoning. The ruler: before this paper, every 10% length reduction cost 5% accuracy.

**Turning Point**: They bet that "knowing when to stop" is a learnable skill, not a hard limit. The model should predict remaining distance like a runner with a watch.

**Solution**: Added a "length value head" to the model. It predicts how many tokens are left. During training, it gets -1 reward per token (so shorter = better). During inference, it checks the prediction and stops when it says "almost done."

**Ending**: Length dropped 30%, accuracy didn't drop (actually improved 2%). Token cloud analysis showed "wait/think" tokens disappeared, replaced by "finalize/confirm" tokens. The ruler: before, 10% length reduction cost 5% accuracy. After, 30% length reduction cost 0% accuracy.

**Core**: "Knowing when to stop" is a learnable skill. You can train models to be concise without sacrificing quality.

**Speed-Read Card**:
一句话: A language model learned to predict when to stop writing, cutting length 30% without losing accuracy.
大想法: Conciseness is a trainable skill, not a hard constraint.
只记三件事: (1) Length prediction is learnable, (2) -1 reward per token works, (3) Token cloud shows behavioral shift.

**PhD Advisor Review**:
选题眼光: Real dilemma (length vs. quality is a known problem).
方法成熟度: Clever (value head is a known technique, but applying it to length is novel). Hidden assumption: the length prediction stays stable during inference (but if you change the generation, the prediction might shift).
实验诚意: Baselines are fair (compared to hard limits and no limits). Ablation shows the value head is necessary.
声称的分量: Moderate improvement (30% length reduction is significant, but 2% accuracy gain is within noise).
判决: weak accept

**Real-World Testing**:
生活测: Works for structured tasks (math, code). Breaks for creative tasks (stories, poems) where length is part of the art.
押未来: In 1-2 years, we'll see "length-aware" models that adapt verbosity to task complexity.

## Integration with OV5

This skill integrates with the OV5 research pipeline:

1. **Researcher** encounters a paper during external research
2. **paper-storytelling** skill transforms extraction → narrative
3. **Story stored** in `mementum/memories/paper-{title}.md`
4. **Downstream**: Stories feed into experiment hypothesis generation
5. **Evolution**: Stories with high keep-rate reinforce the skill

## Eight Keys Reference

| Key | How it applies |
|-----|---------------|
| φ Vitality | Story is alive if listener can retell it |
| λ Fractal | 7 beats repeat at every scale (sentence → paragraph → story) |
| ε Purpose | Every sentence advances the story, no filler |
| τ Wisdom | PhD review shows judgment, not just summary |
| π Synthesis | Core insight connects to broader patterns |
| μ Directness | Speed-read card compresses to 3 lines |
| ∃ Truth | Real-world testing finds both hits and misses |
| ∀ Vigilance | Verification gates ensure story quality |
