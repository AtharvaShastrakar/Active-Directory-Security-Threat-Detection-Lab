# EDR Evasion & Telemetry Blind-Spot Testing Guide

This guide breaks down modern Endpoint Detection & Response (EDR) architecture, user-mode hooking mechanisms, and the primary bypass techniques tested in offensive adversary emulation.

---

## 1. How EDRs Monitor Process Execution

Most commercial EDR agents (CrowdStrike Falcon, SentinelOne, Microsoft Defender for Endpoint, Carbon Black) operate using a hybrid model:

```
+-------------------------------------------------------------------+
|                        USER MODE (Ring 3)                         |
|                                                                   |
|   Attacker / Malware (e.g., powershell.exe, custom_agent.exe)     |
|          │                                                        |
|          ▼                                                        |
|   Win32 APIs (kernel32.dll, advapi32.dll)                         |
|          │                                                        |
|          ▼                                                        |
|   ntdll.dll ──────────▶ [ EDR Injected Hook: JMP to edr.dll ]     |
|          │                     │                                  |
|          │                     ▼ (Inspect arguments & call stack) |
|          │               Blocked? (Alert / Terminate)             |
|          ▼                                                        |
|   SYSCALL (e.g. NtCreateThreadEx, NtAllocateVirtualMemory)        |
+──────────────────────────────────┼────────────────────────────────+
|                                  ▼                                |
|                       KERNEL MODE (Ring 0)                        |
|                                                                   |
|   Kernel Executive / SSDT                                         |
|   Kernel Callbacks (PsSetCreateProcessNotifyRoutine, etc.)        |
+-------------------------------------------------------------------+
```

1. **User-Mode Hooking**: During process startup, the EDR injects its sensor DLL (`edrdll.dll`). It modifies the initial bytes of critical system functions inside `ntdll.dll` (like `NtWriteVirtualMemory`, `NtProtectVirtualMemory`, `NtCreateThreadEx`, `NtOpenProcess`) with an unconditional `JMP` instruction pointing to the EDR's inspection routine.
2. **Kernel Callbacks**: The EDR kernel driver monitors thread creation, process creation, image loads (`PsSetLoadImageNotifyRoutine`), and object handle creation (`ObRegisterCallbacks`).
3. **AMSI & ETW**: In-process scanning interfaces in Windows for scripting runtimes (PowerShell, VBScript, .NET, JScript).

---

## 2. Practical EDR Evasion Techniques & Proofs-of-Concept

### Technique 1: In-Memory AMSI Patching (`AmsiScanBuffer`)

**Mechanism**:
AMSI checks script blocks by sending memory buffers to Defender/EDR via `amsi.dll!AmsiScanBuffer`. If an attacker patches the beginning of `AmsiScanBuffer` to immediately return `AMSI_RESULT_CLEAN` (`0x80070057` / `E_INVALIDARG`), all subsequent commands bypass inspection.

**Testing in PowerShell (Run on CLIENT01)**:
```powershell
# Standard test: AMSI triggers and blocks this string:
'amsiutils'

# In-Memory Patch using Reflection to write return code directly into AmsiScanBuffer:
$Amsi = [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils')
$Field = $Amsi.GetField('amsiInitFailed','NonPublic,Static')
$Field.SetValue($null,$true)

# Now test again - the block string will no longer trigger:
'amsiutils'
Write-Host "[+] AMSI telemetry successfully blinded in current process!" -ForegroundColor Green
```

---

### Technique 2: ETW (Event Tracing for Windows) Patching (`EtwEventWrite`)

**Mechanism**:
PowerShell Script Block Logging (Event ID 4104) and CLR assembly loading telemetry depend on `ntdll.dll!EtwEventWrite`. By patching the entry point of `EtwEventWrite` with a `RET` (`0xC3`) instruction, no events are sent to ETW consumers (including Sysmon and EDR).

**PowerShell Implementation Concept**:
```powershell
# Resolving NtDll EtwEventWrite and overwriting the first byte with RET (0xC3)
$ntdll = [System.Runtime.InteropServices.Marshal]::GetHINSTANCE('ntdll.dll')
# Target: EtwEventWrite
# Byte 0xC3 (RET) causes immediate return before ETW trace can emit.
```

---

### Technique 3: ntdll.dll Unhooking (Fresh ntdll from Disk)

**Mechanism**:
Because EDR hooks reside exclusively in the **memory-mapped** copy of `ntdll.dll` inside the process address space, an attacker can:
1. Open `C:\Windows\System32\ntdll.dll` from disk using `CreateFile` / `MapViewOfFile`.
2. Locate the `.text` section (executable code).
3. Overwrite the in-memory `.text` section of `ntdll.dll` using `VirtualProtect` (or `NtProtectVirtualMemory`).
4. This completely wipes out all EDR `JMP` hooks, restoring pristine syscall stubs!

```
[ In-Memory ntdll.dll ]              [ Fresh Disk ntdll.dll ]
NtCreateThreadEx:                     NtCreateThreadEx:
  JMP EDR_Sensor_Inspect   <--OVERWRITE--   mov r10, rcx
                                            mov eax, 0xC2
                                            syscall
                                            ret
```

---

### Technique 4: Direct & Indirect System Calls (SysWhispers / DInvoke)

**Mechanism**:
Rather than calling high-level APIs (`VirtualAllocEx`, `WriteProcessMemory`, `CreateRemoteThread`) which step through hooked `ntdll.dll` routines, the offensive binary contains its own assembly implementation of the syscall instructions.

- **Direct Syscalls**: Places `syscall` directly inside the offensive executable.
  - *EDR Detection*: EDR inspects the Call Stack of the syscall. If the `syscall` instruction does not return from within the address space of `ntdll.dll`, the EDR flags this as an anomaly (unbacked syscall).
- **Indirect Syscalls (e.g. SysWhispers3 / Halo's Gate)**:
  - The binary prepares the syscall register (`eax = SystemCallID`), but jumps into a legitimate `syscall ; ret` instruction located inside `ntdll.dll`.
  - The RIP points inside `ntdll.dll`, completely satisfying RIP call stack checks!

---

### Technique 5: Process Injection & Telemetry Evasion

Common process injection vectors and their corresponding EDR triggers:

| Injection Technique | Mechanism | EDR Telemetry Trigger | Evasion Method |
| :--- | :--- | :--- | :--- |
| **Classic Remote Thread** | `OpenProcess` -> `VirtualAllocEx` (`RWX`) -> `WriteProcessMemory` -> `CreateRemoteThread` | Kernel callback `CreateThreadNotify` + `PAGE_EXECUTE_READWRITE` memory allocation | Allocate `PAGE_READWRITE`, write payload, convert to `PAGE_EXECUTE_READ` (`RX`), avoid RWX. |
| **Process Hollowing** | Spawn suspended process (`CreateProcessW` with `CREATE_SUSPENDED`), unmap image, write payload, resume thread | Parent-child relationship mismatch, unmapped base address | Early Bird APC Injection or Process Doppelgänging. |
| **Early Bird APC** | Create suspended process, queue User APC (`QueueUserAPC`) before main thread starts, resume | APC executes before EDR DLL is even injected/hooked | Bypasses user-mode hooks completely because hook injection hasn't occurred yet! |

---

## 3. Telemetry Verification Checklist

When testing these techniques in your lab, verify:
1. **Did Sysmon log Event ID 10 (ProcessAccess) against `lsass.exe`?**
2. **Did Event ID 4688 catch the decoded PowerShell command line or just the base64 encoded wrapper?**
3. **Did Script Block Logging (Event ID 4104) fire before and after AMSI patching?**
4. **Did the EDR / Sysmon detect remote thread creation (Event ID 8)?**
