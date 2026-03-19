#!/usr/bin/env bash
# merge-seed.sh — мерж seed-списка ТСПУ-блокировок с пользовательским hostlist zapret2
# Аргументы: [--dry-run]
# Выводит: BEFORE_COUNT, AFTER_COUNT, ADDED_COUNT, MERGE_COMPLETE (машиночитаемый)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SEED_FILE="$REPO_ROOT/data/seed-list.txt"
USER_LIST="/opt/zapret2/ipset/zapret-hosts-user.txt"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    printf 'DRY_RUN=true\n'
fi

# --- Проверки предусловий ---
if [ ! -f "$SEED_FILE" ]; then
    printf 'ERROR_SEED_NOT_FOUND\n'
    exit 1
fi

if [ ! -d "/opt/zapret2/ipset" ]; then
    printf 'ERROR_ZAPRET_NOT_INSTALLED\n'
    exit 1
fi

# --- Подсчёт доменов ДО мержа ---
BEFORE_COUNT=0
if [ -f "$USER_LIST" ]; then
    BEFORE_COUNT=$(grep -cE "^[^#[:space:]]" "$USER_LIST" 2>/dev/null || echo 0)
fi
printf 'BEFORE_COUNT=%d\n' "$BEFORE_COUNT"

# --- Извлечь домены из seed-list.txt ---
SEED_DOMAINS=$(grep -E "^[^#[:space:]]" "$SEED_FILE" 2>/dev/null || true)

if [ "$DRY_RUN" = true ]; then
    # В dry-run режиме — только подсчитать, не писать
    if [ -f "$USER_LIST" ]; then
        MERGED=$(printf '%s\n%s\n' "$SEED_DOMAINS" "$(cat "$USER_LIST")" | sort -u | grep -E "^[^#[:space:]]" 2>/dev/null || true)
    else
        MERGED=$(printf '%s\n' "$SEED_DOMAINS" | sort -u | grep -E "^[^#[:space:]]" 2>/dev/null || true)
    fi
    AFTER_COUNT=$(printf '%s\n' "$MERGED" | grep -cE "^[^[:space:]]" 2>/dev/null || echo 0)
    ADDED_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
    printf 'AFTER_COUNT=%d\n' "$AFTER_COUNT"
    printf 'ADDED_COUNT=%d\n' "$ADDED_COUNT"
    printf 'MERGE_COMPLETE\n'
    exit 0
fi

# --- Бэкап пользовательского списка ---
if [ -f "$USER_LIST" ]; then
    BACKUP_FILE="${USER_LIST}.bak.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$USER_LIST" "$BACKUP_FILE"
fi

# --- Мерж: объединить seed + текущий user list, убрать дубликаты ---
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if [ -f "$USER_LIST" ]; then
    printf '%s\n' "$SEED_DOMAINS" | cat - "$USER_LIST" | sort -u | grep -E "^[^#[:space:]]" > "$TMPFILE" 2>/dev/null || true
else
    printf '%s\n' "$SEED_DOMAINS" | sort -u | grep -E "^[^#[:space:]]" > "$TMPFILE" 2>/dev/null || true
fi

# Атомарная запись через tmpfile + sudo mv (паттерн из manage-hostlist.sh)
sudo mv "$TMPFILE" "$USER_LIST"
sudo chmod 644 "$USER_LIST"
trap - EXIT

# --- Подсчёт доменов ПОСЛЕ мержа ---
AFTER_COUNT=$(grep -cE "^[^#[:space:]]" "$USER_LIST" 2>/dev/null || echo 0)
ADDED_COUNT=$((AFTER_COUNT - BEFORE_COUNT))
printf 'AFTER_COUNT=%d\n' "$AFTER_COUNT"
printf 'ADDED_COUNT=%d\n' "$ADDED_COUNT"
printf 'MERGE_COMPLETE\n'

# --- Отправить SIGHUP демонам nfqws2 для немедленного применения ---
if command -v killall &>/dev/null; then
    sudo killall -HUP nfqws2 2>/dev/null || true
    printf 'HUP_SENT\n'
elif command -v pkill &>/dev/null; then
    sudo pkill -HUP "^nfqws2$" 2>/dev/null || true
    printf 'HUP_SENT\n'
else
    printf 'HUP_SKIPPED\n'
fi
