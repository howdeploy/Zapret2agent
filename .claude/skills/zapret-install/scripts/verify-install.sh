#!/usr/bin/env bash
# verify-install.sh — проверка успешности установки zapret2
# Запускать ПОСЛЕ завершения установки
# Не требует root для базовых проверок (systemctl is-active работает без root)
# Вывод: JSON в stdout с полями success/warnings
# NOTE: -e intentionally omitted — script collects install status, must not abort on individual check failures
set -uo pipefail

warnings=""

# --- DNS hijack check ---
# NOTE: DNS hijack check duplicated from detect-state.sh intentionally for standalone use
# Логика: 3 домена, порог 2/3 — аналогично detect-state.sh (Pitfall 6 из RESEARCH.md)
check_dns_hijack() {
    local _hijack=false
    if command -v dig &>/dev/null; then
        local _mismatch=0
        for _domain in youtube.com rutracker.org telegram.org; do
            local _sys_ip
            local _pub_ip
            _sys_ip=$(dig +short +time=3 "$_domain" 2>/dev/null | grep -E '^[0-9]' | head -1 || true)
            _pub_ip=$(dig +short +time=3 "@8.8.8.8" "$_domain" 2>/dev/null | grep -E '^[0-9]' | head -1 || true)
            if [ -n "$_sys_ip" ] && [ -n "$_pub_ip" ] && [ "$_sys_ip" != "$_pub_ip" ]; then
                _mismatch=$((_mismatch + 1))
            fi
        done
        if [ "$_mismatch" -ge 2 ]; then
            _hijack=true
        fi
    fi
    echo "$_hijack"
}

# --- Основные проверки ---

# 1. Директория zapret2 существует
if [ -d /opt/zapret2 ]; then
    zapret2_dir_exists=true
else
    zapret2_dir_exists=false
fi

# 2. Основной бинарник nfqws2 присутствует
if [ -f /opt/zapret2/nfq2/nfqws2 ]; then
    binary_ok=true
else
    binary_ok=false
fi

# 3. Конфиг существует
if [ -f /opt/zapret2/config ]; then
    config_exists=true
else
    config_exists=false
fi

# 4. Сервис запущен
service_running=false
if command -v systemctl &>/dev/null; then
    if systemctl is-active --quiet zapret2 2>/dev/null; then
        service_running=true
    fi
fi

# 5. Сервис включён (автозапуск)
service_enabled=false
if command -v systemctl &>/dev/null; then
    if systemctl is-enabled --quiet zapret2 2>/dev/null; then
        service_enabled=true
    fi
fi

# 6. DNS-хиджек (Pitfall 6: сервис работает, но DNS отравлен)
dns_hijack_suspected=$(check_dns_hijack)

# 7. Режим фильтрации из конфига
config_mode_filter=""
if [ -f /opt/zapret2/config ]; then
    config_mode_filter=$(grep '^MODE_FILTER=' /opt/zapret2/config 2>/dev/null | cut -d= -f2 | tr -d '"' || true)
fi
config_mode_filter="${config_mode_filter:-unknown}"

# --- Итоговый статус ---
# success = dir + binary + config + service_running
if [ "$zapret2_dir_exists" = "true" ] && \
   [ "$binary_ok" = "true" ] && \
   [ "$config_exists" = "true" ] && \
   [ "$service_running" = "true" ]; then
    success=true
else
    success=false
fi

# --- Предупреждения ---
if [ "$dns_hijack_suspected" = "true" ]; then
    warnings="${warnings:+$warnings,}\"dns_hijack_suspected\""
fi
if [ "$service_running" = "true" ] && [ "$service_enabled" = "false" ]; then
    warnings="${warnings:+$warnings,}\"service_not_enabled\""
fi
if [ "$config_mode_filter" = "none" ] || [ "$config_mode_filter" = "unknown" ]; then
    warnings="${warnings:+$warnings,}\"mode_filter_none\""
fi

cat <<EOF
{
  "success": $success,
  "zapret2_dir_exists": $zapret2_dir_exists,
  "binary_ok": $binary_ok,
  "config_exists": $config_exists,
  "service_running": $service_running,
  "service_enabled": $service_enabled,
  "dns_hijack_suspected": $dns_hijack_suspected,
  "config_mode_filter": "$config_mode_filter",
  "warnings": [$warnings]
}
EOF
