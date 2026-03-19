#!/usr/bin/env bash
# parse-blockcheck-summary.sh — парсинг SUMMARY-секции из вывода blockcheck2.sh
#
# Извлекает найденные стратегии nfqws2 из файла вывода blockcheck2.sh
# и возвращает структурированный JSON для агента.
#
# Использование:
#   parse-blockcheck-summary.sh /path/to/blockcheck-output.txt
#
# Вывод (JSON):
#   {
#     "found_count": N,
#     "strategies": [
#       {"test_func": "curl_test_https_tls12", "ipv": 4, "domain": "rutracker.org", "params": "--payload=..."},
#       ...
#     ],
#     "not_found_count": N,
#     "without_bypass_count": N
#   }
#
# Ошибочные состояния (также JSON):
#   {"error": "file_not_found"}
#   {"error": "no_summary", "interrupted": true}
#
# Источник формата SUMMARY: исходный код blockcheck2.sh строки 1145-1157
#   eval REPORT_N="$2 $1 : $3"
#   где $2="testfunc ipvN", $1=domain, $3="nfqws2 <params or status>"
#   report_print выводит: "{testfunc} ipv{N} {domain} : nfqws2 {strategy_or_status}"

# NOTE: -e intentionally omitted — script parses output, must not abort on individual parse failures
set -uo pipefail

OUTPUT_FILE="${1:-}"

# Проверяем что файл передан и существует
if [ -z "$OUTPUT_FILE" ] || [ ! -f "$OUTPUT_FILE" ]; then
    echo '{"error": "file_not_found"}'
    exit 1
fi

# Проверяем что тест завершился нормально (есть секция * SUMMARY)
if ! grep -q "^\* SUMMARY" "$OUTPUT_FILE"; then
    echo '{"error": "no_summary", "interrupted": true}'
    exit 0
fi

# Извлекаем секцию от "* SUMMARY" до "Please note this SUMMARY"
summary_lines=$(awk '/^\* SUMMARY$/,/^Please note this SUMMARY/' "$OUTPUT_FILE")

# Строки с найденными стратегиями: содержат " nfqws2 ", не содержат "not found",
# "not working", "working without bypass", "Please note"
found_strategies=$(echo "$summary_lines" \
    | grep " nfqws2 " \
    | grep -v " not working" \
    | grep -v "working without bypass" \
    | grep -v "not found" \
    | grep -v "Please note" \
    || true)

# Строки с ненайденными стратегиями
not_found=$(echo "$summary_lines" \
    | grep "not found\|not working" \
    | grep -v "Please note" \
    || true)

# Строки "работало без обхода" (запрос не был заблокирован или запущено при активном zapret)
without_bypass=$(echo "$summary_lines" \
    | grep "working without bypass" \
    || true)

# Формируем JSON через python3 (парсинг строк и сборка структуры)
# Передаём данные через stdin (три секции разделены NUL-байтом) для защиты от command injection
printf '%s\0%s\0%s' "$found_strategies" "$not_found" "$without_bypass" | python3 -c "
import sys, json, re

data = sys.stdin.buffer.read().split(b'\x00')
found = data[0].decode('utf-8', errors='replace').strip()
not_found_str = data[1].decode('utf-8', errors='replace').strip() if len(data) > 1 else ''
without_bp = data[2].decode('utf-8', errors='replace').strip() if len(data) > 2 else ''

strategies = []
for line in found.splitlines():
    line = line.strip()
    if not line:
        continue
    # Парсим: 'testfunc ipvN domain : nfqws2 params'
    # Источник: blockcheck2.sh eval REPORT_N строка, где \$2='testfunc ipvN', \$1=domain, \$3='nfqws2 <params>'
    m = re.match(r'(\S+)\s+ipv(\d)\s+(\S+)\s+:\s+nfqws2\s+(.+)', line)
    if m:
        strategies.append({
            'test_func': m.group(1),
            'ipv': int(m.group(2)),
            'domain': m.group(3),
            'params': m.group(4).strip()
        })

result = {
    'found_count': len(strategies),
    'strategies': strategies,
    'not_found_count': len([l for l in not_found_str.splitlines() if l.strip()]),
    'without_bypass_count': len([l for l in without_bp.splitlines() if l.strip()])
}
print(json.dumps(result, ensure_ascii=False, indent=2))
"
