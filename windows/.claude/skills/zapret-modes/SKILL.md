# Skill: zapret-modes

Switch between Direct mode (zapret only) and Tunnel mode (zapret + VPN).

## Modes Explained

### Direct Mode
```
[Your PC] → zapret (DPI bypass) → Internet
```
- Use for: YouTube, Telegram, Discord, other blocked sites that don't need full VPN
- zapret модифицирует пакеты, ТСПУ не может их заблокировать
- **Limitation**: does NOT bypass whitelist-based blocking (белые списки)

### Tunnel Mode
```
[Your PC] → zapret (DPI bypass) → VPN Server → Internet
```
- Use for: when VPN itself gets blocked/throttled (провайдер режет VPN соединение)
- zapret helps the initial VPN handshake packets pass through
- After VPN connects — full VPN tunnel is active

## Check Current Mode
Read `C:\zapret\config\mode.txt`. Values: `direct` or `tunnel`.

Also confirm with user what they're trying to achieve:
> "Что ты хочешь сделать?
> 1. Просто открыть YouTube/Telegram/Discord — тогда нужен Direct режим
> 2. Подключить VPN, который провайдер блокирует — тогда Tunnel режим"

## Switching to Direct Mode

### 1. Check state
Run `detect-state.ps1`. Note `vpn_detected` and `current_mode`.

### 2. Update config
Append `--autohostlist` for broad bypass, or ensure hostlist is populated:
```powershell
$newArgs = "--wf-tcp=80,443 --wf-udp=443,50000-65535 --lua=zapret-lib.lua --lua=zapret-antidpi.lua --lua-desync=split2"
$newArgs | Set-Content "C:\zapret\config\zapret.conf" -Encoding UTF8
"direct" | Set-Content "C:\zapret\config\mode.txt" -Encoding UTF8
```

### 3. Restart service
```powershell
sc stop winws2
sc start winws2
```

### 4. Verify
Run `health-check.ps1`. Confirm `current_mode: direct`.

---

## Switching to Tunnel Mode

### Prerequisites
- Must have a VPN client installed (WireGuard, OpenVPN, etc.)
- VPN must be configured but unable to connect due to ISP blocking

### 1. Check detected VPN
From `detect-state.ps1` → `vpn_type` and `vpn_interface`.

If no VPN detected:
> "VPN не обнаружен. Установи WireGuard или OpenVPN, настрой подключение, потом вернёмся к этому."

### 2. Identify VPN protocol
Ask user or use detected `vpn_type`:
- **WireGuard** → UDP 51820 (or custom port)
- **OpenVPN** → TCP/UDP 1194 (or custom port)
- **Other** → ask user what port VPN uses

### 3. Apply Tunnel config
For WireGuard:
```powershell
$newArgs = "--wf-tcp=80,443 --wf-udp=443,50000-65535,51820 --filter-l7=wireguard --lua=zapret-lib.lua --lua=zapret-antidpi.lua --lua-desync=fake:blob=rnd"
$newArgs | Set-Content "C:\zapret\config\zapret.conf" -Encoding UTF8
"tunnel" | Set-Content "C:\zapret\config\mode.txt" -Encoding UTF8
```

For OpenVPN:
```powershell
$newArgs = "--wf-tcp=80,443,1194 --wf-udp=443,1194,50000-65535 --lua=zapret-lib.lua --lua=zapret-antidpi.lua --lua-desync=split2"
$newArgs | Set-Content "C:\zapret\config\zapret.conf" -Encoding UTF8
"tunnel" | Set-Content "C:\zapret\config\mode.txt" -Encoding UTF8
```

Show the command, confirm with user, then apply.

### 4. Restart service + deploy rollback timer
```powershell
# Timer: 5 minutes (VPN connection needs more time to test)
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-diagnose\scripts\safe-mode.ps1 -Action arm -Minutes 5
sc stop winws2
sc start winws2
```

### 5. Test VPN connection
Tell user:
> "Запрет перезапущен в Tunnel режиме. Теперь попробуй подключиться к VPN через твой клиент (WireGuard/OpenVPN).
> Если VPN подключился — скажи 'работает', я отменю таймер.
> Если нет — через 5 минут автоматически откатится."

### 6. On success: cancel timer
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-diagnose\scripts\safe-mode.ps1 -Action cancel
```

---

## Critical Constraints

1. **Tunnel mode is for VPN bypass only** — it does NOT replace VPN
2. **White-list bypass** is not possible with zapret (neither mode)
3. **ARM64** — WireGuard filter may not work without test-signing enabled
4. **Multiple VPN clients** — only configure for the one the user actually uses

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| VPN still won't connect in Tunnel mode | Wrong port in filter | Ask user for VPN port, update `--wf-udp` |
| VPN connects but slow | zapret filtering all UDP | Add `--wf-tcp`-only rule for VPN traffic |
| Direct mode: some sites still blocked | Need autohostlist | Add `--hostlist-auto` to config |
| Mode reverted automatically | Rollback timer fired | Config didn't work — re-run blockcheck |
