#!/usr/bin/env python3
"""
全能内容理解 - Playwright 截图+内容提取
用法: python3 chrome-cdp-connect.py <url> [wait_seconds]
实测验证: 2026-05-15
"""
import sys
import os
import re
import time
import glob

PROXY = "http://172.23.32.1:7897"  # Windows Clash Verge（WSL可达）
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

def cleanup():
    """清理临时文件"""
    patterns = ["/tmp/sc_result.png", "/tmp/yt_sub*", "/tmp/bili_sub*",
                "/tmp/douyin_video*", "/tmp/page.md", "/tmp/*.srt", "/tmp/*.vtt"]
    for p in patterns:
        for f in glob.glob(p):
            try: os.remove(f)
            except: pass

def extract_with_playwright(url: str, wait: int = 8) -> dict:
    """Playwright 完整提取：截图 + 标题 + 正文"""
    from playwright.sync_api import sync_playwright

    cleanup()
    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=True,
            args=[
                '--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu',
                '--disable-blink-features=AutomationControlled',
                f'--proxy-server={PROXY}'
            ]
        )
        ctx = browser.new_context(user_agent=UA)
        page = ctx.new_page()

        page.goto(url, timeout=30000, wait_until="domcontentloaded")
        time.sleep(wait)

        # 截图
        sc_bytes = page.screenshot(full_page=True)
        sc_path = '/mnt/c/temp/sc_result.png'
        with open(sc_path, 'wb') as f:
            f.write(sc_bytes)

        title = page.title()
        body = page.inner_text('body')
        body = re.sub(r'\s+', ' ', body).strip()

        browser.close()
        return {
            "title": title,
            "body": body,
            "body_len": len(body),
            "screenshot": sc_path,
            "screenshot_size": len(sc_bytes)
        }

def check_chrome_debug_port():
    """检测 Windows Chrome 调试端口是否可用（通过 PowerShell）"""
    import subprocess
    r = subprocess.run(
        ['powershell.exe', '-Command',
         "try { Invoke-RestMethod -Uri 'http://localhost:9222/json' -UseBasicParsing -TimeoutSec 3 | Out-Null; exit 0 } catch { exit 1 }"],
        capture_output=True, timeout=10
    )
    return r.returncode == 0

def ensure_chrome_running():
    """确保 Windows Chrome 调试端口开启（调用 PowerShell 脚本）"""
    import subprocess
    r = subprocess.run(
        ['powershell.exe', '-ExecutionPolicy', 'Bypass',
         '-File', 'C:\\temp\\ensure_chrome.ps1'],
        capture_output=True, timeout=30
    )
    output = r.stdout.decode('utf-8', errors='replace').strip()
    return output.startswith("STARTED") or output.startswith("ALREADY_RUNNING")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python3 chrome-cdp-connect.py <url> [wait_seconds]")
        sys.exit(1)

    url = sys.argv[1]
    wait = int(sys.argv[2]) if len(sys.argv) > 2 else 8

    print(f"目标: {url}")
    print(f"等待: {wait}s | 代理: {PROXY}")

    try:
        result = extract_with_playwright(url, wait=wait)
        print(f"\n=== 结果 ===")
        print(f"标题: {result['title']}")
        print(f"正文: {result['body_len']} 字")
        print(f"截图: {result['screenshot_size']} bytes → {result['screenshot']}")
        print(f"\n正文预览:\n{result['body'][:300]}")
        cleanup()
    except Exception as e:
        print(f"❌ 提取失败: {e}")
        sys.exit(1)
