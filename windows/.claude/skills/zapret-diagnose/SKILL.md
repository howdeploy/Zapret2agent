# Skill: zapret-diagnose

Diagnose the Windows system state before any zapret installation or configuration.

## When to invoke
- ALWAYS run first before install, config, or mode change
- When the user reports connectivity problems
- When the service won't start
- When "something broke" and state is unclear

## Steps

### 1. Run full diagnostics
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-diagnose\scripts\detect-state.ps1
```
Parse the JSON output. All subsequent decisions are based on this data.

### 2. Run health check
```powershell
powershell -ExecutionPolicy Bypass -File .claude\skills\zapret-diagnose\scripts\health-check.ps1
```
Health check aggregates the state into an overall status: `healthy` / `degraded` / `not_installed` / `error`.

### 3. Interpret and report to user

**If `is_admin: false`:**
> "Нужно запустить терминал от имени Администратора. Закрой этот, щёлкни правой кнопкой на терминале → «Запуск от имени администратора», и попробуй снова."

**If `zapret_installed: false`:**
> Offer to install via zapret-install skill.

**If `service_status: stopped`:**
> Ask if user wants to start the service.

**If `service_status: absent`:**
> Zapret is installed but service is not created — offer to recreate via `create-service.ps1`.

**If `vpn_detected: true`:**
> Note the VPN type. Ask if user wants Tunnel mode (zapret + VPN) or Direct mode.
> Also warn: blockcheck must be run WITHOUT VPN active.

**If `dns_hijacked: true`:**
> "Провайдер подменяет DNS для заблокированных сайтов (YouTube, Telegram и др.). Это **критическая** проблема — zapret обходит DPI, но не подмену DNS. Без исправления DNS сайты не откроются, даже если zapret работает. Нужно поменять DNS на 8.8.8.8 или включить DoH."
>
> Offer to fix DNS:
> ```powershell
> netsh interface ip set dns "Ethernet" static 8.8.8.8
> netsh interface ip add dns "Ethernet" 1.1.1.1 index=2
> ```
> (Replace "Ethernet" with actual adapter name from `active_adapter` field)

**If `antivirus` list is non-empty:**
> "Обнаружен антивирус: [list]. Важно: добавь C:\zapret в исключения антивируса, иначе он может удалить WinDivert64.sys."

### 4. Summary output format
After interpreting, tell the user:
- OS + arch
- Zapret: установлен / не установлен (version if known)
- Сервис: работает / остановлен / отсутствует
- DNS: норма / подменяется (если подменяется — это критично, объяснить)
- VPN: найден [тип] / не обнаружен
- Антивирус: [list]
- Следующий шаг: [one clear recommendation]

## Diagnostic Parameters (from detect-state.ps1)

| Field | Description |
|-------|-------------|
| `os` | Windows version string |
| `os_version` | Build number (e.g. 10.0.22631) |
| `arch` | x64 or arm64 |
| `ps_version` | PowerShell version |
| `is_admin` | Running as Administrator |
| `zapret_installed` | C:\zapret exists and has binaries |
| `zapret_path` | Path to installation |
| `winws2_path` | Path to winws2.exe |
| `windivert_present` | WinDivert64.sys exists |
| `service_status` | running / stopped / absent |
| `vpn_detected` | bool |
| `vpn_type` | wireguard / openvpn / other / null |
| `vpn_interface` | adapter name or null |
| `dns_hijacked` | bool — ISP hijacks DNS for blocked domains |
| `dns_server` | primary DNS server IP |
| `active_adapter` | main network adapter name |
| `network_adapters` | list of all adapters |
| `antivirus` | list of detected AV products |
| `current_mode` | direct / tunnel / unknown |
| `config_exists` | C:\zapret\config\zapret.conf exists |
| `current_config` | content of zapret.conf or null |
