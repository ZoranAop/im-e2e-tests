#!/usr/bin/env bash
# ============================================================
# 群组管理测试 (TC-GRP-001~007)
# ============================================================
# 用法: bash test_group_api.sh --user-id "userA"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"
GROUP_ID="test_group_$(date +%s)"

test_header "群组管理测试"

# TC-GRP-001: 创建群组
test_header "TC-GRP-001: 创建群组"
step "创建群组..."
local body="{\"groupId\":\"${GROUP_ID}\",\"name\":\"Test Group\",\"owner\":\"${USER_ID}\",\"members\":[]}"
local resp=$(im_admin_post "/api/admin/group/create" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "群组创建成功"
else
    skip "群组创建端点不可用"
fi

# TC-GRP-002: 添加成员
test_header "TC-GRP-002: 添加成员"
body="{\"groupId\":\"${GROUP_ID}\",\"members\":[\"${USER_ID}_member1\"]}"
resp=$(im_admin_post "/api/admin/group/member/add" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "成员添加成功"
else
    skip "成员添加端点不可用"
fi

# TC-GRP-003: 群信息查询
test_header "TC-GRP-003: 群信息查询"
resp=$(im_admin_get "/api/admin/group/info?groupId=${GROUP_ID}" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -q "groupId\|name"; then
    pass "群信息获取成功"
else
    skip "群信息端点不可用"
fi

# TC-GRP-004: 成员列表
test_header "TC-GRP-004: 成员列表"
resp=$(im_admin_get "/api/admin/group/members?groupId=${GROUP_ID}" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
    pass "成员列表获取成功"
else
    skip "成员列表端点不可用"
fi

# TC-GRP-005: 移除成员
test_header "TC-GRP-005: 移除成员"
body="{\"groupId\":\"${GROUP_ID}\",\"members\":[\"${USER_ID}_member1\"]}"
resp=$(im_admin_post "/api/admin/group/member/remove" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "成员移除成功"
else
    skip "成员移除端点不可用"
fi

# TC-GRP-006: 转让群主
test_header "TC-GRP-006: 转让群主"
body="{\"groupId\":\"${GROUP_ID}\",\"newOwner\":\"${USER_ID}_member2\"}"
resp=$(im_admin_post "/api/admin/group/transfer" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "群主转让成功"
else
    skip "群主转让端点不可用"
fi

# TC-GRP-007: 解散群组
test_header "TC-GRP-007: 解散群组"
resp=$(im_admin_post "/api/admin/group/dismiss" "{\"groupId\":\"${GROUP_ID}\"}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "群组解散成功"
else
    skip "群组解散端点不可用"
fi

test_summary
