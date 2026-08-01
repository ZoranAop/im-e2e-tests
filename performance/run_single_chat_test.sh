#!/usr/bin/env bash
# ============================================================
# TC-SC-001: 单聊消息发送测试
# TC-SC-002: 单聊消息收发测试
# ============================================================
# 测试目标:
#   TC-SC-001: 测试消息发送阶段性能（接收方离线，排除通知和拉取开销）
#   TC-SC-002: 测试发送→通知→拉取全链路性能（接收方全部在线）
#
# 用法:
#   环境检查:
#     bash run_single_chat_test.sh --mode check
#
#   发送测试 (TC-SC-001):
#     bash run_single_chat_test.sh --mode send
#
#   收发测试 (TC-SC-002):
#     bash run_single_chat_test.sh --mode recv
#
#   完整测试:
#     bash run_single_chat_test.sh --mode full
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../common/db_utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib_stress.sh" 2>/dev/null || true

# ============================================================
# 测试参数
# ============================================================
MODE="check"
while [[ $# -gt 0 ]]; do case "$1" in -m|--mode) MODE="$2"; shift 2;; check|send|recv|full|verify) MODE="$1"; shift;; *) shift;; esac; done
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
REPORT_FILE="${REPORT_DIR}/sc_$(date +%Y%m%d_%H%M%S).md"

# 测试参数（可通过环境变量覆盖）
SC_SENDERS="${SC_SENDERS:-200}"
SC_RECEIVERS="${SC_RECEIVERS:-1000}"
SC_ROUNDS="${SC_ROUNDS:-50}"
SC_TOTAL_MSGS="${SC_TOTAL_MSGS:-10000000}"
SC_CORES="${SC_CORES:-16}"

# ============================================================
# TC-SC-001: 发送消息测试
# ============================================================

test_sc_send() {
    local test_start=$(date +%s%3N)

    print_header "TC-SC-001 单聊发送消息测试"

    log_info "目标: 验证消息发送阶段性能"
    log_info "  发送用户: ${SC_SENDERS}"
    log_info "  接收用户: ${SC_RECEIVERS} (999 离线 + 1 真实手机在线观察)"
    log_info "  发送轮次: ${SC_ROUNDS}"
    log_info "  消息总量: ${SC_TOTAL_MSGS}"
    log_info "  服务资源: 合计 ${SC_CORES}C48G (8C32G IM + 8C16G MySQL)"

    # --- 1. 环境检查 ---
    print_section "1. 环境检查"

    if ! check_prerequisites; then
        log_fail "环境检查失败，退出测试"
        return 1
    fi

    # --- 2. 测试场景参数确认 ---
    print_section "2. 测试参数配置"

    log_metric "发送用户数" "${SC_SENDERS}"
    log_metric "接收用户数" "${SC_RECEIVERS}"
    log_metric "发送轮次" "${SC_ROUNDS}"
    log_metric "消息总量（条）" "${SC_TOTAL_MSGS}"
    log_metric "服务总核心数" "${SC_CORES}"

    # --- 3. 发送准备 ---
    print_section "3. 发送阶段准备"

    log_info "确认 im-server.conf 关键配置:"
    log_info "  [ ] client.request_rate_limit = 1000000"
    log_info "  [ ] message.max_queue = 100000"
    log_info "  [ ] embed.db = 0"
    log_info "  [ ] netty.epoll = true"

    # --- 4. 发送测试详解 ---
    print_section "4. 测试步骤"

    cat << STEPS

  操作步骤:
  
  1. 准备测试环境:
     - 创建 ${SC_SENDERS} 个发送用户
     - 创建 ${SC_RECEIVERS} 个接收用户
     - 1 个接收用户使用真实手机客户端保持在线（观察者）
     - 其余 ${SC_RECEIVERS_MINUS_1} 个接收用户保持离线

  2. 执行发送:
     - 所有发送者同时向全部接收者发送消息
     - 完成 ${SC_ROUNDS} 轮发送
     - stress-tool 配置: Lite = true (只发送，不等待接收)

  3. 数据采集:
     - 记录发送开始时间和结束时间
     - 服务端消息落库数量验证
     - 观察者接收消息条数验证
     - 服务端 CPU / 内存 / DB 利用率监控

  4. 清理:
     - 发送结束后，等待服务端压力降为 0
     - 验证观察者已收齐全部消息

STEPS

    # --- 5. 验证清单 ---
    print_section "5. 数据验证清单"

    log_info "MySQL 消息总量验证:"
    log_info "  SELECT COUNT(*) FROM t_messages_X; （128 张分表总和）"

    log_info "观察者接收验证:"
    local expected_observer_msgs=$((SC_SENDERS * SC_ROUNDS))
    log_info "  预期接收条数: ${expected_observer_msgs}"

    # --- 6. 判定标准与基准 ---
    print_section "6. 判定标准"

    cat << 'CRITERIA'

  合格标准:
  ✅ 消息成功率 = 100%
  ✅ 观察者接收消息条数正确
  ✅ 发送延迟肉眼无法察觉（发送结束后消息立即收齐）
  ✅ 发送结束后服务端压力迅速降为 0

  参考基准（16C48G 环境）:
  ┌──────────────────────┬─────────────────┐
  │ 指标                 │ 实测基准值       │
  ├──────────────────────┼─────────────────┤
  │ 消息总量             │ 1,000 万条       │
  │ 成功率               │ 100%            │
  │ 发送时间             │ 509 秒          │
  │ 发送速率             │ 19,646 条/秒    │
  │ 单核速率             │ 1,227 条/秒/核   │
  │ 单核分发速率          │ 2,455 条/秒/核   │
  └──────────────────────┴─────────────────┘

  计算公式:
  发送速率   = 消息总量 ÷ 发送时间
  单核速率   = 发送速率 ÷ 核心数(16)
  单核分发速率 = 单核速率 × 2（分发到发送者和接收者）

  测试结果判定:
  - 达到基准的 100%+ → 优秀
  - 达到基准的 80%+ → 合格
  - 低于基准的 80% → 需排查

CRITERIA

    # --- 7. 自动执行压测 ---
    print_section "7. 自动执行压测"

    if [ -f "${SCRIPT_DIR}/lib_stress.sh" ] && [ -f "./stress-tool" ]; then
        log_info "检测到 stress-tool，自动执行发送压测..."
        local template="${SCRIPT_DIR}/stress_single_chat.toml"
        if [ -f "${template}" ]; then
            source "${SCRIPT_DIR}/lib_stress.sh"
            run_stress_test "${template}" "sc_send"
            if [ "${RATE:-0}" != "0" ]; then
                check_benchmark "${RATE}" "${BENCH_SC_SEND_RATE}" "发送速率基准"
                assert_success_rate "${SUCCESS:-0}" "消息成功率"
                local expected_msgs=$((SC_SENDERS * SC_RECEIVERS * SC_ROUNDS))
                assert_eq "${TOTAL:-0}" "${expected_msgs}" "消息总量"
                if declare -f count_all_messages &>/dev/null; then
                    local db_count=$(count_all_messages 2>/dev/null || echo "0")
                    if [ "${db_count}" != "0" ]; then
                        assert_ge "${db_count}" "${expected_msgs}" "数据库落库数"
                    fi
                fi
            fi
        fi
    else
        log_skip "stress-tool 未安装，跳过自动压测"
        log_info "手动压测后使用验证模式:  export MEASURED_RATE=...  && bash $0 --mode verify"
    fi

    # --- 8. 测试结论指引 ---
    print_section "8. 测试结论指引"

    cat << 'GUIDE'
  脚本已执行环境检查。要完成完整的性能测试并得出 PASS/FAIL 判定，需：

  1. 部署 stress-tool 并配置对应的 TOML 模板
  2. 运行 stress-tool 进行压测
  3. 将压测结果（发送速率、耗时、成功率）填入以下变量：
     export MEASURED_RATE=    # 实测发送速率
     export MEASURED_TIME=    # 实测发送时间
     export MEASURED_SUCCESS= # 实测成功率(%)

  4. 重新运行本脚本（含 --verify 参数）进行基准比对：
     bash run_single_chat_test.sh --mode verify


  脚本将自动调用 check_benchmark 给出 优秀/合格/不合格 判定。

GUIDE

    # --- 9. 结果记录模板 ---
    print_section "9. 测试结果记录"

    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_section "实测验证指引"
    log_info "完成压测后，运行: bash $0 --mode verify"
    log_info "并设置以下环境变量: RATE TOTAL SUCCESS P99 P95 CPU"

    print_summary
}

# ============================================================
# TC-SC-002: 收发消息测试
# ============================================================

test_sc_recv() {
    print_header "TC-SC-002 单聊收发消息测试"

    log_info "目标: 验证发送→通知→拉取全链路性能"
    log_info "  发送用户: ${SC_SENDERS}"
    log_info "  接收用户: ${SC_RECEIVERS}（全部在线，1 个真实手机观察）"
    log_info "  发送轮次: ${SC_ROUNDS}"
    log_info "  消息总量: ${SC_TOTAL_MSGS}"
    log_info "  服务资源: 合计 ${SC_CORES}C48G"

    # --- 1. 环境检查 ---
    print_section "1. 环境检查"

    if ! check_prerequisites; then
        log_fail "环境检查失败，退出测试"
        return 1
    fi

    # --- 2. 测试参数确认 ---
    print_section "2. 测试参数配置"

    log_metric "发送用户数" "${SC_SENDERS}"
    log_metric "接收用户数（全部在线）" "${SC_RECEIVERS}"
    log_metric "发送轮次" "${SC_ROUNDS}"
    log_metric "消息总量（条）" "${SC_TOTAL_MSGS}"
    log_metric "服务总核心数" "${SC_CORES}"

    # --- 3. 测试步骤 ---
    print_section "3. 测试步骤"

    cat << STEPS

  操作步骤:

  1. 准备测试环境:
     - 创建 ${SC_SENDERS} 个发送用户
     - 创建 ${SC_RECEIVERS} 个接收用户
     - 全部接收用户在线（模拟客户端连接）
     - 1 个接收用户为真实手机客户端（观察者）

  2. 执行收发:
     - 发送者同时向全部接收者发送消息
     - 接收者实时接收并确认
     - 完成 ${SC_ROUNDS} 轮发送
     - stress-tool 配置: Lite = false（收发模式）

  3. 数据采集:
     - 记录收发开始时间和结束时间
     - 服务端消息落库数量验证
     - 观察者接收消息条数和实时性验证
     - 服务端 CPU / 内存 / DB 利用率监控

  4. 清理:
     - 收发结束后，等待服务端压力降为 0
     - 验证观察者已收齐全部消息

STEPS

    # --- 4. 判定标准与基准 ---
    print_section "4. 判定标准与参考基准"

    cat << 'CRITERIA'

  合格标准:
  ✅ 消息成功率 = 100%
  ✅ 观察者接收消息条数正确
  ✅ 收发延迟肉眼无法察觉
  ✅ 发送结束后服务端压力迅速降为 0

  参考基准（16C48G 环境）:
  ┌──────────────────────┬─────────────────┐
  │ 指标                 │ 实测基准值       │
  ├──────────────────────┼─────────────────┤
  │ 消息总量             │ 1,000 万条       │
  │ 成功率               │ 100%            │
  │ 收发时间             │ 719 秒          │
  │ 收发速率             │ 13,908 条/秒    │
  │ 单核速率             │ 869 条/秒/核    │
  └──────────────────────┴─────────────────┘

  通知+拉取速率推导:
  1 ÷ 收发单核速率 = 1 ÷ 发送单核速率 + 1 ÷ (通知+拉取)单核速率
  1 ÷ 869 = 1 ÷ 1227 + 1 ÷ x
  x ≈ 2,978 条/秒/核

  测试结果判定:
  - 达到基准的 100%+ → 优秀
  - 达到基准的 80%+ → 合格
  - 低于基准的 80% → 需排查

CRITERIA

    # --- 5. 自动执行压测 ---
    print_section "5. 自动执行压测"

    if [ -f "${SCRIPT_DIR}/lib_stress.sh" ] && [ -f "./stress-tool" ]; then
        log_info "检测到 stress-tool，自动执行收发压测..."
        local template="${SCRIPT_DIR}/stress_single_chat.toml"
        if [ -f "${template}" ]; then
            source "${SCRIPT_DIR}/lib_stress.sh"
            run_stress_test "${template}" "sc_recv"
            if [ "${RATE:-0}" != "0" ]; then
                check_benchmark "${RATE}" "${BENCH_SC_RECV_RATE}" "收发速率基准"
                assert_success_rate "${SUCCESS:-0}" "消息成功率"
                local expected_msgs=$((SC_SENDERS * SC_RECEIVERS * SC_ROUNDS))
                assert_eq "${TOTAL:-0}" "${expected_msgs}" "消息总量"
                if declare -f count_all_messages &>/dev/null; then
                    local db_count=$(count_all_messages 2>/dev/null || echo "0")
                    if [ "${db_count}" != "0" ]; then
                        assert_ge "${db_count}" "${expected_msgs}" "数据库落库数"
                    fi
                fi
            fi
        fi
    else
        log_skip "stress-tool 未安装，跳过自动压测"
        log_info "手动压测后使用验证模式:  export MEASURED_RATE=...  && bash $0 --mode verify"
    fi

    # --- 6. 性能阶段分析 ---
    print_section "6. 性能模型说明"

    cat << 'MODEL'

  消息处理阶段与单核性能（16C48G 参考值）:
  
  ┌──────────┬─────────────────────┬─────────────────┐
  │ 阶段     │ 说明                │ 单核速率（参考） │
  ├──────────┼─────────────────────┼─────────────────┤
  │ 发送阶段 │ 请求→落库→确认       │ 1,227 条/秒/核   │
  │ 分发阶段 │ 目标时间线插入落库    │ 8,750 条/秒/核   │
  │ 通知阶段 │ 推送新消息通知给在线  │ ≈ 2,978 条/秒/核 │
  │ 拉取阶段 │ 客户端请求消息        │ （见上推导）     │
  │ 推送阶段 │ HTTP 调用推送服务     │ 低开销          │
  └──────────┴─────────────────────┴─────────────────┘

  TC-SC-001 测的是「发送阶段 + 少量分发」的性能。
  TC-SC-002 测的是「发送 + 分发 + 通知 + 拉取」的全链路性能。
  两者差值可推导出通知+拉取阶段的单核性能。

MODEL

    print_section "7. 测试结果记录"

    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# 完整测试（发送 + 收发）
# ============================================================

test_sc_full() {
    print_header "单聊消息完整测试（TC-SC-001 + TC-SC-002）"

    mkdir -p "${REPORT_DIR}"

    log_info "报告目录: ${REPORT_DIR}"
    log_info "测试配置:"
    log_info "  发送用户: ${SC_SENDERS}"
    log_info "  接收用户: ${SC_RECEIVERS}"
    log_info "  发送轮次: ${SC_ROUNDS}"
    log_info "  消息总量: ${SC_TOTAL_MSGS}"

    echo ""
    log_info "=== 第 1 部分: 发送测试 (TC-SC-001) ==="
    test_sc_send

    echo ""
    log_info "=== 第 2 部分: 收发测试 (TC-SC-002) ==="
    test_sc_recv
}

# ============================================================
# 主入口
# ============================================================

main() {
    case "${MODE}" in
        check|--check|-c)
            check_prerequisites
            print_summary
            ;;
        send|--send|-s)
            test_sc_send
            ;;
        recv|--recv|-r)
            test_sc_recv
            ;;
        full|--full|-f)
            test_sc_full
            ;;
        verify)
            print_header "TC-SC-001 基准验证"
            if [ -n "${RATE:-}" ] && [ "${RATE}" != "0" ]; then
                log_metric "实测发送速率" "${RATE} 条/秒"
                check_benchmark "${RATE}" "${BENCH_SC_SEND_RATE}" "发送速率基准"
                assert_success_rate "${SUCCESS:-0}" "消息成功率"
                local expected_msgs=$((SC_SENDERS * SC_RECEIVERS * SC_ROUNDS))
                assert_eq "${TOTAL:-0}" "${expected_msgs}" "消息总量(${expected_msgs})"
                if [ -n "${P99:-}" ] && [ "${P99}" != "0" ]; then
                    assert_latency "${P99}" "${P95:-0}" "500" "300"
                fi
                if [ -n "${CPU:-}" ]; then
                    assert_cpu_under "${CPU}" "95" "CPU利用率"
                fi
            else
                log_fail "未提供实测数据。设置环境变量后运行:"
                log_info "  export RATE=19646 TOTAL=10000000 SUCCESS=100 P99=45 P95=32 CPU=90"
                log_info "  bash $0 --mode verify"
            fi
            print_summary
            ;;
        *)
            echo "用法: $0 --mode <check|send|recv|full>"
            echo ""
            echo "  check  仅检查环境配置"
            echo "  send   执行发送测试 (TC-SC-001)"
            echo "  recv   执行收发测试 (TC-SC-002)"
            echo "  full   执行完整测试"
            echo ""
            echo "环境变量:"
            echo "  IM_HOST          IM 服务地址"
            echo "  SC_SENDERS       发送用户数 (默认: 200)"
            echo "  SC_RECEIVERS     接收用户数 (默认: 1000)"
            echo "  SC_ROUNDS        发送轮次 (默认: 50)"
            echo "  SC_TOTAL_MSGS    消息总量 (默认: 10000000)"
            echo "  SC_CORES         服务总核心数 (默认: 16)"
            exit 1
            ;;
    esac
}

main
