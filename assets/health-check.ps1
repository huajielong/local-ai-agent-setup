$ErrorActionPreference = "SilentlyContinue"

function Check-Url {
    param([string]$Name, [string]$Url)
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 3
        Write-Host ("[OK]   {0}: {1} {2}" -f $Name, $r.StatusCode, $r.Content.Trim())
    }
    catch {
        Write-Host ("[DOWN] {0}: {1}" -f $Name, $Url) -ForegroundColor Red
    }
}

Write-Host "=== Local AI health check ==="
Check-Url -Name "Model server" -Url "http://127.0.0.1:8081/health"
Check-Url -Name "Anthropic proxy" -Url "http://127.0.0.1:8787/health"

Write-Host "`n=== ollama list ==="
ollama list

Write-Host "`n=== ollama ps ==="
ollama ps

Write-Host "`n=== GPU ==="
nvidia-smi --query-gpu=name,memory.used,memory.free,utilization.gpu --format=csv
