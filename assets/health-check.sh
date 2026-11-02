#!/usr/bin/env bash
# Local AI health check. Adjust ports if needed.
set -u

check() {
    name="$1"
    url="$2"
    body="$(curl -fsS --max-time 3 "$url" 2>/dev/null || true)"
    if [ -n "$body" ]; then
        echo "[OK]   $name: $body"
    else
        echo "[DOWN] $name: $url"
    fi
}

echo "=== Local AI health check ==="
check "Model server" "http://127.0.0.1:8081/health"
check "Anthropic proxy" "http://127.0.0.1:8787/health"

echo ""
echo "=== ollama list ==="
command -v ollama >/dev/null 2>&1 && ollama list || echo "ollama not found"

echo ""
echo "=== ollama ps ==="
command -v ollama >/dev/null 2>&1 && ollama ps || true

echo ""
echo "=== GPU ==="
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.used,memory.free,utilization.gpu --format=csv
elif [ "$(uname -s)" = "Darwin" ]; then
    system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|VRAM|Metal" || true
fi
