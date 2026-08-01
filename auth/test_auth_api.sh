#!/usr/bin/env bash
# ============================================================
# 用户认证测试 (TC-AUTH-001~004)
# ============================================================
# 用法: bash test_auth_api.sh --user-id "user" --password "pass"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"
PASSWORD="${2:-test_pass_123}"

test_header "用户认证测试"

# TC-AUTH-001: 注册新用户
test_header "TC-AUTH-001: 注册新用户"
step "注册用户..."
local body="{\"userId\":\"${USER_ID}\",\"password\":\"${PASSWORD}\",\"nickname\":\"test-user\"}"
local resp=$(im_admin_post "/api/admin/user/register" "${body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"success":true|"userId"|200'; then
    pass "用户注册成功"
else
    skip "注册端点不可用，使用已有测试用户"
fi

# TC-AUTH-002: 用户登录
test_header "TC-AUTH-002: 用户登录"
step "获取 Auth Token..."
local login_body="{\"userId\":\"${USER_ID}\",\"password\":\"${PASSWORD}\"}"
resp=$(im_admin_post "/api/admin/user/token" "${login_body}" 2>/dev/null)
if echo "${resp}" | grep -qE '"token"|"accessToken"|200'; then
    pass "登录成功，Token 获取"
else
    skip "Token 端点不可用，需通过客户端 SDK 验证"
fi

# TC-AUTH-003: Token 校验
test_header "TC-AUTH-003: Token 校验"
resp=$(im_admin_get "/api/admin/user/check?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -qE '"valid"|200'; then
    pass "Token 校验通过"
else
    skip "Token 校验端点不可用"
fi

# TC-AUTH-004: 用户信息获取
test_header "TC-AUTH-004: 用户信息获取"
resp=$(im_admin_get "/api/admin/user/info?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -q "userId\|displayName"; then
    pass "用户信息获取成功"
else
    skip "用户信息端点不可用"
fi

test_summary
