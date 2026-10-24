# Multi-VM Active Directory Lab & Red Team Emulation Framework

A production-grade, reproducible laboratory environment built to simulate real-world Active Directory attack paths, lateral movement techniques, and EDR detection/evasion mechanics.

---

## 1. Architecture & Network Topology

```
+---------------------------------------------------------------------------------------+
|                                    HOST MACHINE                                       |
|  - Apple Silicon (M4 / 16 GB RAM) or x86_64 PC                                        |
|  - Virtualization Hypervisor: UTM / VirtualBox                                        |
+───────────────────────────────────────────┬───────────────────────────────────────────+
                                            │
                                            ▼
+---------------------------------------------------------------------------------------+
|                    ISOLATED INTERNAL NETWORK (192.168.56.0/24)                         |
|  - VirtualBox: "Internal Network" (e.g. `ad-lab-net`)                                 |
|  - UTM: "Host Only" or "VLAN / Internal Isolated"                                     |
|  - No bridged external access (Air-gapped attack simulation)                          |
+───────┬───────────────────────────┬───────────────────────────┬───────────────────────+
        │                           │                           │                       │
        ▼                           ▼                           ▼                       ▼
+───────────────+           +───────────────+           +───────────────+       +───────────────+
|     DC01      |           |   CLIENT01    |           |   CLIENT02    |       |  MON01 / KALI |
| 192.168.56.10 |           | 192.168.56.20 |           | 192.168.56.21 |       | 192.168.56.50 |
|               |           |               |           |               |       |               |
| Windows Server|           | Windows Client|           | Windows Client|       |  Kali Linux   |
| AD DS & DNS   |           | Domain Joined |           | Domain Joined |       | Attacker/SIEM |
| Domain Forest |           | Workstation   |           | Workstation   |       | Telemetry Hub |
| `adlab.test`  |           |               |           |               |       |               |
+───────────────+           +───────────────+           +───────────────+       +───────────────+
```

---

## 2. Resource Allocation Matrix (16 GB Host RAM Budget)

To ensure smooth performance without exhausting host memory on a 16 GB system:

| VM Name | Role | Recommended vCPUs | Recommended RAM | Storage | Static IP |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **DC01** | Primary Domain Controller & DNS | 2 vCPUs | **3.5 GB - 4 GB** | 40 GB | `192.168.56.10` |
| **CLIENT01** | Domain Workstation (Initial Compromise) | 2 vCPUs | **3.5 GB - 4 GB** | 40 GB | `192.168.56.20` |
| **CLIENT02** | Lateral Target Workstation | 2 vCPUs | **3.0 GB** *(or start on demand)* | 35 GB | `192.168.56.21` |
| **KALI** | Offensive Machine / Telemetry Collector | 2 vCPUs | **2.5 GB - 3 GB** | 30 GB | `192.168.56.50` |
| **Host macOS**| Reserved for Operating System | - | **2.5 GB - 3.0 GB** | - | - |

> [!TIP]
> **Pro Tip for 16 GB RAM**: You can keep `CLIENT02` powered off during Phase 1 & 2. Only boot `CLIENT02` when executing lateral movement from `CLIENT01` to `CLIENT02`.

---

## 3. Apple Silicon (M-Series) vs VirtualBox Compatibility

If running on Apple Silicon (M1/M2/M3/M4):
- **VirtualBox limitation**: Standard x86_64 Windows ISOs do not run with hardware acceleration under VirtualBox on Apple Silicon.
- **Recommended Hypervisor for Mac**: **UTM** (already installed in `/Applications/UTM.app`) or **VMware Fusion Pro**.
- **Guest OS Images**:
  - **Kali Linux**: `kali-linux-2026.2-installer-arm64.iso` (already present in `~/Downloads`).
  - **Windows Server**: Windows Server 2025 ARM64 Evaluation VHDX/ISO.
  - **Windows Client**: Windows 11 ARM64 (downloadable directly via UTM's built-in Windows installer gallery or CrystalFetch).

If running on an Intel/AMD Windows or Linux PC, Oracle VirtualBox 7.x runs both standard x86 Windows Server 2022 and Windows 10/11 flawlessly.

---

## 4. End-to-End Build Process (Phases 1 to 4)

### Phase 1 — Host & Network Setup
1. Open your hypervisor (UTM or VirtualBox).
2. Configure a dedicated internal virtual network:
   - In VirtualBox: Set Network Adapter 1 on all VMs to **Internal Network** (Name: `ad-lab-net`).
   - In UTM: Configure network mode to **Host Only** or **Isolated Virtual VLAN**.
3. Confirm host disk space (>60 GB recommended).

---

### Phase 2 — Build Domain Controller (DC01)
1. Install Windows Server. Set the local administrator password (e.g., `P@ssw0rd2026!AD`).
2. Open PowerShell as Administrator. Run `scripts/01_setup_dc.ps1`:
   ```powershell
   .\scripts\01_setup_dc.ps1
   ```
   - Sets static IP `192.168.56.10` and DNS `127.0.0.1`.
   - Installs AD DS, RSAT, and DNS.
   - Promotes server to new forest: `adlab.test`.
   - Automatically reboots.
3. After reboot, log in as `ADLAB\Administrator`. Run `scripts/02_populate_ad_environment.ps1`:
   ```powershell
   .\scripts\02_populate_ad_environment.ps1
   ```
   - Creates corporate OUs (`Corp`, `Users`, `Finance`, `IT_Admins`, `ServiceAccounts`).
   - Generates simulated users (`asmith`, `jdoe`, `bwayne`).
   - Registers Kerberoasting target: `svc_sql` (with SPN `MSSQLSvc/dc01.adlab.test:1433`).
   - Configures AS-REP Roasting target: `svc_backup` (`DoesNotRequirePreAuth = $True`).
   - Creates simulated sensitive SMB share (`\\DC01\FinanceShare\db_notes.txt`).

---

### Phase 3 — Configure Domain Endpoints (CLIENT01 & CLIENT02)
1. Install Windows Client OS on `CLIENT01` and `CLIENT02`.
2. On `CLIENT01`, open PowerShell as Administrator and run:
   ```powershell
   .\scripts\03_client_setup.ps1 -ComputerName "CLIENT01" -ClientIP "192.168.56.20"
   ```
3. On `CLIENT02`, open PowerShell as Administrator and run:
   ```powershell
   .\scripts\03_client_setup.ps1 -ComputerName "CLIENT02" -ClientIP "192.168.56.21"
   ```
4. Enter `ADLAB\Administrator` credentials when prompted. The machines will reboot into the domain.
5. Verify domain logins work with `ADLAB\asmith` or `ADLAB\bwayne`.

---

### Phase 4 — Deploy Detection, Telemetry & Auditing
1. On **DC01**, **CLIENT01**, and **CLIENT02**, run `scripts/04_configure_audit_policies.ps1`:
   - Enables Command Line logging for Process Creation (Event ID 4688).
   - Enables PowerShell Script Block Logging (Event ID 4104).
   - Enables Kerberos ticket auditing (Event IDs 4768, 4769).
2. Install Sysmon on endpoints using `scripts/05_install_sysmon.ps1`:
   ```powershell
   .\scripts\05_install_sysmon.ps1
   ```
   - Monitors LSASS dumping, LOLBINs, named pipes, and suspicious parent-child process chains.
3. **Take Clean Snapshots** of all VMs in the hypervisor before launching attacks!

---

## 5. Repository Structure

```
Active Directory Lab & Red Team Emulation/
├── README.md                                # Complete blueprint and deployment guide
├── scripts/
│   ├── 01_setup_dc.ps1                      # Automated DC promotion & static IP config
│   ├── 02_populate_ad_environment.ps1       # Populates realistic OUs, users, SPNs, & preauth flaw
│   ├── 03_client_setup.ps1                  # Configures client IP, DNS, and joins adlab.test
│   ├── 04_configure_audit_policies.ps1      # Enables command-line, PowerShell & Kerberos auditing
│   └── 05_install_sysmon.ps1                # Installs Sysmon with custom threat detection rules
├── configs/
│   └── sysmonconfig.xml                     # Custom Sysmon configuration tuned for offensive telemetry
├── redteam/
│   ├── lateral_movement_playbook.md         # Step-by-step Kali attack commands (AS-REP, Kerberoast, PtH, WinRM)
│   └── edr_evasion_techniques.md            # Deep dive on AMSI/ETW patching, unhooking, and syscalls
└── detection/
    └── detection_engineering_guide.md       # Splunk / Elastic SIEM rules & Windows Event ID mapping
```

---

## 6. Execution & Testing Workflow

1. Consult [`redteam/lateral_movement_playbook.md`](file:///Users/atharvadnyaneshwarshastrakar/Desktop/Active%20Directory%20Lab%20%26%20Red%20Team%20Emulation/redteam/lateral_movement_playbook.md) to execute:
   - Initial domain reconnaissance.
   - AS-REP Roasting & Kerberoasting hash extraction and offline cracking.
   - Pass-the-Hash lateral movement with `impacket-wmiexec` or `evil-winrm`.
2. Consult [`redteam/edr_evasion_techniques.md`](file:///Users/atharvadnyaneshwarshastrakar/Desktop/Active%20Directory%20Lab%20%26%20Red%20Team%20Emulation/redteam/edr_evasion_techniques.md) to test:
   - AMSI memory patching.
   - ETW blinding.
   - DLL unhooking and syscall evasion.
3. Consult [`detection/detection_engineering_guide.md`](file:///Users/atharvadnyaneshwarshastrakar/Desktop/Active%20Directory%20Lab%20%26%20Red%20Team%20Emulation/detection/detection_engineering_guide.md) to inspect:
   - Windows Event Viewer and Sysmon operational logs.
   - Correlate attack timestamps with generated telemetry.
