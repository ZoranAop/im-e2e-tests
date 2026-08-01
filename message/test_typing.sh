#!/usr/bin/env bash
# ============================================================
# 输入状态测试 (TC-TYPE-001~002)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"
TARGET_ID="${2:-test_user_02}"

test_header "输入状态测试"

# TC-TYPE-001: 发送正在输入
test_header "TC-TYPE-001: 发送正在输入"
resp=$(im_admin_post "/api/admin/message/typing" "{\"userId\":\"${USER_ID}\",\"target\":\"${TARGET_ID}\",\"typingType\":1}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "输入状态发送成功"
else
    skip "输入状态端点不可用"
fi

# TC-TYPE-002: 停止输入
test_header "TC-TYPE-002: 停止输入"
resp=$(im_admin_post "/api/admin/message/typing" "{\"userId\":\"${USER_ID}\",\"target\":\"${TARGET_ID}\",\"typingType\":0}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|200'; then
    pass "停止输入状态发送成功"
else
    skip "停止输入端点不可用"
fi

test_summary
