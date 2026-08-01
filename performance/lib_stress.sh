#!/usr/bin/env bash
# ============================================================
# stress-tool Integration Library
# ============================================================
# Provides: TOML rendering / stress-tool launch / output parsing
#
# Usage: source "${SCRIPT_DIR}/lib_stress.sh"
# ============================================================

set -euo pipefail

if ! declare -f log_fail &>/dev/null; then
    if [ -f "$(dirname "$0")/config.sh" ]; then
        source "$(dirname "$0")/config.sh"
    fi
fi

STRESS_TOOL="${STRESS_TOOL:-./stress-tool}"
STRESS_CONFIG_DIR="${STRESS_CONFIG_DIR:-.}"
STRESS_OUTPUT_DIR="${STRESS_OUTPUT_DIR:-./reports}"
STRESS_TIMEOUT="${STRESS_TIMEOUT:-900}"  # 15 min default timeout

# ============================================================
# TOML Template Rendering
# ============================================================

render_toml() {
    local template="$1" output="$2"
    if [ ! -f "${template}" ]; then
        log_fail "Template not found: ${template}"
        return 1
    fi
    cp "${template}" "${output}"
    sed -i "s/YOUR_IM_SERVER_IP/${IM_HOST}/g" "${output}"
    sed -i "s/IM_SERVER_PUBLIC_IP/${IM_HOST}/g" "${output}"
    sed -i "s/YOUR_IM_SERVER_INTERNAL_IP/${IM_INTERNAL_IP:-${IM_HOST}}/g" "${output}"
    sed -i "s/YOUR_OBSERVER_USER_ID/${OBSERVER_USER_ID:-observer}/g" "${output}"
    sed -i "s|HttpPort = 80|HttpPort = ${IM_HTTP_PORT}|g" "${output}"
    sed -i "s|AdminSecret = 123456|AdminSecret = ${IM_ADMIN_SECRET}|g" "${output}"
    log_info "Rendered config: ${output}"
    return 0
}

# ============================================================
# Stress-tool Launch
# ============================================================

launch_stress() {
    local config="$1" label="$2"
    local logfile="${STRESS_OUTPUT_DIR}/${label}_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "${STRESS_OUTPUT_DIR}"

    if [ ! -f "${STRESS_TOOL}" ]; then
        log_skip "stress-tool not found at ${STRESS_TOOL}"
        return 1
    fi
    if [ ! -f "${config}" ]; then
        log_fail "Config not found: ${config}"
        return 1
    fi

    log_info "Launching stress-tool with config: ${config}"
    log_info "Output: ${logfile}"
    
    # Run with timeout
    timeout "${STRESS_TIMEOUT}" "${STRESS_TOOL}" --config "${config}" > "${logfile}" 2>&1 &
    STRESS_PID=$!
    log_info "stress-tool PID: ${STRESS_PID}"
    
    # Wait for completion with progress
    local elapsed=0
    while kill -0 "${STRESS_PID}" 2>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "  Running... ${elapsed}s"
        fi
    done
    
    wait "${STRESS_PID}" 2>/dev/null || true
    local exit_code=$?
    echo "${logfile}"
    return ${exit_code}
}

# ============================================================
# Output Parsing
# ============================================================

parse_stress_output() {
    local logfile="$1"
    
    if [ ! -f "${logfile}" ]; then
        log_warn "Log file not found: ${logfile}"
        return 1
    fi

    # Extract metrics from stress-tool output
    # stress-tool typically outputs lines like:
    #   Total messages: 10000000
    #   Duration: 509s
    #   Rate: 19646 msg/s
    #   Success: 100.00%
    #   P99: 45ms P95: 32ms

    TOTAL=$(grep -i "total.*message\|发送条数\|消息总量" "${logfile}" | tail -1 | grep -oE '[0-9]+' | tail -1 || true)
    DURATION=$(grep -i "duration\|时间\|耗时" "${logfile}" | tail -1 | grep -oE '[0-9.]+' | head -1 || true)
    RATE=$(grep -i "rate\|速率" "${logfile}" | tail -1 | grep -oE '[0-9.]+' | head -1 || true)
    SUCCESS=$(grep -i "success\|成功率" "${logfile}" | tail -1 | grep -oE '[0-9.]+' | head -1 || true)
    P99=$(grep -i "p99\|P99" "${logfile}" | tail -1 | grep -oE '[0-9.]+' | head -1 || true)
    P95=$(grep -i "p95\|P95" "${logfile}" | tail -1 | grep -oE '[0-9.]+' | head -1 || true)
    CPU=$(grep -i "cpu" "${logfile}" | tail -1 | grep -oE '[0-9.]+' | head -1 || true)

    # Write variable assignments to temp file for caller to source
    # (separating data from log output prevents eval from choking on ANSI codes)
    local varfile="${STRESS_OUTPUT_DIR}/.stress_vars_$$"
    cat > "${varfile}" << EOF
TOTAL=${TOTAL:-0}
DURATION=${DURATION:-0}
RATE=${RATE:-0}
SUCCESS=${SUCCESS:-0}
P99=${P99:-0}
P95=${P95:-0}
CPU=${CPU:-0}
EOF

    # Print summary (stdout only, no eval hazard)
    log_info "--- stress-tool Results ---"
    log_metric "Total Messages" "${TOTAL:-N/A}"
    log_metric "Duration" "${DURATION:-N/A}s"
    log_metric "Rate" "${RATE:-N/A} msg/s"
    log_metric "Success Rate" "${SUCCESS:-N/A}%"
    log_metric "P99 Latency" "${P99:-N/A}ms"
    log_metric "P95 Latency" "${P95:-N/A}ms"
    log_metric "CPU" "${CPU:-N/A}%"
    
    return 0
}

# ============================================================
# End-to-end stress test runner
# ============================================================

run_stress_test() {
    local template="$1" label="$2"
    local config="${STRESS_CONFIG_DIR}/config_${label}.toml"
    
    render_toml "${template}" "${config}" || return 1
    local logfile=$(launch_stress "${config}" "${label}" | tail -1) || true
    if [ ! -f "${logfile}" ]; then
        return 1
    fi
    
    # Parse and export results (source varfile, avoid eval on mixed log+data output)
    parse_stress_output "${logfile}" || true
    local varfile="${STRESS_OUTPUT_DIR}/.stress_vars_$$"
    if [ -f "${varfile}" ]; then
        source "${varfile}"
        rm -f "${varfile}"
    fi
    
    # Cleanup
    rm -f "${config}"
}
