#!/usr/bin/env bash
# Read-only hardware detection for local AI model selection.
# Usage: bash detect-hardware.sh
# Works on macOS and Linux. Does not install or download anything.

set -u

OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"

echo "=== Hardware summary ==="
echo "OS      : $OS ($ARCH)"

if [ "$OS" = "Darwin" ]; then
    if command -v sw_vers >/dev/null 2>&1; then
        echo "Version : $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
    fi
    CPU="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model 2>/dev/null || echo unknown)"
    RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
else
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release 2>/dev/null || true
        echo "Version : ${PRETTY_NAME:-unknown}"
    fi
    CPU="$(awk -F: '/model name|Model/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || echo unknown)"
    RAM_BYTES="$(free -b 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 0)"
fi

RAM_GB="$(awk -v b="${RAM_BYTES:-0}" 'BEGIN {printf "%.1f", b/1024/1024/1024}')"
echo "CPU     : $CPU"
echo "RAM     : ${RAM_GB} GB"

if [ "$OS" = "Darwin" ]; then
    echo "Unified : Apple Silicon uses unified memory; treat RAM as the model budget."
fi

echo ""
echo "=== Disk (home) ==="
df -h "$HOME" 2>/dev/null | tail -n +2 || true

echo ""
echo "=== GPU ==="
GPU_FOUND=0

if command -v nvidia-smi >/dev/null 2>&1; then
    NV="$("nvidia-smi" --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>/dev/null || true)"
    if [ -n "$NV" ]; then
        echo "$NV" | while IFS= read -r line; do
            echo "NVIDIA : $line (VRAM in MiB)"
        done
        GPU_FOUND=1
    fi
fi

if [ "$OS" = "Darwin" ]; then
    if command -v system_profiler >/dev/null 2>&1; then
        echo "Apple GPU:"
        system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|Total Number of Cores|VRAM|Metal" | sed 's/^/  /'
        GPU_FOUND=1
    fi
fi

if [ "$GPU_FOUND" -eq 0 ] && command -v lspci >/dev/null 2>&1; then
    echo "PCI display devices:"
    lspci 2>/dev/null | grep -Ei "vga|3d|display" | sed 's/^/  /'
fi

if command -v rocm-smi >/dev/null 2>&1; then
    echo "AMD ROCm:"
    rocm-smi --showproductname --showmeminfo vram 2>/dev/null | head -40 | sed 's/^/  /'
fi

echo ""
echo "=== Tools ==="
for t in ollama claude node npm python3 lms llama-server; do
    p="$(command -v "$t" 2>/dev/null || true)"
    if [ -n "$p" ]; then
        echo "$t: $p"
    else
        echo "$t: not found"
    fi
done

if command -v ollama >/dev/null 2>&1; then
    echo ""
    echo "=== Ollama models ==="
    ollama list 2>/dev/null || true
fi
