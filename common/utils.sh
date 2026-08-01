#!/usr/bin/env bash
# 通用测试工具函数库（Bash 版本）
# 用法: source "$(dirname "$0")/utils.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -- Import config.sh if available (for log_* + env vars) --
if [ -f "${SCRIPT_DIR}/../performance/config.sh" ]; then
    source "${SCRIPT_DIR}/../performance/config.sh"
fi

# ============================================================
# 配置（可通过环境变量覆盖）
# ============================================================
IM_HOST="${IM_HOST:-localhost}"
IM_HTTP_PORT="${IM_HTTP_PORT:-80}"
IM_ADMIN_PORT="${IM_ADMIN_PORT:-18080}"
IM_ADMIN_SECRET="${IM_ADMIN_SECRET:-123456}"
PUSH_HOST="${PUSH_HOST:-localhost}"
PUSH_PORT="${PUSH_PORT:-8085}"
PUSH_ADMIN_PORT="${PUSH_ADMIN_PORT:-8086}"

IM_BASE_URL="http://${IM_HOST}:${IM_HTTP_PORT}"
IM_ADMIN_URL="http://${IM_HOST}:${IM_ADMIN_PORT}"
PUSH_URL="http://${PUSH_HOST}:${PUSH_PORT}"
PUSH_ADMIN_URL="http://${PUSH_HOST}:${PUSH_ADMIN_PORT}"

# ============================================================
# 颜色输出（config.sh 未加载时的回退）
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ============================================================
# 计数器
# ============================================================
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
START_TIME=$(date +%s)

# ============================================================
# 日志函数
# ============================================================
test_header() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

step() {
    echo -e "${YELLOW}>> $1${NC}"
}

pass() {
    if declare -f log_pass &>/dev/null; then log_pass "$@"; return; fi
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    if declare -f log_fail &>/dev/null; then log_fail "$@"; return; fi
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}FAIL${NC}: $1"
}

skip() {
    if declare -f log_skip &>/dev/null; then log_skip "$@"; return; fi
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo -e "${YELLOW}SKIP${NC}: $1"
}

info() {
    if declare -f log_info &>/dev/null; then log_info "$@"; return; fi
    echo -e "${GRAY}INFO: $1${NC}"
}

# Timer functions (minimal stubs for standalone usage)
start_timer() { TEST_START_TIME=$(date +%s%3N); }
elapsed_ms() { echo $(($(date +%s%3N) - ${TEST_START_TIME:-0})); }
elapsed_sec() { echo $(($(elapsed_ms) / 1000)); }
TEST_START_TIME=$(date +%s%3N)

# ============================================================
# HTTP 请求
# ============================================================
im_admin_api() {
    local path="$1" method="${2:-GET}" body="$3"
    local nonce=$RANDOM timestamp=$(date +%s%3N)
    local url="${IM_ADMIN_URL}${path}"
    if [ -n "${body}" ]; then
        curl -s -X "${method}" -H "Content-Type: application/json" \
            -H "nonce: ${nonce}" -H "timestamp: ${timestamp}" \
            -d "${body}" "${url}" 2>/dev/null || echo ""
    else
        curl -s -X "${method}" -H "Content-Type: application/json" \
            -H "nonce: ${nonce}" -H "timestamp: ${timestamp}" \
            "${url}" 2>/dev/null || echo ""
    fi
}

push_api() {
    local path="$1" method="${2:-GET}" body="$3"
    local url="${PUSH_URL}${path}"
    if [ -n "${body}" ]; then
        curl -s -X "${method}" -H "Content-Type: application/json" \
            -d "${body}" "${url}" 2>/dev/null || echo ""
    else
        curl -s -X "${method}" -H "Content-Type: application/json" \
            "${url}" 2>/dev/null || echo ""
    fi
}

# ============================================================
# 断言
# ============================================================
assert_not_null() {
    local value="$1"
    local msg="$2"
    if [ -n "${value}" ]; then
        pass "${msg}"
    else
        fail "${msg}"
    fi
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "${expected}" = "${actual}" ]; then
        pass "${msg}"
    else
        fail "${msg} (expected: ${expected}, actual: ${actual})"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "${haystack}" | grep -q "${needle}"; then
        pass "${msg}"
    else
        fail "${msg} (missing: ${needle})"
    fi
}

assert_http_ok() {
    local response="$1"
    local msg="$2"
    if [ -n "${response}" ] && [ "${response}" != "null" ]; then
        pass "${msg}"
    else
        fail "${msg} (request failed)"
    fi
}

# ============================================================
# TCP Connectivity
# ============================================================
check_tcp() {
    local host="$1"
    local port="$2"
    local timeout_sec="${3:-3}"
    if command -v timeout &>/dev/null; then
        timeout "${timeout_sec}" bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null && return 0 || return 1
    else
        (echo >/dev/tcp/"${host}"/"${port}") 2>/dev/null && return 0 || return 1
    fi
}

# ============================================================
# HTTP with retry and timeout
# ============================================================
http_get_retry() {
    local url="$1"
    local max_retries="${2:-3}"
    local timeout_sec="${3:-10}"
    local attempt=1
    while [ ${attempt} -le ${max_retries} ]; do
        local resp=$(curl -s --max-time "${timeout_sec}" "${url}" 2>/dev/null)
        if [ -n "${resp}" ]; then
            echo "${resp}"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

# ============================================================
# JSON output for CI/CD
# ============================================================
json_test_result() {
    local name="$1"
    local status="$2"  # pass/fail/skip
    local detail="$3"
    echo "{\"test\":\"${name}\",\"status\":\"${status}\",\"detail\":\"${detail}\"}"
}

# ============================================================
# 结果汇总
# ============================================================
test_summary() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))

    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  测试结果汇总${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo -e "  总计: ${total}  通过: ${PASS_COUNT}  失败: ${FAIL_COUNT}  跳过: ${SKIP_COUNT}"
    echo -e "  耗时: ${elapsed}s"
    echo -e "${CYAN}============================================================${NC}"

    if [ "${FAIL_COUNT}" -gt 0 ]; then
        echo -e "${RED}  结果: 失败${NC}"
        exit 1
    else
        echo -e "${GREEN}  结果: 通过${NC}"
        exit 0
    fi
}
