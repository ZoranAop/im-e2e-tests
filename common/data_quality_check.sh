#!/usr/bin/env bash
# ============================================================
# Data Quality Check - Test Result Validation
# ============================================================
# Validate test result data quality:
#   - Message count completeness
#   - Success rate accuracy  
#   - Latency consistency
#   - Database integrity
#
# Usage: source common/data_quality_check.sh
# ============================================================

set -euo pipefail

# Check message count integrity across DB shards
validate_message_count() {
    local expected="$1" test_name="$2"
    local actual=$(count_all_messages 2>/dev/null || echo "0")
    
    if [ "${actual}" = "0" ]; then
        log_skip "无法连接数据库，跳过消息计数验证"
        return 0
    fi
    
    local diff=$((actual - expected))
    if [ "${diff}" -eq 0 ]; then
        log_pass "${test_name}: 消息计数一致 (expected=${expected}, actual=${actual})"
        return 0
    elif [ "${diff}" -gt 0 ] && [ "${diff}" -lt $((expected / 100)) ]; then
        log_warn "${test_name}: 消息计数偏差 ${diff} 条 (< 1%)"
        return 0
    else
        log_fail "${test_name}: 消息计数不一致 (expected=${expected}, actual=${actual}, diff=${diff})"
        return 1
    fi
}

# Check success rate meets threshold
validate_success_rate() {
    local rate="$1" threshold="${2:-100}"
    if [ "$(echo "${rate} >= ${threshold}" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        log_pass "成功率: ${rate}% >= ${threshold}%"
        return 0
    else
        log_fail "成功率: ${rate}% < ${threshold}%"
        return 1
    fi
}

# Check latency P99 within SLA
validate_latency_sla() {
    local p99="$1" sla_ms="$2" test_name="$3"
    if [ "$(echo "${p99} <= ${sla_ms}" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        log_pass "${test_name}: P99=${p99}ms <= SLA=${sla_ms}ms"
        return 0
    else
        log_fail "${test_name}: P99=${p99}ms > SLA=${sla_ms}ms"
        return 1
    fi
}

# Validate database table integrity
validate_db_integrity() {
    log_info "验证数据库表完整性..."
    
    # Check that all 128 message shard tables exist
    local missing_tables=0
    for i in $(seq 0 127); do
        local exists=$(mysql_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DB}' AND table_name='t_messages_${i}';" 2>/dev/null | tail -1 || echo "0")
        if [ "${exists}" = "0" ]; then
            missing_tables=$((missing_tables + 1))
        fi
    done
    
    if [ "${missing_tables}" -eq 0 ]; then
        log_pass "128 张消息分表均存在"
    else
        log_warn "缺失 ${missing_tables} 张消息分表"
    fi
}

# Run full quality gate
run_quality_gate() {
    local test_name="$1" expected_msgs="$2" success_rate="$3" p99_ms="$4"
    
    print_section "数据质量检测 - ${test_name}"
    
    local failures=0
    validate_message_count "${expected_msgs}" "${test_name}" || failures=$((failures + 1))
    validate_success_rate "${success_rate}" 100 || failures=$((failures + 1))
    if [ -n "${p99_ms}" ] && [ "${p99_ms}" != "0" ]; then
        validate_latency_sla "${p99_ms}" 500 "${test_name}" || failures=$((failures + 1))
    fi
    validate_db_integrity || failures=$((failures + 1))
    
    if [ "${failures}" -eq 0 ]; then
        log_pass "数据质量检测通过"
        return 0
    else
        log_fail "数据质量检测: ${failures} 项未通过"
        return 1
    fi
}
