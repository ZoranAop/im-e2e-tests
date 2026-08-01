#!/usr/bin/env bash
# ============================================================
# TC-MX-001: 混合负载性能测试
# ============================================================
# 测试目标: 模拟真实场景下混合负载（单聊+群聊+聊天室）时的服务表现
#
# 用法:
#   bash run_mixed_workload_test.sh --mode check
#   bash run_mixed_workload_test.sh --mode full
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true

MODE="check"
while [[ $# -gt 0 ]]; do case "$1" in -m|--mode) MODE="$2"; shift 2;; -h|--help) MODE="help"; shift;; *) shift;; esac; done

# --- Workload Profile 1: Typical ---
# 70% single chat, 25% group chat, 5% chatroom
PROFILE_TYPICAL_SINGLE="${MX_SINGLE_PCT:-70}"
PROFILE_TYPICAL_GROUP="${MX_GROUP_PCT:-25}"
PROFILE_TYPICAL_CHATROOM="${MX_CHATROOM_PCT:-5}"

# --- Workload Profile 2: Group-Heavy ---
# 30% single chat, 60% group chat, 10% chatroom
PROFILE_GROUP_SINGLE="30"
PROFILE_GROUP_GROUP="60"  
PROFILE_GROUP_CHATROOM="10"

# --- Total target msg rate ---
TARGET_MSG_RATE="${MX_MSG_RATE:-1000}"
CORE_COUNT="${MX_CORES:-16}"
SAFETY_FACTOR="${MX_SAFETY:-1.5}"

test_mixed_workload_check() {
    print_header "TC-MX-001 混合负载测试 - 环境检查"

    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    print_section "混合负载场景定义"

    cat << 'PROFILES'

  两种测试负载配置:

  Profile 1 - 典型场景 (Typical):
    单聊 70% + 群聊 25% + 聊天室 5%
    模拟社交类应用日常负载

  Profile 2 - 群聊密集 (Group-Heavy):
    单聊 30% + 群聊 60% + 聊天室 10%
    模拟企业协作类应用负载

PROFILES
}

test_mixed_workload_capacity() {
    print_header "混合负载容量估算"

    local single_pct="${PROFILE_TYPICAL_SINGLE}"
    local group_pct="${PROFILE_TYPICAL_GROUP}"
    local chatroom_pct="${PROFILE_TYPICAL_CHATROOM}"

    print_section "Profile: 典型场景 (${single_pct}%/${group_pct}%/${chatroom_pct}%)"

    # Per-core rates
    local single_per_core=1077
    local group_per_core=$(echo "scale=0; 8750 / 200" | bc 2>/dev/null || echo "43")
    local chatroom_per_core=$(echo "scale=0; 13000 / 2000" | bc 2>/dev/null || echo "6")

    # Weighted average per-core capacity
    local weighted=$(echo "scale=2; ${single_pct}/100/${single_per_core} + ${group_pct}/100/${group_per_core} + ${chatroom_pct}/100/${chatroom_per_core}" | bc 2>/dev/null || echo "0")
    local mixed_per_core=$(echo "scale=0; 1/${weighted}" | bc 2>/dev/null || echo "0")

    log_metric "单聊单核速率" "${single_per_core} 条/秒/核"
    log_metric "群聊单核速率(200人群)" "${group_per_core} 条/秒/核"
    log_metric "聊天室单核(2000人)" "${chatroom_per_core} 条/秒/核"
    log_metric "混合负载单核速率(加权)" "${mixed_per_core} 条/秒/核"

    local needed=$(echo "scale=1; ${TARGET_MSG_RATE} / ${mixed_per_core} * ${SAFETY_FACTOR}" | bc 2>/dev/null || echo "N/A")
    log_metric "目标消息速率" "${TARGET_MSG_RATE} 条/秒"
    log_metric "安全系数" "${SAFETY_FACTOR}"
    log_metric "所需核心数" "${needed}"

    print_section "Profile: 群聊密集 (30%/60%/10%)"

    weighted=$(echo "scale=2; 30/100/${single_per_core} + 60/100/${group_per_core} + 10/100/${chatroom_per_core}" | bc 2>/dev/null || echo "0")
    mixed_per_core=$(echo "scale=0; 1/${weighted}" | bc 2>/dev/null || echo "0")
    needed=$(echo "scale=1; ${TARGET_MSG_RATE} / ${mixed_per_core} * ${SAFETY_FACTOR}" | bc 2>/dev/null || echo "N/A")

    log_metric "混合负载单核速率(加权)" "${mixed_per_core} 条/秒/核"
    log_metric "所需核心数" "${needed}"

    print_section "测试步骤指引"

    cat << 'STEPS'

  混合负载测试步骤:

  1. 准备3台压测机:
     - 压测机A: 单聊发送 (stress-tool, TestSingleMessageConfig)
     - 压测机B: 群聊发送 (stress-tool, TestGroupMessageConfig)
     - 压测机C: 聊天室接收 (stress-tool, TestChatroomConfig)

  2. 按负载比例配置各压测机的发送速率:
     - 单聊: 目标速率 × 比例
     - 群聊: 目标速率 × 比例
     - 聊天室: 目标速率 × 比例

  3. 先后启动各压测机，观察:
     - CPU 利用率变化
     - 各消息类型成功率
     - DB 负载分布
     - 内存使用趋势

  4. 持续压测 ≥ 10 分钟，记录:
     - P99/P95 延迟
     - 有无消息积压
     - 有无连接掉线

  5. 停止压测，等待服务器负载归零
     验证所有消息落库正确

STEPS

    print_section "基准验证"
    if [ -n "${MEASURED_MIX_RATE:-}" ]; then
        check_benchmark "${MEASURED_MIX_RATE}" "${BENCH_MIX_TYPICAL_CORE_RATE}" "混合负载加权单核速率"
        assert_success_rate "${MEASURED_MIX_SUCCESS:-0}" "混合负载消息成功率"
    else
        log_skip "未提供混合负载实测数据"
        log_info "设置环境变量后验证: export MEASURED_MIX_RATE=108 MEASURED_MIX_SUCCESS=100"
        log_info "  bash $0 --mode verify"
    fi

    print_summary
}

main() {
    case "${MODE}" in
        check|--check|-c)
            test_mixed_workload_check
            ;;
        full|--full|-f)
            test_mixed_workload_check
            echo ""
            test_mixed_workload_capacity
            ;;
        verify)
            print_header "混合负载基准验证"
            if [ -n "${MEASURED_MIX_RATE:-}" ]; then
                check_benchmark "${MEASURED_MIX_RATE}" "${BENCH_MIX_TYPICAL_CORE_RATE}" "混合负载加权单核速率"
                assert_success_rate "${MEASURED_MIX_SUCCESS:-0}" "混合负载消息成功率"
            else
                log_fail "未提供混合负载实测数据"
                log_info "  export MEASURED_MIX_RATE=108 MEASURED_MIX_SUCCESS=100"
            fi
            print_summary
            ;;
        *)
            echo "用法: $0 --mode <check|full>"
            echo "  check  环境检查和场景说明"
            echo "  full   完整容量估算 + 测试指引"
            echo ""
            echo "环境变量:"
            echo "  MX_MSG_RATE      目标消息速率 (默认: 1000)"
            echo "  MX_CORES         服务核心数 (默认: 16)"
            echo "  MX_SAFETY        安全系数 (默认: 1.5)"
            echo "  MX_SINGLE_PCT    单聊占比 (默认: 70)"
            echo "  MX_GROUP_PCT     群聊占比 (默认: 25)"
            echo "  MX_CHATROOM_PCT  聊天室占比 (默认: 5)"
            exit 1
            ;;
    esac
}

main
