# ontology-routing-enriched

💡 **Routing by raw keep-rate alone ignores current status.** The old ontology router scored backends purely by `keep-rate * 100`. This misses: how the backend compares to peers (delta from category baseline), whether performance is improving or declining (recent trend), how trustworthy the data is (confidence from volume), and whether the backend is currently healthy (quota/error rate).

New scoring: `Δ(baseline)×40 + keep-rate×30 + trend×20 + confidence×10 + quota-penalty`. This catches a backend at 30% keep-rate that's declining fast (trend -0.15) vs one at 25% that's improving (trend +0.08). The baseline (avg across all backends per category) prevents false promotion — a 20% backend looks bad in isolation but could be excellent if the category average is 10%.

Four new functions: `category-baseline-keep-rate`, `get-recent-performance-stats`, `backend-quota-health`, and the rewritten `reorder-fallbacks-by-ontology`. All 30 router tests pass without changes — the richer scoring produces the same ordering for test data but better decisions in production.
