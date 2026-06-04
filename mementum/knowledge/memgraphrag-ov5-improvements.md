---
title: MemGraphRAG → OV5 Ontology Improvements
status: active
category: architecture
tags: [ontology, memgraphrag, knowledge-graph, three-layer-memory, multi-agent, ov5]
related: [ontology-gaps.md, semantic-relationships.md, agent-architecture-patterns.md]
depends-on: [gptel-auto-workflow-ontology-router.el, gptel-tools-agent-experiment-core.el]
---

# MemGraphRAG → OV5 Ontology Improvements

## Study: MemGraphRAG (KDD 2026)

**Paper**: [MemGraphRAG: Memory-based Multi-Agent System for Graph Retrieval-Augmented Generation](https://arxiv.org/abs/2606.00610)  
**Repo**: [XMUDeepLIT/MemGraphRAG](https://github.com/XMUDeepLIT/MemGraphRAG)

### Core Innovation

MemGraphRAG solves the problem of **fragmented, inconsistent knowledge graphs** in traditional GraphRAG by introducing a **three-layer memory architecture** with **multi-agent shared memory**:

```
┌─────────────────────────────────────┐
│  Schema Layer (Ontology Patterns)   │  ← (head_type, relation, tail_type)
│  e.g., (FUNCTION, imports, MODULE)  │
├─────────────────────────────────────┤
│  Fact Layer (Extracted Triples)     │  ← (head, relation, tail)
│  e.g., (gptel-tools, imports, gptel)│
├─────────────────────────────────────┤
│  Passage Layer (Text Chunks)        │  ← "(require 'gptel)..."
└─────────────────────────────────────┘
```

**Key capabilities**:
- **Bidirectional indexing**: Navigate Schema→Fact→Passage and back
- **Conflict detection**: Mutual, temporal, granularity conflicts between triples
- **Conflict resolution**: LLM-based resolution with source passages
- **Multi-agent shared memory**: All agents read/write to unified memory
- **Synonymy edges**: Link semantically similar entities
- **Vector embeddings**: Semantic search across all layers

---

## Gap Analysis: MemGraphRAG vs OV5

### Gap 1: Flat Memory vs Three-Layer Hierarchy

**MemGraphRAG**: Schema → Fact → Passage (3 layers with bidirectional indices)

**OV5 Current**:
```
mementum/memories/     ← atomic insights (flat .md files)
mementum/knowledge/    ← synthesized pages (flat .md files)
mementum/state.md      ← working memory
```

**Problem**: No abstraction layer. A memory about "grader bypass" is just text. There's no schema layer abstracting the pattern `(ATTACK_TYPE, bypasses, DEFENSE)` from the concrete fact `(grader-bypass, bypasses, validation-check)`.

**Impact**: 
- Can't query "all bypass attacks" — only grep for "bypass"
- Can't generalize from specific incidents to patterns
- Knowledge synthesis requires human curation

**Solution**: Add schema extraction layer

```elisp
;; Proposed: gptel-auto-workflow-memory-schema.el
(defstruct ov5-schema-node
  idx content frequency embedding fact-indices)

(defstruct ov5-fact-node
  idx content embedding schema-idx passage-indices)

(defstruct ov5-passage-node
  idx chunk-id content embedding fact-indices)
```

When a memory like `grader-bypass-attack-2-blocked.md` is committed:
1. **Extract triples**: `(grader-bypass, exploits, daemon-downtime)`
2. **Infer schema**: `(ATTACK_TYPE, exploits, VULNERABILITY)`
3. **Link to passages**: Memory file + related code changes
4. **Build indices**: Bidirectional navigation

### Gap 2: No Entity Extraction from Memories

**MemGraphRAG**: spaCy NER + LLM relation extraction → structured triples

**OV5 Current**: Memories are free-form Markdown. No entity/triple extraction.

**Problem**: "grader-bypass" and "validation bypass" refer to the same concept but are never linked. Can't answer "what defenses exist against bypass attacks?"

**Solution**: LLM-based extraction at commit time

```elisp
;; In pre-commit hook or memory ingestion
(defun ov5-memory-extract-triples (memory-text)
  "Extract (subject, predicate, object) triples from memory."
  ;; Call LLM with prompt:
  ;; "Extract all factual triples from this memory as (subject, predicate, object)."
  ;; Returns: ((grader-bypass exploits daemon-downtime)
  ;;           (daemon-downtime prevents validation-check)
  ;;           (validation-check blocks mass-deletions))
  )
```

### Gap 3: No Conflict Detection Between Memories

**MemGraphRAG**: Detects three conflict types:
- **Mutual**: A contradicts B (one-to-one)
- **Temporal**: A true at t1, B true at t2 (time-dependent)
- **Granularity**: A more specific than B (different detail levels)

**OV5 Current**: Two memories can contradict without detection.

Example conflict (not detected):
- Memory A (2026-06-03): "Critical files: block ALL changes"
- Memory B (2026-06-04): "Critical files: allow small fixes, block mass deletions"

**Problem**: Human must manually resolve contradictions. No automated consistency checking.

**Solution**: Add conflict detection daemon

```elisp
(defun ov5-detect-memory-conflicts ()
  "Scan all memories for contradictions.
   Triggered: after each commit, or weekly.
   Method: vector similarity + LLM classification."
  ;; 1. Find memories with similar entities
  ;; 2. Encode as vectors
  ;; 3. Check similarity > 0.8
  ;; 4. LLM prompt: "Do these two statements contradict?"
  ;; 5. If yes: create conflict-resolution task
  )
```

### Gap 4: No Bidirectional Navigation

**MemGraphRAG**: Schema→Fact→Passage and reverse (via index lists)

**OV5 Current**: One-way links only:
- Knowledge pages reference memories (via `related:` frontmatter)
- Memories don't reference knowledge pages
- Code changes not linked to memories that explain them

**Problem**: Starting from a code file, can't find all memories/knowledge about it. Starting from a memory, can't find related code.

**Solution**: Enrich git commit messages with memory links

```
Current commit message:
  "⚒ Fix self-evolution discard substring false-positive + add research memory"

Improved commit message (auto-generated):
  "⚒ Fix self-evolution discard substring false-positive + add research memory
   
   @memory: pipeline-false-positive-discard
   @schema: (BUG_TYPE, caused_by, substring_matching)
   @fact: (self-evolution, skipped, discard)
   @code: scripts/run-pipeline.sh:156"
```

### Gap 5: File-Level Similarity vs Concept Graph

**MemGraphRAG**: Graph with synonymy edges between entities

**OV5 Current**: `semantic-relationships.md` uses cosine similarity between files:
```
| gptel-tools-agent-experiment-core.el | gptel-tools-agent-prompt-build.el | 0.385 |
```

**Problem**: Similarity is file-to-file, not concept-to-concept. Two files can be semantically related because they both handle "grader-bypass" but the concept itself isn't represented.

**Solution**: Build concept graph from extracted triples

```elisp
;; Concept graph: entities are nodes, relations are edges
;; Node: "grader-bypass"
;;   Edge: "exploits" → "daemon-downtime"
;;   Edge: "bypasses" → "validation-check"
;;   Edge: "similar-to" → "validation-bypass" (synonymy)
```

### Gap 6: No Multi-Agent Shared Memory

**MemGraphRAG**: All agents read/write to unified `ThreeLayerMemory`

**OV5 Current**: Subagents operate in isolation:
- **Analyzer**: reads code, writes research
- **Executor**: reads research, writes code
- **Grader**: reads code, writes scores
- **Comparator**: reads results, writes decisions

**Problem**: No shared context between subagents. Executor doesn't know grader's past objections. Grader doesn't know analyzer's reasoning.

**Solution**: Shared memory workspace per experiment

```elisp
;; Per-experiment shared memory (in-memory, persisted to disk)
(defstruct ov5-experiment-memory
  experiment-id          ; e.g., "onepi5-r100204z5fbb-exp1"
  schema-layer           ; Ontology patterns discovered
  fact-layer             ; Extracted triples from all subagents
  passage-layer          ; Raw outputs from each subagent
  conflict-log           ; Detected conflicts between subagents
  )
```

### Gap 7: No Synonymy Detection

**MemGraphRAG**: KNN search on entity embeddings → synonymy edges

**OV5 Current**: "grader-bypass" and "validation bypass" are separate concepts. No linking.

**Problem**: Can't find all memories about the same concept expressed differently.

**Solution**: Entity embedding + synonymy linking

```elisp
;; When extracting triples, also extract entities
;; Embed each entity, find nearest neighbors
;; If similarity > threshold, add synonymy edge

(ov5-add-synonymy-edge "grader-bypass" "validation-bypass" 0.92)
(ov5-add-synonymy-edge "daemon" "pmf-value-stream" 0.85)
```

### Gap 8: No Temporal Conflict Detection

**MemGraphRAG**: Temporal conflicts (A true at t1, B true at t2)

**OV5 Current**: No mechanism to detect when old memories become obsolete.

Example:
- Memory (2026-05-31): "ontology-gaps.md: ~98% of gaps closed"
- Memory (2026-06-04): "New gap discovered: no three-layer memory"

**Problem**: First memory is now outdated but still appears in search results.

**Solution**: Temporal versioning for memories

```elisp
;; Each memory has valid-from, valid-until timestamps
;; When new memory supersedes old, set valid-until
;; Search only returns currently-valid memories

(ov5-memory-supersede
  :old "ontology-gaps-98-percent-closed"
  :new "ontology-gaps-memgraphrag-study"
  :reason "New gap discovered from MemGraphRAG study")
```

### Gap 9: Hand-Crafted vs LLM-Extracted Ontology

**MemGraphRAG**: LLM extracts ontology from corpus automatically

**OV5 Current**: Ontology is hand-crafted regex in `ontology-router.el`:
```elisp
(defun gptel-auto-workflow--categorize-target (target)
  (cond
   ((string-match-p "context" basename) :natural-language)
   ((string-match-p "benchmark" basename) :programming)
   ...))
```

**Problem**: Manual maintenance. Doesn't adapt as codebase evolves.

**Solution**: LLM-extracted ontology from code + memories

```elisp
(defun ov5-extract-ontology-from-corpus ()
  "Analyze all .el files and memories to extract ontology.
   Output: schema patterns like
   (MODULE_TYPE, handles, CONCERN)
   (CONCERN, related_to, CONCERN)"
  ;; 1. Parse all .el files → AST
  ;; 2. Extract: function names, require statements, defcustom groups
  ;; 3. Extract from memories: entities, relations
  ;; 4. LLM: "What are the main concepts and their relationships?"
  ;; 5. Update ontology-router.el schema layer
  )
```

---

## Implementation Roadmap

### Phase 1: Schema Extraction (1-2 sessions)
- Add triple extraction to memory commit hook
- Build in-memory schema/fact/passage index
- Store in `mementum/.ov5-memory-index.json`

### Phase 2: Conflict Detection (1 session)
- Vector embedding of memories (use existing embedding infrastructure)
- Weekly conflict scan
- Report conflicts in `mementum/knowledge/conflicts.md`

### Phase 3: Multi-Agent Shared Memory (2-3 sessions)
- Per-experiment memory struct
- Inject shared context into subagent prompts
- Persist experiment memory to disk

### Phase 4: Concept Graph (2-3 sessions)
- Extract entities from all memories
- Build synonymy edges
- Replace file-level similarity with concept-level graph

### Phase 5: Temporal Versioning (1 session)
- Add valid-from/until to memory frontmatter
- Update search to filter by validity
- Auto-supersede when new memory contradicts old

---

## Expected Impact

| Metric | Current | With MemGraphRAG Improvements |
|--------|---------|------------------------------|
| Memory search recall | ~60% (grep-based) | ~90% (entity + synonymy) |
| Conflict detection | 0% (manual only) | ~80% (automated) |
| Cross-memory reasoning | None | Schema-level generalization |
| Multi-agent context sharing | None | Full shared memory |
| Ontology maintenance | Manual regex | LLM-extracted + human review |

---

## Files to Create/Modify

**New files**:
- `lisp/modules/gptel-auto-workflow-memory-schema.el` — three-layer memory
- `lisp/modules/gptel-auto-workflow-memory-conflict.el` — conflict detection
- `lisp/modules/gptel-auto-workflow-entity-graph.el` — concept graph + synonymy

**Modified files**:
- `lisp/modules/gptel-auto-workflow-ontology-router.el` — integrate schema layer
- `scripts/git-hooks/pre-commit` — extract triples at commit time
- `mementum/knowledge/ontology-gaps.md` — update with new gaps

---

## References

- MemGraphRAG paper: [arXiv:2606.00610](https://arxiv.org/abs/2606.00610)
- MemGraphRAG code: [github.com/XMUDeepLIT/MemGraphRAG](https://github.com/XMUDeepLIT/MemGraphRAG)
- OV5 ontology: `lisp/modules/gptel-auto-workflow-ontology-router.el`
- Current gaps: `mementum/knowledge/ontology-gaps.md`
