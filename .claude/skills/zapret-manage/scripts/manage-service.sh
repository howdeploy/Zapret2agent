#!/usr/bin/env bash
# manage-service.sh — управление сервисом zapret2
# Аргументы: status | start | stop | restart
# Всегда выводит JSON для агента; ACTION_OK / ACTION_FAILED для команд управления
# Source: docs/manual.en.md стр. 5393-5416
set -euo pipefail

ACTION="${1:-status}"
SERVICE_NAME="zapret2"

# --- Определение init_system (не зависит от detect-state.sh) ---
INIT_SYSTEM="unknown"
if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif command -v rc-service &>/dev/null; then
    INIT_SYSTEM="openrc"
fi

# --- Получить статус сервиса и подробный вывод ---
get_status() {
    local status="unknown"
    local detail=""

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        # is-active возвращает: active, inactive, activating, deactivating, failed, unknown
        status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")
        detail=$(systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | tail -20 || echo "")
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        if rc-service "$SERVICE_NAME" status 2>/dev/null | grep -q "started"; then
            status="active"
        else
            status="inactive"
        fi
        detail=$(rc-service "$SERVICE_NAME" status 2>/dev/null || echo "")
    fi

    # Экранируем detail через python3 для корректного JSON
    local detail_json
    detail_json=$(printf '%s' "$detail" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""')

    printf '{"status":"%s","init_system":"%s","detail":%s}\n' \
        "$status" "$INIT_SYSTEM" "$detail_json"
}

# --- Выполнить команду управления сервисом ---
run_service_cmd() {
    local cmd="$1"
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        sudo systemctl "$cmd" "$SERVICE_NAME"
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        sudo rc-service "$SERVICE_NAME" "$cmd"
    else
        printf '{"error":"unknown_init_system"}\n'
        return 1
    fi
}

# --- Основная логика ---
case "$ACTION" in
    status)
        get_status
        ;;
    start|stop|restart)
        # Агент уже запросил подтверждение у пользователя (CLAUDE.md протокол безопасности)
        if run_service_cmd "$ACTION"; then
            printf 'ACTION_OK\n'
            get_status
        else
            printf 'ACTION_FAILED\n'
            get_status
        fi
        ;;
    *)
        printf '{"error":"unknown_action","action":"%s"}\n' "$ACTION"
        exit 1
        ;;
esac
