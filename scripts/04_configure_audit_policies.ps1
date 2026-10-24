<#
.SYNOPSIS
    Configures advanced Windows Auditing & PowerShell Telemetry for Red Team detection.
.DESCRIPTION
    Enables:
    - Process Creation with Command-Line Auditing (Event ID 4688)
    - PowerShell Script Block Logging (Event ID 4104) & Module Logging (Event ID 4103)
    - Kerberos Authentication & Service Ticket Auditing (Event IDs 4768, 4769, 4771)
    - Logon & Privilege Escalation Auditing (Event IDs 4624, 4672, 4625)
#>

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Configuring Windows Security Audit Policies            " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Enable Advanced Audit Policies using auditpol
$auditPolCommands = @(
    "auditpol /set /subcategory:`"Process Creation`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Process Termination`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Logon`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Logoff`" /success:enable /failure:disable",
    "auditpol /set /subcategory:`"Special Logon`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Other Logon/Logoff Events`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Kerberos Authentication Service`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Kerberos Service Ticket Operations`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Sensitive Privilege Use`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Security Group Management`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"User Account Management`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Directory Service Access`" /success:enable /failure:enable",
    "auditpol /set /subcategory:`"Directory Service Changes`" /success:enable /failure:enable"
)

foreach ($cmd in $auditPolCommands) {
    Invoke-Expression $cmd | Out-Null
}
Write-Host "[+] Advanced audit subcategories configured successfully." -ForegroundColor Green

# 2. Enable Command Line Logging for Process Creation (Event 4688)
$regAudit = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
if (-not (Test-Path $regAudit)) {
    New-Item -Path $regAudit -Force | Out-Null
}
Set-ItemProperty -Path $regAudit -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord
Write-Host "[+] Enabled Process Creation Command Line Auditing (Event ID 4688)." -ForegroundColor Green

# 3. Enable PowerShell Script Block Logging & Module Logging
$regPS = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $regPS)) {
    New-Item -Path $regPS -Force | Out-Null
}
Set-ItemProperty -Path $regPS -Name "EnableScriptBlockLogging" -Value 1 -Type DWord

$regPSMod = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
if (-not (Test-Path $regPSMod)) {
    New-Item -Path $regPSMod -Force | Out-Null
}
Set-ItemProperty -Path $regPSMod -Name "EnableModuleLogging" -Value 1 -Type DWord

$regPSModNames = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames"
if (-not (Test-Path $regPSModNames)) {
    New-Item -Path $regPSModNames -Force | Out-Null
}
Set-ItemProperty -Path $regPSModNames -Name "*" -Value "*" -Type String
Write-Host "[+] Enabled PowerShell Script Block Logging (Event ID 4104) and Module Logging." -ForegroundColor Green

# 4. Enlarge Security Event Log size to prevent wrapping during simulations
Limit-EventLog -LogName Security -MaximumSize 200MB -OverflowAction OverwriteAsNeeded
Limit-EventLog -LogName "Microsoft-Windows-PowerShell/Operational" -MaximumSize 100MB -OverflowAction OverwriteAsNeeded
Write-Host "[+] Expanded Security and PowerShell Operational Event Log capacities." -ForegroundColor Green
