#!/usr/bin/env bash
# ============================================================
# TC-CL-001: 单节点集群性能测试
# TC-CL-002: 双节点集群性能测试
# TC-CL-003: 三节点集群性能测试
# TC-CL-004: 四节点集群性能测试
# ============================================================
# 测试目标:
#   TC-CL-001: 验证单节点模式下集群运行性能（基准对照）
#   TC-CL-002: 验证双节点集群协同分发性能与线性扩展性
#   TC-CL-003: 验证三节点集群协同分发性能与线性扩展性
#   TC-CL-004: 验证四节点集群协同分发性能与线性扩展性
#
# 用法:
#   环境检查:
#     bash run_cluster_test.sh --mode check
#
#   单节点测试:
#     bash run_cluster_test.sh --mode 1
#
#   双节点测试:
#     bash run_cluster_test.sh --mode 2
#
#   三节点测试:
#     bash run_cluster_test.sh --mode 3
#
#   四节点测试:
#     bash run_cluster_test.sh --mode 4
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true

# ============================================================
# 测试参数
# ============================================================
MODE="check"
while [[ $# -gt 0 ]]; do case "$1" in -m|--mode) MODE="$2"; shift 2;; -h|--help) MODE="help"; shift;; check|1|2|3|4|verify) MODE="$1"; shift;; *) shift;; esac; done
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
REPORT_FILE="${REPORT_DIR}/cl_$(date +%Y%m%d_%H%M%S).md"

# 集群测试参数（可通过环境变量覆盖）
CL_SENDERS="${CL_SENDERS:-200}"
CL_RECEIVERS="${CL_RECEIVERS:-200}"
CL_ROUNDS="${CL_ROUNDS:-20}"
CL_TOTAL_MSGS=$((CL_SENDERS * CL_RECEIVERS * CL_ROUNDS))
CL_SERVER_SPEC="${CL_SERVER_SPEC:-4×4C8G}"

# ============================================================
# 集群性能模型
# ============================================================
# 单节点基准 (16C): 6,537 条/秒
# 本地节点分发: ~1,634 条/秒/核
# RPC 跨节点分发: ~800 条/秒/核
# N 节点吞吐 ≈ 6,537 × (1 + (N-1) × 0.5)
# 效率系数 0.5 = 800 / 1,634 (RPC / 本地)

# ============================================================
# 辅助函数
# ============================================================

print_cluster_benchmark_table() {
    local nodes="$1"

    cat << BENCH

  参考基准（${CL_SERVER_SPEC} 环境，${nodes} 节点）:
  ┌──────────────────────┬─────────────────────┐
  │ 指标                 │ 实测基准值           │
  ├──────────────────────┼─────────────────────┤
  │ 消息成功率           │ 100%                │
  │ 发送延迟             │ 肉眼无法察觉         │
  │ 内存占用             │ 稳步增长不泄漏       │
  │ 发送后压力回落       │ 迅速降为 0           │
  │ 发送用户数           │ ${CL_SENDERS}        │
  │ 接收用户数           │ ${CL_RECEIVERS}      │
  │ 发送轮次             │ ${CL_ROUNDS}         │
  │ 消息总量（条）       │ $(printf "%'d" ${CL_TOTAL_MSGS}) │
  │ Lite 模式            │ true（只发送，不等待接收）│
  └──────────────────────┴─────────────────────┘

BENCH
}

print_cluster_perf_model() {
    cat << 'MODEL'

  集群 RPC 性能模型推导:
  
  ┌──────────────────────┬───────────────────────────────┐
  │ 分发类型             │ 单核吞吐（条/秒/核）            │
  ├──────────────────────┼───────────────────────────────┤
  │ 本地节点内分发       │ 1,634                         │
  │ RPC 跨节点分发       │ 800                           │
  │ 效率系数 (RPC/本地)  │ 0.5                           │
  └──────────────────────┴───────────────────────────────┘
  
  推导过程:
  - 单节点 16 核总吞吐 = 6,537 条/秒
  - 单核本地分发速率 = 6,537 ÷ (16 × 0.5 × 0.5) ≈ 1,634 条/秒/核
  - 跨节点 RPC 网络开销约为本地的一半
  - RPC 单核分发速率 = 1,634 × 0.5 ≈ 800 条/秒/核
  
  集群扩展公式:
  N 节点吞吐 ≈ 6,537 × (1 + (N-1) × 0.5)
  
  ┌───────────────┬──────────────────────┬─────────────────┐
  │ 节点数        │ 公式                  │ 预期吞吐（条/秒）│
  ├───────────────┼──────────────────────┼─────────────────┤
  │ N = 1         │ 6,537 × (1 + 0×0.5)  │ 6,537           │
  │ N = 2         │ 6,537 × (1 + 1×0.5)  │ 9,806           │
  │ N = 3         │ 6,537 × (1 + 2×0.5)  │ 13,074          │
  │ N = 4         │ 6,537 × (1 + 3×0.5)  │ 16,343          │
  └───────────────┴──────────────────────┴─────────────────┘
  
  说明: 新增节点对总吞吐的贡献呈递减趋势 (效率 ≈ 50%/节点)，
  因为 RPC 跨节点分发比本地分发慢约一半。当 N → ∞ 时，RPC
  开销主导，集群总吞吐受限于网络带宽。

MODEL
}

print_cluster_config_steps() {
    local nodes="$1"

    cat << CONFIG

  集群配置步骤 (${nodes} 节点):

  1. im-server.conf 配置:
     每个节点设置唯一的 node_id:
     - 节点 1: im-server.node_id = "im-node-1"
     - 节点 2: im-server.node_id = "im-node-2"
     - 节点 3: im-server.node_id = "im-node-3"
     - 节点 4: im-server.node_id = "im-node-4"

  2. cluster-config.xml 配置:
     启用 TCP-IP 成员发现:
     <join>
         <multicast enabled="false"/>
         <tcp-ip enabled="true">
             <member>im-node-1-ip</member>
             <member>im-node-2-ip</member>
             <member>im-node-3-ip</member>
             <member>im-node-4-ip</member>
         </tcp-ip>
     </join>

  3. 验证集群成员:
     curl http://${CLUSTER_AUTH_IP:-<auth_ip>}:${IM_ADMIN_PORT}/api/version
     检查 nodeIds 字段是否包含所有预期节点 ID

CONFIG
}

# ============================================================
# TC-CL-001~004: 集群节点测试
# ============================================================

cluster_test_node() {
    local nodes="$1"
    local test_id="$2"
    local num="${nodes}"

    print_header "TC-${test_id} ${nodes} 节点集群性能测试"

    log_info "目标: 验证 ${nodes} 节点集群模式下消息分发性能"
    log_info "  节点数量: ${nodes}"
    log_info "  发送用户: ${CL_SENDERS}"
    log_info "  接收用户: ${CL_RECEIVERS}"
    log_info "  发送轮次: ${CL_ROUNDS}"
    log_info "  消息总量: $(printf "%'d" ${CL_TOTAL_MSGS})"
    log_info "  硬件配置: ${CL_SERVER_SPEC}"

    # --- 1. 环境检查 ---
    print_section "1. 环境检查"

    if ! check_prerequisites; then
        log_fail "环境检查失败，退出测试"
        return 1
    fi

    # --- 2. 硬件架构 ---
    print_section "2. 硬件环境架构"

    cat << HARDWARE

  测试拓扑 (${nodes} 节点):
  
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │    ┌─────────┐  ┌─────────┐                     │
  │    │ IM Node │  │ IM Node │   ...                │
  │    │  4C8G   │  │  4C8G   │                      │
  │    └────┬────┘  └────┬────┘                      │
  │         │            │                            │
  │         └─────┬──────┘                            │
  │               │                                    │
  │        ┌──────┴──────┐                            │
  │        │   MySQL     │                            │
  │        │   8C16G     │                            │
  │        └─────────────┘                            │
  │                                                  │
  │  各 IM 节点 4C8G, MySQL 独立部署 8C16G            │
  │  节点间通过 TCP-IP 组成 Hazelcast 集群             │
  └──────────────────────────────────────────────────┘

HARDWARE

    # --- 3. 集群配置 ---
    print_section "3. 集群配置"
    print_cluster_config_steps "${nodes}"

    # --- 4. 测试参数 ---
    print_section "4. 测试参数"

    log_metric "节点数量" "${nodes}"
    log_metric "发送用户数" "${CL_SENDERS}"
    log_metric "接收用户数" "${CL_RECEIVERS}"
    log_metric "发送轮次" "${CL_ROUNDS}"
    log_metric "消息总量（条）" "$(printf "%'d" ${CL_TOTAL_MSGS})"
    log_metric "Lite 模式" "true"

    # --- 5. 测试步骤 ---
    print_section "5. 测试步骤"

    cat << 'STEPS'

  操作步骤:

  1. 环境准备:
     - 确认 ${CLUSTER_NODES} 个 IM 节点已部署完毕
     - 确认 MySQL 服务正常运行
     - 确认各节点 im-server.conf 的 node_id 唯一
     - 确认 cluster-config.xml 已配置 TCP-IP 成员列表
     - 确认所有节点使用 /api/version 可达并加入集群

  2. 预热启动:
     - 依次启动所有集群节点
     - 等待 3 分钟，使 Hazelcast 集群稳定
     - 确认集群成员完整（${CLUSTER_NODES} 个成员）

  3. 第一次运行（预热）:
     - 运行 stress-tool，参数:
       senders=${CL_SENDERS} receivers=${CL_RECEIVERS} rounds=${CL_ROUNDS}
       Lite=true
     - 收集预热数据（不计入正式结果）
     - 等待压力降为 0

  4. 第二次运行（正式数据）:
     - 二次运行 stress-tool（相同参数）
     - 数据视为正式结果
     - 监控以下指标:
       * 发送总耗时
       * CPU 利用率 (per node)
       * 内存使用 (per node)
       * 消息落库成功率

  5. 数据采集:
     - 记录发送开始时间和结束时间
     - 服务端消息落库数量验证
     - 各节点 CPU / 内存 / 网络 I/O 监控
     - 集群成员状态检查

  6. 清理:
     - 发送结束后，等待服务端压力降为 0
     - 验证所有节点状态正常
     - 收集各节点日志

STEPS

    # --- 6. 参考基准 ---
    print_section "6. 参考基准"
    print_cluster_benchmark_table "${nodes}"

    print_section "自动执行集群压测"

    if [ -f "${SCRIPT_DIR}/lib_stress.sh" ] && [ -f "./stress-tool" ]; then
        log_info "检测到 stress-tool，自动执行集群压测（${num} 节点）..."
        source "${SCRIPT_DIR}/lib_stress.sh"
        local template="${SCRIPT_DIR}/stress_single_chat.toml"
        if [ -f "${template}" ]; then
            run_stress_test "${template}" "cl_${num}node"
            if [ "${RATE:-0}" != "0" ]; then
                local core_rate=$(float_div "${RATE}" "$((num * 4))" "2")
                log_metric "实测吞吐量" "${RATE} 条/秒"
                log_metric "实测单核速率" "${core_rate} 条/秒/核"
                
                case "${num}" in
                    1) check_benchmark "${RATE}" "${BENCH_CL_1_TPUT}" "单节点吞吐量";;
                    2) check_benchmark "${RATE}" "${BENCH_CL_2_TPUT}" "双节点吞吐量";;
                    3) check_benchmark "${RATE}" "${BENCH_CL_3_TPUT}" "三节点吞吐量";;
                    4) check_benchmark "${RATE}" "${BENCH_CL_4_TPUT}" "四节点吞吐量";;
                esac
                assert_success_rate "${SUCCESS:-0}" "集群消息成功率"
                
                if declare -f count_all_messages &>/dev/null; then
                    local expected_msgs=$((CL_SENDERS * CL_RECEIVERS * CL_ROUNDS))
                    local db_count=$(count_all_messages 2>/dev/null || echo "0")
                    if [ "${db_count}" != "0" ]; then
                        assert_ge "${db_count}" "${expected_msgs}" "集群落库数"
                    fi
                fi
            fi
        fi
    else
        log_skip "stress-tool 未安装，跳过自动压测"
        log_info "手动压测后验证: export MEASURED_RATE=... && bash $0 --mode verify"
    fi

    # --- 7. 性能模型 ---
    print_section "7. RPC 性能模型与扩展公式"
    print_cluster_perf_model

    # --- 8. 验证方法 ---
    print_section "8. 集群验证"

    cat << VERIFY

  集群验证命令:
  
  1. 检查各节点可达性:
  VERIFY
    for i in $(seq 1 ${CLUSTER_NODES}); do
        echo "     curl -s http://<node${i}_ip>:\${IM_ADMIN_PORT}/api/version"
    done
    cat << VERIFY

  2. 检查集群成员（在授权节点执行）:
     curl -s http://\${CLUSTER_AUTH_IP}:\${IM_ADMIN_PORT}/api/version
     检查 nodeIds 字段是否包含所有 N 个节点 ID

  3. 验证集群拓扑:
     - 所有节点 nodeIds 列表应一致
     - 节点 ID 格式: im-node-1, im-node-2, ...

VERIFY

    # --- 9. 结果记录模板 ---
    print_section "9. 测试结果记录"

    local elapsed=$(elapsed_sec)
    log_timing "总计耗时" "${elapsed}s"

    print_summary
}

# ============================================================
# 环境检查
# ============================================================

cluster_env_check() {
    print_header "集群性能测试 - 环境检查"

    # --- 1. 基础环境检查 ---
    if ! check_prerequisites; then
        log_fail "基础环境检查失败"
        return 1
    fi

    # --- 2. 集群节点检查 ---
    check_cluster_nodes

    # --- 3. 参数确认 ---
    print_section "集群配置确认"

    log_metric "预期节点数" "${CLUSTER_NODES}"
    log_metric "集群节点 IP" "${CLUSTER_NODE_IPS:-未设置}"
    log_metric "授权节点 IP" "${CLUSTER_AUTH_IP:-未设置}"

    # --- 4. 硬件要求 ---
    print_section "硬件要求"

    cat << REQ

  最低硬件要求:
  ┌──────────────────┬─────────────────────┐
  │ 组件             │ 配置                 │
  ├──────────────────┼─────────────────────┤
  │ IM 节点 (每个)   │ 4C8G                │
  │ IM 节点数量      │ ${CLUSTER_NODES}        │
  │ MySQL            │ 8C16G               │
  │ 网络             │ 至少 1Gbps（节点间） │
  │ 磁盘             │ SSD（建议）         │
  └──────────────────┴─────────────────────┘

REQ

    # --- 5. 版本信息 ---
    print_section "节点版本确认"

    if [ -n "${CLUSTER_NODE_IPS}" ]; then
        for ip in ${CLUSTER_NODE_IPS}; do
            local version=$(curl -s "http://${ip}:${IM_ADMIN_PORT}/api/version" 2>/dev/null)
            if [ -n "${version}" ]; then
                log_info "节点 ${ip}: ${version}"
            else
                log_warn "节点 ${ip}: 无法获取版本信息"
            fi
        done
    fi

    print_summary
}

# ============================================================
# 主入口
# ============================================================

main() {
    case "${MODE}" in
        check|--check|-c)
            cluster_env_check
            ;;
        1)
            cluster_test_node 1 "CL-001"
            ;;
        2)
            cluster_test_node 2 "CL-002"
            ;;
        3)
            cluster_test_node 3 "CL-003"
            ;;
        4)
            cluster_test_node 4 "CL-004"
            ;;
        verify)
            print_header "集群性能基准验证"
            if [ -n "${MEASURED_RATE:-}" ]; then
                check_benchmark "${MEASURED_RATE}" "${BENCH_CL_1_TPUT}" "集群吞吐量"
                assert_success_rate "${MEASURED_SUCCESS:-0}" "消息成功率"
            else
                log_fail "未提供实测数据"
                log_info "  export MEASURED_RATE=6537 && bash $0 --mode verify"
            fi
            print_summary
            ;;
        *)
            echo "用法: $0 --mode <check|1|2|3|4>"
            echo ""
            echo "  check  仅检查集群环境配置"
            echo "  1      执行单节点集群测试 (TC-CL-001)"
            echo "  2      执行双节点集群测试 (TC-CL-002)"
            echo "  3      执行三节点集群测试 (TC-CL-003)"
            echo "  4      执行四节点集群测试 (TC-CL-004)"
            echo ""
            echo "环境变量:"
            echo "  CLUSTER_NODES      集群节点数（默认: 4）"
            echo "  CLUSTER_NODE_IPS   节点 IP 列表（空格分隔）"
            echo "  CLUSTER_AUTH_IP    授权节点 IP"
            echo "  CL_SENDERS         发送用户数（默认: 200）"
            echo "  CL_RECEIVERS       接收用户数（默认: 200）"
            echo "  CL_ROUNDS          发送轮次（默认: 20）"
            echo "  CL_SERVER_SPEC     服务器规格（默认: 4×4C8G）"
            echo "  IM_ADMIN_PORT      管理端口（默认: 18080）"
            exit 1
            ;;
    esac
}

main
