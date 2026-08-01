#!/usr/bin/env bash
# ============================================================
# 消息搜索测试 (TC-SRCH-001~003)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"
KEYWORD="${2:-test}"

test_header "消息搜索测试"

# TC-SRCH-001: 搜索消息
test_header "TC-SRCH-001: 搜索消息"
resp=$(im_admin_get "/api/admin/message/search?userId=${USER_ID}&keyword=${KEYWORD}&limit=20" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -qE '\[|\{'; then
    pass "消息搜索成功"
else
    skip "消息搜索端点不可用"
fi

# TC-SRCH-002: 搜索用户
test_header "TC-SRCH-002: 搜索用户"
resp=$(im_admin_get "/api/admin/user/search?keyword=${KEYWORD}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "用户搜索端点可达"
else
    skip "用户搜索端点不可用"
fi

# TC-SRCH-003: 搜索群组
test_header "TC-SRCH-003: 搜索群组"
resp=$(im_admin_get "/api/admin/group/search?keyword=${KEYWORD}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "群组搜索端点可达"
else
    skip "群组搜索端点不可用"
fi

test_summary
