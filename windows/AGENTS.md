# Zapret2agent Windows — Agent Integration Contract

## Purpose
AI-agent for DPI bypass configuration on Windows using zapret-win-bundle (winws2 + WinDivert). Non-technical users describe their problem; the agent configures zapret correctly.

## Platform
**Windows 10 x64+ / Windows 11.** Not Linux, not macOS.

## Compatible Agents
- Claude Code (`claude` CLI)
- OpenAI Codex CLI (`codex`)
- Any agent that reads CLAUDE.md and supports skill invocation

## Essential Read-Only Commands
Safe to run without confirmation:
```powershell
sc query winws2                                    # service status
Get-Service winws2 -ErrorAction SilentlyContinue  # PowerShell service check
Get-Content C:\zapret\config\zapret.conf           # current config
Get-Content C:\zapret\config\mode.txt              # current mode
Get-NetAdapter | Select Name,Status,InterfaceDescription  # network adapters
(Get-WmiObject Win32_OperatingSystem).Caption      # OS version
[System.Environment]::Is64BitOperatingSystem       # arch check
```

## Critical Safety Mandates

1. **Always diagnose first** — run `detect-state.ps1` before any install/config operation
2. **Confirm before privileged ops** — `sc create/delete`, `netsh`, registry writes
3. **Backup before config change** — run `backup-config.ps1` first, always
4. **Rollback timer** — deploy `safe-mode.ps1` before applying new firewall/service config
5. **Admin check** — if `is_admin: false`, stop and tell user to re-run as Administrator
6. **Antivirus warning** — always remind user to add `C:\zapret` to AV exclusions before install

## Supported Operations

### Diagnose
- Detect Windows version, arch, PowerShell version
- Check if zapret is installed and where
- Check winws2 service status
- Detect active VPN (WireGuard, OpenVPN, etc.)
- Check DNS hijacking
- List network adapters

### Install / Upgrade
- Download latest zapret-win-bundle from GitHub
- Extract to `C:\zapret\`
- Create `config\` and `logs\` directories
- Create `winws2` Windows service
- Verify installation

### Configure
- Run blockcheck2 (tests bypass strategies)
- Parse results and recommend strategy
- Apply strategy to `C:\zapret\config\zapret.conf`
- Recreate service with new config
- Rollback if strategy fails

### Manage Domains
- Add/remove domains from `C:\zapret\zapret-winws\files\user-hostlist.txt`
- Merge seed list
- Restart service to apply

### Switch Modes
- **Direct**: zapret → internet (bypass only)
- **Tunnel**: zapret → VPN → internet (bypass + VPN protection)

## Validation Framework

Before reporting success, verify:
- `sc query winws2` returns `RUNNING`
- `C:\zapret\config\zapret.conf` exists and is non-empty
- WinDivert64.sys present at `C:\zapret\zapret-winws\WinDivert64.sys`
- No errors in `C:\zapret\logs\winws2.log` (last 20 lines)
