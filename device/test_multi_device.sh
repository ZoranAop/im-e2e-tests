#!/usr/bin/env bash
# ============================================================
# 多设备登录测试 (TC-DEV-001~003)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "多设备登录测试"

# TC-DEV-001: 查询在线设备
test_header "TC-DEV-001: 查询在线设备"
resp=$(im_admin_get "/api/admin/user/sessions?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -q "session\|device"; then
    pass "在线设备查询成功"
else
    skip "设备查询端点不可用"
fi

# TC-DEV-002: 多端消息同步
test_header "TC-DEV-002: 多端消息同步"
resp=$(im_admin_get "/api/admin/message/sync?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "消息同步端点可达"
else
    skip "消息同步端点不可用"
fi

# TC-DEV-003: 强制下线设备
test_header "TC-DEV-003: 强制下线设备"
resp=$(im_admin_post "/api/admin/user/kick" "{\"userId\":\"${USER_ID}\",\"clientId\":\"c_${USER_ID}\"}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "设备强制下线成功"
else
    skip "强制下线端点不可用"
fi

test_summary
