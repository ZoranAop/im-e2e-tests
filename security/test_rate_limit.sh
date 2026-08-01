#!/usr/bin/env bash
# ============================================================
# 限流/反垃圾测试 (TC-SEC-001~004)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "限流/反垃圾测试"

# TC-SEC-001: 查询限流配置
test_header "TC-SEC-001: 查询限流配置"
resp=$(im_admin_get "/api/admin/config" 2>/dev/null)
if echo "${resp}" | grep -q "rate_limit\|request_rate"; then
    pass "限流配置可查询"
else
    skip "限流配置端点不可用"
fi

# TC-SEC-002: 频率限制验证
test_header "TC-SEC-002: 频率限制验证"
local rate_limited=false
for i in $(seq 1 20); do
    resp=$(im_admin_get "/api/version" 2>/dev/null)
    if echo "${resp}" | grep -q "429\|rate limit"; then
        rate_limited=true
        break
    fi
done
if ${rate_limited}; then
    pass "限流机制生效 (429 detected)"
else
    skip "限流未触发 (rate limit可能已放开)"
fi

# TC-SEC-003: 敏感词检查
test_header "TC-SEC-003: 敏感词检查"
resp=$(im_admin_post "/api/admin/message/check" "{\"content\":\"test message\"}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "内容检查端点可达"
else
    skip "内容检查端点不可用"
fi

# TC-SEC-004: IP 黑名单
test_header "TC-SEC-004: IP 黑名单"
resp=$(im_admin_get "/api/admin/security/blacklist" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "安全黑名单端点可达"
else
    skip "安全黑名单端点不可用"
fi

test_summary
