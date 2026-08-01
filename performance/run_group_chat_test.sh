#!/usr/bin/env bash
# ============================================================
# TC-GC-100 / TC-GC-200 / TC-GC-1000: 群聊消息性能测试
# ============================================================
# 测试目标:
#   TC-GC-100:  百人群聊分发性能
#   TC-GC-200:  两百人群聊分发性能
#   TC-GC-1000: 千人群聊分发性能
#
# 用法:
#   百人群测试:
#     bash run_group_chat_test.sh --mode 100
#
#   两百人群测试:
#     bash run_group_chat_test.sh --mode 200
#
#   千人群测试:
#     bash run_group_chat_test.sh --mode 1000
#
#   环境检查:
#     bash run_group_chat_test.sh --mode check
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ============================================================
# 测试参数
# ============================================================
MODE="${1:-check}"
GC_CORES="${GC_CORES:-16}"
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
REPORT_FILE="${REPORT_DIR}/gc_$(date +%Y%m%d_%H%M%S).md"

# ============================================================
# 内部函数
# ============================================================

print_group_test_result_table() {
    local group_size="$1"
    local groups="$2"
    local senders="$3"
    local normal_members="$4"
    local observers="$5"
    local rounds="$6"
    local total_msgs="$7"
    local expected_observer_msgs="$8"

    cat << TABLE

  ┌──────────────────────┬───────────────┐
  │ 测试参数             │ 值             │
  ├──────────────────────┼───────────────┤
  │ 服务资源             │ ${GC_CORES}C48G │
  │ 群数量               │ ${groups}      │
  │ 每群成员数           │ ${group_size}  │
  │ 发送用户数           │ ${senders}     │
  │ 普通成员数           │ ${normal_members} │
  │ 观察用户数           │ ${observers}    │
  │ 发送轮次             │ ${rounds}       │
  │ 消息总量（条）       │ ${total_msgs}   │
  │ 观察者预期接收       │ ${expected_observer_msgs} │
  └──────────────────────┴───────────────┘

TABLE
}

print_group_benchmark() {
    local size="$1"
    local time="$2"
    local rate="$3"
    local core_rate="$4"
    local dispatch_rate="$5"

    cat << BENCH

  参考基准（${GC_CORES}C48G 环境，${size}人群）:
  ┌──────────────────────┬─────────────────────┐
  │ 指标                 │ 实测基准值           │
  ├──────────────────────┼─────────────────────┤
  │ 消息成功率           │ 100%                │
  │ CPU 利用率           │ 100%（无瓶颈）       │
  │ 发送延迟             │ 肉眼无法察觉         │
  │ 发送时间             │ ${time} 秒           │
  │ 发送速率             │ ${rate} 条/秒        │
  │ 单核速率             │ ${core_rate} 条/秒/核│
  │ 单核分发速率          │ ${dispatch_rate} 条/秒/核│
  └──────────────────────┴─────────────────────┘

  计算公式:
  发送速率     = 消息总量 ÷ 发送时间
  单核速率     = 发送速率 ÷ 核心数(${GC_CORES})
  单核分发速率  = 单核速率 × 群人数(${size})

BENCH
}

# ============================================================
# TC-GC-100: 百人群聊测试
# ============================================================

test_group_100() {
    print_header "TC-GC-100 百人群聊消息测试"

    local groups=100
    local group_size=100
    local senders=50
    local normal_members=49
    local observers=1
    local rounds=20
    local total_msgs=$((senders * groups * rounds))
    local expected_observer_msgs=$((rounds * groups))

    print_group_test_result_table \
        100 100 50 49 1 20 100000 "$((20 * 100))"

    # --- 环境检查 ---
    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    # --- 测试指引 ---
    print_section "测试步骤"

    cat << 'STEPS'

  操作步骤:

  1. 创建群组:
     - 创建 100 个群组
     - 每群 100 成员（49 普通成员 + 1 观察者 + 50 发送者）

  2. 设置观察者:
     - 1 个真实手机客户端作为观察者加入所有群

  3. 执行发送:
     - 50 个发送者同时向各自所在的 100 个群发送消息
     - 完成 20 轮发送

  4. 数据采集:
     - CPU 利用率应达到 100%（代表无瓶颈）
     - 消息成功率应为 100%
     - 观察者应收到 20 × 100 = 2,000 条消息

  5. 判定标准:
     ✅ 消息成功率 = 100%
     ✅ 观察者接收条数正确
     ✅ 发送延迟肉眼无法察觉
     ✅ CPU 利用率 100%（无瓶颈）
     ✅ 发送结束后服务端压力迅速降为 0

STEPS

    print_group_benchmark "100" "74.6" "1,340" "83.75" "8,375"

    print_section "测试结果记录"
    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# TC-GC-200: 两百人群聊测试
# ============================================================

test_group_200() {
    print_header "TC-GC-200 两百人群聊消息测试"

    print_group_test_result_table \
        200 100 100 99 1 10 100000 "$((10 * 100))"

    # --- 环境检查 ---
    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    print_section "测试步骤"

    cat << 'STEPS'

  操作步骤:

  1. 创建群组:
     - 创建 100 个群组
     - 每群 200 成员（99 普通成员 + 1 观察者 + 100 发送者）

  2. 设置观察者:
     - 1 个真实手机客户端作为观察者加入所有群

  3. 执行发送:
     - 100 个发送者同时向各自所在的 100 个群发送消息
     - 完成 10 轮发送

  4. 数据采集:
     - CPU 利用率应达到 100%
     - 消息成功率应为 100%
     - 观察者应收到 10 × 100 = 1,000 条消息

  5. 判定标准:
     ✅ 消息成功率 = 100%
     ✅ 观察者接收条数正确
     ✅ 发送延迟肉眼无法察觉
     ✅ CPU 利用率 100%（无瓶颈）
     ✅ 发送结束后服务端压力迅速降为 0

STEPS

    print_group_benchmark "200" "145.8" "685.8" "42.87" "8,573"

    print_section "测试结果记录"
    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# TC-GC-1000: 千人群聊测试
# ============================================================

test_group_1000() {
    print_header "TC-GC-1000 千人群聊消息测试"

    print_group_test_result_table \
        1000 100 100 899 1 2 20000 "$((2 * 100))"

    # --- 环境检查 ---
    if ! check_prerequisites; then
        log_fail "环境检查失败"
        return 1
    fi

    print_section "测试步骤"

    cat << 'STEPS'

  操作步骤:

  1. 创建群组:
     - 创建 100 个群组
     - 每群 1,000 成员（899 普通成员 + 1 观察者 + 100 发送者）

  2. 设置观察者:
     - 1 个真实手机客户端作为观察者加入所有群

  3. 执行发送:
     - 100 个发送者同时向各自所在的 100 个群发送消息
     - 完成 2 轮发送

  4. 数据采集:
     - CPU 利用率应达到 100%
     - 消息成功率应为 100%
     - 观察者应收到 2 × 100 = 200 条消息

  5. 判定标准:
     ✅ 消息成功率 = 100%
     ✅ 观察者接收条数正确
     ✅ 发送延迟肉眼无法察觉
     ✅ CPU 利用率 100%（无瓶颈）
     ✅ 发送结束后服务端压力迅速降为 0

STEPS

    print_group_benchmark "1000" "142.8" "140" "8.75" "8,750"

    # --- 性能分析 ---
    print_section "群聊分发性能分析"

    cat << 'ANALYSIS'

  群聊测试的核心指标是「单核分发速率」:
  
  单核分发速率 = 单核发送速率 × 群总人数
  
  这条指标反映了消息分发阶段的实际吞吐能力。
  
  对比三个规模的测试:
  ┌────────┬──────────────┬─────────────────┐
  │ 群规模 │ 单核发送速率  │ 单核分发速率      │
  ├────────┼──────────────┼─────────────────┤
  │ 100 人 │ 83.75 条/秒  │ 8,375 条/秒/核   │
  │ 200 人 │ 42.87 条/秒  │ 8,573 条/秒/核   │
  │ 1000 人│ 8.75 条/秒   │ 8,750 条/秒/核   │
  └────────┴──────────────┴─────────────────┘
  
  结论: 不同群规模下，单核分发速率稳定在约 8,750 条/秒/核，
  表明分发阶段是按「总目标数」线性扩展的。

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
            print_header "群聊消息测试 - 环境检查"
            check_prerequisites
            print_summary
            ;;
        100)
            test_group_100
            ;;
        200)
            test_group_200
            ;;
        1000)
            test_group_1000
            ;;
        *)
            echo "用法: $0 --mode <check|100|200|1000>"
            echo ""
            echo "  check  仅检查环境配置"
            echo "  100    执行百人群聊测试 (TC-GC-100)"
            echo "  200    执行两百人群聊测试 (TC-GC-200)"
            echo "  1000   执行千人群聊测试 (TC-GC-1000)"
            echo ""
            echo "环境变量:"
            echo "  IM_HOST          IM 服务地址"
            echo "  GC_CORES         服务总核心数 (默认: 16)"
            exit 1
            ;;
    esac
}

main
