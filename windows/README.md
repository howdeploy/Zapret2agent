# Zapret2agent — Windows Edition

AI-агент для настройки обхода блокировок на Windows. Портирован с [Zapret2agent](https://github.com/howdeploy/Zapret2agent) для Linux.

Оборачивает [zapret-win-bundle](https://github.com/bol-van/zapret-win-bundle) (winws2.exe + WinDivert) в разговорный интерфейс — ты описываешь проблему, агент сам всё настраивает.

Совместим с **Claude Code** и **Codex CLI**.

---

## Что умеет

- Устанавливает zapret-win-bundle (winws2.exe + драйвер WinDivert)
- Автоматически подбирает лучшую стратегию обхода через blockcheck2
- Настраивает Windows-сервис (запускается при старте системы)
- Поддерживает два режима:
  - **Direct** — zapret → интернет (YouTube, Telegram, Discord)
  - **Tunnel** — zapret → VPN → интернет (когда провайдер режет само подключение к VPN)
- Автоматический откат, если новая стратегия сломала соединение
- Объяснения каждого шага на понятном русском

## Требования

- Windows 10 x64+ или Windows 11
- [Claude Code](https://claude.ai/download) или [Codex CLI](https://github.com/openai/codex)
- Права администратора

> **ARM64**: требуется включить тестовый режим подписи: `bcdedit /set testsigning on` + перезагрузка.

---

## Установка

**1. Установи Claude Code или Codex CLI** (если ещё не установлен).

**2. Скачай этот репозиторий** — нажми зелёную кнопку **Code → Download ZIP**, распакуй.

Или через git:
```powershell
git clone https://github.com/howdeploy/Zapret2agent
```

**3. Запусти установщик** — открой PowerShell **от имени Администратора** в папке репозитория:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Или дважды кликни `install.bat` (от имени Администратора).

> **Хочешь запускать из любой папки?** Добавь флаг `-Global`:
> ```powershell
> powershell -ExecutionPolicy Bypass -File install.ps1 -Global
> ```

**4. Добавь `C:\zapret` в исключения антивируса** (важно — до того как агент скачает zapret):
- Windows Defender: Параметры → Безопасность Windows → Защита от вирусов → Исключения → Добавить папку → `C:\zapret`

**5. Запусти агента** (от Администратора, из папки репозитория при локальной установке):
```
claude
```
или
```
codex
```

**6. Напиши:** `запусти диагностику` — агент сам разберётся что делать дальше.

---

## Как выглядит первый запуск

```
Ты: запусти диагностику
Агент: [запускает detect-state.ps1, показывает состояние системы]

Ты: установи zapret
Агент: [проверяет исключения антивируса, скачивает бандл, устанавливает сервис]

Ты: подбери стратегию
Агент: [запускает blockcheck2, выбирает лучшую стратегию, применяет с таймером отката]

Ты: работает
Агент: [отменяет таймер отката, готово]
```

---

## Навыки (Skills)

| Навык | Назначение |
|-------|-----------|
| `zapret-diagnose` | Диагностика системы — запускается первым всегда |
| `zapret-install` | Скачать zapret-win-bundle, создать сервис |
| `zapret-config` | Запустить blockcheck2, подобрать и применить стратегию |
| `zapret-manage` | Добавить/убрать домены, запустить/остановить сервис |
| `zapret-modes` | Переключить режим Direct (только zapret) / Tunnel (zapret + VPN) |

---

## Как это работает (технически)

1. **winws2.exe** (из zapret-win-bundle) перехватывает TCP/UDP пакеты через **драйвер WinDivert**
2. Lua-скрипты (`zapret-antidpi.lua` и др.) модифицируют пакеты так, чтобы ТСПУ/DPI не распознало их
3. Работает как **Windows-сервис** (`winws2`) — стартует автоматически при загрузке
4. Конфиг: `C:\zapret\config\zapret.conf` — одна строка аргументов для winws2
5. Стратегия подбирается через **blockcheck2**, который тестирует десятки техник обхода против твоего провайдера

---

## Отличия от Linux-версии

| | Linux | Windows |
|--|-------|---------|
| Перехват пакетов | iptables / nftables + nfqws | Драйвер WinDivert |
| Управление сервисом | systemd | Windows Service (sc.exe) |
| Скрипты | bash (.sh) | PowerShell (.ps1) |
| Таймер отката | фоновый процесс | Планировщик задач Windows |
| Путь установки | /opt/zapret2 | C:\zapret |

---

## Авторство

- Оригинальный Zapret2agent (Linux): [@howdeploy](https://github.com/howdeploy/Zapret2agent)
- zapret-win-bundle: [@bol-van](https://github.com/bol-van/zapret-win-bundle)
