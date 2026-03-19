# Установка zapret2

**Когда использовать:** пользователь хочет установить zapret2 с нуля. Триггеры: «установи zapret», «поставь zapret», «как установить», «установка zapret».

Если `.claude/skills/zapret-diagnose/scripts/detect-state.sh` показывает `zapret_installed: true` — спросить: «zapret2 уже установлен. Хочешь обновить до последней версии?» Если да — следовать Секции 6 (Режим обновления).

---

## Порядок установки (4 фазы)

### Фаза 1: Pre-check

Запустить:
```bash
bash .claude/skills/zapret-install/scripts/check-install-ready.sh
```

Прочитать JSON-вывод.

| Поле | Что делать |
|------|------------|
| `ready: false` | Показать `issues[]`, помочь решить (см. ниже) |
| `already_installed: true` | Предупредить: «zapret2 уже установлен — будет обновление» |
| `github_accessible: false` | «GitHub недоступен. Проверь интернет-соединение.» |
| `disk_free_mb < 200` | «Мало места на /tmp — нужно освободить минимум 200 МБ» |
| `ready: true` | Сообщить актуальную версию (`latest_version`) и продолжать |

**Решение проблем из issues[]:**
- `curl_missing` → `sudo apt-get install curl` / `sudo pacman -S curl` / `sudo dnf install curl`
- `tar_missing` → `sudo apt-get install tar`
- `sudo_missing` → требует ручной настройки sudo — объяснить пользователю
- `low_disk_space` → предложить очистить /tmp: `rm -rf /tmp/zapret2*`

### Фаза 2: Скачать release с GitHub

Показать команды пользователю и попросить подтверждение перед запуском (протокол безопасности из CLAUDE.md).

```bash
LATEST=$(curl -s https://api.github.com/repos/bol-van/zapret2/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
curl -L --progress-bar \
  "https://github.com/bol-van/zapret2/releases/download/${LATEST}/zapret2-${LATEST}.tar.gz" \
  -o "/tmp/zapret2-${LATEST}.tar.gz"
tar -xzf "/tmp/zapret2-${LATEST}.tar.gz" -C /tmp/
cd "/tmp/zapret2-${LATEST}"
```

**Важно:** НЕ git clone. Бинарники есть только в release-архиве с GitHub. Через git clone папка `binaries/` будет пустой и установка завершится ошибкой.

После скачивания сообщить: «Скачал zapret2 {LATEST}, распаковал в /tmp/zapret2-{LATEST}.»

### Фаза 3: Установить зависимости

Объяснить: «Сейчас запустим скрипт, который установит системные пакеты (curl, iptables/nftables, ipset). Нужен пароль sudo.»

Показать команду и запросить подтверждение:
```bash
cd /tmp/zapret2-${LATEST}
sudo ./install_prereq.sh
```

Проверить что скрипт завершился без ошибок. Если ошибка — показать полный вывод.

### Фаза 4: Запустить install_easy.sh

Перед запуском — **показать шпаргалку ответов** (Секция 3). Для firewall type — запустить `.claude/skills/zapret-diagnose/scripts/detect-state.sh` и определить правильный ответ по `firewall_backend` (маппинг в Секции 3).

Сообщить: «Сейчас запустится интерактивный установщик. Я подготовил ответы на каждый вопрос — смотри шпаргалку ниже. Ты отвечаешь сам, я объясняю что происходит.»

```bash
cd /tmp/zapret2-${LATEST}
sudo ./install_easy.sh
```

Во время установки — не автоматизировать ввод через pipe. Пользователь отвечает сам по шпаргалке.

---

## Шпаргалка ответов install_easy.sh

Показывать пользователю **перед** запуском install_easy.sh:

```
Вопрос                                       Ответ
---------------------------------------------------------------------
copy to /opt/zapret2?                     →  Y
keep config during reinstall?             →  Y (обновление) / N (свежая установка)
firewall type [iptables/nftables]         →  на основе detect-state.sh (см. ниже)
enable ipv6 support?                      →  N
flow offloading [none/software/hardware]  →  1 (none)
select filtering [none/ipset/host/auto]   →  4 (autohostlist)  ← самый важный!
enable nfqws2?                            →  Y
edit nfqws2 options?                      →  N
LAN interface                             →  1 (NONE)
WAN interface                             →  1 (ANY)
auto download host list?                  →  Y
select list                               →  нажать Enter (get_antizapret_domains.sh, дефолт)
```

**Маппинг firewall_backend → ответ:**
- `firewall_backend: iptables-legacy` → `1` (iptables)
- `firewall_backend: iptables-nft` → `2` (nftables) — iptables-nft это frontend над nftables
- `firewall_backend: nftables` → `2` (nftables)
- `firewall_backend: iptables` → `1` (iptables)
- `firewall_backend: unknown` → объяснить оба варианта, спросить пользователя

---

## Объяснения каждого вопроса install_easy.sh

Объяснения для пользователя — простым языком, без канцелярита.

### 1. copy to /opt/zapret2?
```
easy install is supported only from default location : /opt/zapret2
currently its run from /tmp/zapret2-v0.x.y
do you want the installer to copy it for you (default : N) (Y/N) ?
```
«Скрипт просит скопировать себя в стандартное место /opt/zapret2. Отвечаем **Y** — это правильное место для zapret2.»

### 2. keep config during reinstall? (условно — только при обновлении)
```
do you want to delete all files there and copy this version (default : N) (Y/N) ?
keep config, custom scripts and user lists (default : Y) (Y/N) ?
```
«zapret2 уже установлен. Первый вопрос: заменить файлы новой версией — **Y**. Второй: сохранить твои настройки — **Y**.»

### 3. firewall type
```
select firewall type :
1 : iptables
2 : nftables
your choice (default : nftables) :
```
«Это тип файрвола на твоей системе. Я уже проверил через detect-state.sh — у тебя `{firewall_backend}`, выбираем `{N}`. Ошибёшься — zapret не будет работать, поэтому важно выбрать правильно.»

### 4. enable ipv6 support?
```
enable ipv6 support (default : N) (Y/N) ?
```
«IPv6 нужен только если ты используешь IPv6 для выхода в интернет. Для большинства домашних пользователей России — нет. Оставляем **N**.»

### 5. flow offloading
```
select flow offloading :
1 : none
2 : software
3 : hardware
your choice (default : none) :
```
«Ускорение маршрутизации трафика. На обычном компьютере или ноутбуке это не нужно — только на роутерах с медленным CPU. Выбираем **1 (none)**.»

### 6. select filtering — самый важный вопрос!
```
select filtering :
1 : none
2 : ipset
3 : hostlist
4 : autohostlist
your choice (default : none) :
```
«Это самый важный выбор. **autohostlist (4)** — умный режим: DPI-обход применяется автоматически только к сайтам, которые реально заблокированы. none (1) — пропускает весь трафик через обход, что ломает VPN, игровые серверы и другие сервисы. Выбираем **4 (autohostlist)**.»

### 7a. enable nfqws2?
```
enable nfqws2 ? (default : 0) (Y/N) ?
```
«nfqws2 — это основной движок DPI-обхода. Без него zapret2 не будет ничего делать. Включаем — **Y**.»

### 7b. edit nfqws2 options?
```
do you want to edit the options (default : N) (Y/N) ?
```
«Скрипт показывает текущие настройки nfqws2. Дефолтные значения хорошо работают для большинства российских провайдеров. Менять не нужно — **N**.»

### 8a. LAN interface
```
LAN interface :
1 : NONE
2 : lo
3 : eth0
4 : wlan0
your choice (default : NONE) :
```
«LAN-интерфейс нужен только если ты раздаёшь интернет другим устройствам (роутер). На обычном компьютере — **1 (NONE)**.»

### 8b. WAN interface
```
WAN interface :
1 : ANY
2 : lo
3 : eth0
4 : wlan0
your choice (default : ANY) :
```
«WAN — через какой сетевой адаптер применять обход. **ANY** = применять ко всем интерфейсам, это правильно для обычного компьютера.»

### 9. auto download host list?
```
do you want to auto download ip/host list (default : Y) (Y/N) ?
```
«Список заблокированных доменов. Скачать — **Y**. Без списка autohostlist не будет работать с самого начала.»

### 9b. select list
```
1 : get_refilter_domains.sh
2 : get_antizapret_domains.sh
3 : get_reestr_resolvable_domains.sh
your choice (default : get_antizapret_domains.sh) :
```
«`antizapret` — наиболее полный и актуальный список для России. Нажимаем **Enter** (дефолт подходит).»

---

## После установки

### Шаг 1: Запустить verify-install.sh
```bash
bash .claude/skills/zapret-install/scripts/verify-install.sh
```

### Шаг 2: Интерпретировать результат

| Поле | Значение | Реакция агента |
|------|----------|----------------|
| `success: true` | Всё хорошо | Поздравить: «zapret2 установлен и запущен!» |
| `service_running: false` | Сервис не работает | Показать: `journalctl -u zapret2 -n 20` для диагностики |
| `binary_ok: false` | Бинарник не найден | «Ошибка установки бинарников. Повтори Фазу 2-3 с чистого архива» |
| `config_exists: false` | Нет конфига | «install_easy.sh не создал конфиг. Проверь вывод скрипта на ошибки» |
| `dns_hijack_suspected: true` | DNS отравлен | Предупредить (см. ниже) |

### Шаг 3: Проверить статус сервиса
```bash
systemctl status zapret2
```

### Шаг 4: DNS hijack предупреждение

Если `dns_hijack_suspected: true` — **обязательно** сообщить:
«zapret2 установлен и работает, но обнаружено подозрение на DNS-отравление. zapret2 обходит DPI-блокировки на уровне пакетов, но не решает DNS-блокировку. Если сайты всё равно не открываются — нужно дополнительно настроить DNS. Это отдельная задача.»

### Шаг 5: Следующий шаг

После успешной установки напомнить: «Теперь нужно настроить стратегию обхода — скажи мне "настроить стратегию" или "проверить что работает".»

---

## Режим обновления

Если detect-state.sh показывает `zapret_installed: true`:

1. Спросить: «zapret2 уже установлен. Хочешь обновить до {latest_version}? Сервис будет остановлен на время обновления.»
2. Те же 4 фазы установки.
3. При вопросах install_easy.sh — особые ответы:
   - «do you want to delete all files and copy this version» → **Y**
   - «keep config, custom scripts and user lists» → **Y** (сохранить настройки)
4. install_easy.sh сам остановит сервис перед обновлением — агент только предупреждает.
5. После обновления — запустить verify-install.sh как обычно.

---

## Скрипты

- Pre-flight: `.claude/skills/zapret-install/scripts/check-install-ready.sh`
- Post-install: `.claude/skills/zapret-install/scripts/verify-install.sh`
- Состояние системы: `.claude/skills/zapret-diagnose/scripts/detect-state.sh`
