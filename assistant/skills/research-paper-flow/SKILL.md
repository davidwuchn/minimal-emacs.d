---
name: research-paper-flow
description: >
  Workflow chain: researcher → paper-storytelling.
  When researcher encounters a research paper, automatically invoke paper-storytelling
  to transform extraction into narrative understanding. Use when user says "research paper",
  "analyze this paper", "tell me about this paper", or when researcher detects arxiv/PDF links.
version: 1.0.0
level: compound
molecules: [researcher-prompt, paper-storytelling]
triggers: ["research paper", "analyze paper", "tell me about this paper", "arxiv", "conference paper"]
---

# Research Paper Flow

Workflow chain: **researcher → paper-storytelling**

## Trigger Conditions

This workflow activates when:
1. User explicitly requests paper analysis ("analyze this paper", "tell me about this paper")
2. Researcher detects paper URLs (arxiv.org, conference proceedings, PDF links)
3. Researcher encounters phrases like "we propose", "our method", "experimental results"

## Workflow Steps

### Step 1: Researcher (Initial Scan)
The researcher performs initial scan:
- Fetch paper metadata (title, authors, abstract)
- Check if paper is relevant to OV5 research areas
- Extract key sections (introduction, method, results)

### Step 2: Paper Storytelling (Deep Analysis)
Invoke paper-storytelling skill:
- Extract 7-beat narrative spine
- Write continuous story (not bullet points)
- Add speed-read card (3 lines)
- PhD advisor review (honest assessment)
- Real-world testing (where it works/breaks)

### Step 3: Actionable Insights Extraction
From the story, extract:
- 3-5 concrete techniques we can implement in OV5
- Integration points with existing modules
- Estimated implementation effort

### Step 4: Mementum Storage
Store the analysis:
- Save story to `mementum/memories/paper-{title}.md`
- Tag with relevant topics (for future recall)
- Link to related experiments (if any)

## Output Structure

```markdown
# Paper Analysis: {Title}

## Metadata
- Authors: [...]
- Venue: [...]
- Year: [...]
- URL: [...]

## The Story
[7-beat narrative from paper-storytelling]

## Speed-Read Card
一句话: [...]
大想法: [...]
只记三件事: [...]

## PhD Advisor Review
判决: [strong accept / weak accept / borderline / weak reject / strong reject]

## Real-World Testing
生活测: [Where does it work? Where does it break?]
押未来: [If true, what should we see in 1-2 years?]

## Actionable Insights for OV5
1. [Technique 1]: [How to implement]
2. [Technique 2]: [How to implement]
3. [Technique 3]: [How to implement]

## Integration Points
- Module: [Which OV5 module this applies to]
- Effort: [Low/Medium/High]
- Priority: [High/Medium/Low]
```

## Example Usage

### Example 1: User Request
```
User: /research-paper-flow https://arxiv.org/abs/2401.12345
→ Researcher fetches paper
→ Paper-storytelling extracts 7-beat narrative
→ Actionable insights extracted
→ Stored in mementum
```

### Example 2: Researcher Detection
```
Researcher: Found paper "Efficient Attention Mechanisms for Long Context"
→ Detects arxiv URL
→ Invokes paper-storytelling
→ Returns narrative + insights
```

## Integration with OV5 Pipeline

This workflow integrates with the OV5 research pipeline:

1. **Research phase**: Researcher encounters paper → triggers research-paper-flow
2. **Digest phase**: Paper stories feed into research digest
3. **Experiment phase**: Actionable insights become experiment hypotheses
4. **Evolution phase**: Stories with high keep-rate reinforce the workflow

## Verification Gates

- [ ] Story is continuous narrative (not bullet points)?
- [ ] 7 beats are all present (protagonist, dilemma, old path, turning point, solution, ending, core)?
- [ ] Speed-read card has 3 lines?
- [ ] PhD review is honest (not just praising)?
- [ ] Real-world testing found both hits and misses?
- [ ] 3-5 actionable insights extracted?
- [ ] Stored in mementum with proper tags?

## Eight Keys Reference

| Key | How it applies |
|-----|---------------|
| φ Vitality | Story is alive if listener can retell it |
| λ Fractal | 7 beats repeat at every scale |
| ε Purpose | Every sentence advances the story |
| τ Wisdom | PhD review shows judgment |
| π Synthesis | Core insight connects to broader patterns |
| μ Directness | Speed-read card compresses to 3 lines |
| ∃ Truth | Real-world testing finds both hits and misses |
| ∀ Vigilance | Verification gates ensure quality |
