;; Auto-evolved per-axis backend preference
;; Generated: 2026-05-26 14:55 (manual rebalance: let data compete)
;; Git-tracked — shared across machines. Commit after evolution.
;; MiniMax has 20.7% keep-rate (highest) now healthy — give it a
;; small boost to compete with DeepSeek (19.0%+0.05=0.240).
;; DashScope at 0% is a data artifact (listp crash misattributed).
(setq gptel-auto-workflow--task-backend-preference
      '(        ("analyzer" "DashScope" . 0.10)
        ("analyzer" "DeepSeek" . 0.10)
        ("grader" "moonshot" . 0.10)
        ("grader" "DeepSeek" . 0.10)
        ("executor" "DashScope" . 0.05)
        ("executor" "DeepSeek" . 0.05)
        ("executor" "MiniMax" . 0.05)
        ("researcher" "DeepSeek" . 0.15)
        ("researcher" "DashScope" . 0.05)
        ("reviewer" "DeepSeek" . 0.10)
        ("comparator" "DashScope" . 0.10)))
