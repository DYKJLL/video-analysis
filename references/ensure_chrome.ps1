# ensure_chrome.ps1 — 检查并启动 Chrome 调试端口（用于 CDP 连接）
# 放在 references/ 目录，技能代码通过 C:\temp\ensure_chrome.ps1 调用
# 使用方式：powershell.exe -ExecutionPolicy Bypass -File "C:\temp\ensure_chrome.ps1"
param(
    [int]$Port = 9222,
    [string]$UserDataDir = "C:\temp\hermes-chrome-debug"
)

$ErrorActionPreference = 'SilentlyContinue'

# 1. 检查端口是否已有 Chrome 调试
try {
    $existing = Invoke-RestMethod -Uri "http://localhost:$Port/json" -UseBasicParsing -TimeoutSec 3
    if ($existing) {
        $wsUrl = $existing[0].webSocketDebuggerUrl
        Write-Output "ALREADY_RUNNING|$Port|$wsUrl"
        exit 0
    }
} catch {
    # 端口未开，继续启动
}

# 2. 检查 Chrome 进程是否已存在（用户未开调试端口但 Chrome 在运行）
$chromePath = "C:\Users\liud\AppData\Local\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromePath)) {
    $chromePath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
}
if (-not (Test-Path $chromePath)) {
    Write-Output "ERROR: Chrome not found at expected paths"
    exit 1
}

# 3. 启动 Chrome（独立 user-data-dir，避免与主 Chrome 冲突）
$args = @(
    "--remote-debugging-port=$Port",
    "--remote-debugging-address=0.0.0.0",
    "--no-first-run",
    "--no-default-browser-check",
    "--user-data-dir=$UserDataDir"
)
$proc = Start-Process -FilePath $chromePath -ArgumentList $args -PassThru

Start-Sleep -Seconds 3

# 4. 验证启动成功
try {
    $verify = Invoke-RestMethod -Uri "http://localhost:$Port/json" -UseBasicParsing -TimeoutSec 5
    $wsUrl = $verify[0].webSocketDebuggerUrl
    if ($wsUrl) {
        Write-Output "STARTED|$Port|$wsUrl"
        exit 0
    }
} catch { }

Write-Output "STARTED|$Port|"
exit 0
