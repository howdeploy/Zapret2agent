# Skill: zapret-config

Select the optimal DPI bypass strategy by running blockcheck2, then apply it.

## When to invoke
- After fresh install (no strategy configured yet)
- When current config doesn't work (sites still blocked)
- When ISP changes their DPI (strategy that worked before stopped working)
- User says "ютуб не открывается" / "телега не работает"

## CRITICAL: Check for DNS hijacking first

If `detect-state.ps1` shows `dns_hijacked: true`:
> "Провайдер подменяет DNS для заблокированных сайтов. Zapret работает на уровне пакетов и **не обходит DNS**. Нужно сначала исправить DNS — поменять на 8.8.8.8 или включить DoH."

**Fix DNS before running blockcheck:**
```powershell
# Set DNS to Google on main adapter (replace "Ethernet" with actual adapter name from detect-state)
netsh interface ip set dns "Ethernet" static 8.8.8.8
netsh interface ip add dns "Ethernet" 1.1.1.1 index=2
```
After setting DNS, verify: `Resolve-DnsName youtube.com` should return valid IPs.

## CRITICAL: blockcheck must run WITHOUT VPN/proxy

Tell user before running blockcheck:
> "Важно: если у тебя включён VPN, прокси (NekoBox, Outline, WireGuard) — выключи их перед запуском blockcheck. Иначе результаты будут бесполезны — blockcheck протестирует зарубежный сервер, а не твоего провайдера."

If user cannot disable VPN (loses connection to Claude), explain:
> "Понял. Тогда запусти blockcheck самостоятельно: выключи VPN, дважды кликни C:\zapret\blockcheck\blockcheck2.cmd, дожди пока окно само закроется (~10 мин), потом включи VPN и скажи мне — я прочитаю результаты."

## Steps

### 1. Pre-flight
Run `detect-state.ps1`. Verify:
- `zapret_installed: true`
- `is_admin: true`
- `service_status: running` or `stopped` (not `absent`)
- `dns_hijacked: false` (fix DNS first if true)
- `vpn_detected: false` (disable VPN before blockcheck)

### 2. Explain blockcheck to user
> "Сейчас запущу blockcheck — он автоматически тестирует разные способы обхода блокировок и выбирает лучший для твоей сети. Займёт 5-10 минут. Откроется окно — это нормально, не закрывай его."

### 3. Backup current config
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-config\scripts\backup-config.ps1
```

### 4. Run blockcheck
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-config\scripts\run-blockcheck.ps1
```
Output: `{ log_path, finished, exit_code }`

Log is written to: `C:\zapret\blockcheck\blockcheck2.log`

Blockcheck takes 5-10 minutes. Window opens and closes automatically. Tell user to wait.

### 5. Parse results
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-config\scripts\parse-blockcheck-summary.ps1 -LogPath "C:\zapret\blockcheck\blockcheck2.log"
```
Output: `{ strategies[], best_strategy, http_count, tls_count, quic_count, dns_hijack_warning, errors[] }`

**If `dns_hijack_warning: true`:** DNS fix is needed — see CRITICAL section above.

**If `tls_count: 0` and `http_count > 0`:** Only HTTP strategies found. This is common — most blockcheck runs find more HTTP strategies. The config builder will apply the HTTP strategy to TLS connections as well (usually works).

Present to user:
> "Blockcheck нашёл X HTTP-стратегий и Y TLS-стратегий. Лучшая стратегия: [lua_desync value]. Применить?"

### 6. Apply strategy
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-config\scripts\apply-strategy.ps1 -WinArgs "<full_config from best_strategy.full_config>"
```
This writes to `C:\zapret\config\zapret.conf` and recreates the service.

### 7. Deploy rollback timer
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-diagnose\scripts\safe-mode.ps1 -Action arm -Minutes 3
```
Tell user:
> "Применил новую стратегию. Проверь — открывается ли YouTube и Telegram?
> Если да — скажи 'работает' и я отменю таймер. Если нет — через 3 минуты автоматически откатится."

### 8. User confirms → cancel timer
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-diagnose\scripts\safe-mode.ps1 -Action cancel
```

## Strategy Selection Logic

blockcheck2 uses lua-desync strategies. Priority (best → worst):
1. `fakedsplit` + `tcp_md5` — most reliable, works on most Russian ISPs
2. `fakeddisorder` + `tcp_md5` — aggressive splitting
3. `fakedsplit` (without tcp_md5)
4. `multidisorder`, `multisplit` — simpler variants
5. `fake` with blob — packet spoofing
6. `oob` — out-of-band data (last resort)

## Rollback procedure (if strategy fails)
```powershell
# Restore last backup
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-config\scripts\backup-config.ps1 -Action restore
# Recreate service
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-install\scripts\create-service.ps1
```
