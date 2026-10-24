# Detection Engineering & Telemetry Analysis Guide

This guide maps each attack simulation step to specific Windows Event IDs, Sysmon records, and SIEM correlation queries (Splunk SPL and Elastic KQL).

---

## 1. Attack to Event ID Mapping Matrix

| Attack / Technique | Primary Event IDs | Provider / Source | Critical Artifacts / Fields |
| :--- | :--- | :--- | :--- |
| **Kerberoasting** | `4769` | Microsoft-Windows-Security-Auditing | `ServiceName` != `$*`, `TicketEncryptionType = 0x17`, `TicketOptions = 0x40810000` |
| **AS-REP Roasting** | `4768` | Microsoft-Windows-Security-Auditing | `PreAuthType = 0`, `TicketEncryptionType = 0x17` |
| **Pass-the-Hash (WMI)** | `4624`, Sysmon `1` | Security / Sysmon | `LogonType = 3`, `AuthenticationPackageName = NTLM`, `KeyLength = 0`, Parent: `wmiprvse.exe` |
| **PsExec Service Creation** | `7045`, Sysmon `17`/`18` | System / Sysmon | Service Name, ImagePath pointing to `C:\Windows\*`, Named Pipe: `\psexec*` |
| **WinRM Execution** | `4624`, Sysmon `1` | Security / Sysmon | `LogonType = 3`, Parent: `wsmprovhost.exe` -> `powershell.exe` |
| **LSASS Memory Dumping** | Sysmon `10` | Microsoft-Windows-Sysmon | `TargetImage` contains `lsass.exe`, `GrantedAccess` includes `0x1010` or `0x1FFFFF` |
| **PowerShell Malicious Commands**| `4104` | Microsoft-Windows-PowerShell | `ScriptBlockText` containing AMSI bypass strings, `DownloadString`, `IEX` |

---

## 2. Detection Queries (SIEM / Log Analysis)

### Detection 1: Kerberoasting Request Detection

#### Splunk SPL:
```spl
index=windows EventCode=4769 ServiceName!="*$*" TicketEncryptionType="0x17" TicketOptions="0x40810000"
| stats count dc(ServiceName) as distinct_services by src_ip, TargetUserName
| where count > 2
```

#### Elastic KQL:
```kql
event.code: "4769" and not winlog.event_data.ServiceName: *\$ and winlog.event_data.TicketEncryptionType: "0x17"
```

---

### Detection 2: AS-REP Roasting (No Pre-Authentication)

#### Splunk SPL:
```spl
index=windows EventCode=4768 PreAuthType="0" TicketEncryptionType="0x17"
| table _time, TargetUserName, IpAddress, TicketOptions
```

#### Elastic KQL:
```kql
event.code: "4768" and winlog.event_data.PreAuthType: "0" and winlog.event_data.TicketEncryptionType: "0x17"
```

---

### Detection 3: WMI Lateral Movement (wmiprvse.exe Spawning Shells)

#### Splunk SPL:
```spl
index=sysmon EventCode=1 ParentImage="*\\wmiprvse.exe" (Image="*\\cmd.exe" OR Image="*\\powershell.exe")
| table _time, Computer, ParentCommandLine, CommandLine, User
```

#### Elastic KQL:
```kql
event.code: "1" and process.parent.name: "wmiprvse.exe" and process.name: ("cmd.exe" or "powershell.exe")
```

---

### Detection 4: LSASS Access / Credential Dumping (Sysmon Event 10)

#### Splunk SPL:
```spl
index=sysmon EventCode=10 TargetImage="*\\lsass.exe" GrantedAccess IN ("0x1010", "0x1000", "0x1FFFFF", "0x1410")
| table _time, Computer, SourceImage, CallTrace, GrantedAccess
```

#### Elastic KQL:
```kql
event.code: "10" and winlog.event_data.TargetImage: "*\\lsass.exe" and winlog.event_data.GrantedAccess: ("0x1010" or "0x1000" or "0x1FFFFF" or "0x1410")
```

---

## 3. Telemetry Verification Script (Run on DC or Client)

Use this quick PowerShell command on the target VM to verify if an event triggered during testing:

```powershell
# Check for Kerberoasting events (Event 4769)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4769} -MaxEvents 5 | Format-List TimeCreated, Message

# Check for AS-REP Roasting events (Event 4768 with PreAuthType 0)
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4768} -MaxEvents 5 | Format-List TimeCreated, Message

# Check for Sysmon LSASS access (Event 10)
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational'; Id=10} -MaxEvents 5 | Format-List TimeCreated, Message
```
