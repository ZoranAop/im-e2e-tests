#!/usr/bin/env bash
# ============================================================
# 广场 (Square) API 功能测试脚本 (PowerShell 版本)
# ============================================================
# 测试 IM 服务广场功能
#
# 用法:
#   .\test_square_api.ps1 -TestUserId "your_user_id"
#
# ============================================================

param(
    [string]$TestUserId = "test_user_01"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\common\utils.ps1"

# ============================================================
# TC-SQ-001: 广场服务连通性
# ============================================================

Write-TestHeader "TC-SQ-001: 广场服务连通性"

Write-Step "检查 IM 服务连通性..."
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $conn = $tcp.BeginConnect($env:IM_HOST, [int]$env:IM_HTTP_PORT, $null, $null)
    if ($conn.AsyncWaitHandle.WaitOne(3000)) {
        $tcp.EndConnect($conn)
        Write-Pass "IM HTTP 端口可达"
    } else {
        Write-Fail "IM HTTP 端口连接超时"
    }
    $tcp.Close()
} catch {
    Write-Fail "IM HTTP 端口不可达: $_"
}

try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $conn = $tcp.BeginConnect($env:IM_HOST, [int]$env:IM_ADMIN_PORT, $null, $null)
    if ($conn.AsyncWaitHandle.WaitOne(3000)) {
        $tcp.EndConnect($conn)
        Write-Pass "IM Admin 端口可达"
    } else {
        Write-Fail "IM Admin 端口连接超时"
    }
    $tcp.Close()
} catch {
    Write-Fail "IM Admin 端口不可达: $_"
}

$version = Invoke-ImAdminApi -Path "/api/version"
Assert-HttpOk $version "IM 版本信息获取"

# ============================================================
# TC-SQ-002: 广场信息
# ============================================================

Write-TestHeader "TC-SQ-002: 广场信息查询"

Write-Step "SDK API 说明..."
Write-Info "  getSquareList(callback)               -- 获取广场列表"
Write-Info "  getSquareInfo(squareId, callback)      -- 获取广场详情"
Write-Info "验证点: 广场列表正确返回，详情与配置一致"

# ============================================================
# TC-SQ-003: 话题发布
# ============================================================

Write-TestHeader "TC-SQ-003: 话题发布与浏览"

Write-Step "SDK API 说明..."
Write-Info "  publishSquareTopic(squareId, title, content, medias, callback)"
Write-Info "  getSquareTopics(squareId, fromIndex, count, callback)"
Write-Info "  getSquareTopicDetail(topicId, callback)"
Write-Info "验证点: 话题发布成功，列表正确，详情完整"

# ============================================================
# TC-SQ-004: 话题互动
# ============================================================

Write-TestHeader "TC-SQ-004: 话题互动"

Write-Step "SDK API 说明..."
Write-Info "  commentSquareTopic(topicId, content, replyTo, replyCommentId, callback)"
Write-Info "  likeSquareTopic(topicId, callback)"
Write-Info "  unlikeSquareTopic(topicId, callback)"
Write-Info "  deleteSquareComment(commentId, callback)"
Write-Info "验证点: 评论/点赞成功，取消/删除生效"

# ============================================================
# TC-SQ-005: 话题管理
# ============================================================

Write-TestHeader "TC-SQ-005: 话题管理"

Write-Step "SDK API 说明..."
Write-Info "  deleteSquareTopic(topicId, callback)    -- 删除话题"
Write-Info "  reportSquareTopic(topicId, reason, callback) -- 举报话题"
Write-Info "  searchSquareTopics(squareId, keyword, fromIndex, count, callback)"
Write-Info "验证点: 删除后不可见，搜索功能正常"

# ============================================================
# TC-SQ-006: 成员管理
# ============================================================

Write-TestHeader "TC-SQ-006: 广场成员管理"

Write-Step "SDK API 说明..."
Write-Info "  joinSquare(squareId, callback)          -- 加入广场"
Write-Info "  quitSquare(squareId, callback)          -- 退出广场"
Write-Info "  getSquareMembers(squareId, fromIndex, count, callback)"
Write-Info "验证点: 加入/退出有效，成员列表正确"

# ============================================================
# TC-SQ-007: 消息通知
# ============================================================

Write-TestHeader "TC-SQ-007: 广场消息通知"

Write-Step "通知类型说明..."
Write-Info "  setSquareMessageReceiveListener(listener)"
$notifications = @(
    "话题新增通知",
    "评论/回复通知",
    "点赞通知",
    "话题删除通知",
    "@提醒通知"
)
foreach ($n in $notifications) {
    Write-Info "  - $n"
}

# ============================================================
# TC-SQ-008: 配置检查
# ============================================================

Write-TestHeader "TC-SQ-008: 广场功能配置"

Write-Step "配置检查清单..."
$configs = @(
    "广场功能开关",
    "广场管理员用户 ID 列表",
    "单个广场最大话题数限制",
    "话题内容审核规则",
    "广场消息通知策略"
)
foreach ($c in $configs) {
    Write-Info "  [ ] $c"
}

# ============================================================
# TC-SQ-009: 性能要点
# ============================================================

Write-TestHeader "TC-SQ-009: 广场性能注意要点"

Write-Step "性能模型参考..."
$perf = @(
    @{Area="话题发布"; Model="类似单聊消息发送，含内容落库和分发"},
    @{Area="话题分发"; Model="分发到广场所有成员，参考群聊(单核8,750条/秒/核)"},
    @{Area="话题拉取"; Model="支持分页，有缓存机制，热点数据性能好"},
    @{Area="搜索功能"; Model="消耗较大，建议限制搜索频率"},
    @{Area="成员管理"; Model="大批量操作时关注服务端压力"},
    @{Area="媒体上传"; Model="直传对象存储，IM服务压力小"}
)
foreach ($p in $perf) {
    Write-Info "  $($p.Area): $($p.Model)"
}

Write-Info "建议根据实际场景参考群聊/朋友圈测试结果独立压测"

# ============================================================
# 结果汇总
# ============================================================

Write-TestSummary
