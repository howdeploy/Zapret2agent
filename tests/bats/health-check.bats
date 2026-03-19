#!/usr/bin/env bats
# health-check.bats — тесты для health-check.sh
# Запуск: bats tests/bats/health-check.bats

load test_helper

setup() {
    setup_mocks
    prepare_detect_state
    prepare_health_check
}

teardown() {
    teardown_mocks
}

# --- Тест 1: Валидный JSON ---
@test "выводит валидный JSON" {
    run bash "$HEALTH_CHECK"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null
}

# --- Тест 2: JSON содержит обязательные ключи верхнего уровня ---
@test "JSON содержит overall, system, zapret, network, issues" {
    run bash "$HEALTH_CHECK"
    [ "$status" -eq 0 ]
    python3 -c "
import sys, json
d = json.loads('''$output''')
required = ['overall', 'system', 'zapret', 'network', 'issues']
missing = [k for k in required if k not in d]
if missing:
    print('Missing keys: ' + ', '.join(missing))
    sys.exit(1)
print('All top-level keys present')
"
}

# --- Тест 3: overall=ok когда zapret не установлен ---
@test "overall=ok когда zapret не установлен" {
    # zapret2 не установлен (нет nfqws2, нет /opt/zapret2/nfqws2)
    # Моки без VPN и dig — всё чисто
    run bash "$HEALTH_CHECK"
    [ "$status" -eq 0 ]
    local overall_val
    overall_val=$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['overall'])")
    [ "$overall_val" = "ok" ]
}

# --- Тест 4: issues пустой когда всё ok ---
@test "issues пустой когда всё ok" {
    # Чистая среда: нет zapret, нет VPN, нет DNS-проблем
    run bash "$HEALTH_CHECK"
    [ "$status" -eq 0 ]
    python3 -c "
import sys, json
d = json.loads('''$output''')
issues = d.get('issues', [])
if issues:
    print('Expected empty issues, got: ' + str(issues))
    sys.exit(1)
print('issues is empty as expected')
"
}
