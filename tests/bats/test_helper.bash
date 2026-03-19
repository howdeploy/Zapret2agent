#!/usr/bin/env bash
# test_helper.bash — общие helper-функции для bats-тестов zapret2agent
# Используется через: load test_helper

# Путь к директории скриптов zapret-diagnose
ZAPRET_DIAGNOSE_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.claude/skills/zapret-diagnose/scripts"

# setup_mocks() — создаёт mock-скрипты в $BATS_TEST_TMPDIR/bin/
# и добавляет их в начало PATH
setup_mocks() {
    local mock_bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$mock_bin"

    # mock: uname
    cat > "$mock_bin/uname" <<'MOCK'
#!/usr/bin/env bash
if [ "$1" = "-r" ]; then
    echo "6.1.0-test"
else
    echo "Linux testhost 6.1.0-test #1 SMP x86_64 GNU/Linux"
fi
MOCK

    # mock: ip
    cat > "$mock_bin/ip" <<'MOCK'
#!/usr/bin/env bash
# ip link show -> minimal eth0 output
# ip link show type wireguard -> empty (no VPN)
# ip tuntap show -> empty (no tun)
case "$*" in
    "link show")
        echo "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536"
        echo "    link/loopback 00:00:00:00:00:00"
        echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
        echo "    link/ether aa:bb:cc:dd:ee:ff"
        ;;
    "link show type wireguard")
        # no output = no wireguard
        ;;
    "tuntap show")
        # no output = no tun
        ;;
    "link show"*)
        echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
        ;;
    *)
        ;;
esac
MOCK

    # mock: systemctl
    cat > "$mock_bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    "--version")
        echo "systemd 999"
        ;;
    "is-active --quiet zapret2")
        exit 1
        ;;
    "is-active --quiet"*)
        exit 1
        ;;
    "status zapret2"*)
        echo "● zapret2.service - zapret2 DPI bypass"
        echo "   Loaded: loaded"
        echo "   Active: inactive (dead)"
        exit 3
        ;;
    *)
        exit 0
        ;;
esac
MOCK

    # mock: readlink
    cat > "$mock_bin/readlink" <<'MOCK'
#!/usr/bin/env bash
# -f flag: return the argument as-is (no symlink resolution in test)
if [ "$1" = "-f" ]; then
    echo "$2"
else
    echo "$1"
fi
MOCK

    # mock: pgrep — по умолчанию возвращает exit 1 (нет совпадающих процессов)
    cat > "$mock_bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
# Default: no matching processes
exit 1
MOCK

    # mock: curl — по умолчанию возвращает "203.0.113.1" (fake exit IP)
    cat > "$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock for exit IP detection
echo "203.0.113.1"
MOCK

    # mock: nfqws2 (не устанавливаем по умолчанию — zapret not installed)
    # Создаётся только явно в тестах где zapret_installed=true

    # Сделать mock-скрипты исполняемыми
    chmod +x "$mock_bin"/*

    # Добавить mock_bin в начало PATH
    export PATH="$mock_bin:$PATH"

    # Создать fake /etc/os-release
    mkdir -p "$BATS_TEST_TMPDIR/etc"
    create_fake_os_release "Test Linux 1.0"
}

# create_fake_os_release() — создаёт временный os-release файл
# Аргумент: PRETTY_NAME
create_fake_os_release() {
    local pretty_name="${1:-Test Linux 1.0}"
    cat > "$BATS_TEST_TMPDIR/etc/os-release" <<EOF
NAME="Test Linux"
PRETTY_NAME="$pretty_name"
ID=test
VERSION_ID="1.0"
EOF
}

# prepare_detect_state() — копирует и патчит detect-state.sh для тестов
# Заменяет хардкоженные пути на tmpdir-пути
# Устанавливает DETECT_STATE (путь к патченому скрипту)
prepare_detect_state() {
    local src="$ZAPRET_DIAGNOSE_SCRIPTS/detect-state.sh"
    local dst="$BATS_TEST_TMPDIR/detect-state.sh"

    cp "$src" "$dst"

    # Патчим /etc/os-release -> $BATS_TEST_TMPDIR/etc/os-release
    # shellcheck disable=SC2016
    sed -i "s|/etc/os-release|$BATS_TEST_TMPDIR/etc/os-release|g" "$dst"

    # Патчим /opt/zapret2/ -> $BATS_TEST_TMPDIR/opt/zapret2/
    # shellcheck disable=SC2016
    sed -i "s|/opt/zapret2/|$BATS_TEST_TMPDIR/opt/zapret2/|g" "$dst"

    # Создаём директорию (пустую — zapret не установлен)
    mkdir -p "$BATS_TEST_TMPDIR/opt/zapret2"

    chmod +x "$dst"
    export DETECT_STATE="$dst"
}

# prepare_health_check() — копирует и патчит health-check.sh для тестов
# Патчит путь к detect-state.sh и manage-service.sh
# Устанавливает HEALTH_CHECK (путь к патченому скрипту)
prepare_health_check() {
    local src="$ZAPRET_DIAGNOSE_SCRIPTS/health-check.sh"
    local dst="$BATS_TEST_TMPDIR/health-check.sh"

    cp "$src" "$dst"

    # Патчим detect-state.sh: SCRIPT_DIR будет $BATS_TEST_TMPDIR после патча
    # health-check.sh использует "${SCRIPT_DIR}/detect-state.sh"
    # Мы уже подготовили detect-state.sh в tmpdir через prepare_detect_state()
    # Патчим SCRIPT_DIR определение чтобы указывало на tmpdir
    # shellcheck disable=SC2016
    sed -i "s|SCRIPT_DIR=\$(dirname \"\$(readlink -f \"\$0\")\"))|SCRIPT_DIR=\"$BATS_TEST_TMPDIR\"|g" "$dst"
    # Альтернативный патч через замену строки
    sed -i "s|SCRIPT_DIR=\$(dirname \"\$(readlink -f.*|SCRIPT_DIR=\"$BATS_TEST_TMPDIR\"|g" "$dst"

    # Патчим путь к manage-service.sh: указываем на заглушку
    local fake_manage="$BATS_TEST_TMPDIR/manage-service.sh"
    # shellcheck disable=SC2016
    sed -i "s|MANAGE_SERVICE=.*|MANAGE_SERVICE=\"$fake_manage\"|g" "$dst"

    # Создаём fake manage-service.sh (возвращает статус "stopped")
    cat > "$fake_manage" <<'FAKE'
#!/usr/bin/env bash
echo '{"status": "stopped", "active": false}'
FAKE
    chmod +x "$fake_manage"

    chmod +x "$dst"
    export HEALTH_CHECK="$dst"
}

# create_wireguard_mock() — перезаписывает ip mock для показа WireGuard-интерфейса
create_wireguard_mock() {
    cat > "$BATS_TEST_TMPDIR/bin/ip" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
    "link show type wireguard")
        echo "3: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000"
        ;;
    "link show")
        echo "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536"
        echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
        echo "3: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420"
        ;;
    "tuntap show")
        ;;
    *) ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/ip"
}

# create_tun_mock(tun_name) — перезаписывает ip mock для показа TUN-интерфейса с заданным именем
create_tun_mock() {
    local tun_name="${1:-tun0}"
    cat > "$BATS_TEST_TMPDIR/bin/ip" <<MOCK
#!/usr/bin/env bash
case "\$*" in
    "link show type wireguard")
        ;;
    "link show")
        echo "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536"
        echo "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
        echo "3: ${tun_name}: <POINTOPOINT,UP,LOWER_UP> mtu 1500"
        ;;
    "tuntap show")
        echo "${tun_name}: tun"
        ;;
    *) ;;
esac
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/ip"
}

# create_pgrep_mock(process_name) — перезаписывает pgrep mock для совпадения конкретного процесса
# Поддерживает: pgrep -x name (exact), pgrep -fa pattern (full args)
create_pgrep_mock() {
    local proc_name="$1"
    cat > "$BATS_TEST_TMPDIR/bin/pgrep" <<MOCK
#!/usr/bin/env bash
# Mock: match process "$proc_name"
if [ "\$1" = "-x" ] && [ "\$2" = "${proc_name}" ]; then
    echo "12345"
    exit 0
fi
if [ "\$1" = "-fa" ]; then
    case "\$2" in
        *${proc_name}*) echo "12345 ${proc_name}"; exit 0 ;;
    esac
fi
exit 1
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/pgrep"
}

# teardown_mocks() — очистка (bats делает это автоматически через BATS_TEST_TMPDIR)
teardown_mocks() {
    : # bats автоматически удаляет BATS_TEST_TMPDIR
}
