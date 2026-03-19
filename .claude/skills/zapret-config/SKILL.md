# Настройка стратегии обхода DPI (zapret-config)

**Когда использовать:** пользователь говорит «настроить стратегию», «выбрать стратегию обхода», «запустить blockcheck», «обход не работает», «настройка zapret». Или агент определил что zapret2 установлен, но стратегия не настроена.

Если `.claude/skills/zapret-diagnose/scripts/detect-state.sh` показывает `zapret_installed: false` — сразу направить на установку через `.claude/skills/zapret-install/SKILL.md`.

---

## Секция 1: Предварительная проверка (обязательно)

Запустить:
```bash
bash .claude/skills/zapret-diagnose/scripts/detect-state.sh
```

Прочитать JSON-вывод и проверить:

| Поле | Что делать |
|------|------------|
| `zapret_installed: false` | «zapret2 не установлен. Сначала установи его — скажи мне "установить zapret".» СТОП. |
| `zapret_running: true` | Предупредить и предложить остановить (см. ниже) |
| `init_system` | Запомнить значение (`systemd` / `openrc`) — нужно для команд restart |
| `vpn_active: true` | Предупредить: «VPN активен. blockcheck2.sh нужно запускать без VPN — иначе тест будет некорректным.» |
| Mode check | Запустить `bash .claude/skills/zapret-modes/scripts/set-mode.sh status`. Если `current_mode: tunnel` — предупредить: «Сейчас выбран режим защиты туннеля. blockcheck тестирует обход блокировок сайтов — для маскировки VPN-протокола он не нужен. Продолжить тест blockcheck? Это может быть полезно если ты хочешь обходить блокировки и без VPN.» Если `current_mode: direct` или `current_mode: none` — продолжить без предупреждения. |

**Если `zapret_running: true`:**

Объяснить зачем нужно остановить:
```
blockcheck2.sh тестирует стратегии обхода. Если zapret2 работает — трафик уже проходит
через него, и тест покажет "working without bypass" вместо реального результата.
Нужно временно остановить zapret2 на время теста.

Вот что я хочу сделать:
  sudo systemctl stop zapret2   (или: sudo rc-service zapret2 stop)

После теста запустим его с новой стратегией. Остановить? (да/нет)
```

Выполнять остановку только после подтверждения пользователя (протокол безопасности из CLAUDE.md).

---

## Секция 2: Запуск blockcheck2.sh

Предупредить пользователя перед запуском:
```
Запускаю тест стратегий DPI-обхода. Это займёт 3-10 минут — зависит от провайдера.
Вывод будет показан в реальном времени. Не прерывай тест (Ctrl+C) — иначе нужно будет
запускать заново.
```

Запустить:
```bash
bash .claude/skills/zapret-config/scripts/run-blockcheck.sh
```

Скрипт выводит:
- `STARTING_BLOCKCHECK` — тест начался
- `OUTPUT_FILE=/path/...` — путь к файлу с выводом (нужен для парсинга)
- Полный live-вывод blockcheck2.sh (пользователь видит прогресс)
- `BLOCKCHECK_FINISHED` — тест завершён
- `BLOCKCHECK_OUTPUT_FILE=/path/...` — финальный путь (запомнить для следующего шага)
- `BLOCKCHECK_EXIT_CODE=N` — код завершения

Если `BLOCKCHECK_EXIT_CODE != 0` и файл пустой — сообщить об ошибке, показать что пошло не так.

---

## Секция 3: Парсинг и объяснение результатов

Запустить с путём из `BLOCKCHECK_OUTPUT_FILE`:
```bash
bash .claude/skills/zapret-config/scripts/parse-blockcheck-summary.sh /path/to/output-file.txt
```

Вывод — JSON. Обработать по вариантам:

**`error: "no_summary"` или `interrupted: true`:**
«Тест был прерван — секция SUMMARY отсутствует. Полных результатов нет. Запустить blockcheck снова?»

**`found_count: 0` и `without_bypass_count > 0`:**
«Все домены показали "working without bypass" — это значит, что тест запускался при работающем zapret2 (Pitfall 1). Результаты некорректны. Нужно остановить zapret2 и запустить blockcheck снова.»

**`found_count: 0` и `not_found_count > 0`:**
«Blockcheck не нашёл рабочей стратегии для этого провайдера на тестируемом домене. Можно попробовать другой домен или запустить blockcheck с расширенными тестами. Что предпочитаешь?»

**`found_count > 0` (основной случай):**

Показать пронумерованный список стратегий, объяснив каждую простым языком с помощью словаря параметров:

```
Словарь параметров (для перевода на русский):
--payload=tls_client_hello   → «Обход через TLS (HTTPS)»
--payload=http_req           → «Обход через HTTP»
--payload=quic_initial       → «Обход через QUIC (HTTP/3)»
--lua-desync=fake:...        → «Метод: отправка ложного пакета»
--lua-desync=multisplit:...  → «Метод: разбивка пакета на части»
--lua-desync=multidisorder:  → «Метод: перестановка частей пакета»
--lua-desync=wssize:...      → «Метод: уменьшение размера окна»
:tcp_md5                     → «с MD5-подписью TCP»
:ip4_ttl=N                   → «с TTL-ограничением для IPv4»
:tcp_seq=...                 → «с коррекцией TCP sequence»
```

Пример ответа агента:
```
Нашёл 2 рабочих варианта:

1. [TLS] Обход через HTTPS: ложный пакет с MD5-подписью
   Параметры: --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5
   Домен: rutracker.org

2. [HTTP] Обход через HTTP: разбивка пакета на части
   Параметры: --payload=http_req --lua-desync=multisplit:pos=method+2
   Домен: rutracker.org

Рекомендую вариант 1 — он нашёлся первым при тесте TLS 1.2, значит проще и надёжнее.
Какой применить? (1/2/все)
```

Если несколько стратегий для одного протокола (TLS) — рекомендовать первую найденную (она проверена первой = надёжнее).

---

## Секция 4: Формирование NFQWS2_OPT

На основе выбранных стратегий сформировать строки для `NFQWS2_OPT`.

**Маппинг `test_func` → параметры фильтрации:**

| test_func | --filter | --filter-l7 | HOSTLIST плейсхолдер |
|-----------|----------|-------------|----------------------|
| `curl_test_http` | `--filter-tcp=80` | `--filter-l7=http` | `<HOSTLIST>` |
| `curl_test_https_tls12` или `curl_test_https_tls13` | `--filter-tcp=443` | `--filter-l7=tls` | `<HOSTLIST>` |
| `curl_test_http3` | `--filter-udp=443` | `--filter-l7=quic` | `<HOSTLIST_NOAUTO>` |

**Формат одной строки:**
```
{--filter} {--filter-l7} {HOSTLIST} {params_из_blockcheck}
```

**Пример для стратегии 1 выше:**
```
--filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5
```

**Если пользователь выбрал "все"** (несколько стратегий для разных протоколов) — объединить через newline в одну `NFQWS2_OPT`.

**ЗАПРЕЩЕНО:** прямые пути `--hostlist=/path` и `--ipset=/path` — только плейсхолдеры `<HOSTLIST>` и `<HOSTLIST_NOAUTO>`.

Если стратегия из blockcheck содержит прямой путь — предупредить пользователя и убрать перед применением.

---

## Секция 5: Бэкап + показ diff + применение

Выполнять СТРОГО в этом порядке. Без бэкапа — не применять.

### Шаг 1: Создать бэкап

```bash
bash .claude/skills/zapret-config/scripts/backup-config.sh
```

Разобрать вывод:
- `BACKUP_CREATED=/path` → «Создал бэкап: {path}. Продолжаю.»
- `NO_CONFIG_TO_BACKUP` → ОСТАНОВИТЬСЯ: «Конфиг /opt/zapret2/config не найден. Это значит что zapret2 не установлен или установка прошла с ошибкой. Сначала установи zapret2.»

### Шаг 2: Показать что изменится

Прочитать текущий `/opt/zapret2/config`, найти строки `NFQWS2_OPT` и `NFQWS2_ENABLE`.

Показать пользователю:
```
Вот что я изменю в конфиге:

NFQWS2_ENABLE: 0 → 1
NFQWS2_OPT:
  БЫЛО:
    (текущее значение или "не задано")
  СТАНЕТ:
    --filter-tcp=443 --filter-l7=tls <HOSTLIST> --payload=tls_client_hello ...
```

### Шаг 3: Запросить подтверждение

Показать команду и спросить подтверждение (протокол безопасности из CLAUDE.md):
```
Вот что я хочу сделать: записать новую стратегию в /opt/zapret2/config

Применить? (да/нет)
```

Если пользователь ответил «нет» — не применять. Предложить выбрать другую стратегию из найденных.

### Шаг 4: Применить стратегию

```bash
sudo python3 .claude/skills/zapret-config/scripts/apply-strategy.py "содержимое_nfqws2_opt"
```

Проверить вывод:
- `STRATEGY_APPLIED=OK` → успешно, перейти к Секции 6
- Любая другая строка или ошибка → показать полный вывод, помочь разобраться

---

## Секция 6: Перезапуск сервиса

Выбрать команду на основе `init_system` из detect-state.sh:
- `systemd`: `sudo systemctl restart zapret2`
- `openrc`: `sudo rc-service zapret2 restart`

Показать команду и запросить подтверждение:
```
Вот что я хочу сделать: перезапустить zapret2 с новой стратегией
  sudo systemctl restart zapret2

Это запустит DPI-обход. На секунду сеть может моргнуть. Перезапустить? (да/нет)
```

После подтверждения — выполнить и сразу проверить статус:

**systemd:**
```bash
systemctl is-active zapret2
```

**openrc:**
```bash
rc-service zapret2 status
```

Сообщить результат:
- Сервис активен → «zapret2 запущен с новой стратегией. Проверь доступ к нужному сайту.»
- Сервис не запустился → Показать диагностику: `sudo systemctl status zapret2 --no-pager -l` и помочь разобраться с ошибкой.

---

## Секция 7: Управление бэкапами

### Показать список бэкапов

Пользователь спрашивает «какие бэкапы есть», «покажи бэкапы», «список бэкапов»:

```bash
bash .claude/skills/zapret-config/scripts/backup-config.sh list
```

Разобрать `BACKUP_LIST=file1,file2,...` и показать с человекочитаемыми датами:

```
Разбивка имени: config.20260318_142531 → 18.03.2026 14:25:31
```

Пример вывода агента:
```
Найдено 3 бэкапа:
  1. 18.03.2026 14:25:31  (config.20260318_142531)
  2. 18.03.2026 15:00:23  (config.20260318_150023)
  3. 18.03.2026 16:12:05  (config.20260318_161205)

Для восстановления — скажи номер или имя бэкапа.
```

Если `BACKUP_LIST=` (пустой) → «Бэкапов нет. Они создаются автоматически перед каждым изменением конфига.»

### Восстановить из бэкапа

Пользователь хочет восстановить конкретный бэкап:

```bash
bash .claude/skills/zapret-config/scripts/backup-config.sh restore config.20260318_142531
```

Разобрать вывод:
- `RESTORE_CMD=sudo cp /path/backup /opt/zapret2/config`

Показать команду пользователю и запросить подтверждение (протокол безопасности):
```
Вот что я хочу сделать:
  sudo cp /home/user/.zapret-backup/config.20260318_142531 /opt/zapret2/config

Это перезапишет текущий конфиг бэкапом от 18.03.2026 14:25. Восстановить? (да/нет)
```

После выполнения и подтверждения — предложить перезапустить сервис (Секция 6).

---

## Секция 8: Anti-patterns — что НЕЛЬЗЯ делать

**НЕ запускать blockcheck при работающем zapret2** (Pitfall 1)
— Тест покажет "working without bypass" для всех доменов. Результаты бесполезны. Всегда останавливать zapret2 перед тестом.

**НЕ использовать sed для редактирования NFQWS2_OPT** (Pitfall 2)
— NFQWS2_OPT — multiline переменная в двойных кавычках. sed ломается на переносах строк. Всегда использовать `apply-strategy.py`.

**НЕ забывать NFQWS2_ENABLE=1** (Pitfall 2)
— `config.default` имеет `NFQWS2_ENABLE=0`. Если это значение остаётся, nfqws2 не запустится. `apply-strategy.py` устанавливает `NFQWS2_ENABLE=1` автоматически — это защита от этой ошибки.

**НЕ использовать прямые пути --hostlist= в NFQWS2_OPT** (Pitfall 4)
— Ломает MODE_FILTER и скрипты обновления списков. Только `<HOSTLIST>` и `<HOSTLIST_NOAUTO>` плейсхолдеры.

**НЕ применять стратегию без бэкапа** (Pitfall 6)
— Если `NO_CONFIG_TO_BACKUP` — остановиться. Если `BACKUP_CREATED` — продолжать. Никогда не пропускать этот шаг.

**НЕ пропускать подтверждение перед sudo-операциями**
— Остановка сервиса, применение конфига, перезапуск сервиса, восстановление бэкапа — всё требует явного «да» от пользователя.

**НЕ запускать blockcheck с VPN** (смежный с Pitfall 1)
— Если `vpn_active: true` в detect-state.sh — предупредить и попросить отключить VPN перед тестом.

**НЕ запускать blockcheck для маскировки VPN-протокола**
— blockcheck тестирует обход блокировок веб-сайтов, а не маскировку VPN-трафика. Для режима tunnel используй готовые стратегии из `.claude/skills/zapret-modes/SKILL.md`, Секция 5.

---

## Скрипты

- Запуск теста: `.claude/skills/zapret-config/scripts/run-blockcheck.sh`
- Парсинг результатов: `.claude/skills/zapret-config/scripts/parse-blockcheck-summary.sh`
- Применение стратегии: `.claude/skills/zapret-config/scripts/apply-strategy.py`
- Бэкап конфига: `.claude/skills/zapret-config/scripts/backup-config.sh`
- Состояние системы: `.claude/skills/zapret-diagnose/scripts/detect-state.sh`

---

## Полный workflow (от запроса до работающего обхода)

```
1. Пользователь: «настроить стратегию»
   ↓
2. detect-state.sh → проверить zapret_installed, zapret_running, init_system, vpn_active
   ↓
3. Если zapret_running: true → объяснить + запросить подтверждение → остановить сервис
   ↓
4. run-blockcheck.sh → live-вывод теста (3-10 минут)
   ↓
5. parse-blockcheck-summary.sh → JSON с найденными стратегиями
   ↓
6. Объяснить стратегии на русском → пронумерованный список → запросить выбор
   ↓
7. Сформировать NFQWS2_OPT строки из маппинга testfunc → filter параметры
   ↓
8. backup-config.sh → BACKUP_CREATED → сообщить путь бэкапа
   ↓
9. Показать diff конфига (NFQWS2_OPT старое/новое) → запросить подтверждение
   ↓
10. apply-strategy.py → STRATEGY_APPLIED=OK
    ↓
11. Показать команду restart → запросить подтверждение → systemctl/rc-service restart
    ↓
12. Проверить статус → сообщить результат пользователю
```
