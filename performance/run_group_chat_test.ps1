# 群聊消息性能测试 (PowerShell)
# TC-GC-100/200/1000: 百人群/两百人群/千人群
#
# 用法:
#   .\run_group_chat_test.ps1 -GroupSize 100
#   .\run_group_chat_test.ps1 -GroupSize 200
#   .\run_group_chat_test.ps1 -GroupSize 1000

param(
    [ValidateSet("check",100,200,1000)]
    $GroupSize = "check",
    [int]$Cores = 16
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\common\utils.ps1"

function Test-GroupChat {
    param([int]$Size, [int]$Groups, [int]$Senders, [int]$NormalMembers, [int]$Observers, [int]$Rounds)
    
    $totalMsgs = $Senders * $Groups * $Rounds
    $expectedObserver = $Rounds * $Groups
    $totalMembers = $Senders + $NormalMembers + $Observers

    Write-TestHeader ("TC-GC-" + $Size + ": " + $Size + "人群聊消息测试")

    Write-Step "测试参数..."
    Write-Info "  服务资源: ${Cores}C48G"
    Write-Info "  群数量: $Groups | 每群人数: $totalMembers"
    Write-Info "  发送用户: $Senders | 普通成员: $NormalMembers | 观察者: $Observers"
    Write-Info "  发送轮次: $Rounds | 消息总量: $totalMsgs"
    Write-Info "  观察者预期接收: $expectedObserver 条"

    Write-Step "检查 IM 服务连通性..."
    $version = Invoke-ImAdminApi -Path "/api/version"
    Assert-HttpOk $version "IM 服务可达"

    Write-Step "im-server.conf 关键配置..."
    Write-Info "  [ ] client.request_rate_limit = 1000000"
    Write-Info "  [ ] message.max_queue = 100000"
    Write-Info "  [ ] netty.epoll = true"

    Write-Step "测试步骤..."
    Write-Info "  1. 创建 $Groups 个群组，每群 $totalMembers 人"
    Write-Info "  2. 1个观察用户使用真实手机加入所有群"
    Write-Info "  3. stress-tool 配置: CreateGroup=true, Lite=true"
    Write-Info "  4. $Senders 个发送者向各自的群发送 $Rounds 轮消息"

    Write-Step "判定标准..."
    Write-Info "  消息成功率 = 100%"
    Write-Info "  观察者接收条数 = $expectedObserver"
    Write-Info "  CPU 利用率 = 100% (无瓶颈)"
    Write-Info "  发送结束后压力迅速降为0"

    Write-Step "计算公式..."
    Write-Info "  单核速率 = 发送速率 / $Cores"
    Write-Info "  单核分发速率 = 单核速率 * $totalMembers"
}

switch ($GroupSize) {
    "check" {
        Write-TestHeader "群聊消息测试 - 环境检查"
        $version = Invoke-ImAdminApi -Path "/api/version"
        Assert-HttpOk $version "IM 服务可达"
    }
    100 {
        Test-GroupChat -Size 100 -Groups 100 -Senders 50 -NormalMembers 49 -Observers 1 -Rounds 20
        Write-Info "参考基准: 74.6秒 | 1,340条/秒 | 单核分发 8,375"
    }
    200 {
        Test-GroupChat -Size 200 -Groups 100 -Senders 100 -NormalMembers 99 -Observers 1 -Rounds 10
        Write-Info "参考基准: 145.8秒 | 685.8条/秒 | 单核分发 8,573"
    }
    1000 {
        Test-GroupChat -Size 1000 -Groups 100 -Senders 100 -NormalMembers 899 -Observers 1 -Rounds 2
        Write-Info "参考基准: 142.8秒 | 140条/秒 | 单核分发 8,750"
    }
}

Write-TestSummary