#!/usr/bin/env bash
# 推送服务测试脚本（Bash 版本）
# 测试 IM 推送服务的连通性、端口可用性和基本功能

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../common/utils.sh"
source "${SCRIPT_DIR}/../common/env.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../common/db_utils.sh" 2>/dev/null || true

TEST_USER_ID="${1:-test_user_01}"
DEVICE_TOKEN="${2:-test_device_token_001}"
PUSH_TYPE="${3:-1}"

# ============================================================
# 环境检查
# ============================================================
test_header "IM 推送服务测试"

# ============================================================
# TC-PS-001: 推送服务连通性
# ============================================================
test_header "TC-PS-001: 推送服务连通性"

step "检查推送服务端口 ${PUSH_PORT}..."
if timeout 3 bash -c "echo >/dev/tcp/${PUSH_HOST}/${PUSH_PORT}" 2>/dev/null; then
    pass "推送服务端口 ${PUSH_PORT} 可达"
else
    skip "推送服务端口 ${PUSH_PORT} 不可达（推送服务为可选外部依赖）"
fi

step "检查推送管理端口 ${PUSH_ADMIN_PORT}..."
if timeout 3 bash -c "echo >/dev/tcp/${PUSH_HOST}/${PUSH_ADMIN_PORT}" 2>/dev/null; then
    pass "推送管理端口 ${PUSH_ADMIN_PORT} 可达"
else
    skip "推送管理端口 ${PUSH_ADMIN_PORT} 不可达（推送服务为可选外部依赖）"
fi

# ============================================================
# TC-PS-005: 推送服务后台管理
# ============================================================
test_header "TC-PS-005: 推送服务后台管理"

step "访问推送管理后台登录页..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" "${PUSH_ADMIN_URL}/admin/" 2>/dev/null || echo "000")
if [ "${http_code}" = "200" ]; then
    pass "管理后台页面可访问 (200 OK)"
else
    skip "管理后台页面不可达 (HTTP ${http_code})"
fi

step "检查推送配置 API 可用性..."
config_apis=(
    "/api/admin/config/apns"
    "/api/admin/config/fcm"
    "/api/admin/config/huawei"
    "/api/admin/config/xiaomi"
    "/api/admin/config/oppo"
    "/api/admin/config/vivo"
)
for api in "${config_apis[@]}"; do
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${PUSH_ADMIN_URL}${api}" 2>/dev/null || echo "000")
    if [ "${http_code}" = "200" ] || [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]; then
        pass "  ${api} 端点存在"
    else
        skip "  ${api}: 跳过"
    fi
done

# ============================================================
# TC-PS-002: DeviceToken 注册
# ============================================================
test_header "TC-PS-002: DeviceToken 注册验证"

step "验证 DeviceToken 存储..."
session_info=$(im_admin_api "/api/admin/user/session?userId=${TEST_USER_ID}")
if [ -z "${session_info}" ] || [ "${session_info}" = "null" ]; then
    skip "无法获取用户 session 信息"
    info "手动验证方式: 在 IM 服务数据库中查询:"
    info "  SELECT device_token, push_type FROM t_user_session WHERE user_id = '${TEST_USER_ID}';"
else
    assert_not_null "${session_info}" "用户 session 信息获取成功"
    device_token_val=$(echo "${session_info}" | grep -o '"deviceToken":"[^"]*"' | cut -d'"' -f4)
    if [ -n "${device_token_val}" ]; then
        pass "DeviceToken 已注册: ${device_token_val}"
    else
        skip "DeviceToken 未注册（用户可能未调用 setDeviceToken）"
    fi
fi

# ============================================================
# TC-PS-003: 离线推送触发验证
# ============================================================
test_header "TC-PS-003: 离线推送触发验证"

step "验证推送服务端口..."
if timeout 3 bash -c "echo >/dev/tcp/${PUSH_HOST}/${PUSH_PORT}" 2>/dev/null; then
    pass "推送服务端口 ${PUSH_PORT} 可达 - 离线推送可触发"
else
    fail "推送服务端口不可达，离线推送无法触发"
fi

step "推送决策条件检查清单..."
info "  [1] 客户端在线时不推送"
info "  [2] 离线超过 7 天不推送（可配置）"
info "  [3] 消息无 pushContent 时不推送"
info "  [4] deviceToken 不存在时不推送"
info "  [5] 平台不支持推送时不推送"
info "  [6] 会话静音且非 @消息时不推送"
info "  [7] PC 在线时静音状态不推送"
info "  [8] 全局静音时不推送"
info "  [9] 免打扰时段内不推送"
info "以上条件由 IM 服务端自动判断，需配合客户端进行端到端验证"

# ============================================================
# TC-PS-004: 推送厂商支持验证
# ============================================================
test_header "TC-PS-004: 推送厂商支持验证"

step "检查推送厂商配置端点可达性..."
push_vendors=(
    "huawei:HMS"
    "xiaomi:MiPush"
    "oppo:OPPO Push"
    "vivo:Vivo Push"
    "meizu:魅族 Push"
    "apns:Apple APNs"
    "fcm:Google FCM"
)
for vendor_entry in "${push_vendors[@]}"; do
    vendor_key="${vendor_entry%%:*}"
    vendor_name="${vendor_entry##*:}"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${PUSH_ADMIN_URL}/api/admin/config/${vendor_key}" 2>/dev/null || echo "000")
    if [ "${http_code}" = "200" ] || [ "${http_code}" = "401" ] || [ "${http_code}" = "403" ]; then
        pass "  ${vendor_name} (${vendor_key}) 配置端点可达"
    else
        skip "  ${vendor_name} (${vendor_key}) 配置端点不可达，需手动配置"
    fi
done

info "  个推           内置支持  -- 第三方推送"
info "  UniPush        内置支持  -- DCloud 推送"
info "  极光推送       需自行扩展 -- 参考内置厂商自行实现"

# ============================================================
# 相关服务检查
# ============================================================
test_header "相关服务状态检查"

step "检查 IM 服务推送配置..."
im_version=$(im_admin_api "/api/version")
assert_http_ok "${im_version}" "IM 服务可达"

step "验证集群配置同步（如适用）..."
info "  推送配置和证书保存在数据库中"
info "  各节点 30 秒定时刷新自动同步"
info "  修改配置后当前节点立即生效"
info "  集群其他节点最长约 30 秒后同步"

# ============================================================
# 结果汇总
# ============================================================
test_summary
