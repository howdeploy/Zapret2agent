#!/usr/bin/env bash
# run-blockcheck.sh — запуск blockcheck2.sh с захватом вывода
#
# Wrapper для безопасного запуска blockcheck2.sh с дублированием вывода в файл.
# Агент вызывает этот скрипт после подтверждения пользователя.
# ВАЖНО: запускать только с остановленным zapret2 (иначе результаты некорректны).
#
# Использование:
#   run-blockcheck.sh [ZAPRET_DIR]   — запустить blockcheck2.sh из ZAPRET_DIR
#
# Аргументы:
#   ZAPRET_DIR — директория zapret2 (дефолт: /opt/zapret2)
#
# Stdout-протокол:
#   STARTING_BLOCKCHECK
#   OUTPUT_FILE=/home/user/.zapret-blockcheck/blockcheck-YYYYMMDD_HHMMSS.txt
#   <вывод blockcheck2.sh в реальном времени>
#   BLOCKCHECK_FINISHED
#   BLOCKCHECK_OUTPUT_FILE=/home/user/.zapret-blockcheck/blockcheck-YYYYMMDD_HHMMSS.txt
#   BLOCKCHECK_EXIT_CODE=N
#
# Примечание: НЕ останавливает zapret2 сам — это решение агента на уровне SKILL.md.

# NOTE: -e intentionally omitted — script collects blockcheck output, must not abort on individual check failures
set -uo pipefail

ZAPRET_DIR="${1:-/opt/zapret2}"
BLOCKCHECK="${ZAPRET_DIR}/blockcheck2.sh"
OUTPUT_DIR="${HOME}/.zapret-blockcheck"
OUTPUT_FILE="${OUTPUT_DIR}/blockcheck-$(date +%Y%m%d_%H%M%S).txt"

# Проверяем наличие blockcheck2.sh
if [ ! -f "$BLOCKCHECK" ]; then
    echo "ERROR_NO_BLOCKCHECK: blockcheck2.sh not found in ${ZAPRET_DIR}" >&2
    exit 1
fi

# Создаём директорию для хранения выводов
mkdir -p "$OUTPUT_DIR"

# Структурированный stdout-протокол
echo "STARTING_BLOCKCHECK"
echo "OUTPUT_FILE=${OUTPUT_FILE}"

# Запускаем blockcheck2.sh через sudo с перенаправлением в файл + на экран
# tee позволяет агенту видеть прогресс в реальном времени И сохранять вывод для парсинга
# PIPESTATUS[0] захватывает exit code blockcheck2.sh, не tee
cd "$ZAPRET_DIR" && sudo bash blockcheck2.sh 2>&1 | tee "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}

echo "BLOCKCHECK_FINISHED"
echo "BLOCKCHECK_OUTPUT_FILE=${OUTPUT_FILE}"
echo "BLOCKCHECK_EXIT_CODE=${EXIT_CODE}"
