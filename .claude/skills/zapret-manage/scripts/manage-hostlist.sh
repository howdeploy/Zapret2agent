#!/usr/bin/env bash
# manage-hostlist.sh — управление пользовательским hostlist zapret2
# Аргументы: add <domain> | remove <domain> | list
# Всегда выводит машиночитаемый вывод для агента
# Source: ipset/def.sh (ZUSERLIST), common/list.sh, docs/manual.en.md стр. 860-966
set -euo pipefail

USER_LIST="/opt/zapret2/ipset/zapret-hosts-user.txt"
AUTO_LIST="/opt/zapret2/ipset/zapret-hosts-auto.txt"

ACTION="${1:-}"

# --- Нормализация домена ---
# Убрать протокол, www., path, query; привести к lowercase
normalize_domain() {
    local raw="$1"
    local domain
    domain=$(printf '%s' "$raw" | sed 's|^https\?://||; s|/.*||; s|\?.*||' | tr '[:upper:]' '[:lower:]')
    # Убрать www. если после удаления осталось что-то валидное (не пустая строка)
    if printf '%s' "$domain" | grep -q "^www\."; then
        local without_www
        without_www=$(printf '%s' "$domain" | sed 's|^www\.||')
        if [ -n "$without_www" ]; then
            domain="$without_www"
        fi
    fi
    printf '%s' "$domain"
}

# --- Валидация домена ---
# Проверить hostname regex; в zapret2 один домен на строку без wildcards
validate_domain() {
    local domain="$1"
    if ! printf '%s' "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'; then
        printf 'ERROR_INVALID_DOMAIN\n'
        exit 1
    fi
}

# --- Отправить SIGHUP демонам nfqws2 ---
# Pitfall 5: демон может быть остановлен — ошибки игнорируются
hup_zapret_daemons() {
    if command -v killall &>/dev/null; then
        sudo killall -HUP nfqws2 2>/dev/null || true
        printf 'HUP_SENT\n'
    elif command -v pkill &>/dev/null; then
        sudo pkill -HUP "^nfqws2$" 2>/dev/null || true
        printf 'HUP_SENT\n'
    else
        printf 'HUP_SKIPPED\n'
    fi
}

# --- Action: add ---
action_add() {
    local raw_domain="${1:-}"
    if [ -z "$raw_domain" ]; then
        printf 'ERROR_MISSING_DOMAIN\n'
        exit 1
    fi

    # Нормализовать
    local domain
    domain=$(normalize_domain "$raw_domain")

    # Валидировать
    validate_domain "$domain"

    # Сообщить о нормализации если отличается от ввода
    if [ "$domain" != "$raw_domain" ]; then
        printf 'NORMALIZED=%s\n' "$domain"
    fi

    # Проверить дубликат (точное совпадение строки)
    if [ -f "$USER_LIST" ] && grep -qxF "$domain" "$USER_LIST" 2>/dev/null; then
        printf 'DOMAIN_ALREADY_EXISTS\n'
        exit 0
    fi

    # Создать файл если не существует
    if [ ! -f "$USER_LIST" ]; then
        sudo touch "$USER_LIST" && sudo chmod 644 "$USER_LIST"
    fi

    # Добавить домен
    printf '%s\n' "$domain" | sudo tee -a "$USER_LIST" >/dev/null
    printf 'DOMAIN_ADDED\n'

    # Отправить HUP для немедленного применения (без restart)
    hup_zapret_daemons
}

# --- Action: remove ---
action_remove() {
    local raw_domain="${1:-}"
    if [ -z "$raw_domain" ]; then
        printf 'ERROR_MISSING_DOMAIN\n'
        exit 1
    fi

    # Нормализовать
    local domain
    domain=$(normalize_domain "$raw_domain")

    # Сообщить о нормализации если отличается от ввода
    if [ "$domain" != "$raw_domain" ]; then
        printf 'NORMALIZED=%s\n' "$domain"
    fi

    # Проверить наличие файла
    if [ ! -f "$USER_LIST" ]; then
        printf 'HOSTLIST_NOT_FOUND\n'
        exit 1
    fi

    # Проверить наличие домена (точное совпадение строки — не substring!)
    # КРИТИЧНО: grep -xF чтобы не зацепить sub.example.com при удалении example.com
    if ! grep -qxF "$domain" "$USER_LIST" 2>/dev/null; then
        printf 'DOMAIN_NOT_FOUND\n'
        exit 0
    fi

    # Удалить через tmpfile (атомарная операция, Pitfall 6)
    local tmpfile
    tmpfile=$(mktemp)
    grep -vxF "$domain" "$USER_LIST" > "$tmpfile" || true
    sudo mv "$tmpfile" "$USER_LIST"
    sudo chmod 644 "$USER_LIST"

    printf 'DOMAIN_REMOVED\n'

    # Отправить HUP для немедленного применения
    hup_zapret_daemons
}

# --- Action: list ---
action_list() {
    local user_count=0
    local auto_count=0
    local user_domains=""
    local auto_domains=""

    if [ -f "$USER_LIST" ]; then
        user_count=$(grep -c . "$USER_LIST" 2>/dev/null || echo 0)
        user_domains=$(cat "$USER_LIST" 2>/dev/null || echo "")
    fi

    if [ -f "$AUTO_LIST" ]; then
        auto_count=$(grep -c . "$AUTO_LIST" 2>/dev/null || echo 0)
        auto_domains=$(head -20 "$AUTO_LIST" 2>/dev/null || echo "")
    fi

    # JSON-вывод через python3 для надёжного экранирования (как в parse-blockcheck-summary.sh)
    local user_json auto_json
    user_json=$(printf '%s' "$user_domains" | python3 -c 'import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))' 2>/dev/null || printf '[]')
    auto_json=$(printf '%s' "$auto_domains" | python3 -c 'import sys,json; lines=[l.strip() for l in sys.stdin if l.strip()]; print(json.dumps(lines))' 2>/dev/null || printf '[]')

    printf '{"user_count":%d,"auto_count":%d,"user_domains":%s,"auto_sample":%s}\n' \
        "$user_count" "$auto_count" "$user_json" "$auto_json"
}

# --- Диспетчер ---
case "$ACTION" in
    add)
        action_add "${2:-}"
        ;;
    remove)
        action_remove "${2:-}"
        ;;
    list)
        action_list
        ;;
    *)
        printf 'Usage: %s <add <domain>|remove <domain>|list>\n' "$0" >&2
        exit 1
        ;;
esac
