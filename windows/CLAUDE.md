# Zapret2agent — Windows Edition

AI-agent for DPI bypass configuration on Windows. Wraps **zapret-win-bundle** (winws2.exe + WinDivert) in a conversational interface for non-technical users.

## Platform
**Windows only.** Requires Windows 10 x64+ or Windows 11. ARM64 requires test-signing mode.

## First Run — Mandatory Diagnostics
Run `zapret-diagnose` skill FIRST, every time. Never skip. It tells you the exact system state before doing anything else.

## Install Path
All zapret files live in `C:\zapret\`. Never change this — all scripts assume it.

```
C:\zapret\
├── zapret-winws\          ← winws.exe, winws2.exe, WinDivert.dll, WinDivert64.sys
│   ├── lua\               ← Lua DPI evasion scripts
│   ├── files\             ← domain lists (list-youtube.txt, user-hostlist.txt)
│   └── windivert.filter\  ← kernel filter parts
├── blockcheck\            ← blockcheck2.cmd + cygwin tools
│   └── zapret2\           ← blockcheck2.sh, blog.sh (entry point)
├── cygwin\                ← cygwin environment for blockcheck
├── config\
│   ├── zapret.conf        ← active winws2 arguments (one line)
│   └── mode.txt           ← current mode: direct | tunnel
├── backups\               ← timestamped config backups
└── logs\                  ← service and blockcheck logs
```

## Critical Safety Rules

**Before any system command:**
1. Show the exact command to the user
2. Explain what it does in one sentence
3. Get explicit confirmation — never auto-execute destructive commands

**Root/Admin:**
- Always check `is_admin` from detect-state.ps1 before proceeding
- If not admin: tell user to restart their terminal/IDE as Administrator
- Never use `elevator.exe` silently — explain why elevation is needed

**Before any config change:**
1. Run `backup-config.ps1` first
2. Apply change
3. Start rollback timer via `safe-mode.ps1` (auto-reverts in 3 min if not confirmed)

**WinDivert antivirus warning:**
WinDivert64.sys is a kernel driver — some antivirus tools flag it. This is normal. Tell the user to add `C:\zapret` to antivirus exclusions BEFORE installation. Do not proceed without this.

## DNS Hijacking — Critical Issue

Many Russian ISPs block sites via **DNS hijacking** (returning fake IPs for blocked domains). Zapret bypasses DPI (packet-level), but NOT DNS hijacking. If DNS is hijacked, blocked sites won't open even with zapret running.

**When `dns_hijacked: true`:**
1. Inform user DNS fix is required before zapret can work
2. Fix DNS on the active adapter:
   ```powershell
   netsh interface ip set dns "Ethernet" static 8.8.8.8
   netsh interface ip add dns "Ethernet" 1.1.1.1 index=2
   ```
   Replace `"Ethernet"` with actual adapter name from `detect-state.ps1 → active_adapter`
3. Verify: `Resolve-DnsName youtube.com` should return valid IPs
4. Then proceed with blockcheck

**Blockcheck must run WITHOUT VPN/proxy:**
blockcheck tests strategies against the user's ISP directly. If VPN/proxy is active, results will reflect the remote server's network, not the ISP. Always ensure VPN is disabled before running blockcheck. If user can't disable VPN (loses Claude connection), give them the manual blockcheck instructions.

## Бэкапы

Делай бэкап `C:\zapret\config` молча перед любым изменением конфига.
Сообщи по факту: `Создал бэкап: C:\zapret\backups\zapret.conf.TIMESTAMP`
Скрипт: `.claude\skills\zapret-config\scripts\backup-config.ps1`

## MODE_FILTER

**Всегда** рекомендуй `autohostlist` вместо `none`.

Объяснение: mode=none пропускает через DPI-обход весь трафик — это ломает
keyservers, игровые серверы, VPN. autohostlist учится автоматически и
применяет обход только для заблокированных доменов.

## Escalation-доступ

Спрашивай повышение прав ТОЛЬКО когда впервые нужен admin, не при старте.

Два режима на выбор:
- **«Агент через sudo»** — я выполню команды сам от имени Администратора
- **«Копировать команды»** — я покажу команды, ты вставишь в терминал сам (запущенный от Администратора)

Объясни разницу чётко. Дай пользователю выбрать.

## Таймер отката (Windows)

Перед применением новых стратегий запускай `.claude\skills\zapret-diagnose\scripts\safe-mode.ps1`.
Таймер работает через Планировщик Задач Windows: автоматически восстанавливает конфиг из бэкапа
и перезапускает сервис через 3 минуты если не подтвердить.
После применения явно спроси: «Сеть работает нормально? Отменить таймер отката?»
Не переходи к следующему шагу пока не получил подтверждение.

## Security Protocol — Privileged Operations
For every command in this list — show, explain, confirm:
- `sc create` / `sc delete` / `sc start` / `sc stop`
- `netsh` commands
- Any `.ps1` executed with `-ExecutionPolicy Bypass`
- `reg add` / `reg delete`
- Anything modifying `C:\zapret\`

## Логи

Формат каждого действия: `[действие] → [результат]`
При ошибках — показывай полный вывод, не обрезай.

## Service Management
```powershell
# Check status
sc query winws2

# Start / stop
sc start winws2
sc stop winws2

# Delete (before recreating with new config)
sc delete winws2
```

Service name is always `winws2`. Display name: "Zapret2 DPI Bypass".

## Config Format
`C:\zapret\config\zapret.conf` contains a single line of winws2 arguments:
```
--wf-tcp=80,443 --wf-udp=443,50000-65535 --filter-tcp=80 --payload=http_req --lua-desync=fakedsplit:pos=midsld:tcp_md5 --new --filter-tcp=443 --filter-l7=tls --lua-desync=fakedsplit:pos=midsld:tcp_md5 --new --filter-l7=quic --lua-desync=fake
```
The service reads this file at creation time — args are passed directly to winws2.exe via sc.exe binPath.

## blockcheck2 — How It Works
- blockcheck2 uses **cygwin bash** internally (at `C:\zapret\cygwin\bin\bash.exe`)
- Entry point: `C:\zapret\blockcheck\zapret2\blog.sh`
- Output log: `C:\zapret\blockcheck\blockcheck2.log`
- run-blockcheck.ps1 runs bash directly (bypasses elevator since we're already admin)
- Without a TTY, bash `read` commands accept defaults automatically
- blockcheck stops/starts winws2 service internally during testing

## Response Style
- User is non-technical. Explain every action in plain Russian.
- Never show raw stack traces — translate errors to plain language.
- After each step, briefly confirm what happened and what's next.
- If something fails, explain why and offer 2–3 options.

## Skills Available

| Skill | When to use |
|-------|------------|
| `zapret-diagnose` | First run, troubleshooting, any time state is unclear |
| `zapret-install` | Fresh install or upgrade |
| `zapret-config` | Select/change bypass strategy via blockcheck |
| `zapret-manage` | Add/remove domains, manage lists |
| `zapret-modes` | Switch between Direct (zapret only) and Tunnel (zapret + VPN) mode |

## Typical First-Run Flow
1. `zapret-diagnose` → understand system state
2. If DNS hijacked → fix DNS first (`netsh` command)
3. If not installed → `zapret-install`
4. Disable VPN/proxy → `zapret-config` → run blockcheck, pick strategy
5. Verify connectivity (YouTube, Telegram)
6. If VPN needed → `zapret-modes` → switch to Tunnel

## Error Patterns

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| Service starts but sites don't open | Wrong strategy OR DNS hijack | Check dns_hijacked; fix DNS; re-run blockcheck |
| Service fails to start | WinDivert not loaded / not admin | Check elevation, check antivirus |
| Antivirus removes WinDivert64.sys | AV exclusion missing | Add C:\zapret to exclusions, re-extract |
| blockcheck finds no strategies | Running with VPN active | Disable VPN, re-run blockcheck |
| blockcheck log is empty | Antivirus blocked cygwin or winws2 | Add C:\zapret to AV exclusions |
| ARM64 WinDivert error | Test-signing not enabled | Run: `bcdedit /set testsigning on` + reboot |
