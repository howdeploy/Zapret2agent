#!/usr/bin/env bash
# set-mode.sh — управление режимом работы zapret2
#
# Два режима:
#   direct  — прямой обход DPI без VPN (autohostlist + blockcheck)
#   tunnel  — защита VPN-туннеля (маскировка VPN-протокола от DPI)
#
# Состояние хранится в ~/.zapret-mode (plain text, одна строка: direct | tunnel)
#
# Subcommands:
#   status              — вывести JSON с текущим режимом и состоянием VPN
#   set direct|tunnel   — установить режим явно
#   set auto            — определить режим автоматически по vpn_active
#
# Stdout-протокол:
#   status  → JSON
#   set     → KEY=VALUE (MODE_SET=direct|tunnel, AUTO_DETECTED=true при auto)
#   ошибки  → ERROR_USAGE | ERROR_INVALID_MODE, exit 1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE_FILE="${HOME}/.zapret-mode"
DETECT_STATE="${SCRIPT_DIR}/../../zapret-diagnose/scripts/detect-state.sh"

# --- Вспомогательная функция: получить поле из JSON detect-state.sh ---
parse_detect_field() {
    local json="$1"
    local field="$2"
    printf '%s' "$json" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    val = d.get('${field}')
    if isinstance(val, bool):
        print('true' if val else 'false')
    else:
        print(val if val is not None else '')
except Exception:
    print('')
" 2>/dev/null
}

# --- Читаем текущий режим из файла ---
read_current_mode() {
    if [ -f "$MODE_FILE" ]; then
        local mode
        mode=$(cat "$MODE_FILE" | tr -d '[:space:]')
        case "$mode" in
            direct|tunnel) printf '%s' "$mode" ;;
            *)             printf 'none' ;;
        esac
    else
        printf 'none'
    fi
}

# --- Запускаем detect-state.sh и возвращаем JSON ---
run_detect_state() {
    if [ -f "$DETECT_STATE" ]; then
        bash "$DETECT_STATE" 2>/dev/null || true
    else
        printf '{}'
    fi
}

# --- Subcommand: status ---
cmd_status() {
    local current_mode
    current_mode=$(read_current_mode)

    local detect_json
    detect_json=$(run_detect_state)

    local vpn_active vpn_client vpn_protocol_family recommended_mode
    vpn_active=$(parse_detect_field "$detect_json" "vpn_active")
    vpn_client=$(parse_detect_field "$detect_json" "vpn_client")
    vpn_protocol_family=$(parse_detect_field "$detect_json" "vpn_protocol_family")

    # Рекомендуем режим: если VPN активен — tunnel, иначе direct
    if [ "$vpn_active" = "true" ]; then
        recommended_mode="tunnel"
    else
        recommended_mode="direct"
    fi

    # Безопасное экранирование строк для JSON
    _esc() { printf '%s' "$1" | sed 's/"/\\"/g'; }

    cat <<JSON
{
  "current_mode": "$(_esc "$current_mode")",
  "vpn_active": ${vpn_active:-false},
  "vpn_client": "$(_esc "${vpn_client:-none}")",
  "vpn_protocol_family": "$(_esc "${vpn_protocol_family:-unknown}")",
  "recommended_mode": "$recommended_mode"
}
JSON
}

# --- Subcommand: set ---
cmd_set() {
    local mode="${1:-}"

    case "$mode" in
        direct|tunnel)
            printf '%s\n' "$mode" > "$MODE_FILE"
            printf 'MODE_SET=%s\n' "$mode"
            ;;
        auto)
            local detect_json vpn_active chosen_mode
            detect_json=$(run_detect_state)
            vpn_active=$(parse_detect_field "$detect_json" "vpn_active")

            if [ "$vpn_active" = "true" ]; then
                chosen_mode="tunnel"
            else
                chosen_mode="direct"
            fi

            printf '%s\n' "$chosen_mode" > "$MODE_FILE"
            printf 'MODE_SET=%s\n' "$chosen_mode"
            printf 'AUTO_DETECTED=true\n'
            ;;
        "")
            printf 'ERROR_USAGE\n' >&2
            exit 1
            ;;
        *)
            printf 'ERROR_INVALID_MODE\n' >&2
            exit 1
            ;;
    esac
}

# --- Точка входа ---
SUBCOMMAND="${1:-}"

case "$SUBCOMMAND" in
    status)
        cmd_status
        ;;
    set)
        cmd_set "${2:-}"
        ;;
    "")
        printf 'ERROR_USAGE\n' >&2
        exit 1
        ;;
    *)
        printf 'ERROR_USAGE\n' >&2
        exit 1
        ;;
esac
