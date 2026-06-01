;; Auto-evolved per-axis backend preference
;; Updated: 2026-06-01 — MiniMax-M3 preferred for all roles.
;; MiniMax-M3 (1M context, Agent reasoning, tool calls) outperforms m2.7.
(setq gptel-auto-workflow--task-backend-preference
      '(("analyzer" "MiniMax" . 0.30)
        ("executor" "MiniMax" . 0.30)
        ("grader" "MiniMax" . 0.30)
        ("researcher" "MiniMax" . 0.30)
        ("reviewer" "MiniMax" . 0.30)
        ("comparator" "MiniMax" . 0.30)
        ("analyzer" "DeepSeek" . 0.20)
        ("executor" "DeepSeek" . 0.20)
        ("grader" "DeepSeek" . 0.20)
        ("researcher" "DeepSeek" . 0.20)
        ("reviewer" "DeepSeek" . 0.20)
        ("comparator" "DeepSeek" . 0.20)
        ("analyzer" "DashScope" . 0.10)
        ("executor" "DashScope" . 0.10)
        ("grader" "DashScope" . 0.10)
        ("researcher" "DashScope" . 0.10)
        ("reviewer" "DashScope" . 0.10)
        ("comparator" "DashScope" . 0.10)))
