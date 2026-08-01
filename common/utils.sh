#!/usr/bin/env bash
# 通用测试工具函数库（Bash 版本）
# 用法: source "$(dirname "$0")/utils.sh"

set -euo pipefail

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
# 颜色输出
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
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "${RED}FAIL${NC}: $1"
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo -e "${YELLOW}SKIP${NC}: $1"
}

info() {
    echo -e "${GRAY}INFO: $1${NC}"
}

# ============================================================
# HTTP 请求
# ============================================================
im_admin_api() {
    local path="$1"
    local method="${2:-GET}"
    local body="$3"
    local curl_opts="-s -X ${method}"

    curl_opts="${curl_opts} -H 'Content-Type: application/json'"
    curl_opts="${curl_opts} -H 'nonce: '${RANDOM}"
    curl_opts="${curl_opts} -H 'timestamp: '$(date +%s%3N)"

    if [ -n "${body}" ]; then
        curl_opts="${curl_opts} -d '${body}'"
    fi

    eval "curl ${curl_opts} '${IM_ADMIN_URL}${path}'" 2>/dev/null || echo ""
}

push_api() {
    local path="$1"
    local method="${2:-GET}"
    local body="$3"
    local curl_opts="-s -X ${method} -H 'Content-Type: application/json'"

    if [ -n "${body}" ]; then
        curl_opts="${curl_opts} -d '${body}'"
    fi

    eval "curl ${curl_opts} '${PUSH_URL}${path}'" 2>/dev/null || echo ""
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
