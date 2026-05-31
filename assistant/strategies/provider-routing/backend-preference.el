;; Auto-evolved per-axis backend preference
;; Updated: 2026-05-31 — MiniMax for analyzer (fast, no thinking)
;; DeepSeek for executor/grader (complex prompts).
;; DashScope timeout fixed with increased timeout.
(setq gptel-auto-workflow--task-backend-preference
      '(("analyzer" "MiniMax" . 0.30)
        ("analyzer" "DeepSeek" . 0.20)
        ("analyzer" "DashScope" . 0.10)
        ("grader" "DeepSeek" . 0.30)
        ("grader" "MiniMax" . 0.20)
        ("grader" "DashScope" . 0.10)
        ("executor" "DeepSeek" . 0.30)
        ("executor" "MiniMax" . 0.20)
        ("executor" "DashScope" . 0.10)
        ("researcher" "DeepSeek" . 0.30)
        ("researcher" "MiniMax" . 0.20)
        ("researcher" "DashScope" . 0.10)
        ("reviewer" "DeepSeek" . 0.30)
        ("reviewer" "MiniMax" . 0.20)
        ("reviewer" "DashScope" . 0.10)
        ("comparator" "DeepSeek" . 0.30)
        ("comparator" "MiniMax" . 0.20)
        ("comparator" "DashScope" . 0.10)))
