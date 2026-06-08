---
title: Bailian Model Pricing
status: active
category: pricing
tags: [bailian, token-plan, dashscope, pricing, token-economics]
last-updated: 2026-06-08T16:00:00
source: https://bailian.console.aliyun.com/cn-beijing/?tab=doc#/doc/?type=model&url=2987148
---

# Bailian Model Pricing (百炼模型定价)

> **Single source of truth for token economics.**
> This page is machine-read by `gptel-auto-workflow-self-audit--check-pricing-freshness`.
> Format: `MODEL | input_CNY | output_CNY | cache_CNY | context_window | speed`
> All prices in CNY (元) per million tokens.
> Speed: fast / medium / slow. Used for routing + cost-quality tradeoffs.

## TokenPlan Models (token-plan.cn-beijing.maas.aliyuncs.com)

```pricing
qwen3.7-max | 12 | 36 | 1.2 | 1000000 | slow | SOTA reasoning
qwen3.7-plus | 6 | 24 | 0.6 | 1000000 | medium | Tiered ¥2-6/¥8-24
qwen3.6-flash | 4.8 | 28.8 | 0.5 | 1000000 | fast | Tiered ¥1.2-4.8/¥7.2-28.8
deepseek-v4-pro | 3.1 | 6.2 | 0.03 | 1000000 | slow | Reasoning model
deepseek-v4-flash | 1 | 2 | 0.02 | 1000000 | fast | Fast variant
kimi-k2.6 | 15 | 60 | 2.0 | 262144 | medium | Cache miss ¥15, hit ¥2.0
glm-5.1 | 3.6 | 14.4 | 0.4 | 128000 | medium | Zhipu GLM-5.1
```

## DashScope Models (coding.dashscope.aliyuncs.com)

```pricing
qwen3.7-plus | 6 | 24 | 0.6 | 1000000 | Same as TokenPlan tier
qwen3.6-plus | 2 | 8 | 0.2 | 1000000 | (estimate, not confirmed from console)
```

## MiniMax Models (api.minimaxi.com)
> Source: https://platform.minimaxi.com/subscribe/token-plan?tab=api-enterprise

```pricing
MiniMax-M3 | 4.2 | 16.8 | 0.84 | 1000000 | fast | 50% off effective: ¥2.1/¥8.4/¥0.42
MiniMax-M2.7 | 2.1 | 8.4 | 0.42 | 196608 | medium | Cache write ¥2.625
MiniMax-M2.7-highspeed | 4.2 | 16.8 | 0.42 | 196608 | fast | Cache write ¥2.625
```

## Conversion Rate

- 1 CNY ≈ 0.138 USD (used for registry USD pricing)
- USD prices in registry: `pricing-input`, `pricing-output`, `pricing-cache-hit`

## Auto-Update Protocol

1. Human updates this page from Bailian console whenever new pricing is published
2. Pipeline Step 0.4 (self-audit) reads this page and compares against `gptel-backend-registry`
3. Discrepancies logged as `pricing-stale` issues
4. Pipeline Step 0.5 writes `var/tmp/pricing-stale.txt` flag
5. Token economics in Step 6 uses registry prices for real cost calculations

## Effort-Level Economics (Future)

- **Question**: which effort level (xhigh/high/low) is most economic per model?
- **Mechanism**: higher effort = model thinks longer = more output tokens = higher cost + slower
- **Metric**: cost-per-kept-experiment at each effort level
  - `xhigh`: slowest, highest quality(?), highest cost (more thinking tokens)
  - `high`: medium speed/quality/cost
  - `low` (default): fastest, cheapest, baseline quality
- **$/token is the same** at all effort levels — total cost differs because token count differs
- **Current limitation**: TSV doesn't record per-experiment effort level or token count
- **Needed**: add effort-level + token-usage fields to TSV; A/B test across cycles
- **Registry**: `gptel-backend-effort-levels` maps model→(effort→API value)
  e.g., `(qwen3.7-max . ((xhigh . "high") (high . "medium") (default . "low")))`
- **Status**: `--compute-token-economics` tracks per-model cost; per-effort tracking pending
