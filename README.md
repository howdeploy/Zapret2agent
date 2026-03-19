![Claude Code](https://img.shields.io/badge/Claude_Code-black?logo=anthropic&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

[**RU**](#ru) | [**EN**](#en)

---

<a name="ru"></a>

# zapret2agent

AI-агент на базе [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) для настройки обхода DPI-блокировок через [zapret2](https://github.com/bol-van/zapret).

## Что это

Обёртка над zapret2 — низкоуровневым инструментом обхода DPI. Вместо ручной настройки iptables и nfqws ты разговариваешь с агентом: он сам разбирается в системе, задаёт вопросы и делает всё по шагам.

Не нужно знать что такое DPI, nfqws или iptables — агент объяснит каждый шаг и предложит правильный вариант для твоей системы.

## Возможности

- Диагностика системы (ОС, ядро, тип firewall, VPN, DNS-отравление)
- Установка zapret2 с нуля через пошаговый диалог
- Автоматический подбор стратегии обхода (через blockcheck)
- Два режима работы: прямой обход (без VPN) / защита туннеля (с VPN)
- Определение VPN-клиента при запуске (Throne, Nekoray, Hiddify, v2rayA, AmneziaVPN, Clash, sing-box, WireGuard, OpenVPN)
- Управление сервисом (старт, стоп, рестарт, статус)
- Управление списком доменов (добавить, удалить, просмотреть)
- Полный seed-список ТСПУ-блокировок с автоматическим мержем
- Бэкап и восстановление конфигурации
- Таймер отката для безопасных изменений iptables/nftables

## Требования

- **Linux**: Ubuntu, Fedora, Arch, Manjaro
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) — установлен и авторизован
- git, bash, curl, sudo, ip
- dig — опционально (для проверки DNS)

> **macOS / Windows:** не поддерживается. zapret2 использует nfqws (Linux netfilter). На macOS есть ограниченная поддержка через tpws, на Windows — через WinDivert, но этот агент их не реализует.

## Быстрый старт

```bash
git clone https://github.com/howdeploy/Zapret2agent.git
cd Zapret2agent
claude
```

Агент поприветствует тебя и предложит меню. Скажи что нужно — установить, настроить или починить.

## Как это работает

Проект состоит из трёх слоёв:

**CLAUDE.md** — инструкции для агента: как себя вести, что говорить, протокол безопасности. Читается Claude Code автоматически при запуске.

**.claude/skills/** — пять скиллов с детальными процедурами:
- `zapret-diagnose` — диагностика системы
- `zapret-install` — установка zapret с нуля
- `zapret-config` — настройка стратегии обхода
- `zapret-manage` — управление сервисом и списками
- `zapret-modes` — режимы работы (прямой обход / защита туннеля)

**scripts/** — bash и python скрипты для надёжных операций: диагностика системы, бэкапы конфигов, парсинг результатов blockcheck, применение стратегий.

## Безопасность

Перед каждой системной операцией (iptables, systemctl, запись в конфиг) агент показывает точную команду и ждёт подтверждения. Без «да» — ничего не выполняется.

Перед изменением iptables/nftables автоматически запускается таймер отката на 5 минут. Если что-то пошло не так — правила откатятся сами.

Конфигурация `/opt/zapret2/config` бэкапится автоматически перед каждым изменением.

## Ручное управление zapret2

Если агент сломался или нужно управлять zapret вручную:

```bash
# Статус сервиса
sudo systemctl status zapret2

# Остановить
sudo systemctl stop zapret2

# Отключить автозапуск
sudo systemctl disable zapret2

# Включить обратно
sudo systemctl enable zapret2 && sudo systemctl start zapret2

# Полное удаление
sudo /opt/zapret2/uninstall_easy.sh
```

## Ссылки

- zapret2: https://github.com/bol-van/zapret
- Claude Code: https://docs.anthropic.com/en/docs/claude-code/overview

---

<a name="en"></a>

# zapret2agent

AI agent powered by [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) for configuring DPI bypass via [zapret2](https://github.com/bol-van/zapret).

## What is this

A wrapper around zapret2 — a low-level DPI bypass tool. Instead of manually configuring iptables and nfqws, you talk to an agent: it analyzes your system, asks questions, and walks you through everything step by step.

No need to know what DPI, nfqws, or iptables are — the agent explains each step and suggests the right option for your system.

## Features

- System diagnostics (OS, kernel, firewall type, VPN, DNS poisoning)
- Full zapret2 installation through a guided dialog
- Automatic bypass strategy selection (via blockcheck)
- Two operating modes: direct bypass (no VPN) / tunnel protection (with VPN)
- VPN client detection at startup (Throne, Nekoray, Hiddify, v2rayA, AmneziaVPN, Clash, sing-box, WireGuard, OpenVPN)
- Service management (start, stop, restart, status)
- Domain list management (add, remove, view)
- Full TSPU block seed list with automatic merging
- Configuration backup and restore
- Rollback timer for safe iptables/nftables changes

## Requirements

- **Linux**: Ubuntu, Fedora, Arch, Manjaro
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) — installed and authorized
- git, bash, curl, sudo, ip
- dig — optional (for DNS checks)

> **macOS / Windows:** not supported. zapret2 uses nfqws (Linux netfilter). macOS has limited support via tpws, Windows via WinDivert, but this agent does not implement them.

## Quick start

```bash
git clone https://github.com/howdeploy/Zapret2agent.git
cd Zapret2agent
claude
```

The agent will greet you and offer a menu. Tell it what you need — install, configure, or troubleshoot.

## How it works

The project has three layers:

**CLAUDE.md** — agent instructions: behavior, safety protocol, conversation style. Automatically loaded by Claude Code when launched in the repo directory.

**.claude/skills/** — five skills with detailed procedures:
- `zapret-diagnose` — system diagnostics
- `zapret-install` — zapret installation from scratch
- `zapret-config` — bypass strategy configuration
- `zapret-manage` — service and list management
- `zapret-modes` — operating modes (direct bypass / tunnel protection)

**scripts/** — bash and python scripts for reliable operations: system diagnostics, config backups, blockcheck result parsing, strategy application.

## Security

Before every system operation (iptables, systemctl, config writes), the agent shows the exact command and waits for confirmation. Nothing runs without an explicit "yes".

Before modifying iptables/nftables, a 5-minute rollback timer starts automatically. If something goes wrong — the rules revert on their own.

The `/opt/zapret2/config` is backed up automatically before every change.

## Manual zapret2 control

If the agent breaks or you need to manage zapret manually:

```bash
# Service status
sudo systemctl status zapret2

# Stop
sudo systemctl stop zapret2

# Disable autostart
sudo systemctl disable zapret2

# Re-enable
sudo systemctl enable zapret2 && sudo systemctl start zapret2

# Full removal
sudo /opt/zapret2/uninstall_easy.sh
```

## Links

- zapret2: https://github.com/bol-van/zapret
- Claude Code: https://docs.anthropic.com/en/docs/claude-code/overview

---

Built with [Claude Code](https://claude.ai/claude-code)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
