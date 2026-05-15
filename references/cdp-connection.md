# Chrome DevTools CDP 连接方案（2026-05-15 实测，v1.5.1 更新）

> 核心原理：连接 Windows Chrome（已登录各平台），通过 CDP 协议控制浏览器导航/截图/取快照，绕过所有平台反爬和登录限制。**不需要任何额外登录、Cookie 或 API Key。**

---

## ⚠️ WSL 网络限制（重要发现 v1.4，v1.5.1 修正）

**问题**：WSL 直接连接 Windows Chrome 调试端口（`172.23.32.1:9222`）会失败——TCP 三次握手成功，但 Chrome 返回 **空响应（exit code 52）**，HTTP 请求被防火墙拦截。

**网络架构图（v1.5.1 修正）**：
```
WSL (172.23.37.x)
  ├─ 172.23.32.1:7897 → Windows Clash Verge ✅（HTTP/SOCKS5代理，可访问外网）
  └─ 172.23.32.1:9222 → Windows Chrome调试端口 ❌（TCP可达，HTTP被防火墙拦）
       PowerShell → localhost:9222 → [::1]:9222 (IPv6) → ✅ 同一机器，无防火墙问题
```

**关键修正**：`172.23.32.1:7897`（Windows Clash Verge）WSL 可正常连接，用于 Playwright/yt-dlp 代理出口。Chrome debug 端口（9222）仍被拦，需通过 PowerShell 中转或 Playwright 独立浏览器解决。

---

## 完整连接流程

### 1. 启动 Chrome 并开放调试端口

**PowerShell（每次使用前执行）**：
```powershell
Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Process 'C:\Users\liud\AppData\Local\Google\Chrome\Application\chrome.exe' -ArgumentList '--remote-debugging-port=9222','--remote-debugging-address=0.0.0.0','--no-first-run','--no-default-browser-check','--user-data-dir=C:\temp\chrome-debug'
```

> `--user-data-dir=C:\temp\chrome-debug` **必须指定**，否则 Chrome 拒绝开启调试模式（默认 profile 被锁定）。

### 2. 验证端口可用

```powershell
# PowerShell 本地验证（最可靠）
Invoke-RestMethod -Uri 'http://localhost:9222/json' -UseBasicParsing

# WSL 直接验证 9222（被防火墙拦，不可用）
curl -s http://172.23.32.1:9222/json

# WSL 验证代理 7897（✅ 可用）
curl -s --proxy http://172.23.32.1:7897 https://github.com
```

### 3. Windows 防火墙放行（可选，让 WSL 直连）

```powershell
New-NetFirewallRule -DisplayName "Chrome Remote Debugging" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9222 -Program "C:\Users\liud\AppData\Local\Google\Chrome\Application\chrome.exe" -EdgeTraversalPolicy Allow
```

> 即使创建此规则，WSL 直连 9222 仍可能失败。**推荐始终使用 PowerShell 中转或 Playwright 独立浏览器**。

### 4. PowerShell 中转 CDP（备用方法）

所有 CDP 操作通过 `powershell.exe` 执行：
```bash
powershell.exe -Command "Invoke-RestMethod -Uri 'http://localhost:9222/json' -UseBasicParsing | ConvertFrom-Json | ConvertTo-Json -Compress"
```

WebSocket CDP 操作（内容提取、截图）见 SKILL.md Section 3.2-3.3。

---

## 自动检测 + 启动脚本

**推荐**：使用 PowerShell 脚本 `references/ensure_chrome.ps1`（自动检测端口 + 启动 Chrome）：

```python
import subprocess

def ensure_chrome_running():
    r = subprocess.run(
        ['powershell.exe', '-ExecutionPolicy', 'Bypass',
         '-File', 'C:\\temp\\ensure_chrome.ps1'],
        capture_output=True, timeout=30
    )
    output = r.stdout.decode('utf-8', errors='replace').strip()
    # 输出格式: STARTED|9222|ws://localhost:9222/... 或 ALREADY_RUNNING|9222|ws://...
    return output.startswith("STARTED") or output.startswith("ALREADY_RUNNING")
```

**Python subprocess 启动 Chrome 不靠谱**：从 WSL 调用 Windows exe 路径解析会失败。务必用 PowerShell 脚本。

---

## 平台实测结果（2026-05-15 v1.5 全流程验证）

| 平台 | URL | 截图 | 正文 | 方案 | 结果 |
|------|-----|------|------|------|------|
| 抖音 | `7633032163209879012` | ✅ 220KB | ✅ 6896字 | Playwright | 内容全提取，含章节+评论+统计 |
| Bilibili | `BV1Et421V7ij` | ✅ 816KB | ✅ 1130字 | Playwright | 标题+时间戳 |
| YouTube | `dQw4w9WgXcQ` | ✅ 740KB | ✅ 2670字 | Playwright+代理 | 标题+统计+字幕 |
| X/Twitter | `OpenAI/status/...` | ✅ 579KB | ✅ 1481字 | Playwright+代理 | 个人资料+简介 |
| 小红书 | `xhslink.com/...` | ✅ 2.5MB | ⚠️ 需登录 | Playwright+代理 | 截图正常，正文需登录态 |

---

## 关键Bug修复（2026-05-15）

### Bug 1: PowerShell WebSocket receive 返回值误解

```powershell
$r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $ct)
$r.Wait(500)  # ❌ 返回布尔值，不等于收到了数据
```

**正确写法**：
```powershell
$r = $ws.ReceiveAsync([ArraySegment[byte]]$buf, $ct)
if ($r.Wait(500) -eq $false) { continue }  # 方法未完成，继续等待
$received = $r.Result.Count               # ✅ 从 Result.Count 取实际字节数
if ($received -eq 0) { break }             # 对端关闭连接
```

### Bug 2: PowerShell 终端中文编码乱码

**现象**：stdout 中文乱码，但文件写入的数据实际正确。

**解法**：不用 stdout 传回，改用临时文件：
```powershell
[System.IO.File]::WriteAllBytes("C:\temp\cdp_out.json", $buffer[0..($endPos-1)])
```
Python 读取：`with open("/mnt/c/temp/cdp_out.json", 'rb') as f: raw = f.read()`

### Bug 3: Chrome 路径错误

**错误**：`C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe`（不存在）
**正确**：`C:\\Users\\liud\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe`

### Bug 4: CDP WebSocket 多JSON对象拼接（2026-05-15 v1.5 新发现）

**现象**：PowerShell WebSocket 收到多个 CDP 响应拼接在一起，如：
```
{"id":1,"result":{...}}{"id":2,"result":{...}}
```
直接 `JSON.parse()` 会报 `Extra data` 错误。

**解法**：`}{` → `},{` 替换后包装成 JSON 数组：
```python
text = raw.decode('utf-8', errors='replace')
fixed = text.replace('}{', '},{')
arr = json.loads(f'[{fixed}]')  # JSON 数组
for obj in arr:
    if obj.get('id') == target_id:
        val = obj['result']['result']['value']
```

### Bug 5: `ensure_chrome_running()` Python subprocess 启动 Windows Chrome 不可靠

**原因**：Python `subprocess.Popen` 从 WSL 调用 Windows exe 路径解析失败。
**解法**：用 PowerShell 脚本 `C:\\temp\\ensure_chrome.ps1`（见 `references/ensure_chrome.ps1`）。

---

## 已知限制

1. **截图功能**：✅ **已解决（v1.5）**——Playwright `page.screenshot()` 接管截图，实测220KB一次成功
2. **YouTube**：需要 Windows Clash Verge 代理（`172.23.32.1:7897`）开启
3. **X/Twitter**：未登录状态只能看公开内容；CDP 可复用 Chrome 已有登录态
4. **Chrome 必须开着**：调试端口在 Chrome 关闭后失效
5. **小红书**：正文提取需要登录态，截图功能正常（2.5MB），登录墙可被 CDP 复用 Cookie 绕过
6. **mihomo Reality 节点**：WSL 内置 mihomo（`/mnt/d/AI/hermes-agent/proxy/`）的 VLESS Reality 节点可能与 curl/requests 不兼容（TLS 握手失败），使用 `172.23.32.1:7897` Windows Clash Verge 代理更可靠
