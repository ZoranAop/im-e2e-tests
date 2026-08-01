#!/usr/bin/env bash
# ============================================================
# TC-LC-001: 百万长连接性能测试
# ============================================================
# 测试目标: 验证单台 IM 服务在百万级并发长连接下持续在线的稳定性
#
# 前置条件:
#   1. IM 服务已部署（建议 16C32G）
#   2. MySQL 已配置（建议 4C8G）
#   3. im-server.conf 中已调整以下参数:
#      - client.request_rate_limit = 1000000
#      - netty.epoll = true
#
# 用法:
#   方式一（完整压测）:
#     export IM_HOST="your-im-server"
#     bash run_long_connection_test.sh --mode full
#
#   方式二（仅环境检查）:
#     bash run_long_connection_test.sh --mode check
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../common/db_utils.sh" 2>/dev/null || true

# ============================================================
# 测试参数（可通过命令行或环境变量覆盖）
# ============================================================
MODE="check"
while [[ $# -gt 0 ]]; do case "$1" in -m|--mode) MODE="$2"; shift 2;; -h|--help) MODE="help"; shift;; *) shift;; esac; done
CONNECTION_COUNT="${LC_CONN_COUNT:-1000000}"
DURATION_MINUTES="${LC_DURATION:-30}"
IM_SERVER_SPEC="${LC_SERVER_SPEC:-16C32G}"
MYSQL_SERVER_SPEC="${LC_MYSQL_SPEC:-4C8G}"
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"
REPORT_FILE="${REPORT_DIR}/lc_$(date +%Y%m%d_%H%M%S).md"

# ============================================================
# 测试场景: TC-LC-001
# ============================================================

test_long_connection_check() {
    print_header "TC-LC-001 百万长连接测试 - 环境预检"

    # --- 1. 服务连通性 ---
    print_section "1. 服务连通性检查"

    log_info "检查 IM 服务端口..."
    if check_tcp "${IM_HOST}" "${IM_HTTP_PORT}" 3; then
        log_pass "IM HTTP 端口 ${IM_HOST}:${IM_HTTP_PORT} 可达"
    else
        log_fail "IM HTTP 端口 ${IM_HOST}:${IM_HTTP_PORT} 不可达"
    fi

    log_info "检查 IM Admin 端口..."
    if check_tcp "${IM_HOST}" "${IM_ADMIN_PORT}" 3; then
        log_pass "IM Admin 端口 ${IM_HOST}:${IM_ADMIN_PORT} 可达"
    else
        log_fail "IM Admin 端口 ${IM_HOST}:${IM_ADMIN_PORT} 不可达"
    fi

    # --- 2. IM 服务配置检查 ---
    print_section "2. 服务配置检查"

    local svr_info=$(im_admin_get "/api/admin/config")
    if [ -n "${svr_info}" ]; then
        log_pass "IM Admin API 响应正常"
    else
        log_fail "IM Admin API 无响应"
    fi

    # 检查版本信息确认长连接协议支持
    local version=$(im_admin_get "/api/version")
    if [ -n "${version}" ] && echo "${version}" | grep -q "version"; then
        log_pass "IM 版本信息获取成功"
    else
        log_warn "无法获取版本信息"
    fi

    # 检查节点信息
    log_info "检查节点状态..."
    local node_info=$(im_admin_get "/api/version")
    if [ -n "${node_info}" ]; then
        log_pass "节点信息获取成功"
        log_info "  响应: ${node_info}"
    fi

    # --- 3. MySQL 配置检查 ---
    print_section "3. MySQL 状态检查"

    if [ -n "${MYSQL_PASS}" ]; then
        local db_conn=$(mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASS}" -e "SELECT 1;" 2>/dev/null)
        if [ -n "${db_conn}" ]; then
            log_pass "MySQL 连接正常"
        else
            log_warn "MySQL 连接失败（请检查 MYSQL_HOST/MYSQL_USER/MYSQL_PASS）"
        fi
    else
        log_skip "未配置 MYSQL_PASS，跳过 MySQL 检查"
    fi

    # --- 4. 系统资源配置检查 ---
    print_section "4. 系统资源配置检查"

    log_info "当前服务器规格应为: ${IM_SERVER_SPEC}"
    log_info "MySQL 服务器规格应为: ${MYSQL_SERVER_SPEC}"

    # 系统限制检查
    log_info "检查系统文件描述符限制..."
    local fd_limit=$(ulimit -n 2>/dev/null || echo "unknown")
    log_timing "  文件描述符上限" "${fd_limit}"
    if [ "${fd_limit}" != "unknown" ] && [ "${fd_limit}" -lt 1000000 ]; then
        log_warn "文件描述符上限过低（${fd_limit}），需要 ≥ 1,000,000（建议 ulimit -n 1048576）"
    elif [ "${fd_limit}" != "unknown" ]; then
        log_pass "文件描述符上限满足要求（${fd_limit}）"
    fi

    # --- 5. 关键配置项检查清单 ---
    print_section "5. im-server.conf 关键配置检查"

    local config_checks=(
        "netty.epoll=true (启用 Linux epoll 提升网络性能)"
        "client.request_rate_limit=1000000 (放开限频)"
        "message.max_queue=100000 (防止队列溢出丢消息)"
        "embed.db=0 (使用外部 MySQL)"
        "server.ip 配置为当前服务器 IP"
    )
    for check in "${config_checks[@]}"; do
        log_info "  [ ] ${check}"
    done

    log_info "请手动确认以上配置项均已正确设置"

    # --- 6. 测试准备指引 ---
    print_section "6. 执行长连接压测指引"

    cat << 'GUIDE'

  压测执行步骤:
  
  1. 部署长连接压测工具
  2. 启动模拟客户端，逐步建立连接至 1,000,000 个并发连接
  3. 维持所有连接在线，不发送业务消息
  4. 持续观察 ≥ 30 分钟，记录连接状态与服务资源占用
  5. 逐步关闭连接，清理环境

  监控指标:
  - 连接掉线率（目标: 0%）
  - IM 服务 CPU 利用率（16C32G 下应 ≈ 10 核）
  - MySQL 利用率（应接近 0%）
  - IM 服务内存使用
  - 网络带宽

  判定标准:
  ✅ 30 分钟内无掉线
  ✅ IM 服务 CPU 不超过 12 核
  ✅ MySQL 利用率接近 0%

  参考基准（16C32G 单机）:
  - 保持 30 分钟以上，无掉线
  - IM 服务 CPU ≈ 10 核
  - MySQL 利用率 = 0%

GUIDE

    # --- 6. 数据库校验指引 ---
    print_section "6. 数据库校验指引"
    cat << 'DBCHECK'
  压测完成后，验证 MySQL 连接数为 0:
    SELECT COUNT(*) FROM information_schema.processlist WHERE USER != 'root';
  
  长连接不产生消息，t_messages_X 表应无新增。
DBCHECK

    print_summary
}

# ============================================================
# 主入口
# ============================================================

main() {
    case "${MODE}" in
        check|--check|-c)
            test_long_connection_check
            ;;
        full|--full|-f)
            mkdir -p "${REPORT_DIR}"
            log_info "报告将保存到: ${REPORT_FILE}"
            log_info "完整压测需要部署长连接压测工具"
            test_long_connection_check

            print_section "自动执行长连接测试"
            if [ -f "./stress-tool" ]; then
                log_info "长连接压测需专用的 C1000K 测试工具"
                log_info "stress-tool 不支持模拟百万连接，请使用专用的连接压力工具"
            else
                log_skip "长连接压测工具未安装"
                log_info "手动压测后使用: export LC_DROPOFF=0 LC_CPU=10 LC_MYSQL=0 && bash $0 --mode verify"
            fi
            ;;
        verify)
            print_header "TC-LC-001 长连接基准验证"
            if [ -n "${LC_DROPOFF:-}" ]; then
                assert_eq "${LC_DROPOFF}" "${BENCH_LC_DROPOFF}" "掉线率(0%)"
            else
                log_skip "未提供掉线率数据"
            fi
            if [ -n "${LC_CPU:-}" ]; then
                assert_cpu_under "${LC_CPU}" "${BENCH_LC_CPU_MAX}" "CPU利用率(≤12核)"
            fi
            if [ -n "${LC_MYSQL:-}" ]; then
                assert_eq "${LC_MYSQL}" "${BENCH_LC_MYSQL_CPU}" "MySQL利用率(≈0%)"
            fi
            print_summary
            ;;
        *)
            echo "用法: $0 [--mode check|full|verify]"
            echo ""
            echo "  check   仅检查环境和配置（默认）"
            echo "  full    完整测试（需要部署压测工具）"
            echo "  verify  基准验证模式"
            echo ""
            echo "环境变量:"
            echo "  IM_HOST          IM 服务地址 (默认: localhost)"
            echo "  IM_HTTP_PORT     IM HTTP 端口 (默认: 80)"
            echo "  IM_ADMIN_PORT    IM Admin 端口 (默认: 18080)"
            echo "  MYSQL_HOST       MySQL 地址"
            echo "  MYSQL_USER       MySQL 用户名"
            echo "  MYSQL_PASS       MySQL 密码"
            echo "  LC_CONN_COUNT    目标连接数 (默认: 1000000)"
            echo "  LC_DURATION      持续时间/分钟 (默认: 30)"
            exit 1
            ;;
    esac
}

main
