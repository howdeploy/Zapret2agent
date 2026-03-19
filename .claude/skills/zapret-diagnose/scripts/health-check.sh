#!/usr/bin/env bash
# health-check.sh — агрегированная проверка здоровья системы zapret2
#
# Вызывает detect-state.sh и manage-service.sh status,
# агрегирует результаты в единый JSON для быстрой диагностики.
#
# Stdout-протокол: JSON с полями overall/system/zapret/network/issues
#   - overall: "ok" | "warning" | "critical"
#   - critical: zapret установлен но не запущен, или dns_hijack_suspected=true
#   - warning: vpn_active=true, или dns_ok=false
#   - ok: всё остальное

set -euo pipefail

# Определяем директорию скрипта для относительных вызовов
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
MANAGE_SERVICE="${SCRIPT_DIR}/../../zapret-manage/scripts/manage-service.sh"

# --- Шаг 1: Вызвать detect-state.sh ---
DETECT_OUT=""
if [ -f "${SCRIPT_DIR}/detect-state.sh" ]; then
    DETECT_OUT=$(bash "${SCRIPT_DIR}/detect-state.sh" 2>/dev/null || true)
fi

# --- Парсинг detect-state.sh через python3 ---
parse_detect_state() {
    echo "$DETECT_OUT" | python3 -c "
import sys, json

try:
    d = json.loads(sys.stdin.read())
    print(d.get('os', 'unknown'))
    print(d.get('kernel', 'unknown'))
    print(d.get('init_system', 'unknown'))
    print(d.get('firewall_backend', 'unknown'))
    print(str(d.get('vpn_active', False)).lower())
    print(str(d.get('zapret_installed', False)).lower())
    print(str(d.get('zapret_running', False)).lower())
    print(str(d.get('dns_ok', True)).lower())
    print(str(d.get('dns_hijack_suspected', False)).lower())
except Exception:
    print('unknown')
    print('unknown')
    print('unknown')
    print('unknown')
    print('false')
    print('false')
    print('false')
    print('true')
    print('false')
" 2>/dev/null
}

# Читаем поля из detect-state.sh
if [ -n "$DETECT_OUT" ]; then
    DS_FIELDS=$(parse_detect_state)
    OS=$(printf '%s' "$DS_FIELDS" | sed -n '1p')
    KERNEL=$(printf '%s' "$DS_FIELDS" | sed -n '2p')
    INIT_SYSTEM=$(printf '%s' "$DS_FIELDS" | sed -n '3p')
    FIREWALL_BACKEND=$(printf '%s' "$DS_FIELDS" | sed -n '4p')
    VPN_ACTIVE=$(printf '%s' "$DS_FIELDS" | sed -n '5p')
    ZAPRET_INSTALLED=$(printf '%s' "$DS_FIELDS" | sed -n '6p')
    ZAPRET_RUNNING=$(printf '%s' "$DS_FIELDS" | sed -n '7p')
    DNS_OK=$(printf '%s' "$DS_FIELDS" | sed -n '8p')
    DNS_HIJACK=$(printf '%s' "$DS_FIELDS" | sed -n '9p')
else
    OS="unknown"
    KERNEL="unknown"
    INIT_SYSTEM="unknown"
    FIREWALL_BACKEND="unknown"
    VPN_ACTIVE="false"
    ZAPRET_INSTALLED="false"
    ZAPRET_RUNNING="false"
    DNS_OK="true"
    DNS_HIJACK="false"
fi

# --- Шаг 2: Получить статус сервиса через manage-service.sh ---
SERVICE_STATUS="unknown"
if [ "$ZAPRET_INSTALLED" = "true" ] && [ -f "$MANAGE_SERVICE" ]; then
    SVC_OUT=$(bash "$MANAGE_SERVICE" status 2>/dev/null || true)
    if [ -n "$SVC_OUT" ]; then
        SERVICE_STATUS=$(echo "$SVC_OUT" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(d.get('status', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")
    fi
fi

# --- Шаг 3: Определить overall и собрать issues ---
ISSUES=""
OVERALL="ok"

# Critical: zapret установлен но не запущен
if [ "$ZAPRET_INSTALLED" = "true" ] && [ "$ZAPRET_RUNNING" = "false" ]; then
    OVERALL="critical"
    ISSUES="${ISSUES:+$ISSUES,}\"zapret установлен, но сервис не запущен\""
fi

# Critical: dns_hijack_suspected
if [ "$DNS_HIJACK" = "true" ]; then
    OVERALL="critical"
    ISSUES="${ISSUES:+$ISSUES,}\"подозрение на перехват DNS-трафика провайдером\""
fi

# Warning (только если не critical уже)
if [ "$OVERALL" = "ok" ]; then
    if [ "$VPN_ACTIVE" = "true" ]; then
        OVERALL="warning"
        ISSUES="${ISSUES:+$ISSUES,}\"VPN активен — результаты диагностики могут быть некорректны\""
    fi
    if [ "$DNS_OK" = "false" ]; then
        OVERALL="warning"
        ISSUES="${ISSUES:+$ISSUES,}\"DNS-резолвер не отвечает или работает нестабильно\""
    fi
fi

# --- Шаг 4: Вывод агрегированного JSON ---
HC_OVERALL="$OVERALL" \
HC_OS="$OS" \
HC_KERNEL="$KERNEL" \
HC_INIT_SYSTEM="$INIT_SYSTEM" \
HC_FIREWALL_BACKEND="$FIREWALL_BACKEND" \
HC_VPN_ACTIVE="$VPN_ACTIVE" \
HC_ZAPRET_INSTALLED="$ZAPRET_INSTALLED" \
HC_ZAPRET_RUNNING="$ZAPRET_RUNNING" \
HC_SERVICE_STATUS="$SERVICE_STATUS" \
HC_DNS_OK="$DNS_OK" \
HC_DNS_HIJACK="$DNS_HIJACK" \
HC_ISSUES="$ISSUES" \
python3 -c "
import os, json

overall = os.environ['HC_OVERALL']
os_val = os.environ['HC_OS']
kernel = os.environ['HC_KERNEL']
init_system = os.environ['HC_INIT_SYSTEM']
firewall_backend = os.environ['HC_FIREWALL_BACKEND']
vpn_active = os.environ['HC_VPN_ACTIVE'] == 'true'
zapret_installed = os.environ['HC_ZAPRET_INSTALLED'] == 'true'
zapret_running = os.environ['HC_ZAPRET_RUNNING'] == 'true'
service_status = os.environ['HC_SERVICE_STATUS']
dns_ok = os.environ['HC_DNS_OK'] == 'true'
dns_hijack_suspected = os.environ['HC_DNS_HIJACK'] == 'true'
issues_str = os.environ['HC_ISSUES']

issues = [i.strip().strip('\"') for i in issues_str.split(',') if i.strip()] if issues_str else []

result = {
    'overall': overall,
    'system': {
        'os': os_val,
        'kernel': kernel,
        'init_system': init_system,
        'firewall_backend': firewall_backend
    },
    'zapret': {
        'installed': zapret_installed,
        'running': zapret_running,
        'service_status': service_status
    },
    'network': {
        'vpn_active': vpn_active,
        'dns_ok': dns_ok,
        'dns_hijack_suspected': dns_hijack_suspected
    },
    'issues': issues
}
print(json.dumps(result, ensure_ascii=False, indent=2))
"
