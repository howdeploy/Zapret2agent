#!/usr/bin/env bash
# check-install-ready.sh — проверка готовности системы к установке zapret2
# Запускать ПЕРЕД началом установки
# Не требует root — только read-only проверки
# Вывод: JSON в stdout с полями ready/issues
# NOTE: -e intentionally omitted — script collects system info, must not abort on individual check failures
set -uo pipefail

issues=""
ready=true

# Проверить наличие curl
if command -v curl &>/dev/null; then
    curl_ok=true
else
    curl_ok=false
    issues="${issues:+$issues,}\"curl_missing\""
    ready=false
fi

# Проверить наличие tar
if command -v tar &>/dev/null; then
    tar_ok=true
else
    tar_ok=false
    issues="${issues:+$issues,}\"tar_missing\""
    ready=false
fi

# Проверить доступность sudo
if command -v sudo &>/dev/null; then
    sudo_ok=true
else
    sudo_ok=false
    issues="${issues:+$issues,}\"sudo_missing\""
    ready=false
fi

# Проверить свободное место в /tmp (нужно >= 200MB для tarball + распаковка)
disk_free_mb=$(df -m /tmp 2>/dev/null | awk 'NR==2 {print $4}')
disk_free_mb=${disk_free_mb:-0}
if [ "${disk_free_mb}" -lt 200 ]; then
    issues="${issues:+$issues,}\"low_disk_space\""
    ready=false
fi

# Проверить доступность GitHub API + получить последнюю версию
github_accessible=false
latest_version="unknown"
if [ "$curl_ok" = "true" ]; then
    github_response=$(curl -s --max-time 5 --connect-timeout 3 \
        https://api.github.com/repos/bol-van/zapret2/releases/latest 2>/dev/null || true)
    if [ -n "$github_response" ]; then
        github_accessible=true
        # Парсинг tag_name: предпочитаем python3, fallback на grep+cut
        if command -v python3 &>/dev/null; then
            latest_version=$(printf '%s' "$github_response" \
                | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tag_name','unknown'))" \
                2>/dev/null || echo "unknown")
        else
            latest_version=$(printf '%s' "$github_response" \
                | grep '"tag_name"' | head -1 | cut -d'"' -f4 || echo "unknown")
        fi
        [ -z "$latest_version" ] && latest_version="unknown"
    fi
fi

# Проверить: zapret2 уже установлен?
if [ -d /opt/zapret2 ]; then
    already_installed=true
else
    already_installed=false
fi

latest_version_safe=$(printf '%s' "$latest_version" | sed 's/"/\\"/g')

cat <<EOF
{
  "ready": $ready,
  "curl_ok": $curl_ok,
  "tar_ok": $tar_ok,
  "sudo_ok": $sudo_ok,
  "disk_free_mb": $disk_free_mb,
  "github_accessible": $github_accessible,
  "latest_version": "$latest_version_safe",
  "already_installed": $already_installed,
  "issues": [$issues]
}
EOF
