#!/usr/bin/env bash
# safe-mode.sh — таймер автоотката для iptables/nftables
#
# Использование:
#   safe-mode.sh '<rollback_command>'
#   safe-mode.sh cancel <TIMER_NAME>
#
# Примеры:
#   safe-mode.sh "iptables-restore < /tmp/zapret-backup.rules"
#   safe-mode.sh cancel zapret-rollback-1234567890
#
# Переменные окружения:
#   SAFE_MODE_TIMEOUT — таймаут в секундах (по умолчанию 300 = 5 минут)
#
# Stdout-протокол (агент читает этот вывод):
#   SAFE_MODE_ACTIVE
#   BACKUP_FILE=/tmp/zapret-iptables-backup-XXX.rules
#   NFTABLES_BACKUP_FILE=/tmp/zapret-nftables-backup-XXX.ruleset
#   TIMER_NAME=zapret-rollback-XXX
#   TIMER_METHOD=systemd-run|at|background
#   ROLLBACK_IN=300s

set -euo pipefail

TIMEOUT=${SAFE_MODE_TIMEOUT:-300}
ACTION="${1:-}"

# --- Вывод usage при отсутствии аргументов ---
if [ -z "$ACTION" ]; then
    echo "Использование: safe-mode.sh '<rollback_command>'" >&2
    echo "              safe-mode.sh cancel <TIMER_NAME>" >&2
    echo "" >&2
    echo "Примеры:" >&2
    echo "  safe-mode.sh \"iptables-restore < /tmp/backup.rules\"" >&2
    echo "  safe-mode.sh cancel zapret-rollback-1234567890" >&2
    exit 1
fi

# --- Режим отмены таймера ---
if [ "$ACTION" = "cancel" ]; then
    TIMER_NAME="${2:-}"
    if [ -z "$TIMER_NAME" ]; then
        echo "Ошибка: не указано имя таймера для отмены" >&2
        echo "Использование: safe-mode.sh cancel <TIMER_NAME>" >&2
        exit 1
    fi

    # Попытка отмены через systemd
    if command -v systemctl &>/dev/null; then
        systemctl stop "${TIMER_NAME}.timer" 2>/dev/null || true
        systemctl stop "${TIMER_NAME}.service" 2>/dev/null || true
        echo "TIMER_CANCELLED=${TIMER_NAME}"
        exit 0
    fi

    # Попытка отмены через at (at не возвращает job id здесь, сообщаем об ограничении)
    if command -v atq &>/dev/null; then
        echo "TIMER_METHOD=at" >&2
        echo "Предупреждение: отмена at-таймера не поддерживается автоматически." >&2
        echo "Выполните вручную: atq | tail -5 (найти job ID) && atrm <ID>" >&2
        exit 1
    fi

    # Попытка отмены через PID-файл (background subshell)
    PID_FILE="/tmp/zapret-rollback.pid"
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null || true)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "TIMER_CANCELLED=background_pid_${PID}"
        else
            echo "TIMER_NOT_FOUND=${TIMER_NAME}" >&2
            rm -f "$PID_FILE"
            exit 1
        fi
    else
        echo "TIMER_NOT_FOUND=${TIMER_NAME}" >&2
        exit 1
    fi
    exit 0
fi

# --- Основной режим: запуск таймера автоотката ---
ROLLBACK_CMD="$ACTION"

# Шаг 1: Бэкап текущих правил iptables
EPOCH=$(date +%s)
IPTABLES_BACKUP=""
NFTABLES_BACKUP=""

if command -v iptables-save &>/dev/null; then
    IPTABLES_BACKUP="/tmp/zapret-iptables-backup-${EPOCH}.rules"
    iptables-save > "$IPTABLES_BACKUP" 2>/dev/null || IPTABLES_BACKUP=""
fi

# Бэкап nftables (дополнительно)
if command -v nft &>/dev/null; then
    NFTABLES_BACKUP="/tmp/zapret-nftables-backup-${EPOCH}.ruleset"
    nft list ruleset > "$NFTABLES_BACKUP" 2>/dev/null || NFTABLES_BACKUP=""
fi

# Шаг 2: Запуск таймера отката (три метода с fallback)
TIMER_NAME="zapret-rollback-${EPOCH}"
TIMER_METHOD=""

if command -v systemd-run &>/dev/null; then
    # Метод 1: systemd-run (приоритет — работает везде с systemd)
    systemd-run \
        --unit="${TIMER_NAME}" \
        --on-active="${TIMEOUT}s" \
        --timer-property=AccuracySec=1s \
        bash -c "${ROLLBACK_CMD} && echo 'ROLLBACK_APPLIED: zapret safe-mode timer fired'" \
        2>/dev/null
    TIMER_METHOD="systemd-run"

elif command -v at &>/dev/null; then
    # Метод 2: at (fallback 1)
    echo "${ROLLBACK_CMD}" | at "now + $((TIMEOUT / 60)) minutes" 2>/dev/null
    TIMER_METHOD="at"

else
    # Метод 3: background subshell (fallback 2)
    # shellcheck disable=SC2064
    ( sleep "${TIMEOUT}" && bash -c "${ROLLBACK_CMD}" ) &
    echo $! > /tmp/zapret-rollback.pid
    TIMER_METHOD="background"
fi

# Шаг 3: Вывод структурированного протокола для агента
echo "SAFE_MODE_ACTIVE"
[ -n "$IPTABLES_BACKUP" ] && echo "BACKUP_FILE=${IPTABLES_BACKUP}"
[ -n "$NFTABLES_BACKUP" ] && echo "NFTABLES_BACKUP_FILE=${NFTABLES_BACKUP}"
echo "TIMER_NAME=${TIMER_NAME}"
echo "TIMER_METHOD=${TIMER_METHOD}"
echo "ROLLBACK_IN=${TIMEOUT}s"
