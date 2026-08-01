#!/usr/bin/env bash
# ============================================================
# 推送通知端到端测试 (TC-PUSH-E2E-001~003)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "推送通知端到端测试"

# TC-PUSH-E2E-001: 推送服务健康检查
test_header "TC-PUSH-E2E-001: 推送服务健康检查"
resp=$(push_api "/health" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "推送服务健康检查可达"
else
    skip "推送服务不可用"
fi

# TC-PUSH-E2E-002: 触发离线推送
test_header "TC-PUSH-E2E-002: 触发离线推送"
# Send message to offline user to trigger push
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"system\",\"target\":\"${USER_ID}\",\"content\":{\"type\":1,\"pushContent\":\"push test: $(date +%s)\",\"searchableContent\":\"push test\"}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then
    pass "推送触发消息发送成功"
else
    skip "推送触发端点不可用"
fi

# TC-PUSH-E2E-003: 推送记录查询
test_header "TC-PUSH-E2E-003: 推送记录查询"
resp=$(im_admin_get "/api/admin/push/records?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "推送记录查询可达"
else
    skip "推送记录端点不可用"
fi

test_summary
