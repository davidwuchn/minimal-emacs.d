# DeepSearcher Gap Analysis

**Context:** Studied [zilliztech/deep-searcher](https://github.com/zilliztech/deep-searcher) and compared it with OV5.

**Key insight:** DeepSearcher is a strong reference for *document-QA RAG* (chunking, vector retrieval, reranking, multi-hop agents, evaluation). OV5 has no dedicated vector memory backend, no sentence-window chunking, and no multi-hop RAG agent over memories.

**Highest-leverage gap:** Vector search over mementum memories — answered by **Datahike + Proximum** (already in the stack). OV5's World Store is built on Datahike; Proximum adds HNSW vector indexing with the same immutable, git-like semantics. No new dependency needed — extend `gptel-ext-world-store.el` to embed memory chunks and store them as Datahike entities with Proximum vector indices.

**Other gaps:**
- LLM-based per-chunk reranking after retrieval
- Collection / knowledge-domain router
- Per-query agent router (plan vs agent mode)
- Web-to-memory loader (FireCrawl/Crawl4AI/Jina)
- Retrieval recall evaluation harness

**What OV5 does better:** self-evolution, git-based memory continuity, L1-L4 safety, ontology learning, Emacs-native code tools, World Store structured storage.

**Full analysis:** `mementum/knowledge/deep-searcher-vs-ov5-gaps.md`

**Symbol:** 💡
