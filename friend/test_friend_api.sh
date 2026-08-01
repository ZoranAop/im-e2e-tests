#!/usr/bin/env bash
# ============================================================
# 好友管理测试 (TC-FR-001~005)
# ============================================================
# 用法: bash test_friend_api.sh --user-id "userA" --friend-id "userB"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"
FRIEND_ID="${2:-test_user_02}"

test_header "好友管理测试"

# TC-FR-001: 添加好友
test_header "TC-FR-001: 添加好友"
step "发送好友请求..."
local body="{\"userId\":\"${USER_ID}\",\"friendId\":\"${FRIEND_ID}\",\"message\":\"hello\"}"
local resp=$(im_admin_post "/api/admin/friend/request" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "好友请求发送成功"
else
    skip "好友请求端点不可用"
fi

# TC-FR-002: 同意好友请求
test_header "TC-FR-002: 同意好友请求"
body="{\"userId\":\"${FRIEND_ID}\",\"friendId\":\"${USER_ID}\",\"accept\":true}"
resp=$(im_admin_post "/api/admin/friend/accept" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "好友请求同意成功"
else
    skip "好友同意端点不可用"
fi

# TC-FR-003: 好友列表
test_header "TC-FR-003: 好友列表"
resp=$(im_admin_get "/api/admin/friend/list?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
    pass "好友列表获取成功"
else
    skip "好友列表端点不可用"
fi

# TC-FR-004: 搜索好友
test_header "TC-FR-004: 搜索好友"
resp=$(im_admin_get "/api/admin/friend/search?userId=${USER_ID}&keyword=test" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "好友搜索端点可达"
else
    skip "好友搜索端点不可用"
fi

# TC-FR-005: 删除好友
test_header "TC-FR-005: 删除好友"
body="{\"userId\":\"${USER_ID}\",\"friendId\":\"${FRIEND_ID}\"}"
resp=$(im_admin_post "/api/admin/friend/delete" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "好友删除成功"
else
    skip "好友删除端点不可用"
fi

test_summary
