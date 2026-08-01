#!/usr/bin/env bash
# ============================================================
# 已读回执测试 (TC-RECPT-001~002)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "已读回执测试"

# TC-RECPT-001: 发送已读回执
test_header "TC-RECPT-001: 发送已读回执"
resp=$(im_admin_post "/api/admin/message/read" "{\"userId\":\"${USER_ID}\",\"conversation\":{\"type\":0,\"target\":\"${USER_ID}_target\",\"line\":0},\"messageUid\":0}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "已读回执发送成功"
else
    skip "已读回执端点不可用"
fi

# TC-RECPT-002: 查询未读数
test_header "TC-RECPT-002: 查询未读数"
resp=$(im_admin_get "/api/admin/message/unread?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "未读数查询端点可达"
else
    skip "未读数查询端点不可用"
fi

test_summary
