# 单聊消息性能测试 (PowerShell)
# TC-SC-001: 发送消息测试
# TC-SC-002: 收发消息测试
#
# 用法:
#   .\run_single_chat_test.ps1 -Mode check
#   .\run_single_chat_test.ps1 -Mode send
#   .\run_single_chat_test.ps1 -Mode recv
#   .\run_single_chat_test.ps1 -Mode full

param(
    [ValidateSet("check","send","recv","full")]
    [string]$Mode = "check",
    [int]$Senders = 200,
    [int]$Receivers = 1000,
    [int]$Rounds = 50,
    [int]$TotalMsgs = 10000000,
    [int]$Cores = 16
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\common\utils.ps1"

function Test-SCSend {
    Write-TestHeader "TC-SC-001: 单聊发送消息测试"
    
    Write-Step "测试参数..."
    Write-Info "  发送用户: $Senders"
    Write-Info "  接收用户: $Receivers (999离线 + 1在线观察)"
    Write-Info "  发送轮次: $Rounds"
    Write-Info "  消息总量: $TotalMsgs"
    Write-Info "  服务资源: 合计 ${Cores}C48G"

    Write-Step "检查 IM 服务连通性..."
    $version = Invoke-ImAdminApi -Path "/api/version"
    Assert-HttpOk $version "IM 服务可达"

    Write-Step "验证 im-server.conf 关键配置..."
    Write-Info "  [ ] client.request_rate_limit = 1000000"
    Write-Info "  [ ] message.max_queue = 100000"
    Write-Info "  [ ] embed.db = 0"
    Write-Info "  [ ] netty.epoll = true"

    Write-Step "测试步骤..."
    Write-Info "  1. 创建 $Senders 个发送用户 + $Receivers 个接收用户"
    Write-Info "  2. 1个接收用户使用真实手机在线观察"
    Write-Info "  3. 其余离线，stress-tool 配置 Lite=true"
    Write-Info "  4. 执行 $Rounds 轮发送，总量 $TotalMsgs 条"
    Write-Info "  5. 记录发送时间、CPU利用率、消息成功率"

    Write-Step "判定标准..."
    Write-Info "  消息成功率 = 100%"
    Write-Info "  观察者接收条数 = $($Senders * $Rounds)"
    Write-Info "  发送结束后服务端压力迅速降为0"

    Write-Step "参考基准 (16C48G) ..."
    Write-Info "  发送时间: 509秒 | 速率: 19,646条/秒 | 单核: 1,227条/秒/核"
    
    Write-TestHeader "TC-SC-001 完成"
}

function Test-SCRecv {
    Write-TestHeader "TC-SC-002: 单聊收发消息测试"
    
    Write-Step "测试参数..."
    Write-Info "  发送用户: $Senders"
    Write-Info "  接收用户: $Receivers (全部在线，1个真实手机)"
    Write-Info "  发送轮次: $Rounds"
    Write-Info "  消息总量: $TotalMsgs"
    Write-Info "  服务资源: 合计 ${Cores}C48G"

    Write-Step "检查 IM 服务连通性..."
    $version = Invoke-ImAdminApi -Path "/api/version"
    Assert-HttpOk $version "IM 服务可达"

    Write-Step "测试步骤..."
    Write-Info "  1. 需要2台压测机: 发送机(Lite=true) + 接收机(Lite=false)"
    Write-Info "  2. 先启动接收机，等待所有用户连接"
    Write-Info "  3. 再启动发送机，执行 $Rounds 轮发送"
    Write-Info "  4. 记录收发时间、CPU/DB利用率、消息成功率"

    Write-Step "参考基准 (16C48G)..."
    Write-Info "  收发时间: 719秒 | 速率: 13,908条/秒 | 单核: 869条/秒/核"
    Write-Info "  通知+拉取阶段 ≈ 2,978 条/秒/核 (推导值)"
}

switch ($Mode) {
    "check" {
        Write-TestHeader "单聊消息测试 - 环境检查"
        $version = Invoke-ImAdminApi -Path "/api/version"
        Assert-HttpOk $version "IM 服务可达"
    }
    "send" { Test-SCSend }
    "recv" { Test-SCRecv }
    "full" { Test-SCSend; Write-Host ""; Test-SCRecv }
}

Write-TestSummary