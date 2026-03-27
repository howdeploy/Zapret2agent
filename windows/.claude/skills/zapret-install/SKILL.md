# Skill: zapret-install

Download zapret-win-bundle, extract to C:\zapret, create Windows service.

## Prerequisites
- Must be running as Administrator (`is_admin: true` from detect-state.ps1)
- User must have added C:\zapret to antivirus exclusions first

## Pre-check prompt to user
Before running anything:
> "Прежде чем начать — важно: добавь папку C:\zapret в исключения антивируса. Иначе он удалит WinDivert64.sys и ничего не заработает.
> [Windows Defender: Параметры → Безопасность Windows → Защита от вирусов → Исключения → Добавить папку → C:\zapret]
> Готово? Отвечай Да/Нет."

Wait for confirmation before proceeding.

## Phase 1: Pre-flight check
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-install\scripts\check-install-ready.ps1
```
Check output:
- `ready: true` → proceed
- `ready: false` → show `blockers` list to user, fix before continuing

## Phase 2: Download + Extract

Show user:
> "Скачиваю zapret-win-bundle с GitHub (~5-10 МБ). Это займёт несколько секунд."

Show command, confirm, then run:
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-install\scripts\download-bundle.ps1
```

Output fields:
- `downloaded_to`: temp zip path
- `extracted_to`: C:\zapret
- `version`: release tag

## Phase 3: Create service

Show user:
> "Создаю службу Windows (winws2). Она будет запускаться автоматически при старте системы."

Show the sc.exe command, confirm, run:
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-install\scripts\create-service.ps1
```

This creates the service with a default/minimal config. Full strategy config happens via zapret-config skill.

## Phase 4: Verify
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-install\scripts\verify-install.ps1
```

Output:
- `success: true` → report to user, suggest running zapret-config next
- `success: false` → show `errors` list

## Upgrade Mode
If zapret is already installed (`zapret_installed: true` from detect-state):
1. Stop service: `sc stop winws2`
2. Backup config: run `backup-config.ps1`
3. Download new bundle
4. Extract (overwrites binaries, NOT config/)
5. Restart service
6. Verify

## Service Creation Details
The service runs winws2.exe as a Windows service using the config in `C:\zapret\config\zapret.conf`.

After install, config will contain a minimal default:
```
--wf-tcp=80,443 --wf-udp=443
```
Run zapret-config to find the optimal strategy via blockcheck.

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Extract fails / files missing after extract | Antivirus deleted WinDivert | Add exclusion, re-extract |
| Service fails to start | Not admin | Re-run as Administrator |
| Download fails | No internet / GitHub blocked | Check connection; try with VPN |
| `sc create` error 1073 | Service already exists | Run `sc delete winws2` first |
