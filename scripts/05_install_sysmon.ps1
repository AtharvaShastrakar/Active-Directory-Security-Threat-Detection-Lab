<#
.SYNOPSIS
    Installs Microsoft Sysinternals Sysmon with custom telemetry configuration.
.DESCRIPTION
    Works in both connected and completely isolated/air-gapped lab environments:
    - If Sysmon.zip or Sysmon64.exe is in the current directory or $env:TEMP, it uses it directly.
    - If not present locally and internet is available, it downloads from Microsoft Sysinternals.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\..\configs\sysmonconfig.xml",
    [string]$LocalBinary = ""
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Installing Sysinternals Sysmon Telemetry Sensor        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Resolve config path
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found at: $ConfigPath"
    exit 1
}
$resolvedConfig = (Resolve-Path $ConfigPath).Path
Write-Host "[+] Using configuration file: $resolvedConfig" -ForegroundColor Green

# 1. Check if Sysmon is already installed
if (Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue) {
    Write-Host "[+] Sysmon service is already installed. Reloading configuration..." -ForegroundColor Yellow
    $installedSysmon = if (Test-Path "C:\Windows\Sysmon64.exe") { "C:\Windows\Sysmon64.exe" } else { "C:\Windows\Sysmon.exe" }
    & $installedSysmon -c $resolvedConfig
    Write-Host "[+] Configuration successfully refreshed!" -ForegroundColor Green
    exit 0
}

# 2. Locate or Download Sysmon binary
$sysmonExe = $null

# Check candidate paths for pre-copied binary
$candidates = @(
    $LocalBinary,
    "$PSScriptRoot\Sysmon64.exe",
    "$PSScriptRoot\Sysmon.exe",
    "$env:TEMP\Sysmon\Sysmon64.exe",
    "$env:TEMP\Sysmon\Sysmon.exe"
)

foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) {
        $sysmonExe = $c
        Write-Host "[+] Found local Sysmon executable at: $sysmonExe" -ForegroundColor Green
        break
    }
}

# If not found locally, attempt download
if (-not $sysmonExe) {
    Write-Host "[+] No local Sysmon executable found. Attempting download from Microsoft..." -ForegroundColor Yellow
    $zipPath = "$env:TEMP\Sysmon.zip"
    $extractDir = "$env:TEMP\Sysmon"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile $zipPath -TimeoutSec 15
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $sysmonExe = if ([Environment]::Is64BitOperatingSystem) { "$extractDir\Sysmon64.exe" } else { "$extractDir\Sysmon.exe" }
    } catch {
        Write-Warning "[-] Online download failed (typical for air-gapped / isolated VM networks)."
        Write-Host "[!] INSTRUCTIONS FOR AIR-GAPPED LAB:" -ForegroundColor Cyan
        Write-Host "    1. Download Sysmon.zip on your host or Kali VM."
        Write-Host "    2. Copy Sysmon64.exe into this folder: $PSScriptRoot"
        Write-Host "    3. Re-run .\05_install_sysmon.ps1"
        exit 1
    }
}

# 3. Install Sysmon Service
Write-Host "[+] Installing Sysmon Service with custom configuration..." -ForegroundColor Green
& $sysmonExe -i $resolvedConfig -accepteula

Start-Sleep -Seconds 2
$svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host "[+] Sysmon is RUNNING and logging high-fidelity endpoint events!" -ForegroundColor Green
    Write-Host "[+] Target Log: Event Viewer -> Applications and Services Logs -> Microsoft -> Windows -> Sysmon -> Operational" -ForegroundColor Cyan
} else {
    Write-Warning "[-] Sysmon installed but service is not running. Check Windows Application logs."
}
