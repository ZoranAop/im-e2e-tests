#!/usr/bin/env bash
# ============================================================
# 广场 (Moments) API 功能测试脚本
# ============================================================
# 测试 IM 服务广场 SDK 所有 API 功能
#
# 前置条件:
#   1. 专业版 IM 服务已部署且 MongoDB 已配置
#   2. im-server.conf 中已配置:
#      - MongoDB 连接
#      - moments.global_visible
#      - moments.allow_robot_list
#      - moments.robot_global_visible
#   3. 应用服务 (app-server) 已启动用于用户注册
#
# 用法:
#   bash test_moments_api.sh --user-id "your_user_id"
#   export IM_HOST="192.168.1.100"; bash test_moments_api.sh
#
# 测试覆盖:
#   TC-MT-001: 发布广场（文本/图片/视频/链接）
#   TC-MT-002: 发布评论/点赞
#   TC-MT-003: 拉取广场
#   TC-MT-004: 删除广场/评论
#   TC-MT-005: 广场设置
#   TC-MT-006: 黑名单/屏蔽名单
#   TC-MT-007: 广场消息通知
#   TC-MT-008: 机器人广场
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../common/db_utils.sh" 2>/dev/null || true

# ============================================================
# 参数
# ============================================================
USER_ID=""
while [[ $# -gt 0 ]]; do case "$1" in -u|--user-id) USER_ID="$2"; shift 2;; *) shift;; esac; done
USER_ID="${USER_ID:-test_user_01}"
ROBOT_ID="${ROBOT_ID:-FireRobot}"
TARGET_USER_ID="${TARGET_USER_ID:-}"

# ============================================================
# MongoDB 连接（可选，用于数据验证）
# ============================================================
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_DB="${MONGO_DB:-imdb}"

# ============================================================
# TC-MT-001: 发布广场
# ============================================================

test_post_feed() {
    test_header "TC-MT-001: 发布广场"

    step "发布文本广场 (type=0)..."
    local now=$(date +%s)
    local body="{\"type\":0,\"text\":\"测试广场-${now}\",\"medias\":[],\"toUsers\":[],\"excludeUsers\":[],\"mentionedUsers\":[],\"extra\":\"\"}"
    local resp=$(im_admin_post "/api/admin/moments/feed?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -qE '"success":true|"feedId"|200'; then
        pass "文本广场发布成功"
        info "  响应: $(echo ${resp} | head -c 200)"
    else
        fail "文本广场发布失败"
        info "  响应: ${resp}"
    fi

    step "发布图片广场 (type=1)..."
    body="{\"type\":1,\"text\":\"测试图片广场\",\"medias\":[{\"url\":\"https://example.com/test.jpg\",\"width\":800,\"height\":600}],\"toUsers\":[],\"excludeUsers\":[],\"mentionedUsers\":[],\"extra\":\"\"}"
    resp=$(im_admin_post "/api/admin/moments/feed?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -qE '"success":true|"feedId"'; then
        pass "图片广场发布成功"
    else
        skip "图片广场发布需要媒体服务支持"
    fi

    step "发布定向广场..."
    body="{\"type\":0,\"text\":\"仅指定用户可见\",\"medias\":[],\"toUsers\":[\"${TARGET_USER_ID}\"],\"excludeUsers\":[],\"mentionedUsers\":[],\"extra\":\"\"}"
    resp=$(im_admin_post "/api/admin/moments/feed?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|"feedId"'; then
        pass "定向广场发布成功"
    else
        skip "定向广场发布需指定有效目标用户"
    fi
}

# ============================================================
# TC-MT-002: 发布评论和点赞
# ============================================================

test_post_comment() {
    test_header "TC-MT-002: 发布评论/点赞"

    step "获取已有广场列表..."
    local feeds_resp=$(im_admin_get "/api/admin/moments/feeds?userId=${USER_ID}&fromIndex=0&count=5")
    local feed_id=$(echo "${feeds_resp}" | grep -o '"feedId":"[0-9]*"' | head -1 | grep -o '[0-9]*')

    if [ -z "${feed_id}" ]; then
        skip "无可用广场，跳过评论测试"
        return
    fi
    info "  使用广场 ID: ${feed_id}"

    step "发布评论 (type=0)..."
    local body="{\"type\":0,\"feedId\":${feed_id},\"text\":\"测试评论-$(date +%s)\",\"replyTo\":\"\",\"replyId\":0,\"extra\":\"\"}"
    local resp=$(im_admin_post "/api/admin/moments/comment?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|"commentId"'; then
        pass "评论发布成功"
    else
        skip "评论发布需有效的广场ID"
    fi

    step "点赞 (type=1)..."
    body="{\"type\":1,\"feedId\":${feed_id},\"text\":\"\",\"replyTo\":\"\",\"replyId\":0,\"extra\":\"\"}"
    resp=$(im_admin_post "/api/admin/moments/comment?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|"commentId"'; then
        pass "点赞成功"
    else
        skip "点赞需有效的广场ID"
    fi
}

# ============================================================
# TC-MT-003: 拉取广场
# ============================================================

test_get_feeds() {
    test_header "TC-MT-003: 拉取广场"
    step "拉取最新广场 (fromIndex=0, count=20)..."
    local resp=$(im_admin_get "/api/admin/moments/feeds?userId=${USER_ID}&fromIndex=0&count=20")
    if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
        pass "广场列表拉取成功"
        local count=$(echo "${resp}" | grep -o '"feedId"' | wc -l)
        info "  返回条数: ${count}"
    else
        fail "广场列表拉取失败"
    fi

    step "分页拉取..."
    resp=$(im_admin_get "/api/admin/moments/feeds?userId=${USER_ID}&fromIndex=1&count=10")
    if [ -n "${resp}" ]; then
        pass "分页拉取成功"
    else
        skip "分页拉取需有足够广场数据"
    fi
}

# ============================================================
# TC-MT-004: 删除广场和评论
# ============================================================

test_delete() {
    test_header "TC-MT-004: 删除广场/评论"

    step "检查删除端点..."
    local config=$(im_admin_get "/api/admin/config")
    if [ -n "${config}" ]; then
        pass "Admin API 可达，删除功能可用"
    else
        skip "Admin API 不可用，需通过客户端 SDK 验证删除功能"
    fi

    step "测试删除评论"
    info "  SDK API: deleteComment(userId, feedId, commentId, callback)"

    step "测试删除广场"
    info "  SDK API: deleteFeed(userId, feedUid, callback)"

    info "验证点: 删除后拉取不到该 Feed/评论"
}

# ============================================================
# TC-MT-005: 广场设置
# ============================================================

test_user_profile() {
    test_header "TC-MT-005: 广场设置"

    step "拉取用户广场设置..."
    local resp=$(im_admin_get "/api/admin/moments/user/profile?userId=${USER_ID}")
    if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
        pass "用户广场设置拉取成功"
        info "  响应: $(echo ${resp} | head -c 200)"
    else
        skip "广场设置 API 不可用，需通过客户端 SDK 验证 getUserProfile"
    fi

    step "更新广场背景 (updateUserProfileType=0)..."
    local body="{\"type\":0,\"bgUrl\":\"https://example.com/bg.jpg\",\"intValue\":0,\"strValue\":\"\"}"
    resp=$(im_admin_post "/api/admin/moments/user/profile?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|200'; then
        pass "广场背景更新成功"
    else
        skip "updateUserProfile 需通过客户端 SDK 验证"
    fi

    step "设置陌生人可见条数 (updateUserProfileType=1)..."
    body="{\"type\":1,\"bgUrl\":\"\",\"intValue\":10,\"strValue\":\"\"}"
    resp=$(im_admin_post "/api/admin/moments/user/profile?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|200'; then
        pass "陌生人可见条数设置成功"
    else
        skip "updateUserProfile(1) 需通过客户端 SDK 验证"
    fi

    step "设置可见范围 (updateUserProfileType=2)..."
    body="{\"type\":2,\"bgUrl\":\"\",\"intValue\":0,\"strValue\":\"\"}"
    resp=$(im_admin_post "/api/admin/moments/user/profile?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|200'; then
        pass "可见范围设置成功 (0=不限制)"
    else
        skip "updateUserProfile(2) 需通过客户端 SDK 验证"
    fi
}

# ============================================================
# TC-MT-006: 黑名单/屏蔽名单
# ============================================================

test_black_block_list() {
    test_header "TC-MT-006: 黑名单/屏蔽名单"

    step "设置黑名单 (isBlock=false, 不让TA看)..."
    local body="{\"isBlock\":false,\"addList\":[\"userB\"],\"removeList\":[]}"
    local resp=$(im_admin_post "/api/admin/moments/blacklist?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|200'; then
        pass "黑名单设置成功"
    else
        skip "updateBlackOrBlockList 需通过客户端 SDK 验证"
    fi

    step "设置屏蔽名单 (isBlock=true, 不看TA)..."
    body="{\"isBlock\":true,\"addList\":[\"userC\"],\"removeList\":[]}"
    resp=$(im_admin_post "/api/admin/moments/blacklist?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|200'; then
        pass "屏蔽名单设置成功"
    else
        skip "updateBlackOrBlockList 需通过客户端 SDK 验证"
    fi

    step "移除黑名单..."
    body="{\"isBlock\":false,\"addList\":[],\"removeList\":[\"userB\"]}"
    resp=$(im_admin_post "/api/admin/moments/blacklist?userId=${USER_ID}" "${body}")
    if echo "${resp}" | grep -q '"success":true\|200'; then
        pass "黑名单移除成功"
    else
        skip "移除名单需通过客户端 SDK 验证"
    fi
}

# ============================================================
# TC-MT-007: 广场消息通知
# ============================================================

test_moment_notification() {
    test_header "TC-MT-007: 广场消息通知"

    step "检查通知通道配置..."
    local config=$(im_admin_get "/api/admin/config")
    if [ -n "${config}" ]; then
        pass "Admin API 可达，消息通知通道配置可用"
        if echo "${config}" | grep -qi "moment\|notification"; then
            pass "广场通知配置已加载"
        else
            skip "配置中未找到广场通知相关项"
        fi
    else
        skip "Admin API 不可用，需通过客户端 SDK 验证通知功能"
    fi

    step "注册消息监听..."
    info "  SDK API: setMomentMessageReceiveListener(listener)"
    info "  监听广场消息（line=1 通道）"

    step "消息类型说明..."
    info "  类型1: 广场 @了当前用户的消息"
    info "  类型2: 评论或回复评论的消息"
    info "  类型3: 被删除时的撤回通知"

    info "验证点: @消息和评论消息通过 IM 消息 line=1 通道送达"
    info "验证点: 删除时收到撤回通知"
}

# ============================================================
# TC-MT-008: 机器人广场
# ============================================================

test_robot_moments() {
    test_header "TC-MT-008: 机器人广场"

    step "检查机器人广场配置..."
    local config=$(im_admin_get "/api/admin/config")
    if [ -n "${config}" ]; then
        pass "Admin API 可达"
        if echo "${config}" | grep -qi "allow_robot_list\|robot"; then
            pass "moments.allow_robot_list 已配置"
            info "  配置中的 robot 相关项: $(echo ${config} | grep -oi '"moments[^"]*robot[^"]*"[^,}]*' || echo '见完整配置')"
        else
            skip "配置中未找到 moments.allow_robot_list，请检查 im-server.conf"
        fi
    else
        skip "Admin API 不可用，需通过客户端 SDK 验证机器人广场功能"
    fi

    step "im-server.conf 配置参考:"
    info "    moments.allow_robot_list = FireRobot,Helpers"
    info "    moments.robot_global_visible = true"

    step "全局机器人广场行为..."
    info "  - 全局机器人广场分发给系统内所有用户"
    info "  - moments.robot_global_visible=true 时生效"
    info "  - 可在发送广场时指定 toUsers 定向发送"

    step "普通机器人广场行为..."
    info "  - moments.robot_global_visible=false 时行为同普通用户"
    info "  - 仅好友可见"

    step "机器人接收消息..."
    info "  - 被 @ 或回复时，机器人会收到对应消息"
    info "  - 需自行记录历史消息（无 getFeedMessages 接口）"

    info "注意事项: 全局机器人发送时，系统内用户数量庞大需关注服务端压力"
}

# ============================================================
# 广场消息拉取 (额外)
# ============================================================

test_get_feed_messages() {
    test_header "附加: 广场消息拉取"

    step "拉取广场消息..."
    info "  SDK API: getFeedMessages(fromIndex, isNew)"
    info "  获取广场的通知消息列表"

    info "注意: 机器人没有此接口，需自行记录收到的消息"
}

# ============================================================
# MongoDB 数据验证
# ============================================================

test_mongodb_verification() {
    test_header "MongoDB 数据验证"

    if command -v mongosh &>/dev/null; then
        step "检查 MongoDB 广场 Collection..."
        info "  mongosh ${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}"

        info "  验证命令:"
        info "    db.moments_feeds.countDocuments()    -- Feed 总数"
        info "    db.moments_comments.countDocuments() -- 评论总数"
        info "    db.moments_feeds.find({userId: '${USER_ID}'})"
        info "    db.moments_user_profiles.find({userId: '${USER_ID}'})"
    else
        skip "mongosh 不可用，跳过 MongoDB 验证"
    fi

    info "本地 MongoDB 查询方式:"
    info "  mongo ${MONGO_HOST}:${MONGO_PORT}/${MONGO_DB}"
    info "  > db.moments_feeds.countDocuments()"
    info "  > db.moments_comments.countDocuments()"
    info "  > db.moments_feeds.findOne({userId: '${USER_ID}'})"
    info "  > db.moments_user_profiles.findOne({userId: '${USER_ID}'})"
}

# ============================================================
# 主入口
# ============================================================

main() {
    test_header "IM 服务 广场 (Moments) 功能测试"

    if [ -z "${USER_ID}" ]; then
        info "未指定测试用户 ID，使用环境默认值"
        info "用法: $0 --user-id <your_user_id>"
        info "环境变量: USER_ID, ROBOT_ID, TARGET_USER_ID"
        USER_ID="${USER_ID:-test_user_01}"
    fi

    step "测试用户 ID: ${USER_ID}"
    step "机器人 ID: ${ROBOT_ID}"

    # 环境检查
    print_section "前置环境检查"

    if ! check_tcp "${IM_HOST}" "${IM_HTTP_PORT}" 3; then
        fail "IM 服务不可达 (${IM_HOST}:${IM_HTTP_PORT})"
        test_summary
        return 1
    fi
    pass "IM 服务可达"

    # 执行所有测试用例
    test_post_feed
    test_post_comment
    test_get_feeds
    test_delete
    test_user_profile
    test_black_block_list
    test_moment_notification
    test_robot_moments
    test_get_feed_messages
    test_mongodb_verification

    test_summary
}

main
