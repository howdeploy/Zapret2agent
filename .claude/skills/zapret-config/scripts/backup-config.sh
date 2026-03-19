#!/usr/bin/env bash
# backup-config.sh — бэкап /opt/zapret2/config перед изменениями
#
# Вызывается агентом молча перед любым write в конфиг.
# НЕ требует root для создания бэкапа (пишет в ~ пользователя).
# ТРЕБУЕТ root для restore (пишет в /opt/zapret2/).
#
# Использование:
#   backup-config.sh               — создать бэкап (основной режим)
#   backup-config.sh list          — список существующих бэкапов
#   backup-config.sh restore <файл> — подготовить команду восстановления
#
# Stdout-протокол:
#   backup:  BACKUP_CREATED=/path\nBACKUP_COUNT=N
#   list:    BACKUP_LIST=file1,file2,...
#   restore: RESTORE_CMD=sudo cp /path/backup /opt/zapret2/config
#   нет конфига: NO_CONFIG_TO_BACKUP

set -euo pipefail

CONFIG_SRC="/opt/zapret2/config"
BACKUP_DIR="${HOME}/.zapret-backup"
MAX_BACKUPS=50
ACTION="${1:-backup}"

# --- Режим: list ---
if [ "$ACTION" = "list" ]; then
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "BACKUP_LIST="
        exit 0
    fi
    # Получаем список файлов бэкапов, отсортированных по имени (имя содержит timestamp)
    BACKUP_LIST=$(find "$BACKUP_DIR" -maxdepth 1 -name "config.*" -type f \
        | sort | xargs -I{} basename {} 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)
    echo "BACKUP_LIST=${BACKUP_LIST}"
    exit 0
fi

# --- Режим: restore ---
if [ "$ACTION" = "restore" ]; then
    RESTORE_TARGET="${2:-}"
    if [ -z "$RESTORE_TARGET" ]; then
        echo "Ошибка: не указан файл для восстановления" >&2
        echo "Использование: backup-config.sh restore config.YYYYMMDD_HHMMSS" >&2
        exit 1
    fi

    # Поддерживаем как полный путь, так и только имя файла
    if [ -f "$RESTORE_TARGET" ]; then
        RESTORE_PATH="$RESTORE_TARGET"
    elif [ -f "${BACKUP_DIR}/${RESTORE_TARGET}" ]; then
        RESTORE_PATH="${BACKUP_DIR}/${RESTORE_TARGET}"
    else
        echo "Ошибка: бэкап не найден: ${RESTORE_TARGET}" >&2
        exit 1
    fi

    # Выводим команду восстановления — агент показывает её пользователю и просит подтверждение
    echo "RESTORE_CMD=sudo cp '${RESTORE_PATH}' '${CONFIG_SRC}'"
    exit 0
fi

# --- Режим: backup (основной) ---

# Проверяем наличие исходного конфига
if [ ! -f "$CONFIG_SRC" ]; then
    echo "NO_CONFIG_TO_BACKUP"
    exit 0
fi

# Создаём директорию для бэкапов если нет
mkdir -p "$BACKUP_DIR"

# Создаём бэкап с timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/config.${TIMESTAMP}"
cp "$CONFIG_SRC" "$BACKUP_FILE"

# Ротация: удаляем старые бэкапы если их больше MAX_BACKUPS
CURRENT_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "config.*" -type f | wc -l)
if [ "$CURRENT_COUNT" -gt "$MAX_BACKUPS" ]; then
    # Удаляем самые старые (сортировка по имени = сортировка по времени через timestamp)
    DELETE_COUNT=$((CURRENT_COUNT - MAX_BACKUPS))
    find "$BACKUP_DIR" -maxdepth 1 -name "config.*" -type f \
        | sort \
        | head -n "$DELETE_COUNT" \
        | xargs rm -f 2>/dev/null || true
fi

# Подсчитываем итоговое количество бэкапов
BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "config.*" -type f | wc -l)

# Вывод структурированного протокола для агента
echo "BACKUP_CREATED=${BACKUP_FILE}"
echo "BACKUP_COUNT=${BACKUP_COUNT}"
