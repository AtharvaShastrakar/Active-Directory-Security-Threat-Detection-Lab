<#
.SYNOPSIS
    Automated Active Directory Domain Controller Configuration for DC01.
.DESCRIPTION
    Phase 1: Configures static IP, DNS, and renames computer to DC01 (requires reboot if renamed).
    Phase 2: Installs AD-Domain-Services and DNS roles, and promotes to Forest Root: adlab.test.
.NOTES
    Run as Administrator in an elevated PowerShell session.
#>

[CmdletBinding()]
param(
    [string]$DomainName = "adlab.test",
    [string]$NetbiosName = "ADLAB",
    [string]$IPAddress = "192.168.56.10",
    [int]$PrefixLength = 24,
    [string]$Gateway = "192.168.56.1",
    [string]$NewComputerName = "DC01",
    [securestring]$SafeModePassword = (ConvertTo-SecureString "P@ssw0rd2026!AD" -AsPlainText -Force)
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 1: DC01 Network Configuration & Computer Name    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Identify active network adapter
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.InterfaceDescription -match 'Ethernet|VirtIO|Intel|Broadcom' } | Select-Object -First 1

if (-not $adapter) {
    $adapter = Get-NetAdapter | Select-Object -First 1
}

if ($adapter) {
    Write-Host "[+] Found Adapter: $($adapter.Name) ($($adapter.InterfaceDescription))" -ForegroundColor Green
    
    # Check if IP is already configured
    $currentIP = (Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($currentIP -notcontains $IPAddress) {
        Write-Host "[+] Removing temporary DHCP/conflicting addresses..." -ForegroundColor Yellow
        Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false

        Write-Host "[+] Assigning Static IP: $IPAddress / $PrefixLength" -ForegroundColor Green
        New-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway -ErrorAction SilentlyContinue
    } else {
        Write-Host "[+] Static IP $IPAddress is already assigned." -ForegroundColor Green
    }

    # Set DNS to loopback for Domain Controller
    Write-Host "[+] Setting DNS Server to 127.0.0.1 (Localhost)" -ForegroundColor Green
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses ("127.0.0.1", "1.1.1.1")
} else {
    Write-Warning "[-] No active network adapter found! Please check VM network settings."
}

# 2. Check if Computer Name is DC01
if ($env:COMPUTERNAME -ne $NewComputerName) {
    Write-Host "[!] Computer name is currently '$env:COMPUTERNAME'. Renaming to '$NewComputerName'..." -ForegroundColor Yellow
    Rename-Computer -NewName $NewComputerName -Force
    Write-Host "[!] A REBOOT IS REQUIRED to apply the new computer name before promoting to Domain Controller." -ForegroundColor Red
    Write-Host "[!] System will reboot in 10 seconds. After reboot, simply run this script once more to complete DC promotion." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    exit 0
} else {
    Write-Host "[+] Hostname verified as $NewComputerName. Proceeding to AD DS promotion..." -ForegroundColor Green
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 2: Installing AD DS & DNS Windows Features       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$features = @("AD-Domain-Services", "RSAT-AD-Tools", "DNS")
foreach ($feature in $features) {
    $check = Get-WindowsFeature -Name $feature
    if (-not $check.Installed) {
        Write-Host "[+] Installing feature: $feature..." -ForegroundColor Yellow
        Install-WindowsFeature -Name $feature -IncludeManagementTools | Out-Null
    } else {
        Write-Host "[+] Feature $feature is already installed." -ForegroundColor Green
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   STAGE 3: Promoting to Forest Root Domain Controller    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Check if already a Domain Controller
$isDC = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq 2
if ($isDC) {
    Write-Host "[+] This system is already a Domain Controller for $DomainName." -ForegroundColor Green
    exit 0
}

Write-Host "[+] Promoting server to new Active Directory Forest: $DomainName (NetBIOS: $NetbiosName)..." -ForegroundColor Yellow
Write-Host "[!] Server will reboot automatically upon completion." -ForegroundColor Green

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -ForestMode "WinThreshold" `
    -DomainMode "WinThreshold" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword $SafeModePassword `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true
