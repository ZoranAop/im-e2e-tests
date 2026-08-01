# 广场功能测试脚本
# 测试 IM 服务广场 SDK API 的 HTTP 层连通性和基本功能
# 
# 前置条件:
#   1. IM 服务已部署并配置 MongoDB
#   2. 广场配置已在 im-server.conf 中设置
#   3. 至少有一个测试用户已注册并登录
#
# 用法:
#   .\test_moments_api.ps1
#   或指定 IM 地址:
#   $env:IM_HOST="192.168.1.100"; .\test_moments_api.ps1

param(
    [string]$TestUserId = "test_user_01",
    [string]$TargetUserId = "test_user_02"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\common\utils.ps1"

# ============================================================
# 环境检查
# ============================================================

Write-TestHeader "IM 服务广场功能测试"

Write-Step "检查 IM 服务连通性..."
$version = Invoke-ImAdminApi -Path "/api/version"
if (Assert-HttpOk $version "IM 服务可达") {
    Write-Info "IM 服务版本: $($version | ConvertTo-Json -Compress)"
}

Write-Step "检查 MongoDB 连接..."
# 尝试通过 admin API 获取服务状态（如果有对应端点）
$health = Invoke-ImAdminApi -Path "/api/admin/health"
if ($null -eq $health) {
    Write-Skip "健康检查端点不可用，跳过 MongoDB 检查（请手动验证）"
} else {
    Assert-NotNull $health "服务健康状态返回正常"
}

# ============================================================
# TC-MT-001: 发布广场
# ============================================================

Write-TestHeader "TC-MT-001: 发布广场"

Write-Step "测试发布文本类型广场 (type=0)..."
$feedBody = @{
    userId       = $TestUserId
    type         = 0
    text         = "这是一条测试广场文本 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    medias       = @()
    toUsers      = @()
    excludeUsers = @()
    mentionedUsers = @()
    extra        = ""
}
$response = Invoke-ImAdminApi -Path "/api/admin/moments/feed" -Method "POST" -Body $feedBody
if (Assert-HttpOk $response "文本广场发布") {
    $feedId = $response.feedId
    Assert-NotNull $feedId "返回有效 Feed ID"
}

Write-Step "测试发布图片类型广场 (type=1)..."
$feedBody.type = 1
$feedBody.medias = @(@{ url = "https://example.com/test.jpg"; width = 800; height = 600 })
$response = Invoke-ImAdminApi -Path "/api/admin/moments/feed" -Method "POST" -Body $feedBody
Assert-HttpOk $response "图片广场发布"

Write-Step "测试发布定向广场..."
$feedBody.type = 0
$feedBody.toUsers = @($TargetUserId)
$response = Invoke-ImAdminApi -Path "/api/admin/moments/feed" -Method "POST" -Body $feedBody
Assert-HttpOk $response "定向广场发布（指定接收用户）"

# ============================================================
# TC-MT-002: 发布评论/点赞
# ============================================================

Write-TestHeader "TC-MT-002: 发布评论与点赞"

Write-Step "查找测试用 Feed..."
# 拉取用户广场获取 Feed ID
$feeds = Invoke-ImAdminApi -Path "/api/admin/moments/feeds?userId=$TestUserId&count=5"
if ($null -ne $feeds -and $feeds.Count -gt 0) {
    $targetFeedId = $feeds[0].feedId
    Write-Info "使用 Feed ID: $targetFeedId"
} else {
    Write-Skip "无可用 Feed，跳过评论测试（请先发布广场）"
}

if ($targetFeedId) {
    Write-Step "测试发布评论 (type=0)..."
    $commentBody = @{
        userId  = $TargetUserId
        type    = 0
        feedId  = $targetFeedId
        text    = "这是一条测试评论 - $(Get-Date)"
        replyTo = ""
        replyId = 0
        extra   = ""
    }
    $response = Invoke-ImAdminApi -Path "/api/admin/moments/comment" -Method "POST" -Body $commentBody
    Assert-HttpOk $response "评论发布"

    Write-Step "测试发布点赞 (type=1)..."
    $commentBody.type = 1
    $commentBody.text = ""
    $response = Invoke-ImAdminApi -Path "/api/admin/moments/comment" -Method "POST" -Body $commentBody
    Assert-HttpOk $response "点赞发布"

    Write-Step "测试回复评论..."
    $commentBody.type = 0
    $commentBody.text = "回复评论测试"
    $commentBody.replyTo = $TestUserId
    if ($null -ne $response -and $null -ne $response.commentId) {
        $commentBody.replyId = $response.commentId
    }
    $response = Invoke-ImAdminApi -Path "/api/admin/moments/comment" -Method "POST" -Body $commentBody
    Assert-HttpOk $response "回复评论发布"
}

# ============================================================
# TC-MT-003: 拉取广场
# ============================================================

Write-TestHeader "TC-MT-003: 拉取广场"

Write-Step "拉取最新广场 (fromIndex=0, count=20)..."
$response = Invoke-ImAdminApi -Path "/api/admin/moments/feeds?userId=$TestUserId&count=20"
if (Assert-HttpOk $response "拉取最新广场") {
    Assert-NotNull $response "返回 Feed 列表"
    if ($null -ne $response.Count) {
        Write-Info "返回 $($response.Count) 条 Feed"
    }
}

Write-Step "分页拉取更旧广场..."
if ($null -ne $response -and $null -ne $response[-1] -and $null -ne $response[-1].feedId) {
    $lastFeedId = $response[-1].feedId
    $page2 = Invoke-ImAdminApi -Path "/api/admin/moments/feeds?userId=$TestUserId&count=20&fromIndex=$lastFeedId"
    Assert-HttpOk $page2 "分页拉取（fromIndex=$lastFeedId）"
}

# ============================================================
# TC-MT-005: 广场设置
# ============================================================

Write-TestHeader "TC-MT-005: 广场设置"

Write-Step "获取广场设置..."
$profile = Invoke-ImAdminApi -Path "/api/admin/moments/profile?userId=$TestUserId"
if (Assert-HttpOk $profile "获取广场设置") {
    Write-Info "当前设置: $($profile | ConvertTo-Json -Compress)"
}

Write-Step "更新广场背景图 (type=0)..."
$body = @{ userId = $TestUserId; type = 0; strValue = "https://example.com/bg.jpg"; intValue = 0 }
$response = Invoke-ImAdminApi -Path "/api/admin/moments/profile" -Method "POST" -Body $body
Assert-HttpOk $response "更新背景图"

Write-Step "设置陌生人可见条数 (type=1)..."
$body.type = 1; $body.strValue = ""; $body.intValue = 10
$response = Invoke-ImAdminApi -Path "/api/admin/moments/profile" -Method "POST" -Body $body
Assert-HttpOk $response "设置陌生人可见 10 条"

Write-Step "设置可见范围 (type=2): 3天..."
$body.type = 2; $body.intValue = 1
$response = Invoke-ImAdminApi -Path "/api/admin/moments/profile" -Method "POST" -Body $body
Assert-HttpOk $response "设置可见范围为 3 天"

Write-Step "设置可见范围 (type=2): 半年..."
$body.type = 2; $body.intValue = 3
$response = Invoke-ImAdminApi -Path "/api/admin/moments/profile" -Method "POST" -Body $body
Assert-HttpOk $response "设置可见范围为 6 个月"

# ============================================================
# TC-MT-006: 黑名单/屏蔽名单
# ============================================================

Write-TestHeader "TC-MT-006: 黑名单与屏蔽名单"

Write-Step "添加黑名单（不让TA看）..."
$body = @{
    userId    = $TestUserId
    isBlock   = $false
    addList   = @($TargetUserId)
    removeList = @()
}
$response = Invoke-ImAdminApi -Path "/api/admin/moments/blacklist" -Method "POST" -Body $body
Assert-HttpOk $response "添加黑名单"

Write-Step "移除黑名单..."
$body.addList = @(); $body.removeList = @($TargetUserId)
$response = Invoke-ImAdminApi -Path "/api/admin/moments/blacklist" -Method "POST" -Body $body
Assert-HttpOk $response "移除黑名单"

Write-Step "添加屏蔽名单（不看TA）..."
$body.isBlock = $true; $body.addList = @($TargetUserId); $body.removeList = @()
$response = Invoke-ImAdminApi -Path "/api/admin/moments/blacklist" -Method "POST" -Body $body
Assert-HttpOk $response "添加屏蔽名单"

# ============================================================
# 配置验证
# ============================================================

Write-TestHeader "广场服务端配置验证"

# 检查广场相关配置项
Write-Step "验证 moments.global_visible 配置..."
# 尝试获取服务端配置（取决于 IM 服务是否暴露此接口）
$config = Invoke-ImAdminApi -Path "/api/admin/config"
if ($null -ne $config) {
    Write-Info "服务端配置已返回"
    Assert-NotNull $config "配置获取成功"
} else {
    Write-Skip "配置接口不可用，请手动检查 im-server.conf"
}

# ============================================================
# MongoDB 数据验证
# ============================================================

Write-TestHeader "MongoDB 数据验证"

Write-Step "提示：请手动登录 MongoDB 验证以下内容..."
Write-Info "  - moments_feeds 集合: 确认发布的 Feed 已写入"
Write-Info "  - moments_comments 集合: 确认评论和点赞记录已写入"
Write-Info "  - moments_user_profiles 集合: 确认用户设置已持久化"
Write-Info ""
Write-Info "MongoDB 查询命令示例:"
Write-Info '  db.moments_feeds.find({ userId: "' + $TestUserId + '" }).limit(5)'
Write-Info '  db.moments_comments.find({ feedId: <feedId> }).limit(5)'
Write-Info '  db.moments_user_profiles.find({ userId: "' + $TestUserId + '" })'

# ============================================================
# 结果汇总
# ============================================================

Write-TestSummary
