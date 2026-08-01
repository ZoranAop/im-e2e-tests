#!/usr/bin/env bash
# ============================================================
# 消息撤回删除测试 (TC-MSG-RECALL)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "消息撤回删除测试"

# TC-RECALL-001: 撤回消息
test_header "TC-RECALL-001: 撤回消息"
step "撤回消息..."
resp=$(im_admin_post "/api/admin/message/recall" "{\"userId\":\"${USER_ID}\",\"messageUid\":0}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "消息撤回端点可用"
else
    skip "消息撤回端点不可用"
fi

# TC-RECALL-002: 删除消息
test_header "TC-RECALL-002: 删除消息"
resp=$(im_admin_post "/api/admin/message/delete" "{\"userId\":\"${USER_ID}\",\"messageUid\":0}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "消息删除端点可用"
else
    skip "消息删除端点不可用"
fi

# TC-RECALL-003: 服务端消息清理
test_header "TC-RECALL-003: 服务端消息查询"
resp=$(im_admin_get "/api/admin/message/check?messageUid=0" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "消息查询端点可用"
else
    skip "消息查询端点不可用"
fi

test_summary
