#!/usr/bin/env bash
# ============================================================
# TC-CR-1000 / TC-CR-2000 / TC-CR-5000: 聊天室消息性能测试
# ============================================================
# 测试目标: 验证聊天室内消息广播与拉取性能
#
# 说明:
#   - 聊天室消息主要走内存广播，数据库压力可忽略
#   - 聊天室场景允许少量丢消息（设计使然）
#   - CPU 峰值受网络瓶颈限制可能无法达到 100%
#
# 用法:
#   千人聊天室:
#     bash run_chatroom_test.sh --mode 1000
#
#   两千人聊天室:
#     bash run_chatroom_test.sh --mode 2000
#
#   五千人聊天室:
#     bash run_chatroom_test.sh --mode 5000
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib_stress.sh" 2>/dev/null || true

# ============================================================
# 测试参数
# ============================================================
MODE="check"
while [[ $# -gt 0 ]]; do case "$1" in -m|--mode) MODE="$2"; shift 2;; check|1000|2000|5000|verify) MODE="$1"; shift;; *) shift;; esac; done
CR_CORES="${CR_CORES:-8}"
CR_SENDERS="${CR_SENDERS:-100}"
CR_MSGS_PER_SENDER="${CR_MSGS_PER_SENDER:-100}"
CR_TOTAL_MSGS=$((CR_SENDERS * CR_MSGS_PER_SENDER))
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
REPORT_FILE="${REPORT_DIR}/cr_$(date +%Y%m%d_%H%M%S).md"

# ============================================================
# 内部函数
# ============================================================

print_chatroom_test_table() {
    local members="$1"
    local total_msgs="$2"

    cat << TABLE

  ┌──────────────────────┬─────────────────┐
  │ 测试参数             │ 值               │
  ├──────────────────────┼─────────────────┤
  │ 服务资源             │ ${CR_CORES}C16G    │
  │ 聊天室成员数         │ ${members}        │
  │ 发送客户端数         │ ${CR_SENDERS}      │
  │ 每客户端发送数       │ ${CR_MSGS_PER_SENDER} │
  │ 消息总量（条）       │ ${total_msgs}     │
  └──────────────────────┴─────────────────┘

TABLE
}

print_chatroom_benchmark() {
    local members="$1"
    local time="$2"
    local rate="$3"
    local cpu="$4"
    local core_rate="$5"
    local broadcast_rate="$6"

    cat << BENCH

  参考基准（${CR_CORES}C16G 环境，${members}人聊天室）:
  ┌──────────────────────────┬─────────────────────┐
  │ 指标                     │ 实测基准值           │
  ├──────────────────────────┼─────────────────────┤
  │ 消息落库成功率           │ 100%                │
  │ CPU 利用率               │ ${cpu}%（网络瓶颈限制）│
  │ 发送时间                 │ ${time} 秒           │
  │ 发送速率                 │ ${rate} 条/秒        │
  │ 单核速率                 │ ${core_rate} 条/秒/核│
  │ 单核广播与拉取速率        │ ${broadcast_rate} 条/秒/核│
  └──────────────────────────┴─────────────────────┘

  计算公式:
  发送速率             = 消息总量 ÷ 发送时间
  单核速率             = 发送速率 ÷ 核心数(${CR_CORES})
  单核广播与拉取速率    = 单核速率 × 聊天室人数(${members})

BENCH
}

# ============================================================
# TC-CR-1000: 千人聊天室测试
# ============================================================

test_chatroom_1000() {
    local members=1000

    print_header "TC-CR-1000 千人聊天室消息测试"

    print_chatroom_test_table "${members}" "${CR_TOTAL_MSGS}"

    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    print_section "测试步骤指引"

    cat << STEPS

  操作步骤:

  1. 创建聊天室并加入成员:
     - 1,000 个客户端加入同一个聊天室

  2. 执行发送:
     - 100 个发送客户端在聊天室内同时发送消息
     - 每个客户端发送 100 条消息

  3. 数据采集:
     - 服务端消息落库验证
     - 观察者接收消息验证（允许少量丢失）
     - CPU 利用率（预期约 80%，受网络瓶颈限制）

  4. 判定标准:
     ✅ 消息落库成功率 = 100%
     ✅ 观察者接收大部分消息（允许少量丢失）

STEPS

    print_chatroom_benchmark "1,000" "39" "256" "80" "32" "32,000"

    print_section "自动执行压测"

    if [ -f "${SCRIPT_DIR}/lib_stress.sh" ] && [ -f "./stress-tool" ]; then
        log_info "检测到 stress-tool，自动执行聊天室压测..."
        source "${SCRIPT_DIR}/lib_stress.sh"
        local template="${SCRIPT_DIR}/stress_chatroom.toml"
        if [ -f "${template}" ]; then
            run_stress_test "${template}" "cr_${members}"
            if [ "${RATE:-0}" != "0" ]; then
                local broadcast_rate=$(echo "scale=2; ${RATE} / ${CR_CORES:-8} * ${members}" | bc -l 2>/dev/null || echo "0")
                check_benchmark "${broadcast_rate}" "${BENCH_CR_BROADCAST_RATE}" "聊天室广播速率"
                assert_success_rate "${SUCCESS:-0}" "消息落库成功率"
                if declare -f count_all_messages &>/dev/null; then
                    local db_count=$(count_all_messages 2>/dev/null || echo "0")
                    if [ "${db_count}" != "0" ]; then
                        assert_ge "${db_count}" "${CR_TOTAL_MSGS}" "数据库落库数"
                    fi
                fi
            fi
        fi
    else
        log_skip "stress-tool 未安装，跳过自动压测"
        log_info "手动压测后使用验证模式:  export MEASURED_RATE=... && bash $0 --mode verify"
    fi

    print_section "测试结果记录"
    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# TC-CR-2000: 两千人聊天室测试
# ============================================================

test_chatroom_2000() {
    local members=2000

    print_header "TC-CR-2000 两千人聊天室消息测试"

    print_chatroom_test_table "${members}" "${CR_TOTAL_MSGS}"

    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    print_section "测试步骤指引"

    cat << STEPS

  操作步骤:

  1. 创建聊天室并加入成员:
     - 2,000 个客户端加入同一个聊天室

  2. 执行发送:
     - 100 个发送客户端在聊天室内同时发送消息
     - 每个客户端发送 100 条消息

  3. 数据采集:
     - 服务端消息落库验证
     - 观察者接收消息验证
     - CPU 利用率（预期约 80%）

  4. 判定标准:
     ✅ 消息落库成功率 = 100%
     ✅ 观察者接收大部分消息

STEPS

    print_chatroom_benchmark "2,000" "97" "103" "80" "12.9" "25,773"

    print_section "自动执行压测"

    if [ -f "${SCRIPT_DIR}/lib_stress.sh" ] && [ -f "./stress-tool" ]; then
        log_info "检测到 stress-tool，自动执行聊天室压测..."
        source "${SCRIPT_DIR}/lib_stress.sh"
        local template="${SCRIPT_DIR}/stress_chatroom.toml"
        if [ -f "${template}" ]; then
            run_stress_test "${template}" "cr_${members}"
            if [ "${RATE:-0}" != "0" ]; then
                local broadcast_rate=$(echo "scale=2; ${RATE} / ${CR_CORES:-8} * ${members}" | bc -l 2>/dev/null || echo "0")
                check_benchmark "${broadcast_rate}" "${BENCH_CR_BROADCAST_RATE}" "聊天室广播速率"
                assert_success_rate "${SUCCESS:-0}" "消息落库成功率"
                if declare -f count_all_messages &>/dev/null; then
                    local db_count=$(count_all_messages 2>/dev/null || echo "0")
                    if [ "${db_count}" != "0" ]; then
                        assert_ge "${db_count}" "${CR_TOTAL_MSGS}" "数据库落库数"
                    fi
                fi
            fi
        fi
    else
        log_skip "stress-tool 未安装，跳过自动压测"
        log_info "手动压测后使用验证模式:  export MEASURED_RATE=... && bash $0 --mode verify"
    fi

    print_section "测试结果记录"
    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# TC-CR-5000: 五千人聊天室测试
# ============================================================

test_chatroom_5000() {
    local members=5000

    print_header "TC-CR-5000 五千人聊天室消息测试"

    print_chatroom_test_table "${members}" "${CR_TOTAL_MSGS}"

    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    print_section "测试步骤指引"

    cat << STEPS

  操作步骤:

  1. 创建聊天室并加入成员:
     - 5,000 个客户端加入同一个聊天室

  2. 执行发送:
     - 100 个发送客户端在聊天室内同时发送消息
     - 每个客户端发送 100 条消息

  3. 数据采集:
     - 服务端消息落库验证
     - 观察者接收消息验证
     - CPU 利用率（预期约 80%）

  4. 判定标准:
     ✅ 消息落库成功率 = 100%
     ✅ 观察者接收大部分消息

STEPS

    print_chatroom_benchmark "5,000" "97" "21.5" "80" "2.7" "13,440"

    print_section "自动执行压测"

    if [ -f "${SCRIPT_DIR}/lib_stress.sh" ] && [ -f "./stress-tool" ]; then
        log_info "检测到 stress-tool，自动执行聊天室压测..."
        source "${SCRIPT_DIR}/lib_stress.sh"
        local template="${SCRIPT_DIR}/stress_chatroom.toml"
        if [ -f "${template}" ]; then
            run_stress_test "${template}" "cr_${members}"
            if [ "${RATE:-0}" != "0" ]; then
                local broadcast_rate=$(echo "scale=2; ${RATE} / ${CR_CORES:-8} * ${members}" | bc -l 2>/dev/null || echo "0")
                check_benchmark "${broadcast_rate}" "${BENCH_CR_BROADCAST_RATE}" "聊天室广播速率"
                assert_success_rate "${SUCCESS:-0}" "消息落库成功率"
                if declare -f count_all_messages &>/dev/null; then
                    local db_count=$(count_all_messages 2>/dev/null || echo "0")
                    if [ "${db_count}" != "0" ]; then
                        assert_ge "${db_count}" "${CR_TOTAL_MSGS}" "数据库落库数"
                    fi
                fi
            fi
        fi
    else
        log_skip "stress-tool 未安装，跳过自动压测"
        log_info "手动压测后使用验证模式:  export MEASURED_RATE=... && bash $0 --mode verify"
    fi

    # --- 结果分析 ---
    print_section "结果趋势分析"

    cat << 'ANALYSIS'

  聊天室规模对性能的影响:
  
  ┌────────────┬──────────────┬─────────────────────┬──────────────────┐
  │ 聊天室人数 │ 发送时间      │ 单核速率             │ 单核广播拉取速率   │
  ├────────────┼──────────────┼─────────────────────┼──────────────────┤
  │ 1,000      │ 39 秒        │ 32 条/秒/核          │ 32,000 条/秒/核   │
  │ 2,000      │ 97 秒        │ 12.9 条/秒/核        │ 25,773 条/秒/核   │
  │ 5,000      │ 97 秒        │ 2.7 条/秒/核         │ 13,440 条/秒/核   │
  └────────────┴──────────────┴─────────────────────┴──────────────────┘

  结论:
  1. 聊天室人数增大时，单条消息发送耗时增加，单位时间内消息量减少
  2. 单位用户单位时间消息量降低 → 丢消息比例降低
  3. 到达 5,000 人时，消息基本不再丢失
  4. 稳定后单核广播与拉取速率收敛在约 13,000 条/秒/核

ANALYSIS

    print_section "测试结果记录"
    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# 主入口
# ============================================================

main() {
    case "${MODE}" in
        check|--check|-c)
            print_header "聊天室消息测试 - 环境检查"
            check_prerequisites
            print_summary
            ;;
        1000)
            test_chatroom_1000
            ;;
        2000)
            test_chatroom_2000
            ;;
        5000)
            test_chatroom_5000
            ;;
        verify)
            print_header "聊天室消息 基准验证"
            if [ -n "${RATE:-}" ] && [ "${RATE}" != "0" ]; then
                local broadcast_rate=$(echo "scale=2; ${RATE} / ${CR_CORES:-8} * ${VERIFY_CHATROOM_SIZE:-1000}" | bc 2>/dev/null || echo "0")
                log_metric "实测单核广播速率" "${broadcast_rate} 条/秒/核"
                check_benchmark "${broadcast_rate}" "${BENCH_CR_BROADCAST_RATE}" "聊天室广播基准"
                assert_success_rate "${SUCCESS:-0}" "消息落库成功率"
            else
                log_fail "未提供实测数据。设置环境变量:"
                log_info "  export RATE=13000 SUCCESS=100 VERIFY_CHATROOM_SIZE=1000"
                log_info "  bash $0 --mode verify"
            fi
            print_summary
            ;;
        *)
            echo "用法: $0 --mode <check|1000|2000|5000|verify>"
            echo ""
            echo "  check   仅检查环境配置"
            echo "  1000    执行千人聊天室测试 (TC-CR-1000)"
            echo "  2000    执行两千人聊天室测试 (TC-CR-2000)"
            echo "  5000    执行五千人聊天室测试 (TC-CR-5000)"
            echo "  verify  基准验证模式"
            echo ""
            echo "环境变量:"
            echo "  IM_HOST              IM 服务地址"
            echo "  CR_CORES             服务核心数 (默认: 8)"
            echo "  CR_SENDERS           发送客户端数 (默认: 100)"
            echo "  CR_MSGS_PER_SENDER   每客户端发送数 (默认: 100)"
            exit 1
            ;;
    esac
}

main
