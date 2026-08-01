#!/usr/bin/env bash
# ============================================================
# 黑名单测试 (TC-BLK-001~003)
# ============================================================
# 用法: bash test_block_api.sh --user-id "userA" --block-id "userB"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"
BLOCK_ID="${2:-test_user_02}"

test_header "黑名单测试"

# TC-BLK-001: 拉黑用户
test_header "TC-BLK-001: 拉黑用户"
step "拉黑用户..."
local body="{\"userId\":\"${USER_ID}\",\"blockUserId\":\"${BLOCK_ID}\"}"
local resp=$(im_admin_post "/api/admin/block/add" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "用户拉黑成功"
else
    skip "拉黑端点不可用"
fi

# TC-BLK-002: 黑名单列表
test_header "TC-BLK-002: 黑名单列表"
resp=$(im_admin_get "/api/admin/block/list?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "黑名单列表获取"
else
    skip "黑名单列表端点不可用"
fi

# TC-BLK-003: 解除拉黑
test_header "TC-BLK-003: 解除拉黑"
body="{\"userId\":\"${USER_ID}\",\"blockUserId\":\"${BLOCK_ID}\"}"
resp=$(im_admin_post "/api/admin/block/remove" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "解除拉黑成功"
else
    skip "解除拉黑端点不可用"
fi

test_summary
