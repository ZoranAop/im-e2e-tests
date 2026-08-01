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
#   export IM_HOST="192.168.1.100"; bash test_square_api.sh
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# ============================================================
# 测试参数
# ============================================================
USER_ID="${1:-}"

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

    step "发布话题..."
    info "  SDK API: publishSquareTopic(squareId, title, content, medias, callback)"
    info "  参数说明:"
    info "    squareId: 广场 ID"
    info "    title: 话题标题"
    info "    content: 话题内容"
    info "    medias: 媒体附件列表"

    step "拉取话题列表..."
    info "  SDK API: getSquareTopics(squareId, fromIndex, count, callback)"
    info "  分页拉取广场下的所有话题"

    step "获取话题详情..."
    info "  SDK API: getSquareTopicDetail(topicId, callback)"
    info "  获取话题的完整内容、评论、点赞等"

    info "验证点: 话题发布成功，列表正确显示，详情完整"
}

# ============================================================
# TC-SQ-004: 话题互动
# ============================================================

test_square_interaction() {
    test_header "TC-SQ-004: 话题互动"

    step "评论话题..."
    info "  SDK API: commentSquareTopic(topicId, content, replyTo, replyCommentId, callback)"
    info "  对话题发表评论或回复评论"

    step "点赞话题..."
    info "  SDK API: likeSquareTopic(topicId, callback)"
    info "  对话题点赞"

    step "取消点赞..."
    info "  SDK API: unlikeSquareTopic(topicId, callback)"

    step "删除评论..."
    info "  SDK API: deleteSquareComment(commentId, callback)"

    info "验证点: 评论/点赞成功，话题详情中可见"
    info "验证点: 取消点赞和删除评论生效"
}

# ============================================================
# TC-SQ-005: 话题删除与管理
# ============================================================

test_square_manage() {
    test_header "TC-SQ-005: 话题管理"

    step "删除话题..."
    info "  SDK API: deleteSquareTopic(topicId, callback)"
    info "  删除自己发布的话题"

    step "举报话题..."
    info "  SDK API: reportSquareTopic(topicId, reason, callback)"
    info "  举报违规话题"

    step "搜索话题..."
    info "  SDK API: searchSquareTopics(squareId, keyword, fromIndex, count, callback)"
    info "  在广场内搜索话题"

    info "验证点: 删除后话题不可见，搜索功能正常"
}

# ============================================================
# TC-SQ-006: 广场成员管理
# ============================================================

test_square_member() {
    test_header "TC-SQ-006: 广场成员管理"

    step "加入广场..."
    info "  SDK API: joinSquare(squareId, callback)"

    step "退出广场..."
    info "  SDK API: quitSquare(squareId, callback)"

    step "获取广场成员列表..."
    info "  SDK API: getSquareMembers(squareId, fromIndex, count, callback)"

    info "验证点: 加入/退出操作有效，成员列表正确"
}

# ============================================================
# TC-SQ-007: 广场消息通知
# ============================================================

test_square_notification() {
    test_header "TC-SQ-007: 广场消息通知"

    step "注册广场消息监听..."
    info "  SDK API: setSquareMessageReceiveListener(listener)"
    info "  监听广场相关消息通知"

    step "通知类型说明..."
    info "  - 话题新增通知"
    info "  - 评论/回复通知"
    info "  - 点赞通知"
    info "  - 话题删除通知"
    info "  - @提醒通知"

    info "验证点: 各类通知通过 IM 消息正确送达"
}

# ============================================================
# TC-SQ-008: 广场功能配置检查
# ============================================================

test_square_config() {
    test_header "TC-SQ-008: 广场功能配置检查"

    step "检查广场配置项..."
    info "  im-server.conf 相关配置:"

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

    cat << 'PERF'

  广场功能性能注意事项:
  
  1. 话题发布性能:
     - 发布话题类似于单聊消息发送，包含内容落库和分发
     - 话题分发到广场所有成员，成员数越大消耗越高
     - 性能模型可参考群聊消息分发（单核分发 8,750 条/秒/核）

  2. 话题拉取性能:
     - 列表拉取类似朋友圈拉取，支持分页
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

    info "以上性能模型参考群聊/朋友圈测试结果，建议根据实际场景独立压测"
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
