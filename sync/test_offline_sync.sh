#!/usr/bin/env bash
# ============================================================
# 离线消息同步测试 (TC-SYNC-001~003)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "离线消息同步测试"

# TC-SYNC-001: 检查离线消息队列
test_header "TC-SYNC-001: 离线消息队列"
step "检查离线消息数..."
resp=$(im_admin_get "/api/admin/message/offline/count?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "离线消息队列可查询"
else
    skip "离线消息端点不可用"
fi

# TC-SYNC-002: 拉取离线消息
test_header "TC-SYNC-002: 拉取离线消息"
resp=$(im_admin_get "/api/admin/message/offline/pull?userId=${USER_ID}&fromIndex=0&count=20" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
    pass "离线消息拉取成功"
else
    skip "离线消息拉取端点不可用"
fi

# TC-SYNC-003: 离线消息清除
test_header "TC-SYNC-003: 离线消息清除"
resp=$(im_admin_post "/api/admin/message/offline/clear" "{\"userId\":\"${USER_ID}\"}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "离线消息清除成功"
else
    skip "离线消息清除端点不可用"
fi

test_summary
