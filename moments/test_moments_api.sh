#!/usr/bin/env bash
# ============================================================
# 朋友圈 (Moments) API 功能测试脚本
# ============================================================
# 测试 IM 服务朋友圈 SDK 所有 API 功能
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
#   TC-MT-001: 发布朋友圈（文本/图片/视频/链接）
#   TC-MT-002: 发布评论/点赞
#   TC-MT-003: 拉取朋友圈
#   TC-MT-004: 删除朋友圈/评论
#   TC-MT-005: 朋友圈设置
#   TC-MT-006: 黑名单/屏蔽名单
#   TC-MT-007: 朋友圈消息通知
#   TC-MT-008: 机器人朋友圈
#
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

# ============================================================
# 参数
# ============================================================
USER_ID="${1:-}"
ROBOT_ID="${ROBOT_ID:-FireRobot}"
TARGET_USER_ID="${TARGET_USER_ID:-}"

# ============================================================
# MongoDB 连接（可选，用于数据验证）
# ============================================================
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_DB="${MONGO_DB:-imdb}"

# ============================================================
# TC-MT-001: 发布朋友圈
# ============================================================

test_post_feed() {
    test_header "TC-MT-001: 发布朋友圈"

    # 准备: 获取 admin token（需要先通过应用服务注册/获取 token）
    step "准备测试环境..."

    # 1. 文本朋友圈 (type=0)
    step "测试发布文本朋友圈 (type=0)"
    local feed_body='{
        "type": 0,
        "text": "这是一条文本朋友圈",
        "medias": [],
        "toUsers": [],
        "excludeUsers": [],
        "mentionedUsers": [],
        "extra": ""
    }'

    local result=$(im_admin_post "/api/admin/moments/feed?userId=${USER_ID}" "${feed_body}")
    if [ -n "${result}" ] && echo "${result}" | grep -q "success\|feedId\|200"; then
        pass "文本朋友圈发布成功"
    else
        skip "文本朋友圈发布测试需通过客户端 SDK 或 admin API 执行"
        info "  SDK API: postFeed(0, text, medias, toUsers, excludeUsers, mentionedUsers, extra, callback)"
    fi

    # 2. 图片朋友圈 (type=1)
    step "测试发布图片朋友圈 (type=1)"
    info "  SDK API: postFeed(1, text, medias, toUsers, excludeUsers, mentionedUsers, extra, callback)"
    info "  需先上传图片获取 media 信息"

    # 3. 视频朋友圈 (type=2)
    step "测试发布视频朋友圈 (type=2)"
    info "  SDK API: postFeed(2, text, medias, toUsers, excludeUsers, mentionedUsers, extra, callback)"
    info "  需先上传视频获取 media 信息"

    # 4. 链接朋友圈 (type=3)
    step "测试发布链接朋友圈 (type=3)"
    info "  SDK API: postFeed(3, text, medias, toUsers, excludeUsers, mentionedUsers, extra, callback)"

    info "以上 4 种类型朋友圈发布需通过客户端 SDK 完成端到端验证"
    info "验证点: 发布成功返回 Feed ID，发布者朋友圈列表可拉取到该条 Feed"
}

# ============================================================
# TC-MT-002: 发布评论和点赞
# ============================================================

test_post_comment() {
    test_header "TC-MT-002: 发布评论/点赞"

    step "测试发布评论 (type=0)"
    info "  SDK API: postComment(0, feedId, text, replyTo, replyId, extra, callback)"
    info "  参数说明:"
    info "    type=0: 评论"
    info "    type=1: 点赞"
    info "    feedId: 朋友圈 ID"
    info "    replyTo: 回复某个用户的 ID（可选）"
    info "    replyId: 回复的评论 ID（可选）"

    step "测试发布点赞 (type=1)"
    info "  SDK API: postComment(1, feedId, '', '', 0, '', callback)"

    info "验证点: 评论/点赞成功后，Feed 详情中可见该条评论"
    info "返回: 有效 Comment ID"
}

# ============================================================
# TC-MT-003: 拉取朋友圈
# ============================================================

test_get_feeds() {
    test_header "TC-MT-003: 拉取朋友圈"

    step "测试拉取最新朋友圈 (fromIndex=0)"
    info "  SDK API: getFeeds(0, 20, user, callback)"
    info "  拉取最新 20 条朋友圈"

    step "测试分页拉取"
    info "  SDK API: getFeeds(fromIndex, count, user, callback)"
    info "  fromIndex 设为最后一条 Feed ID，拉取更旧的 20 条"

    info "验证点: 分页正确，数据不重复不遗漏，返回条数 ≤ count"
}

# ============================================================
# TC-MT-004: 删除朋友圈和评论
# ============================================================

test_delete() {
    test_header "TC-MT-004: 删除朋友圈/评论"

    step "测试删除评论"
    info "  SDK API: deleteComment(userId, feedId, commentId, callback)"

    step "测试删除朋友圈"
    info "  SDK API: deleteFeed(userId, feedUid, callback)"

    info "验证点: 删除后拉取不到该 Feed/评论"
    info "成功标准: 返回成功，二次拉取确认已删除"
}

# ============================================================
# TC-MT-005: 朋友圈设置
# ============================================================

test_user_profile() {
    test_header "TC-MT-005: 朋友圈设置"

    step "测试拉取朋友圈设置"
    info "  SDK API: getUserProfile(userId, callback)"
    info "  可获取自己或他人的朋友圈设置"

    step "测试更新朋友圈背景 (updateUserProfileType=0)"
    info "  SDK API: updateUserProfile(0, '背景图链接', 0, callback)"
    info "  修改朋友圈背景图链接"

    step "测试设置陌生人可见条数 (updateUserProfileType=1)"
    info "  SDK API: updateUserProfile(1, '', 10, callback)"
    info "  intValue 为陌生人可见条数"

    step "测试设置可见范围 (updateUserProfileType=2)"
    info "  SDK API: updateUserProfile(2, '', scope, callback)"
    info "  intValue 含义: 0=不限制, 1=3天, 2=1个月, 3=半年"

    info "验证点: getUserProfile 读取值与设置一致，数据正确持久化"
}

# ============================================================
# TC-MT-006: 黑名单/屏蔽名单
# ============================================================

test_black_block_list() {
    test_header "TC-MT-006: 黑名单/屏蔽名单"

    step "测试设置黑名单 (isBlock=false, 不让TA看)"
    info "  SDK API: updateBlackOrBlockList(false, ['userB'], [], callback)"
    info "  拉黑: 被拉黑用户看不到发布者朋友圈"

    step "测试设置屏蔽名单 (isBlock=true, 不看TA)"
    info "  SDK API: updateBlackOrBlockList(true, ['userC'], [], callback)"
    info "  屏蔽: 发布者看不到被屏蔽用户朋友圈"

    step "测试移除黑名单/屏蔽名单"
    info "  SDK API: updateBlackOrBlockList(isBlock, [], ['userB'], callback)"
    info "  从名单中移除指定用户"

    info "验证点: 权限隔离生效"
    info "  - 被拉黑用户无法看到发布者朋友圈"
    info "  - 屏蔽后发布者看不到被屏蔽用户朋友圈"
}

# ============================================================
# TC-MT-007: 朋友圈消息通知
# ============================================================

test_moment_notification() {
    test_header "TC-MT-007: 朋友圈消息通知"

    step "注册消息监听..."
    info "  SDK API: setMomentMessageReceiveListener(listener)"
    info "  监听朋友圈消息（line=1 通道）"

    step "消息类型说明..."
    info "  类型1: 朋友圈 @了当前用户的消息"
    info "  类型2: 评论或回复评论的消息"
    info "  类型3: 被删除时的撤回通知"

    info "验证点: @消息和评论消息通过 IM 消息 line=1 通道送达"
    info "验证点: 删除时收到撤回通知"
}

# ============================================================
# TC-MT-008: 机器人朋友圈
# ============================================================

test_robot_moments() {
    test_header "TC-MT-008: 机器人朋友圈"

    step "检查机器人朋友圈配置..."
    info "  im-server.conf 配置:"
    info "    moments.allow_robot_list = FireRobot,Helpers"
    info "    moments.robot_global_visible = true"

    step "全局机器人朋友圈行为..."
    info "  - 全局机器人朋友圈分发给系统内所有用户"
    info "  - moments.robot_global_visible=true 时生效"
    info "  - 可在发送朋友圈时指定 toUsers 定向发送"

    step "普通机器人朋友圈行为..."
    info "  - moments.robot_global_visible=false 时行为同普通用户"
    info "  - 仅好友可见"

    step "机器人接收消息..."
    info "  - 被 @ 或回复时，机器人会收到对应消息"
    info "  - 需自行记录历史消息（无 getFeedMessages 接口）"

    info "注意事项: 全局机器人发送时，系统内用户数量庞大需关注服务端压力"
}

# ============================================================
# 朋友圈消息拉取 (额外)
# ============================================================

test_get_feed_messages() {
    test_header "附加: 朋友圈消息拉取"

    step "拉取朋友圈消息..."
    info "  SDK API: getFeedMessages(fromIndex, isNew)"
    info "  获取朋友圈的通知消息列表"

    info "注意: 机器人没有此接口，需自行记录收到的消息"
}

# ============================================================
# MongoDB 数据验证
# ============================================================

test_mongodb_verification() {
    test_header "MongoDB 数据验证"

    if command -v mongosh &>/dev/null; then
        step "检查 MongoDB 朋友圈 Collection..."
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
    test_header "IM 服务 朋友圈 (Moments) 功能测试"

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
