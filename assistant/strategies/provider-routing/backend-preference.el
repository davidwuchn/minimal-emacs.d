;; Auto-evolved per-axis backend preference
;; Generated: 2026-05-26 22:00 (moonshot second chance — bugs fixed)
;; Git-tracked — shared across machines. Commit after evolution.
;; MiniMax at 20.7% leads executor. moonshot at 8.8% was depressed by
;; 5 let-binding tool-errors (model-symbol fix) + 1 curl-35 (retry fix).
;; Give it +0.15 boost to get traffic and prove its real keep-rate.
(setq gptel-auto-workflow--task-backend-preference
      '(        ("analyzer" "DashScope" . 0.10)
        ("analyzer" "DeepSeek" . 0.10)
        ("grader" "moonshot" . 0.15)
        ("grader" "DeepSeek" . 0.10)
        ("executor" "DashScope" . 0.05)
        ("executor" "DeepSeek" . 0.05)
        ("executor" "MiniMax" . 0.05)
        ("executor" "moonshot" . 0.15)
        ("researcher" "DeepSeek" . 0.15)
        ("researcher" "DashScope" . 0.05)
        ("reviewer" "DeepSeek" . 0.10)
        ("comparator" "DashScope" . 0.10)))
