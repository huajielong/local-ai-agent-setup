# Read-only hardware detection for local AI model selection.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\detect-hardware.ps1
# It does not install or download anything.

$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$result = [ordered]@{}

# --- OS ---
$os = Get-CimInstance Win32_OperatingSystem
$result.OS = [ordered]@{
    Caption      = $os.Caption
    Version      = $os.Version
    Architecture = $os.OSArchitecture
}

# --- CPU ---
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$result.CPU = [ordered]@{
    Name              = $cpu.Name
    Cores             = $cpu.NumberOfCores
    LogicalProcessors = $cpu.NumberOfLogicalProcessors
}

# --- RAM ---
$cs = Get-CimInstance Win32_ComputerSystem
$result.RAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)

# --- Disks ---
$disks = @()
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $disks += [ordered]@{
        Drive  = $_.DeviceID
        FreeGB = [math]::Round($_.FreeSpace / 1GB, 1)
        SizeGB = [math]::Round($_.Size / 1GB, 1)
    }
}
$result.Disks = $disks

# --- GPUs ---
$gpus = @()

# NVIDIA first: nvidia-smi reports the real VRAM reliably.
$nv = & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>$null
if ($LASTEXITCODE -eq 0 -and $nv) {
    foreach ($line in $nv) {
        $parts = $line -split ','
        if ($parts.Count -ge 3) {
            $gpus += [ordered]@{
                Vendor  = "NVIDIA"
                Name    = ($parts[0].Trim() -replace '^NVIDIA\s+', '')
                VRAM_GB = [math]::Round([double]$parts[1].Trim() / 1024, 1)
                Driver  = $parts[2].Trim()
                Source  = "nvidia-smi"
            }
        }
    }
}

# Fallback / additional GPUs: registry qwMemorySize (AdapterRAM is capped at 4GB in WMI).
$vramByDriver = @{}
$classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
Get-ChildItem $classPath -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
    if ($p."HardwareInformation.qwMemorySize") {
        try {
            $vramByDriver[$p.DriverDesc] = [math]::Round([UInt64]$p."HardwareInformation.qwMemorySize" / 1GB, 1)
        }
        catch { }
    }
}

Get-CimInstance Win32_VideoController | ForEach-Object {
    $name = $_.Name -replace '^NVIDIA\s+', ''
    $already = $gpus | Where-Object { $_.Name -eq $name }
    if (-not $already) {
        $vram = $null
        if ($vramByDriver.ContainsKey($name)) { $vram = $vramByDriver[$name] }
        $gpus += [ordered]@{
            Vendor  = $_.AdapterCompatibility
            Name    = $name
            VRAM_GB = $vram
            Driver  = $_.DriverVersion
            Source  = "Win32_VideoController"
        }
    }
}
$result.GPUs = $gpus

# --- Tools ---
$toolNames = @("ollama", "claude", "node", "npm", "python", "lms", "llama-server")
$tools = [ordered]@{}
foreach ($t in $toolNames) {
    $cmd = Get-Command $t -ErrorAction SilentlyContinue
    if ($cmd) {
        $tools[$t] = $cmd.Source
    }
    else {
        $tools[$t] = $null
    }
}
$result.Tools = $tools

# --- Ollama models (read-only) ---
$ollamaList = & ollama list 2>$null
if ($LASTEXITCODE -eq 0 -and $ollamaList) {
    $result.OllamaModels = ($ollamaList | Out-String).Trim()
}

# --- Human summary ---
Write-Host "=== Hardware summary ==="
Write-Host ("OS      : {0} ({1})" -f $result.OS.Caption, $result.OS.Architecture)
Write-Host ("CPU     : {0} ({1}C/{2}T)" -f $result.CPU.Name, $result.CPU.Cores, $result.CPU.LogicalProcessors)
Write-Host ("RAM     : {0} GB" -f $result.RAM_GB)
foreach ($d in $result.Disks) {
    Write-Host ("Disk    : {0} {1} GB free / {2} GB" -f $d.Drive, $d.FreeGB, $d.SizeGB)
}
if ($gpus.Count -eq 0) {
    Write-Host "GPU     : none detected"
}
else {
    foreach ($g in $gpus) {
        Write-Host ("GPU     : {0} VRAM={1} GB driver={2}" -f $g.Name, $g.VRAM_GB, $g.Driver)
    }
}
Write-Host ""
Write-Host "=== Tools ==="
foreach ($t in $toolNames) {
    if ($tools[$t]) { Write-Host ("{0}: {1}" -f $t, $tools[$t]) }
    else { Write-Host ("{0}: not found" -f $t) }
}
if ($result.OllamaModels) {
    Write-Host ""
    Write-Host "=== Ollama models ==="
    Write-Host $result.OllamaModels
}

Write-Host ""
Write-Host "=== JSON ==="
$result | ConvertTo-Json -Depth 6
