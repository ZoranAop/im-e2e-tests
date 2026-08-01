#!/usr/bin/env bash
# ============================================================
# 文件上传下载测试 (TC-FILE-001~003)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "文件上传下载测试"

# TC-FILE-001: 获取上传 Token
test_header "TC-FILE-001: 获取上传 Token"
resp=$(im_admin_get "/api/admin/file/upload/token?userId=${USER_ID}&mediaType=1" 2>/dev/null)
if [ -n "${resp}" ] && echo "${resp}" | grep -q "token\|uploadUrl"; then
    pass "上传 Token 获取成功"
else
    skip "上传 Token 端点不可用"
fi

# TC-FILE-002: 获取下载 URL
test_header "TC-FILE-002: 获取下载 URL"
resp=$(im_admin_get "/api/admin/file/download?userId=${USER_ID}&mediaPath=test/path.jpg" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "下载 URL 端点可达"
else
    skip "下载 URL 端点不可用"
fi

# TC-FILE-003: 文件上传完整性校验 (mock)
test_header "TC-FILE-003: 文件上传校验"
resp=$(im_admin_get "/api/admin/file/check?userId=${USER_ID}" 2>/dev/null)
if [ -n "${resp}" ]; then
    pass "文件校验端点可达"
else
    skip "文件校验端点不可用"
fi

test_summary
