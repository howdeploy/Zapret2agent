#!/usr/bin/env bash
# detect-state.sh — единственный источник правды о состоянии системы
# Вывод: JSON в stdout (16 полей)
# Поля: os, kernel, init_system, firewall_backend, vpn_active, vpn_type, vpn_client,
#        vpn_protocol_family, exit_ip, zapret_installed, zapret_version, zapret_running,
#        zapret_config_exists, dns_ok, dns_hijack_suspected, interfaces
# Требования: bash 5.x, ip, dig (необязателен), systemctl (необязателен)
# Не требует root — только read-only проверки
set -euo pipefail

# --- OS Info ---
os_pretty="unknown"
kernel=$(uname -r)
init_system="unknown"
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    os_pretty=$(. /etc/os-release && echo "$PRETTY_NAME")
fi
if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
    init_system="systemd"
elif command -v rc-service &>/dev/null; then
    init_system="openrc"
fi

# --- Firewall Backend ---
# Приоритет: readlink -f на реальный путь iptables, затем fallback
firewall_backend="unknown"
iptables_real=$(readlink -f "$(command -v iptables 2>/dev/null)" 2>/dev/null || echo "")
if   echo "$iptables_real" | grep -q "nft";    then firewall_backend="iptables-nft"
elif echo "$iptables_real" | grep -q "legacy"; then firewall_backend="iptables-legacy"
elif command -v nft &>/dev/null;               then firewall_backend="nftables"
elif [ -n "$iptables_real" ];                  then firewall_backend="iptables"
fi

# --- VPN / Proxy Detection ---
# Определяем не только классические VPN (WireGuard, OpenVPN), но и
# прокси-клиенты с tun2socks (Throne, Nekoray, Hiddify, AmneziaVPN, v2rayA и др.)
# Выходные поля: vpn_active, vpn_type, vpn_client, vpn_protocol_family, exit_ip
vpn_active=false
vpn_type="none"
vpn_client="none"
vpn_protocol_family="unknown"
exit_ip="unknown"

# 1) WireGuard — проверяем в ЛЮБОМ state (не только UP) — Pitfall 5
if ip link show type wireguard 2>/dev/null | grep -q .; then
    vpn_active=true
    vpn_type="wireguard"
    vpn_client="wireguard"
    vpn_protocol_family="wireguard"

# 2) OpenVPN — классический процесс
elif pgrep -x openvpn &>/dev/null 2>&1; then
    vpn_active=true
    vpn_type="openvpn"
    vpn_client="openvpn"
    vpn_protocol_family="openvpn"

# 3) TUN-based proxy clients (tun2socks pattern)
#    Ищем TUN-интерфейсы, исключая docker/veth/br-/virbr/tailscale
elif ip tuntap show 2>/dev/null | grep -vE 'docker|veth|br-|virbr|tailscale' | grep -q .; then
    vpn_active=true
    vpn_type="tun-proxy"

    # Определяем клиент по имени TUN-интерфейса
    _tun_name=$(ip tuntap show 2>/dev/null | grep -vE 'docker|veth|br-|virbr|tailscale' | head -1 | cut -d: -f1)
    case "$_tun_name" in
        throne*)     vpn_client="throne" ;;
        nekoray*|neko*|tun-nekoray*) vpn_client="nekoray" ;;
        hiddify*)    vpn_client="hiddify" ;;
        v2raya*|tun-v2raya*) vpn_client="v2raya" ;;
        amnezia*)    vpn_client="amneziavpn" ;;
        clash*|meta*|mihomo*) vpn_client="clash" ;;
        sing-box*|sbox*) vpn_client="sing-box" ;;
        *)           vpn_client="unknown-tun" ;;
    esac

    # Подтверждаем по запущенным процессам прокси-ядер
    if [ "$vpn_client" = "unknown-tun" ]; then
        if pgrep -fa "xray" 2>/dev/null | grep -qv grep; then vpn_client="xray"
        elif pgrep -fa "sing-box" 2>/dev/null | grep -qv grep; then vpn_client="sing-box"
        elif pgrep -fa "v2ray" 2>/dev/null | grep -qv grep; then vpn_client="v2ray"
        elif pgrep -fa "clash\|mihomo" 2>/dev/null | grep -qv grep; then vpn_client="clash"
        elif pgrep -fa "hysteria" 2>/dev/null | grep -qv grep; then vpn_client="hysteria"
        elif pgrep -fa "trojan-go\|trojan" 2>/dev/null | grep -qv grep; then vpn_client="trojan"
        elif pgrep -fa "naiveproxy\|naive" 2>/dev/null | grep -qv grep; then vpn_client="naiveproxy"
        elif pgrep -fa "tun2socks" 2>/dev/null | grep -qv grep; then vpn_client="tun2socks"
        elif systemctl is-active --quiet AmneziaVPN 2>/dev/null; then vpn_client="amneziavpn"
        fi
    fi

    # Определяем протокол из имени клиента (эвристика)
    # Точный протокол (VLESS/VMess/Trojan/SS) зависит от конфига клиента,
    # но можно дать подсказку
    case "$vpn_client" in
        throne|nekoray|hiddify|xray|v2ray|v2raya|sing-box)
            vpn_protocol_family="xray-family" ;;  # VLESS/VMess/Trojan/SS — уточнить по конфигу
        clash)      vpn_protocol_family="clash" ;;
        hysteria)   vpn_protocol_family="hysteria" ;;
        trojan)     vpn_protocol_family="trojan" ;;
        naiveproxy) vpn_protocol_family="naiveproxy" ;;
        amneziavpn) vpn_protocol_family="amnezia-wg" ;;  # чаще всего AmneziaWG
        *)          vpn_protocol_family="unknown" ;;
    esac
fi

# 4) Fallback: проверяем процессы прокси-ядер даже без TUN
#    (могут работать как SOCKS/HTTP прокси без tun2socks)
if [ "$vpn_active" = "false" ]; then
    for _proc in xray sing-box v2ray clash mihomo hysteria trojan-go naiveproxy; do
        if pgrep -x "$_proc" &>/dev/null 2>&1; then
            vpn_active=true
            vpn_type="proxy-no-tun"
            vpn_client="$_proc"
            vpn_protocol_family="xray-family"
            break
        fi
    done
fi

# 5) Получаем внешний IP (быстро, таймаут 3 сек)
exit_ip=$(curl -s --max-time 3 https://ifconfig.me 2>/dev/null || echo "unknown")

# --- zapret ---
zapret_installed=false
zapret_version="none"
zapret_running=false
zapret_config_exists=false
if [ -f /opt/zapret2/nfq2/nfqws2 ] || command -v nfqws2 &>/dev/null 2>&1; then
    zapret_installed=true
    zapret_version=$(/opt/zapret2/nfq2/nfqws2 --version 2>/dev/null || nfqws2 --version 2>/dev/null | head -1 || echo "unknown")
fi
# Проверяем запущен ли сервис (systemd или openrc)
if command -v systemctl &>/dev/null 2>&1; then
    systemctl is-active --quiet zapret2 2>/dev/null && zapret_running=true || true
elif command -v rc-service &>/dev/null 2>&1; then
    rc-service zapret2 status &>/dev/null 2>&1 && zapret_running=true || true
fi
if [ -f /opt/zapret2/config ]; then
    zapret_config_exists=true
fi

# --- DNS Check ---
# 3 домена: если 2 из 3 расходятся — dns_hijack_suspected=true
# Порог 2/3 снижает false positive от CDN-геолокации (Pitfall 3)
dns_ok=true
dns_hijack_suspected=false
if command -v dig &>/dev/null; then
    _dns_mismatch=0
    _dns_checked=0
    for _domain in youtube.com rutracker.org telegram.org; do
        _sys_ip=$(dig +short +time=3 "$_domain" 2>/dev/null | grep -E '^[0-9]' | head -1 || true)
        _pub_ip=$(dig +short +time=3 "@8.8.8.8" "$_domain" 2>/dev/null | grep -E '^[0-9]' | head -1 || true)
        # Если системный resolver вернул пустоту — DNS не работает
        if [ -z "$_sys_ip" ] && [ "$_domain" = "youtube.com" ]; then
            dns_ok=false
        fi
        # Считаем расхождение только если оба вернули IP
        if [ -n "$_sys_ip" ] && [ -n "$_pub_ip" ] && [ "$_sys_ip" != "$_pub_ip" ]; then
            _dns_mismatch=$((_dns_mismatch + 1))
        fi
        if [ -n "$_sys_ip" ] || [ -n "$_pub_ip" ]; then
            _dns_checked=$((_dns_checked + 1))
        fi
    done
    # 2 из 3 расходятся — подозрение (не подтверждение, CDN может дать 1 расхождение)
    if [ "$_dns_mismatch" -ge 2 ]; then
        dns_hijack_suspected=true
    fi
else
    # dig недоступен — degraded mode, не ошибка
    dns_ok=true
    dns_hijack_suspected=false
fi

# --- Network Interfaces (без lo) ---
ifaces=$(ip link show 2>/dev/null | awk -F': ' '/^[0-9]+:/ && !/lo:/ {gsub(/@.*/, "", $2); print $2}' | tr '\n' ',' | sed 's/,$//' || echo "unknown")

# --- Вывод JSON ---
# Экранируем кавычки в строковых значениях через sed
cat <<EOF
{
  "os": "$(printf '%s' "$os_pretty" | sed 's/"/\\"/g')",
  "kernel": "$(printf '%s' "$kernel" | sed 's/"/\\"/g')",
  "init_system": "$init_system",
  "firewall_backend": "$firewall_backend",
  "vpn_active": $vpn_active,
  "vpn_type": "$vpn_type",
  "vpn_client": "$vpn_client",
  "vpn_protocol_family": "$vpn_protocol_family",
  "exit_ip": "$(printf '%s' "$exit_ip" | sed 's/"/\\"/g')",
  "zapret_installed": $zapret_installed,
  "zapret_version": "$(printf '%s' "$zapret_version" | sed 's/"/\\"/g')",
  "zapret_running": $zapret_running,
  "zapret_config_exists": $zapret_config_exists,
  "dns_ok": $dns_ok,
  "dns_hijack_suspected": $dns_hijack_suspected,
  "interfaces": "$(printf '%s' "$ifaces" | sed 's/"/\\"/g')"
}
EOF
