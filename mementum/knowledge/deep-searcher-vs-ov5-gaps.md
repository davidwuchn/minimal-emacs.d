---
title: DeepSearcher vs OV5 - Gap Analysis
status: active
category: research
tags: deep-searcher, RAG, vector-search, agentic-retrieval, multi-hop, mementum, OV5
related: mementum protocol, gptel-ext-world-store, self-heal-semantic, ontology-router, gptel-tools-agent-research
created: 2026-06-12
---

# DeepSearcher vs OV5 - Gap Analysis

**Source:** [zilliztech/deep-searcher](https://github.com/zilliztech/deep-searcher) (v0.x, master branch, 2026-06-12)

DeepSearcher is a Python open-source "deep research" alternative built around agentic RAG over private data. It is product-oriented: load documents, embed them into a vector database, then answer complex queries with iterative retrieval and summarization.

OV5 is an Emacs-native self-evolving agent environment focused on *code evolution*, *research automation*, and *memory persistence*. It already has some RAG-like pieces (mementum memories, research digests, World Store), but it is not primarily a document-QA product.

This page records what OV5 could borrow from DeepSearcher and where OV5 already exceeds it.

---

## 1. DeepSearcher Architecture

| Layer | Components |
|-------|------------|
| LLM | OpenAI, DeepSeek, Claude, Gemini, Grok, Qwen, Ollama, etc. |
| Embedding | OpenAI, Milvus built-in, Voyage, FastEmbed, Bedrock, etc. |
| Vector DB | Milvus/Zilliz Cloud, Qdrant, Azure AI Search |
| Document Loaders | PDF, Text, Unstructured, Docling |
| Web Crawlers | FireCrawl, Crawl4AI, Jina Reader, Docling |
| RAG Agents | NaiveRAG, DeepSearch, ChainOfRAG |
| Routing | CollectionRouter (which collection), RAGRouter (which agent) |
| Serving | FastAPI service + CLI |
| Evaluation | 2WikiMultiHopQA recall benchmark |

### 1.1 Agentic Retrieval Flow (DeepSearch agent)

1. **Sub-query generation** — LLM breaks the original query into up to 4 sub-queries.
2. **Collection routing** — LLM selects relevant vector DB collections.
3. **Parallel vector search** — Each sub-query is embedded and searched in parallel.
4. **Per-chunk LLM reranking** — Each retrieved chunk is scored YES/NO by the LLM.
5. **Reflection / gap queries** — LLM decides whether more search is needed and emits up to 3 follow-up queries.
6. **Iterate** — Up to `max_iter` cycles (default 3).
7. **Summarize** — Final answer generated from accepted chunks.

### 1.2 ChainOfRAG Agent

- Iteratively generates follow-up questions.
- Produces intermediate answers for each sub-query.
- Uses LLM to select *supporting documents* for each intermediate answer.
- Optional early stopping when enough information is gathered.

---

## 2. Capability Comparison

| Capability | DeepSearcher | OV5 |
|------------|--------------|-----|
| Primary use case | Private-document Q&A / reports | Self-evolving Emacs AI environment |
| Vector database abstraction | Pluggable (Milvus, Qdrant, Azure) | None dedicated; mementum uses git + JSON index |
| Embedding abstraction | Pluggable, many providers | N/A for code; trigram fallback in skill routing |
| Document chunking | Recursive splitter + sentence-window | None systematic |
| Multi-hop / iterative retrieval | DeepSearch + ChainOfRAG | Research controller can iterate, but not multi-hop RAG |
| LLM-based reranking | Per-chunk YES/NO rerank | None |
| Collection routing | LLM-based collection selection | Skill-routing ontology, no collection router |
| Agent selection router | RAGRouter picks agent per query | gptel-agent preset switching, but no per-query agent router |
| Web crawling for RAG | FireCrawl, Crawl4AI, Jina | Web research exists but not integrated as RAG loader |
| Evaluation harness | 2WikiMultiHopQA recall benchmark | Grader-based keep-rate benchmarks, no retrieval recall benchmark |
| REST/CLI service | FastAPI + CLI | Emacs-only |
| Self-healing / evolution | None | Self-heal-semantic + evolution loop |
| Memory persistence | In-vector-DB only | Git-based mementum + World Store |
| Safety layers | Basic env vars / API keys | L1-L4 defense-in-depth |
| Ontology learning | None | Ontology graph from experiments |
| Source-level adaptation | None | Source-level self-evolution |

---

## 3. Actionable Gaps in OV5

These are features or patterns OV5 could adopt, ordered by leverage.

### 3.1 Pluggable Vector Memory Backend

**Gap:** Mementum memories are files on disk with a JSON index. There is no dense-vector retrieval backend.

**Why it matters:** As memory grows, keyword/n-gram retrieval will miss conceptually related memories that do not share exact words.

**Solution: Datahike + Proximum (already in the stack).** OV5 already has Datahike wired via `gptel-ext-world-store.el` (Phase 1 complete). Datahike provides:
- Immutable fact storage with full audit history (git-like semantics, aligns with mementum).
- Proximum: an HNSW vector index built for Datahike's persistent data model, bringing semantic search/RAG directly into the Datalog store (EPL-2.0 licensed).
- Datalog queries can combine structured filters + vector similarity in a single query.

**Possible path:**
- Extend `gptel-ext-world-store.el` to chunk and embed mementum memories into Datahike entities with vector indices via Proximum.
- Use Datahike's datalog to query by category/tag/date AND vector similarity simultaneously.
- Keep mementum git files as the authoritative source; Datahike is a read-optimized search index.

### 3.2 Sentence-Window Chunking for Memories

**Gap:** Memories are stored whole. Long knowledge pages are not chunked with context windows.

**Why it matters:** A single long knowledge page can drown a prompt or be retrieved only as an all-or-nothing unit.

**Possible path:**
- Chunk `mementum/knowledge/*.md` and `mementum/memories/*.md` with sentence-window strategy.
- Store chunks in the vector store with `reference` pointing back to the source file.
- Retrieve chunks, but present the surrounding window to the LLM.

### 3.3 Multi-Hop RAG Agent for Research

**Gap:** OV5 research is driven by `gptel-tools-agent-research` and web search, not by iterative retrieval over a private memory corpus.

**Why it matters:** Complex user questions ("Why did strategy X fail in the last 3 experiments?") require joining facts from multiple memories.

**Possible path:**
- Implement a `ChainOfRAG`-like agent in `gptel-auto-workflow-research-*`.
- Generate follow-up queries based on intermediate answers from retrieved memory chunks.
- Track supporting documents explicitly (as DeepSearcher does).

### 3.4 LLM-Based Reranking of Retrieved Memories

**Gap:** Memory retrieval currently uses keyword/n-gram/index methods. There is no LLM-based relevance filter.

**Why it matters:** Embeddings retrieve candidates, but an LLM can judge whether a candidate actually answers the query.

**Possible path:**
- After vector retrieval, ask a cheap/fast model (e.g., gpt-5.4-mini) for a YES/NO relevance verdict per chunk.
- Use this as a filter before synthesizing the final answer.

### 3.5 Collection / Knowledge-Domain Router

**Gap:** When querying memories, OV5 does not first decide which *domain* of knowledge is relevant.

**Why it matters:** Searching all memories for every query is noisy and expensive.

**Possible path:**
- Add a `knowledge-domain-router` that picks among `mementum/memories/`, `mementum/knowledge/`, World Store, research findings, etc.
- Use collection descriptions (frontmatter `category`/`tags`) as routing signals.

### 3.6 Per-Query Agent Router

**Gap:** OV5 switches presets (`gptel-plan`, `gptel-agent`) manually; there is no automatic per-query agent selection.

**Why it matters:** Different tasks need different tool profiles and safety levels.

**Possible path:**
- Add a lightweight `agent-router` that classifies the incoming task and selects plan vs. agent mode, plus which skill set to load.

### 3.7 Web-to-Memory RAG Loader

**Gap:** Web crawling exists for research but is not a first-class "load this URL into mementum" operation.

**Why it matters:** Users may want to ingest web pages or documents into long-term memory for later multi-hop questions.

**Possible path:**
- Add a `load-from-url-into-mementum` tool (FireCrawl/Crawl4AI/Jina Reader).
- Chunk, embed, and store with source reference.

### 3.8 Retrieval Recall Evaluation Harness

**Gap:** OV5 evaluates code evolution via grader scores, not retrieval quality.

**Why it matters:** If vector memory is added, we need a benchmark to measure whether retrieval actually finds relevant memories.

**Possible path:**
- Create a small internal benchmark: given a question, identify the set of memories/knowledge pages that should be retrieved.
- Measure recall@K and answer accuracy.

---

## 4. What OV5 Already Does Better

| Area | OV5 Advantage |
|------|---------------|
| Self-evolution | Source-level repair and evolution loops; DeepSearcher has none. |
| Memory continuity | Git-based mementum survives restarts and syncs across branches. |
| Safety | L1-L4 defense-in-depth; DeepSearcher relies on env-var API keys. |
| Code context | Native Emacs integration with code tools, syntax validation, worktree isolation. |
| Ontology learning | Experiments update an ontology graph; DeepSearcher has no learning layer. |
| Research automation | Paper analysis, research digest, and automated recall; DeepSearcher only retrieves documents. |
| World Store | Structured Datahike storage for experiment facts; DeepSearcher is purely vector RAG. |

---

## 5. Why Datahike + Proximum Over External Vector DBs

OV5 already has Datahike wired as the World Store. Adding Proximum means:

| Factor | Datahike + Proximum | External (Milvus/Qdrant) |
|--------|---------------------|--------------------------|
| New dependency | None (already in stack) | New service or library |
| Immutability | Native (git-like snapshots) | None or bolted on |
| Structured + vector | Datalog combines both | Separate query languages |
| Audit trail | Built-in (time-travel) | None |
| Cross-session | Babashka brepl already connected | New connection layer |
| Storage | File/LMDB/S3 (via konserve) | Vendor-specific |
| License | EPL-2.0 (open source) | Varies |

Proximum is dual-licensed (EPL-2.0 + commercial, 2026). The open-source license is sufficient for OV5's needs.

---

## 6. Synthesis

DeepSearcher is a strong reference for the *document-QA* product surface: chunking, vector retrieval, reranking, multi-hop agents, and evaluation. OV5 should selectively adopt these patterns *without* becoming a generic RAG product.

The highest-leverage borrow is **vector search over mementum memories**, and the answer is already in the stack: **Datahike + Proximum**. OV5's World Store is built on Datahike; Proximum adds HNSW vector indexing with the same immutable, git-like semantics. No new service or library is needed — extend `gptel-ext-world-store.el` to embed memory chunks and store them as Datahike entities with Proximum vector indices.

After vector search, a **multi-hop RAG agent over memories** and an **LLM-based reranker** would make OV5 research and memory recall materially stronger.

The lowest priority is the FastAPI/CLI service layer; OV5's value is Emacs-native, agentic code evolution, not a standalone document chat API.

---

## 6. Related Files

- `lisp/modules/gptel-ext-world-store.el` — emerging structured memory store
- `lisp/modules/gptel-auto-workflow-memory-schema.el` — graph index over mementum
- `lisp/modules/gptel-tools-agent-research.el` — current research agent
- `lisp/modules/skill-routing-onto.el` — ontology-based skill routing
- `mementum/knowledge/self-evolving-agent-research.md` — prior research-paper comparisons
