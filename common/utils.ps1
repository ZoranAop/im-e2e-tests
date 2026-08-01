# 通用测试工具函数库
# 用法: . "$PSScriptRoot\utils.ps1"  (PowerShell)
# 用法: source "$(dirname "$0")/utils.sh"  (Bash)

# ============================================================
# 配置
# ============================================================

# 默认配置（可通过环境变量覆盖）
$env:IM_HOST ??= "localhost"
$env:IM_HTTP_PORT ??= "80"
$env:IM_ADMIN_PORT ??= "18080"
$env:IM_ADMIN_SECRET ??= "123456"
$env:PUSH_HOST ??= "localhost"
$env:PUSH_PORT ??= "8085"
$env:PUSH_ADMIN_PORT ??= "8086"

function Get-ImBaseUrl { "http://$($env:IM_HOST):$($env:IM_HTTP_PORT)" }
function Get-ImAdminUrl { "http://$($env:IM_HOST):$($env:IM_ADMIN_PORT)" }
function Get-PushUrl { "http://$($env:PUSH_HOST):$($env:PUSH_PORT)" }
function Get-PushAdminUrl { "http://$($env:PUSH_HOST):$($env:PUSH_ADMIN_PORT)" }

# ============================================================
# 日志
# ============================================================

$script:TestStartTime = Get-Date
$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host ">> $Message" -ForegroundColor Yellow
}

function Write-Pass {
    param([string]$Message)
    $script:PassCount++
    Write-Host "PASS" -ForegroundColor Green -NoNewline
    Write-Host ": $Message"
}

function Write-Fail {
    param([string]$Message)
    $script:FailCount++
    Write-Host "FAIL" -ForegroundColor Red -NoNewline
    Write-Host ": $Message"
}

function Write-Skip {
    param([string]$Message)
    $script:SkipCount++
    Write-Host "SKIP" -ForegroundColor DarkYellow -NoNewline
    Write-Host ": $Message"
}

function Write-Info {
    param([string]$Message)
    Write-Host "INFO: $Message" -ForegroundColor Gray
}

# ============================================================
# HTTP 请求工具
# ============================================================

function Invoke-ImAdminApi {
    param(
        [string]$Path,
        [string]$Method = "GET",
        $Body = $null
    )
    $uri = "$(Get-ImAdminUrl)$Path"
    $headers = @{ "nonce" = (Get-Random -Maximum 99999999).ToString(); "timestamp" = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString() }
    $params = @{ Uri = $uri; Method = $Method; Headers = $headers; ContentType = "application/json" }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Compress) }
    try { return Invoke-RestMethod @params -ErrorAction Stop }
    catch { return $null }
}

function Invoke-PushApi {
    param(
        [string]$Path,
        [string]$Method = "GET",
        $Body = $null
    )
    $uri = "$(Get-PushUrl)$Path"
    $params = @{ Uri = $uri; Method = $Method; ContentType = "application/json" }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Compress) }
    try { return Invoke-RestMethod @params -ErrorAction Stop }
    catch { return $null }
}

# ============================================================
# 断言
# ============================================================

function Assert-NotNull {
    param($Value, [string]$Message)
    if ($null -ne $Value) { Write-Pass $Message; return $true }
    else { Write-Fail $Message; return $false }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -eq $Actual) { Write-Pass $Message; return $true }
    else { Write-Fail "$Message (expected: $Expected, actual: $Actual)"; return $false }
}

function Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Message)
    if ($Haystack -like "*$Needle*") { Write-Pass $Message; return $true }
    else { Write-Fail "$Message (missing: $Needle)"; return $false }
}

function Assert-HttpOk {
    param($Response, [string]$Message)
    if ($null -ne $Response) { Write-Pass $Message; return $true }
    else { Write-Fail "$Message (request failed)"; return $false }
}

# ============================================================
# 结果汇总
# ============================================================

function Write-TestSummary {
    $elapsed = (Get-Date) - $script:TestStartTime
    $total = $script:PassCount + $script:FailCount + $script:SkipCount
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  测试结果汇总" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  总计: $total  通过: $($script:PassCount)  失败: $($script:FailCount)  跳过: $($script:SkipCount)" -ForegroundColor White
    Write-Host "  耗时: $([math]::Round($elapsed.TotalSeconds, 1))s" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    if ($script:FailCount -gt 0) {
        Write-Host "  结果: 失败" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "  结果: 通过" -ForegroundColor Green
        exit 0
    }
}
