<#
.SYNOPSIS
    Automated Workstation Setup & Domain Join Script for CLIENT01 / CLIENT02.
.DESCRIPTION
    Configures static IP / DNS to point to DC01 (192.168.56.10), renames
    the workstation, and joins the adlab.test domain.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [Parameter(Mandatory=$true)]
    [string]$ClientIP,

    [string]$DCIP = "192.168.56.10",
    [string]$DomainName = "adlab.test",
    [string]$Gateway = "192.168.56.1",
    [int]$PrefixLength = 24
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Configuring Network for $ComputerName                 " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Identify active network adapter
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.InterfaceDescription -match 'Ethernet|VirtIO|Intel|Broadcom' } | Select-Object -First 1

if (-not $adapter) {
    $adapter = Get-NetAdapter | Select-Object -First 1
}

if ($adapter) {
    Write-Host "[+] Configuring adapter: $($adapter.Name)" -ForegroundColor Green
    
    # Configure IP
    $currentIP = (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($currentIP -notcontains $ClientIP) {
        Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
        Write-Host "[+] Setting Static IP: $ClientIP / $PrefixLength" -ForegroundColor Yellow
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $ClientIP -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction SilentlyContinue
    }

    # Set DNS directly to DC01 (CRITICAL FOR DOMAIN JOIN)
    Write-Host "[+] Pointing DNS to Domain Controller: $DCIP" -ForegroundColor Yellow
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ($DCIP)
} else {
    Write-Error "[-] No network adapter found!"
    exit 1
}

# 2. Test DNS resolution and connectivity to DC01
Write-Host "[+] Testing connection to Domain Controller ($DCIP)..." -ForegroundColor Yellow
$ping = Test-Connection -ComputerName $DCIP -Count 2 -Quiet
if ($ping) {
    Write-Host "[+] Successfully connected to $DCIP." -ForegroundColor Green
} else {
    Write-Warning "[-] Ping to $DCIP did not respond. (Ensure DC01 is running and Windows Firewall allows ICMP, or continue if RPC/SMB are reachable)."
}

# 3. Check domain membership
$domainCheck = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
if ($domainCheck) {
    Write-Host "[+] Machine is already joined to domain: $((Get-CimInstance Win32_ComputerSystem).Domain)" -ForegroundColor Green
    exit 0
}

# 4. Join Domain
Write-Host "[+] Joining $ComputerName to domain $DomainName..." -ForegroundColor Cyan
Write-Host "[!] Please enter Domain Administrator credentials when prompted (e.g. ADLAB\Administrator):" -ForegroundColor Yellow
$cred = Get-Credential

Add-Computer -DomainName $DomainName -NewName $ComputerName -Credential $cred -Restart -Force
