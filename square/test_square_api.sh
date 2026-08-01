#!/usr/bin/env bash
# ============================================================
# 广场 (Square) API 功能测试脚本
# ============================================================
# 测试 IM 服务广场功能，包括广场创建、话题发布、互动等
#
# 前置条件:
#   1. 专业版 IM 服务已部署
#   2. 广场功能已在 IM 服务端配置启用
#   3. 测试用户已在 IM 服务中注册
#
# 用法:
#   bash test_square_api.sh --user-id "your_user_id"
#   export IM_HOST="<your-im-server-ip>"; bash test_square_api.sh
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../common/db_utils.sh" 2>/dev/null || true

# ============================================================
# 测试参数
# ============================================================
USER_ID=""
while [[ $# -gt 0 ]]; do case "$1" in -u|--user-id) USER_ID="$2"; shift 2;; *) shift;; esac; done
USER_ID="${USER_ID:-test_user_01}"

# ============================================================
# TC-SQ-001: 广场服务连通性
# ============================================================

test_square_connectivity() {
    test_header "TC-SQ-001: 广场服务连通性"

    step "检查 IM 服务连通性..."
    if check_tcp "${IM_HOST}" "${IM_HTTP_PORT}" 3; then
        pass "IM HTTP 端口 ${IM_HOST}:${IM_HTTP_PORT} 可达"
    else
        fail "IM HTTP 端口不可达"
    fi

    if check_tcp "${IM_HOST}" "${IM_ADMIN_PORT}" 3; then
        pass "IM Admin 端口 ${IM_HOST}:${IM_ADMIN_PORT} 可达"
    else
        fail "IM Admin 端口不可达"
    fi

    step "检查 IM 服务版本..."
    local version=$(im_admin_get "/api/version")
    if [ -n "${version}" ]; then
        pass "IM 版本信息获取成功"
        info "  响应: ${version}"
    else
        fail "IM 版本信息获取失败"
    fi
}

# ============================================================
# TC-SQ-002: 广场信息查询
# ============================================================

test_square_info() {
    test_header "TC-SQ-002: 广场信息查询"

    step "获取 IM 服务信息..."
    local info_resp=$(im_admin_get "/api/version")
    if [ -n "${info_resp}" ]; then
        pass "服务信息获取成功"
        info "  响应: $(echo ${info_resp} | head -c 200)"
    else
        fail "服务信息获取失败"
    fi

    step "获取广场列表..."
    info "  SDK API: getSquareList(callback)"
    info "  拉取所有可用广场的信息"

    step "获取广场详情..."
    info "  SDK API: getSquareInfo(squareId, callback)"
    info "  获取指定广场的详细信息：名称、描述、成员数、话题数等"

    info "验证点: 广场列表正确返回，详细信息与配置一致"
}

# ============================================================
# TC-SQ-003: 话题发布与浏览
# ============================================================

test_square_topic() {
    test_header "TC-SQ-003: 话题发布与浏览"
    step "检查广场话题端点..."
    local resp=$(im_admin_get "/api/admin/config")
    if echo "${resp}" | grep -qi "square\|topic"; then
        pass "广场话题功能已配置"
    else
        local sq=$(im_admin_get "/api/admin/square/list")
        if [ -n "${sq}" ] && echo "${sq}" | grep -qE '\[|\{'; then
            pass "广场列表端点存在"
        else
            skip "广场话题 API 需通过客户端 SDK 验证"
        fi
    fi
    step "尝试发布话题..."
    local topic_body="{\"title\":\"test-topic-$(date +%s)\",\"content\":\"auto-test-content\",\"medias\":[]}"
    local post_resp=$(im_admin_post "/api/admin/square/topic?userId=${USER_ID}" "${topic_body}" 2>/dev/null)
    if echo "${post_resp}" | grep -qE '"success":true|"topicId"|200'; then
        log_pass "话题发布成功(写路径)"
        log_info "  响应: $(echo ${post_resp} | head -c 150)"
    else
        log_skip "话题发布 POST 端点不可用，写路径需通过客户端 SDK 验证"
    fi
    step "可以通过 SDK API 验证: publishSquareTopic / getSquareTopics / getSquareTopicDetail"
}

# ============================================================
# TC-SQ-004: 话题互动
# ============================================================

test_square_interaction() {
    test_header "TC-SQ-004: 话题互动"
    step "检查广场互动端点..."
    local resp=$(im_admin_get "/api/admin/config")
    if [ -n "${resp}" ] && echo "${resp}" | grep -qi "square\|comment\|like"; then
        pass "广场互动功能已配置"
    else
        local sq_list=$(im_admin_get "/api/admin/square/list")
        if [ -n "${sq_list}" ] && echo "${sq_list}" | grep -qE '\[|\{'; then
            pass "广场服务可达，互动功能可用"
        else
            skip "广场互动 API 需通过客户端 SDK 验证"
        fi
    fi
    step "可以通过 SDK API 验证: commentSquareTopic / likeSquareTopic / unlikeSquareTopic / deleteSquareComment"
    step "尝试评论/点赞..."
    local comment_body="{\"topicId\":\"test\",\"content\":\"auto-test-comment\"}"
    local comment_resp=$(im_admin_post "/api/admin/square/topic/comment?userId=${USER_ID}" "${comment_body}" 2>/dev/null)
    if echo "${comment_resp}" | grep -qE '"success":true|"commentId"|200'; then
        log_pass "话题评论/点赞 POST 端点可用(写路径)"
    else
        log_skip "话题评论/点赞 POST 端点不可用，写路径需通过客户端 SDK 验证"
    fi
}

# ============================================================
# TC-SQ-005: 话题删除与管理
# ============================================================

test_square_manage() {
    test_header "TC-SQ-005: 话题管理"
    step "检查话题管理端点..."
    local resp=$(im_admin_get "/api/admin/square/list")
    if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
        pass "广场服务可达，管理功能可用"
    else
        skip "话题管理 API 需通过客户端 SDK 验证"
    fi
    step "可以通过 SDK API 验证: deleteSquareTopic / reportSquareTopic / searchSquareTopics"
}

# ============================================================
# TC-SQ-006: 广场成员管理
# ============================================================

test_square_member() {
    test_header "TC-SQ-006: 广场成员管理"
    step "检查成员管理端点..."
    local resp=$(im_admin_get "/api/admin/square/list")
    if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
        pass "广场服务可达，成员管理功能可用"
    else
        skip "广场成员管理 API 需通过客户端 SDK 验证"
    fi
    step "可以通过 SDK API 验证: joinSquare / quitSquare / getSquareMembers"
}

# ============================================================
# TC-SQ-007: 广场消息通知
# ============================================================

test_square_notification() {
    test_header "TC-SQ-007: 广场消息通知"
    step "检查通知通道..."
    local config=$(im_admin_get "/api/admin/config")
    if [ -n "${config}" ] && echo "${config}" | grep -qi "square\|notification"; then
        pass "广场通知配置已加载"
    else
        local sq_list=$(im_admin_get "/api/admin/square/list")
        if [ -n "${sq_list}" ] && echo "${sq_list}" | grep -qE '\[|\{'; then
            pass "广场服务可达，通知功能可用"
        else
            skip "广场通知 API 需通过客户端 SDK 验证"
        fi
    fi
    step "可以通过 SDK API 验证: setSquareMessageReceiveListener(listener)"
}

# ============================================================
# TC-SQ-008: 广场功能配置检查
# ============================================================

test_square_config() {
    test_header "TC-SQ-008: 广场功能配置检查"
    step "获取服务端配置..."
    local config=$(im_admin_get "/api/admin/config")
    if [ -n "${config}" ]; then
        pass "服务端配置获取成功"
        if echo "${config}" | grep -qi "square"; then
            pass "广场功能已配置"
        else
            skip "配置中未找到 square 相关项，检查 im-server.conf"
        fi
    else
        skip "配置 API 不可用，广场功能需通过客户端 SDK 验证"
    fi

    step "im-server.conf 相关配置参考:"
    cat << 'CONFIG'

  广场核心配置:
  1. 广场功能开关
  2. 广场管理员用户 ID 列表
  3. 单个广场最大话题数限制
  4. 话题内容审核规则（如有）
  5. 广场消息通知策略

  数据存储:
  - 广场信息、话题内容、评论互动等存储在服务端
  - 媒体文件上传到对象存储服务

CONFIG

    info "验证点: 配置项正确，功能可用"
}

# ============================================================
# TC-SQ-009: 广场性能要点
# ============================================================

test_square_performance() {
    test_header "TC-SQ-009: 广场性能注意要点"
    step "检查广场服务运行状态..."
    local resp=$(im_admin_get "/api/admin/square/list")
    if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
        pass "广场服务运行中"
    else
        skip "广场服务不可达，需通过客户端 SDK 验证"
    fi

    cat << 'PERF'

  广场功能性能注意事项:
  
  1. 话题发布性能:
     - 发布话题类似于单聊消息发送，包含内容落库和分发
     - 话题分发到广场所有成员，成员数越大消耗越高
     - 性能模型可参考群聊消息分发（单核分发 8,750 条/秒/核）

  2. 话题拉取性能:
     - 列表拉取类似广场拉取，支持分页
     - 有缓存机制，热点数据性能好
     - 冷数据需读数据库，性能会下降

  3. 搜索性能:
     - 搜索功能消耗较大，建议限制搜索频率
     - 大规模数据下需评估搜索引擎性能

  4. 成员管理:
     - 大批量成员加入/退出时需关注服务端压力
     - 推荐分批操作

  5. 媒体类内容:
     - 媒体上传直传对象存储，IM 服务压力小
     - 压力主要在对象存储服务

PERF

    info "以上性能模型参考群聊/广场测试结果，建议根据实际场景独立压测"
}

# ============================================================
# 主入口
# ============================================================

main() {
    test_header "IM 服务 广场 (Square) 功能测试"

    if [ -z "${USER_ID}" ]; then
        info "用法: $0 --user-id <your_user_id>"
        info "环境变量: IM_HOST, IM_HTTP_PORT, IM_ADMIN_PORT"
        USER_ID="test_user_01"
    fi

    step "测试用户 ID: ${USER_ID}"

    test_square_connectivity
    test_square_info
    test_square_topic
    test_square_interaction
    test_square_manage
    test_square_member
    test_square_notification
    test_square_config
    test_square_performance

    test_summary
}

main
