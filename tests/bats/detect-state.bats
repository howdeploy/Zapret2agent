#!/usr/bin/env bats
# detect-state.bats — тесты для detect-state.sh
# Запуск: bats tests/bats/detect-state.bats

load test_helper

setup() {
    setup_mocks
    prepare_detect_state
}

teardown() {
    teardown_mocks
}

# --- Тест 1: Валидный JSON ---
@test "выводит валидный JSON" {
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null
}

# --- Тест 2: Все 16 полей присутствуют ---
@test "JSON содержит все 16 полей" {
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    python3 -c "
import sys, json
d = json.loads('''$output''')
required = [
    'os', 'kernel', 'init_system', 'firewall_backend',
    'vpn_active', 'vpn_type', 'vpn_client', 'vpn_protocol_family', 'exit_ip',
    'zapret_installed', 'zapret_version',
    'zapret_running', 'zapret_config_exists',
    'dns_ok', 'dns_hijack_suspected', 'interfaces'
]
missing = [k for k in required if k not in d]
if missing:
    print('Missing fields: ' + ', '.join(missing))
    sys.exit(1)
print('All 16 fields present')
"
}

# --- Тест 3: Определяет ОС из os-release ---
@test "определяет ОС из os-release" {
    create_fake_os_release "Test Linux 1.0"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    local os_val
    os_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['os'])")
    [ "$os_val" = "Test Linux 1.0" ]
}

# --- Тест 4: vpn_active=false когда нет VPN ---
@test "vpn_active=false когда нет VPN" {
    # Моки ip уже возвращают пустой вывод для wireguard и tuntap
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    local vpn_val
    vpn_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(str(d['vpn_active']).lower())")
    [ "$vpn_val" = "false" ]
}

# --- Тест 5: zapret_installed=false когда нет nfqws2 ---
@test "zapret_installed=false когда нет nfqws2" {
    # nfqws2 не установлен (нет в PATH через мок и нет /opt/zapret2/nfqws2)
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    local installed_val
    installed_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(str(d['zapret_installed']).lower())")
    [ "$installed_val" = "false" ]
}

# --- Тест 6: zapret_installed=true когда есть nfqws2 ---
@test "zapret_installed=true когда есть nfqws2" {
    # Создаём fake nfqws2 в fake /opt/zapret2/nfq2/
    mkdir -p "$BATS_TEST_TMPDIR/opt/zapret2/nfq2"
    cat > "$BATS_TEST_TMPDIR/opt/zapret2/nfq2/nfqws2" <<'FAKE'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
    echo "nfqws2 v1.2.3"
fi
FAKE
    chmod +x "$BATS_TEST_TMPDIR/opt/zapret2/nfq2/nfqws2"

    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    local installed_val
    installed_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(str(d['zapret_installed']).lower())")
    [ "$installed_val" = "true" ]
}

# --- Тест 7: dns_ok=true без dig (degraded mode) ---
@test "dns_ok=true без dig (degraded mode)" {
    # dig не создавался в setup_mocks — он отсутствует в PATH
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    local dns_ok_val
    dns_ok_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(str(d['dns_ok']).lower())")
    [ "$dns_ok_val" = "true" ]
    local dns_hijack_val
    dns_hijack_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(str(d['dns_hijack_suspected']).lower())")
    [ "$dns_hijack_val" = "false" ]
}

# --- Тест 8: init_system=systemd при наличии systemctl ---
@test "init_system=systemd при наличии systemctl" {
    # Мок systemctl уже создан в setup_mocks
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    local init_val
    init_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['init_system'])")
    [ "$init_val" = "systemd" ]
}

# --- VPN Detection Tests ---

# --- Тест 9: WireGuard detection ---
@test "vpn_client=wireguard при WireGuard интерфейсе" {
    create_wireguard_mock
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'wireguard', f'vpn_client should be wireguard, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'wireguard', f'vpn_protocol_family should be wireguard, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 10: OpenVPN detection ---
@test "vpn_client=openvpn при запущенном openvpn процессе" {
    create_pgrep_mock "openvpn"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'openvpn', f'vpn_client should be openvpn, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'openvpn', f'vpn_protocol_family should be openvpn, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 11: Nekoray via TUN name ---
@test "vpn_client=nekoray при TUN-интерфейсе nekoray-tun" {
    create_tun_mock "nekoray-tun"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'nekoray', f'vpn_client should be nekoray, got {d[\"vpn_client\"]}'
assert d['vpn_type'] == 'tun-proxy', f'vpn_type should be tun-proxy, got {d[\"vpn_type\"]}'
assert d['vpn_protocol_family'] == 'xray-family', f'vpn_protocol_family should be xray-family, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 12: Throne via TUN name ---
@test "vpn_client=throne при TUN-интерфейсе throne0" {
    create_tun_mock "throne0"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'throne', f'vpn_client should be throne, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'xray-family', f'vpn_protocol_family should be xray-family, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 13: Hiddify via TUN name ---
@test "vpn_client=hiddify при TUN-интерфейсе hiddify-tun" {
    create_tun_mock "hiddify-tun"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'hiddify', f'vpn_client should be hiddify, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'xray-family', f'vpn_protocol_family should be xray-family, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 14: AmneziaVPN via TUN name ---
@test "vpn_client=amneziavpn при TUN-интерфейсе amnezia-tun" {
    create_tun_mock "amnezia-tun"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'amneziavpn', f'vpn_client should be amneziavpn, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'amnezia-wg', f'vpn_protocol_family should be amnezia-wg, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 15: Clash via TUN name ---
@test "vpn_client=clash при TUN-интерфейсе clash0" {
    create_tun_mock "clash0"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'clash', f'vpn_client should be clash, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'clash', f'vpn_protocol_family should be clash, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 16: sing-box via TUN name ---
@test "vpn_client=sing-box при TUN-интерфейсе sing-box-tun" {
    create_tun_mock "sing-box-tun"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'sing-box', f'vpn_client should be sing-box, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'xray-family', f'vpn_protocol_family should be xray-family, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 17: v2rayA via TUN name ---
@test "vpn_client=v2raya при TUN-интерфейсе v2raya-tun" {
    create_tun_mock "v2raya-tun"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'v2raya', f'vpn_client should be v2raya, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'xray-family', f'vpn_protocol_family should be xray-family, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 18: Unknown TUN + xray process fallback ---
@test "vpn_client=xray при неизвестном TUN и процессе xray" {
    create_tun_mock "tun0"
    create_pgrep_mock "xray"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_client'] == 'xray', f'vpn_client should be xray, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'xray-family', f'vpn_protocol_family should be xray-family, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}

# --- Тест 19: proxy-no-tun detection ---
@test "vpn_type=proxy-no-tun при процессе xray без TUN" {
    create_pgrep_mock "xray"
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == True, f'vpn_active should be True, got {d[\"vpn_active\"]}'
assert d['vpn_type'] == 'proxy-no-tun', f'vpn_type should be proxy-no-tun, got {d[\"vpn_type\"]}'
assert d['vpn_client'] == 'xray', f'vpn_client should be xray, got {d[\"vpn_client\"]}'
print('OK')
"
}

# --- Тест 20: exit_ip field populated ---
@test "exit_ip содержит IP адрес" {
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['exit_ip'] == '203.0.113.1', f'exit_ip should be 203.0.113.1, got {d[\"exit_ip\"]}'
print('OK')
"
}

# --- Тест 21: no VPN — all VPN fields have default values ---
@test "VPN-поля имеют дефолтные значения без VPN" {
    run bash "$DETECT_STATE"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['vpn_active'] == False, f'vpn_active should be False, got {d[\"vpn_active\"]}'
assert d['vpn_type'] == 'none', f'vpn_type should be none, got {d[\"vpn_type\"]}'
assert d['vpn_client'] == 'none', f'vpn_client should be none, got {d[\"vpn_client\"]}'
assert d['vpn_protocol_family'] == 'unknown', f'vpn_protocol_family should be unknown, got {d[\"vpn_protocol_family\"]}'
print('OK')
"
}
