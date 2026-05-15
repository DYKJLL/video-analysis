# ensure_chrome.ps1 - 检查并启动 Chrome 调试端口
param(
    [int]$Port = 9222,
    [string]$UserDataDir = "C:\temp\hermes-chrome-debug"
)

$ErrorActionPreference = 'SilentlyContinue'

# Check if port already has Chrome debug
$existing = Invoke-RestMethod -Uri "http://localhost:$Port/json" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
if ($existing -and $existing[0].webSocketDebuggerUrl) {
    $wsUrl = $existing[0].webSocketDebuggerUrl
    Write-Output "ALREADY_RUNNING|$Port|$wsUrl"
    exit 0
}

# Try to start Chrome
$chromePath = "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromePath)) {
    Write-Output "CHROME_NOT_FOUND"
    exit 1
}

$proc = Start-Process -FilePath $chromePath -ArgumentList @(
    "--remote-debugging-port=$Port",
    "--remote-debugging-address=127.0.0.1",
    "--no-first-run",
    "--no-default-browser-check",
    "--user-data-dir=$UserDataDir"
) -PassThru -WindowStyle Hidden

Start-Sleep -Seconds 3

# Verify it started
$verify = Invoke-RestMethod -Uri "http://localhost:$Port/json" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
if ($verify -and $verify[0].webSocketDebuggerUrl) {
    $wsUrl = $verify[0].webSocketDebuggerUrl
    Write-Output "STARTED|$Port|$wsUrl"
    exit 0
}

Write-Output "START_FAILED"
exit 1
