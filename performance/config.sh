#!/usr/bin/env bash
# IM 服务性能测试 - 公共配置与工具函数
# 用法: source "$(dirname "$0")/config.sh"

set -euo pipefail

# ============================================================
# 环境变量配置（可通过环境变量覆盖）
# ============================================================
IM_HOST="${IM_HOST:-localhost}"
IM_HTTP_PORT="${IM_HTTP_PORT:-80}"
IM_ADMIN_PORT="${IM_ADMIN_PORT:-18080}"
IM_ADMIN_SECRET="${IM_ADMIN_SECRET:-123456}"
MYSQL_HOST="${MYSQL_HOST:-localhost}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-}"
MYSQL_DB="${MYSQL_DB:-imdb}"

# Cluster test params
CLUSTER_NODES="${CLUSTER_NODES:-4}"
CLUSTER_NODE_IPS="${CLUSTER_NODE_IPS:-}"      # space-separated IPs
CLUSTER_AUTH_IP="${CLUSTER_AUTH_IP:-}"        # license auth node IP

IM_BASE_URL="http://${IM_HOST}:${IM_HTTP_PORT}"
IM_ADMIN_URL="http://${IM_HOST}:${IM_ADMIN_PORT}"

# ============================================================
# 参考基准数据（16C48G 环境）
# ============================================================
# 单聊发送测试基准
BENCH_SC_SEND_RATE=19646          # 发送速率（条/秒）
BENCH_SC_SEND_CORE_RATE=1227      # 单核发送速率（条/秒/核）
BENCH_SC_SEND_CORE_DISPATCH=2455  # 单核分发速率（条/秒/核）
BENCH_SC_SEND_TIME=509            # 发送时间（秒）

# 单聊收发测试基准
BENCH_SC_RECV_RATE=13908          # 收发速率（条/秒）
BENCH_SC_RECV_CORE_RATE=869       # 单核收发速率（条/秒/核）
BENCH_SC_RECV_TIME=719            # 收发时间（秒）

# 群聊分发基准
BENCH_GC_DISPATCH_RATE=8750       # 单核分发速率（条/秒/核，千人群）

# 聊天室广播基准
BENCH_CR_BROADCAST_RATE=13000     # 稳定后单核广播与拉取速率（条/秒/核）

# ============================================================
# 颜色输出
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================
# 测试计数器与计时器
# ============================================================
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
TEST_START_TIME=$(date +%s%3N)
CURRENT_TEST_START=0

# ============================================================
# 日志函数
# ============================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-56s ${CYAN}║${NC}\n" "  $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
}

log_info() {
    echo -e "${GRAY}[INFO]${NC} $1"
}

log_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${RED}[FAIL]${NC} $1"
}

log_skip() {
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_metric() {
    printf "  ${WHITE}%-30s${NC} ${GREEN}%s${NC}\n" "$1:" "$2"
}

log_timing() {
    printf "  ${WHITE}%-30s${NC} %s\n" "$1:" "$2"
}

# ============================================================
# 计时函数
# ============================================================

start_timer() {
    CURRENT_TEST_START=$(date +%s%3N)
}

elapsed_ms() {
    local now=$(date +%s%3N)
    echo $((now - CURRENT_TEST_START))
}

elapsed_sec() {
    local ms=$(elapsed_ms)
    echo "scale=1; $ms / 1000" | bc 2>/dev/null || echo "$((ms / 1000)).$((ms % 1000 / 100))"
}

# ============================================================
# HTTP 请求函数
# ============================================================

im_admin_get() {
    local path="$1"
    local nonce=$RANDOM
    local timestamp=$(date +%s%3N)
    curl -s -X GET \
        -H "Content-Type: application/json" \
        -H "nonce: ${nonce}" \
        -H "timestamp: ${timestamp}" \
        "${IM_ADMIN_URL}${path}" 2>/dev/null || echo ""
}

im_admin_post() {
    local path="$1"
    local body="$2"
    local nonce=$RANDOM
    local timestamp=$(date +%s%3N)
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "nonce: ${nonce}" \
        -H "timestamp: ${timestamp}" \
        -d "${body}" \
        "${IM_ADMIN_URL}${path}" 2>/dev/null || echo ""
}

# ============================================================
# TCP 连通性检查
# ============================================================

check_tcp() {
    local host="$1"
    local port="$2"
    local timeout="${3:-3}"
    timeout "${timeout}" bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null && return 0 || return 1
}

# ============================================================
# 性能指标计算
# ============================================================

calc_rate() {
    local total="$1"
    local seconds="$2"
    if [ "${seconds}" = "0" ] || [ -z "${seconds}" ]; then
        echo "0"
    else
        echo "scale=0; ${total} / ${seconds}" | bc 2>/dev/null || echo "0"
    fi
}

calc_core_rate() {
    local rate="$1"
    local cores="$2"
    if [ "${cores}" = "0" ] || [ -z "${cores}" ]; then
        echo "0"
    else
        echo "scale=2; ${rate} / ${cores}" | bc 2>/dev/null || echo "0"
    fi
}

calc_dispatch_rate() {
    local core_rate="$1"
    local members="$2"
    echo "scale=0; ${core_rate} * ${members}" | bc 2>/dev/null || echo "0"
}

percentage_of_benchmark() {
    local actual="$1"
    local benchmark="$2"
    if [ "${benchmark}" = "0" ] || [ -z "${benchmark}" ]; then
        echo "0"
    else
        echo "scale=1; ${actual} * 100 / ${benchmark}" | bc 2>/dev/null || echo "0"
    fi
}

# ============================================================
# 环境检查
# ============================================================

check_prerequisites() {
    print_section "环境检查"

    # 检查 bc（用于浮点计算）
    if ! command -v bc &>/dev/null; then
        log_warn "缺少 bc 命令，浮点计算将降级为整数计算"
    fi

    # 检查 curl
    if ! command -v curl &>/dev/null; then
        log_fail "缺少 curl 命令，无法执行 HTTP 请求"
        return 1
    fi
    log_pass "curl 可用"

    # 检查 timeout
    if ! command -v timeout &>/dev/null; then
        log_warn "缺少 timeout 命令，TCP 检查可能不可用"
    fi

    # IM 服务连通性
    log_info "检查 IM 服务连通性 (${IM_ADMIN_URL})..."
    local version=$(im_admin_get "/api/version")
    if [ -n "${version}" ] && [ "${version}" != "null" ]; then
        log_pass "IM 服务可达"
        log_info "  版本信息: ${version}"
    else
        log_fail "IM 服务不可达 (${IM_ADMIN_URL})"
        return 1
    fi

    return 0
}

# ============================================================
# 集群节点检查
# ============================================================

check_cluster_nodes() {
    print_section "检查集群节点"
    if [ -z "${CLUSTER_NODE_IPS}" ]; then
        log_warn "CLUSTER_NODE_IPS 未设置，跳过节点检查"
        return 0
    fi
    local expected_node_ids=""
    for ip in ${CLUSTER_NODE_IPS}; do
        local version=$(curl -s "http://${ip}:${IM_ADMIN_PORT}/api/version" 2>/dev/null)
        if [ -n "${version}" ]; then
            log_pass "节点 ${ip} 可达"
        else
            log_fail "节点 ${ip} 不可达"
        fi
    done
    if [ -n "${CLUSTER_AUTH_IP}" ]; then
        local cluster_info=$(curl -s "http://${CLUSTER_AUTH_IP}:${IM_ADMIN_PORT}/api/version" 2>/dev/null)
        local node_ids=$(echo "${cluster_info}" | grep -o '"nodeIds":"[^"]*"' | cut -d'"' -f4)
        if [ -n "${node_ids}" ]; then
            log_pass "集群节点 ID: ${node_ids}"
        else
            log_warn "无法获取集群节点 ID"
        fi
    fi
}

# ============================================================
# 结果判定
# ============================================================

check_benchmark() {
    local actual="$1"
    local benchmark="$2"
    local metric_name="$3"
    local result

    result=$(percentage_of_benchmark "${actual}" "${benchmark}")
    if [ "$(echo "${result} >= 80" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        if [ "$(echo "${result} >= 100" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
            log_pass "${metric_name}: ${actual}（优秀，达到基准的 ${result}%）"
        else
            log_pass "${metric_name}: ${actual}（合格，达到基准的 ${result}%）"
        fi
    else
        log_warn "${metric_name}: ${actual}（低于基准的 80%，基准 ${benchmark}）"
    fi
}

# ============================================================
# 报告生成
# ============================================================

generate_report_header() {
    local report_file="$1"
    local title="$2"
    local server_spec="$3"

    cat > "${report_file}" << EOF
# ${title}

## 测试环境

| 项目 | 配置 |
|------|------|
| 测试日期 | $(date '+%Y-%m-%d %H:%M:%S') |
| IM 服务器 | ${server_spec} |
| IM 地址 | ${IM_HOST}:${IM_HTTP_PORT} |
| MySQL 地址 | ${MYSQL_HOST}:${MYSQL_PORT} |

## 测试结果

EOF
}

append_to_report() {
    local report_file="$1"
    shift
    echo "$@" >> "${report_file}"
}

generate_report() {
    local report_file="$1"
    local title="$2"
    local server_spec="$3"
    local test_params="$4"
    local results="$5"

    mkdir -p "$(dirname "${report_file}")"
    cat > "${report_file}" << EOF
# ${title}

## 测试环境
| 项目 | 配置 |
|------|------|
| 测试日期 | $(date '+%Y-%m-%d %H:%M:%S') |
| 服务器 | ${server_spec} |
| IM 地址 | ${IM_HOST}:${IM_HTTP_PORT} |

## 测试参数
${test_params}

## 测试结果
${results}

## 结果判定
总体: $([ ${FAILED_TESTS} -eq 0 ] && echo "通过" || echo "失败")
通过: ${PASSED_TESTS} | 失败: ${FAILED_TESTS} | 跳过: ${SKIPPED_TESTS}
EOF
    log_info "报告已保存: ${report_file}"
}

print_summary() {
    local total_sec=$(elapsed_sec)
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-56s ${CYAN}║${NC}\n" "  测试结果汇总"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${NC}  %-54s ${CYAN}║${NC}\n" "总计: ${TOTAL_TESTS}  通过: ${PASSED_TESTS}  失败: ${FAILED_TESTS}  跳过: ${SKIPPED_TESTS}"
    printf "${CYAN}║${NC}  %-54s ${CYAN}║${NC}\n" "耗时: ${total_sec}s"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ "${FAILED_TESTS}" -gt 0 ]; then
        echo -e "${RED}结果: 失败${NC}"
        return 1
    else
        echo -e "${GREEN}结果: 通过${NC}"
        return 0
    fi
}

pass() { log_pass "$@"; }
fail() { log_fail "$@"; }
skip() { log_skip "$@"; }
info() { log_info "$@"; }
PASS_COUNT="${PASSED_TESTS}"
FAIL_COUNT="${FAILED_TESTS}"
SKIP_COUNT="${SKIPPED_TESTS}"

# ============================================================
# 基准验证模式
# ============================================================

run_verify_mode() {
    local test_name="$1"
    local measured="$2"
    local benchmark="$3"
    local unit="$4"
    
    print_section "${test_name} 基准验证"
    if [ -z "${measured}" ]; then
        log_warn "未提供实测值，设置环境变量后使用 --mode verify 进行判定"
        log_info "  bash $0 --mode verify"
        return 1
    fi
    
    log_metric "实测值" "${measured} ${unit}"
    log_metric "基准值" "${benchmark} ${unit}"
    check_benchmark "${measured}" "${benchmark}" "${test_name}"
    return 0
}
