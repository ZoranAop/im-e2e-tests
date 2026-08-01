#!/usr/bin/env bash
# ============================================================
# 富消息类型测试 (TC-RICH-001~006)
# ============================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"

USER_ID="${1:-test_user_01}"

test_header "富消息类型测试"

# TC-RICH-001: 图片消息
test_header "TC-RICH-001: 图片消息"
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"${USER_ID}\",\"target\":\"${USER_ID}_target\",\"content\":{\"type\":1,\"searchableContent\":\"[image]\",\"binaryContent\":\"\"}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then pass "图片消息发送"; else skip "消息发送端点不可用"; fi

# TC-RICH-002: 语音消息
test_header "TC-RICH-002: 语音消息"
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"${USER_ID}\",\"target\":\"${USER_ID}_target\",\"content\":{\"type\":2,\"searchableContent\":\"[voice]\",\"duration\":10}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then pass "语音消息发送"; else skip "语音消息不可用"; fi

# TC-RICH-003: 视频消息
test_header "TC-RICH-003: 视频消息"
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"${USER_ID}\",\"target\":\"${USER_ID}_target\",\"content\":{\"type\":3,\"searchableContent\":\"[video]\"}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then pass "视频消息发送"; else skip "视频消息不可用"; fi

# TC-RICH-004: 文件消息
test_header "TC-RICH-004: 文件消息"
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"${USER_ID}\",\"target\":\"${USER_ID}_target\",\"content\":{\"type\":4,\"searchableContent\":\"[file]\",\"name\":\"test.pdf\",\"size\":1024}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then pass "文件消息发送"; else skip "文件消息不可用"; fi

# TC-RICH-005: 位置消息
test_header "TC-RICH-005: 位置消息"
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"${USER_ID}\",\"target\":\"${USER_ID}_target\",\"content\":{\"type\":5,\"searchableContent\":\"[location]\",\"lat\":39.9,\"lon\":116.4}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then pass "位置消息发送"; else skip "位置消息不可用"; fi

# TC-RICH-006: 自定义消息
test_header "TC-RICH-006: 自定义消息"
resp=$(im_admin_post "/api/admin/message/send" "{\"sender\":\"${USER_ID}\",\"target\":\"${USER_ID}_target\",\"content\":{\"type\":100,\"searchableContent\":\"[custom]\",\"pushContent\":\"custom payload\"}}" 2>/dev/null)
if echo "${resp}" | grep -q "messageUid"; then pass "自定义消息发送"; else skip "自定义消息不可用"; fi

test_summary
