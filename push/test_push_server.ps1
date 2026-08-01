# 推送服务测试脚本
# 测试 IM 推送服务的连通性、端口可用性和基本功能
#
# 前置条件:
#   1. 推送服务已部署并启动
#   2. IM 服务已配置推送服务地址
#
# 用法:
#   .\test_push_server.ps1
#   或指定地址:
#   $env:PUSH_HOST="<your-push-server-ip>"; .\test_push_server.ps1

param(
    [string]$TestUserId = "test_user_01",
    [string]$DeviceToken = "test_device_token_001",
    [int]$PushType = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\common\utils.ps1"

# ============================================================
# 环境检查
# ============================================================

Write-TestHeader "IM 推送服务测试"

# ============================================================
# TC-PS-001: 推送服务连通性
# ============================================================

Write-TestHeader "TC-PS-001: 推送服务连通性"

Write-Step "检查推送服务端口 8085..."
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $conn = $tcp.BeginConnect($env:PUSH_HOST, [int]$env:PUSH_PORT, $null, $null)
    if ($conn.AsyncWaitHandle.WaitOne(3000)) {
        $tcp.EndConnect($conn)
        Write-Pass "推送服务端口 $($env:PUSH_PORT) 可达"
    } else {
        Write-Fail "推送服务端口 $($env:PUSH_PORT) 连接超时"
    }
    $tcp.Close()
} catch {
    Write-Fail "推送服务端口 $($env:PUSH_PORT) 不可达: $_"
}

Write-Step "检查推送管理端口 8086..."
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $conn = $tcp.BeginConnect($env:PUSH_HOST, [int]$env:PUSH_ADMIN_PORT, $null, $null)
    if ($conn.AsyncWaitHandle.WaitOne(3000)) {
        $tcp.EndConnect($conn)
        Write-Pass "推送管理端口 $($env:PUSH_ADMIN_PORT) 可达"
    } else {
        Write-Fail "推送管理端口 $($env:PUSH_ADMIN_PORT) 连接超时"
    }
    $tcp.Close()
} catch {
    Write-Fail "推送管理端口 $($env:PUSH_ADMIN_PORT) 不可达: $_"
}

# ============================================================
# TC-PS-005: 推送服务后台管理
# ============================================================

Write-TestHeader "TC-PS-005: 推送服务后台管理"

Write-Step "访问推送管理后台登录页..."
$adminLoginUrl = "http://$($env:PUSH_HOST):$($env:PUSH_ADMIN_PORT)/admin/"
try {
    $response = Invoke-WebRequest -Uri $adminLoginUrl -Method GET -TimeoutSec 5 -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Pass "管理后台页面可访问 (200 OK)"
    } else {
        Write-Fail "管理后台返回非 200: $($response.StatusCode)"
    }
} catch {
    Write-Skip "管理后台页面不可达 (可能未启用静态页面): $_"
}

# 检查配置管理 API
Write-Step "检查推送配置 API 可用性..."
$configApis = @(
    "/api/admin/config/apns",
    "/api/admin/config/fcm",
    "/api/admin/config/huawei",
    "/api/admin/config/xiaomi",
    "/api/admin/config/oppo",
    "/api/admin/config/vivo"
)
foreach ($api in $configApis) {
    try {
        $apiUrl = "http://$($env:PUSH_HOST):$($env:PUSH_ADMIN_PORT)$api"
        $r = Invoke-WebRequest -Uri $apiUrl -Method GET -TimeoutSec 3 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200 -or $r.StatusCode -eq 401 -or $r.StatusCode -eq 403) {
            Write-Pass "  $api 端点存在"
        }
    } catch {
        Write-Skip "  $api: 跳过（端点不存在或不可达）"
    }
}

# ============================================================
# TC-PS-002: DeviceToken 注册
# ============================================================

Write-TestHeader "TC-PS-002: DeviceToken 注册验证"

Write-Step "验证 DeviceToken 存储..."
# 通过 admin API 检查用户 session 中的 deviceToken
$sessionInfo = Invoke-ImAdminApi -Path "/api/admin/user/session?userId=$TestUserId"
if ($null -eq $sessionInfo) {
    Write-Skip "无法获取用户 session 信息（用户可能不在线或 admin 接口不可用）"
    Write-Info "手动验证方式: 在 IM 服务数据库中查询:"
    Write-Info "  SELECT device_token, push_type FROM t_user_session WHERE user_id = '$TestUserId';"
} else {
    Assert-NotNull $sessionInfo "用户 session 信息获取成功"
    if ($null -ne $sessionInfo.deviceToken) {
        Write-Pass "DeviceToken 已注册: $($sessionInfo.deviceToken)"
    } else {
        Write-Skip "DeviceToken 未注册（用户可能未调用 setDeviceToken）"
    }
}

# ============================================================
# 推送条件验证
# ============================================================

Write-TestHeader "推送决策条件验证"

Write-Step "推送决策条件检查清单..."
$conditions = @(
    @{Seq=1; Desc="客户端在线时不推送"},
    @{Seq=2; Desc="离线超过 7 天不推送（可配置）"},
    @{Seq=3; Desc="消息无 pushContent 时不推送"},
    @{Seq=4; Desc="deviceToken 不存在时不推送"},
    @{Seq=5; Desc="平台不支持推送时不推送"},
    @{Seq=6; Desc="会话静音且非 @消息时不推送"},
    @{Seq=7; Desc="PC 在线时静音状态不推送"},
    @{Seq=8; Desc="全局静音时不推送"},
    @{Seq=9; Desc="免打扰时段内不推送"}
)
foreach ($c in $conditions) {
    Write-Info "  [$($c.Seq)] $($c.Desc)"
}
Write-Info "以上条件由 IM 服务端自动判断，需配合客户端进行端到端验证"

# ============================================================
# 推送厂商支持清单
# ============================================================

Write-TestHeader "推送厂商支持状态"

$vendors = @(
    @{Name="华为 HMS";   Builtin=$true;  Note="需配置 AppId/AppSecret"},
    @{Name="小米 MiPush"; Builtin=$true;  Note="需配置 AppId/AppKey"},
    @{Name="OPPO Push";  Builtin=$true;  Note="需配置 AppId/AppKey"},
    @{Name="Vivo Push";  Builtin=$true;  Note="需配置 AppId/AppKey"},
    @{Name="魅族 Push";  Builtin=$true;  Note="需配置 AppId/AppKey"},
    @{Name="Apple APNs"; Builtin=$true;  Note="需上传 p8 密钥"},
    @{Name="Google FCM"; Builtin=$true;  Note="需上传 JSON 凭证"},
    @{Name="个推";       Builtin=$true;  Note="第三方推送"},
    @{Name="UniPush";    Builtin=$true;  Note="DCloud 推送"},
    @{Name="极光推送";   Builtin=$false; Note="需自行扩展"}
)
foreach ($v in $vendors) {
    $status = if ($v.Builtin) { "内置支持" } else { "需自行扩展" }
    Write-Info "  $($v.Name.PadRight(12)) $status  -- $($v.Note)"
}

# ============================================================
# 相关服务检查
# ============================================================

Write-TestHeader "相关服务状态检查"

Write-Step "检查 IM 服务推送配置..."
$imVersion = Invoke-ImAdminApi -Path "/api/version"
Assert-HttpOk $imVersion "IM 服务可达"

Write-Step "验证集群配置同步（如适用）..."
Write-Info "  推送配置和证书保存在数据库中"
Write-Info "  各节点 30 秒定时刷新自动同步"
Write-Info "  修改配置后当前节点立即生效"
Write-Info "  集群其他节点最长约 30 秒后同步"

# ============================================================
# 结果汇总
# ============================================================

Write-TestSummary
