#!/usr/bin/env python3
# apply-strategy.py — записать новую стратегию в /opt/zapret2/config
#
# Обновляет переменную NFQWS2_OPT в конфиг-файле zapret2 и включает NFQWS2_ENABLE=1.
# Использует python3 stdlib (re) вместо sed — sed ломается на multiline-переменных.
#
# Использование:
#   apply-strategy.py "<nfqws2_params>"
#
# Аргументы:
#   sys.argv[1] — новое содержимое NFQWS2_OPT (может быть многострочным)
#
# Env vars:
#   ZAPRET_CONFIG — путь к конфиг-файлу (дефолт: /opt/zapret2/config)
#
# Stdout-протокол:
#   STRATEGY_APPLIED=OK
#   CONFIG_PATH=/opt/zapret2/config
#
# Stderr:
#   ERROR: empty strategy
#   ERROR: config not found: /path
#
# Источник: config.default строки 87-91 (структура NFQWS2_OPT)
#           config.default строка 68 (NFQWS2_ENABLE=0 дефолт)
#           manual.en.md строки 4882-4927 (правила NFQWS2_OPT)

import sys
import re
import os

CONFIG_PATH = os.environ.get('ZAPRET_CONFIG', '/opt/zapret2/config')
new_strategy = sys.argv[1] if len(sys.argv) > 1 else ""

# Проверяем что стратегия не пустая
if not new_strategy.strip():
    print("ERROR: empty strategy", file=sys.stderr)
    sys.exit(1)

# Проверяем что конфиг-файл существует
if not os.path.exists(CONFIG_PATH):
    print(f"ERROR: config not found: {CONFIG_PATH}", file=sys.stderr)
    sys.exit(1)

# Проверяем права на запись перед модификацией конфига
if not os.access(CONFIG_PATH, os.W_OK):
    print(f"ERROR: no write permission for {CONFIG_PATH}. Run with sudo.", file=sys.stderr)
    sys.exit(1)

with open(CONFIG_PATH, 'r') as f:
    content = f.read()

# Обновляем NFQWS2_OPT (multiline-переменная в двойных кавычках)
# Паттерн NFQWS2_OPT="..." охватывает всё содержимое включая переносы строк (re.DOTALL)
# Источник: config.default формат NFQWS2_OPT="...\n...\n"
pattern = r'NFQWS2_OPT="[^"]*"'
replacement = f'NFQWS2_OPT="\n{new_strategy.strip()}\n"'
new_content, n = re.subn(pattern, replacement, content, flags=re.DOTALL)

if n == 0:
    # NFQWS2_OPT отсутствует в конфиге — добавляем в конец файла
    new_content = content.rstrip() + f'\n\nNFQWS2_OPT="\n{new_strategy.strip()}\n"\n'

# Включаем NFQWS2_ENABLE=1 (дефолт в config.default = 0; стратегия не применится без этого)
# Источник: config.default строка 68: NFQWS2_ENABLE=0
# Pitfall 2 (RESEARCH.md): забыть включить NFQWS2_ENABLE=1 — стратегия не работает
# Regex покрывает: NFQWS2_ENABLE=0, #NFQWS2_ENABLE=0, # NFQWS2_ENABLE=0, NFQWS2_ENABLE=1 (идемпотентно)
new_content = re.sub(r'^#?\s*NFQWS2_ENABLE=\d+', 'NFQWS2_ENABLE=1', new_content, flags=re.MULTILINE)

# Атомарная запись через tmpfile + os.rename (защита от повреждения конфига при crash)
# os.rename() — атомарная операция на одной FS, гарантирует целостность
tmp_path = CONFIG_PATH + '.tmp'
try:
    with open(tmp_path, 'w') as f:
        f.write(new_content)
    os.rename(tmp_path, CONFIG_PATH)
except Exception:
    # Очищаем tmpfile при ошибке
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print("STRATEGY_APPLIED=OK")
print(f"CONFIG_PATH={CONFIG_PATH}")
