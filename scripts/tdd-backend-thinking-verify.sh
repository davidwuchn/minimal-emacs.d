#!/bin/bash
# TDD: Verify all LLM backends with correct thinking params
set -e

AUTHINFO="$HOME/.authinfo.gpg"
TIMEOUT=30
PASS=0
FAIL=0

PROMPT="Say hello in exactly one word."

get_key() {
  gpg --batch -q -d "$AUTHINFO" 2>/dev/null | awk -v h="$1" '$0~"^machine "h" " {for(i=1;i<=NF;i++) if($i=="password") print $(i+1)}'
}

test_backend() {
  local name="$1" url="$2" key_host="$3" model="$4"
  local key
  key=$(get_key "$key_host")
  
  if [ -z "$key" ]; then
    echo "  ⚠ SKIP $name: no API key"
    return
  fi
  
  # Use temp file for JSON to avoid escaping issues
  local tmp=$(mktemp)
  cat > "$tmp" <<JSONEOF
{
  "model": "$model",
  "messages": [{"role": "user", "content": "$PROMPT"}],
  "max_completion_tokens": 20,
  "stream": false
JSONEOF
  # Append extra params line by line
  shift 4
  for p in "$@"; do
    echo "  ,$p" >> "$tmp"
  done
  echo "}" >> "$tmp"
  
  local resp
  resp=$(curl -s --max-time $TIMEOUT -X POST "$url" \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -d @"$tmp" 2>/dev/null)
  rm -f "$tmp"
  
  if echo "$resp" | grep -q '"content"'; then
    local content
    content=$(echo "$resp" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')
    echo "  ✅ $name ($model):${content:0:50}"
    PASS=$((PASS + 1))
  elif echo "$resp" | grep -q '"error"'; then
    local err
    err=$(echo "$resp" | grep -o '"message":"[^"]*"' | head -1)
    echo "  ❌ $name ($model): $err"
    FAIL=$((FAIL + 1))
  else
    echo "  ❌ $name ($model): $(echo "$resp" | head -c 200)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== TDD: Backend Thinking Mode Verification ==="
echo ""

echo "--- Thinking DISABLED ---"

test_backend "MiniMax-M3" \
  "https://api.minimaxi.com/v1/chat/completions" \
  "api.minimaxi.com" \
  "MiniMax-M3" \
  '"thinking":{"type":"disabled"}' \
  '"max_completion_tokens":8192'

test_backend "Z-AI/glm5.1" \
  "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions" \
  "open.bigmodel.cn" \
  "glm-5.1" \
  '"thinking":{"type":"disabled"}' \
   '"max_tokens":50'

echo ""
echo "--- Thinking ENABLED ---"

test_backend "DeepSeek/v4-flash" \
  "https://api.deepseek.com/chat/completions" \
  "api.deepseek.com" \
  "deepseek-v4-flash" \
  '"thinking":{"type":"enabled"}'

test_backend "moonshot/kimi-k2.6" \
  "https://api.kimi.com/coding/v1/chat/completions" \
  "api.kimi.com" \
  "kimi-k2.6" \
  '"thinking":{"type":"enabled"}' \
  '"reasoning_effort":"high"'

echo ""
echo "--- CF-Gateway ---"

test_backend "CF-GW/kimi-k2.6" \
  "https://gateway.ai.cloudflare.com/v1/e68f70855c32831717611057ed23aa46/mindward/workers-ai/v1/chat/completions" \
  "gateway.ai.cloudflare.com" \
  "@cf/moonshotai/kimi-k2.6"

echo ""
echo "══════════════════════"
echo "Results: $PASS PASS, $FAIL FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1