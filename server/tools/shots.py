"""生成演示截图（需要 playwright + Chrome/Chromium）。
用法: python tools/shots.py [输出目录]   —— 全部使用虚构的示例数据。"""
import json, os, socket, subprocess, sys, time, urllib.request
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "shots"); OUT.mkdir(parents=True, exist_ok=True)
PORT = 8100; BASE = f"http://127.0.0.1:{PORT}"
DATA = Path("/tmp/clip_demo_data")
CHROME = next((p for p in ("/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser") if os.path.exists(p)), None)

def post(path, body):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))

def upload(name, data):
    b = "----x"; body = (f'--{b}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n').encode() + data + f"\r\n--{b}--\r\n".encode()
    req = urllib.request.Request(BASE + "/upload_file", data=body, headers={"Content-Type": f"multipart/form-data; boundary={b}"})
    return json.load(urllib.request.urlopen(req))

MEETING = """周五产品评审会 · 纪要（示例）
1. 新版首页改版方案通过，下周一开始排期
2. 导出功能延期一周，原因：第三方接口限流
3. 待办：@小林 整理用户访谈结论；@阿杰 更新设计规范 v2.3
4. 下次例会：周三 10:30，会议室 B
5. 风险：测试环境数据不足，需要补充 500 条样例数据
备注：以上均为演示文本，不含任何真实信息。"""
CMD = "docker run -d --name demo -p 8080:80 -v $(pwd)/data:/data nginx:alpine"
PROMPT = "请把下面这段话改写得更简洁、更有礼貌，保留所有数字和日期。"
JSON_ = '{\n  "name": "demo-app",\n  "version": "1.2.0",\n  "scripts": {\n    "dev": "vite",\n    "build": "vite build"\n  }\n}'
TOKEN = "demo_token_0000_aaaa_bbbb_cccc_1111_dddd"

def seed():
    post("/clear_clipboard", {"command": "clear"})
    now = time.time()
    specs = [("file", "report.pdf", b"%PDF demo" * 2000, 60 * 3), ("text", TOKEN, None, 60 * 9), ("file", "预算表-2026.xlsx", b"x" * 48000, 3600 * 2),
             ("text", MEETING, None, 3600 * 5), ("file", "cover.png", b"x" * 1_800_000, 86400 + 3600), ("text", CMD, None, 86400 * 2),
             ("file", "assets.zip", b"x" * 12_400_000, 86400 * 3), ("text", JSON_, None, 86400 * 4), ("text", PROMPT, None, 86400 * 5),
             ("file", "产品演示-最终版-v3-请勿外传-正式发布前再确认一次.mp4", b"x" * 22_000_000, 86400 * 6), ("file", "main.py", b"print(1)" * 100, 86400 * 8)]
    for kind, v, data, ago in reversed(specs):
        post("/content", {"content": v}) if kind == "text" else upload(v, data)
    items = json.load(open(DATA / "items.json"))
    # items 按插入顺序 = specs 反序，写入对应时间
    for it, (k, v, d, ago) in zip(items, reversed(specs)):
        it["created"] = now - ago
    json.dump(items, open(DATA / "items.json", "w"), ensure_ascii=False)

def main():
    import shutil; shutil.rmtree(DATA, ignore_errors=True)
    env = dict(os.environ, CLIP_DATA_DIR=str(DATA))
    srv = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app", "--port", str(PORT), "--log-level", "warning"], cwd=ROOT, env=env)
    for _ in range(50):
        try: urllib.request.urlopen(BASE + "/api/config"); break
        except Exception: time.sleep(.2)
    try:
        with sync_playwright() as p:
            br = p.chromium.launch(executable_path=CHROME, args=["--no-sandbox"])
            for vname, vp, mobile in (("mobile", (390, 844), True), ("desktop", (1280, 800), False)):
                for theme in ("light", "dark"):
                    seed()
                    ctx = br.new_context(viewport={"width": vp[0], "height": vp[1]}, color_scheme=theme, device_scale_factor=2 if mobile else 1,
                                         is_mobile=mobile, has_touch=mobile, locale="zh-CN", timezone_id="Asia/Shanghai")
                    pg = ctx.new_page(); errs = []
                    pg.on("pageerror", lambda e: errs.append(str(e))); pg.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
                    pg.goto(BASE); pg.wait_for_selector(".card"); pg.wait_for_timeout(1300)
                    pre = f"{vname}-{theme}"
                    pg.screenshot(path=OUT / f"{pre}-1-list.png")
                    # overflow check
                    ov = pg.evaluate("document.documentElement.scrollWidth - document.documentElement.clientWidth")
                    small = pg.evaluate("""[...document.querySelectorAll('button,a.btn,.navbtn,input,.seg button')].filter(e=>e.offsetParent&&(e.getBoundingClientRect().height<43.5)&&!e.matches('.skip,.dz input')).map(e=>e.className+':'+Math.round(e.getBoundingClientRect().height))""")
                    print(pre, "overflowX=", ov, "small-targets=", small[:6], "errors=", errs[:3])
                    # full page (all cards) — scrolled shot
                    pg.screenshot(path=OUT / f"{pre}-1b-full.png", full_page=True) if not mobile else None
                    # expand long card
                    # add sheet
                    pg.click(".fab" if mobile else ".side-actions .btn--accent"); pg.wait_for_selector(".sheet-root.open textarea")
                    pg.fill(".sheet textarea", "明天上午 10 点评审会，会议链接稍后补充。\n记得带上投影转接头。")
                    pg.wait_for_timeout(600); pg.screenshot(path=OUT / f"{pre}-2-add.png")
                    # upload in progress
                    pg.click(".tabs2 button:nth-child(3)")
                    cdp = ctx.new_cdp_session(pg); cdp.send("Network.enable")
                    cdp.send("Network.emulateNetworkConditions", {"offline": False, "latency": 40, "downloadThroughput": -1, "uploadThroughput": 400 * 1024})
                    pg.set_input_files(".dz input", [{"name": "季度汇报.pptx", "mimeType": "application/octet-stream", "buffer": b"p" * 3_000_000},
                                                  {"name": "photo.jpg", "mimeType": "image/jpeg", "buffer": b"j" * 500_000}])
                    pg.wait_for_timeout(300); pg.screenshot(path=OUT / f"{pre}-3a-queued.png") if False else None
                    pg.click(".sheet .btn--accent.btn--block"); pg.wait_for_timeout(3500)
                    pg.screenshot(path=OUT / f"{pre}-3-upload.png")
                    # close sheet -> pill visible
                    pg.keyboard.press("Escape"); pg.wait_for_timeout(600)
                    pg.screenshot(path=OUT / f"{pre}-3b-pill.png")
                    pg.evaluate("window.__clip.openAdd('file')"); pg.wait_for_timeout(300)
                    for r in pg.query_selector_all(".up .rm"): r.click(); pg.wait_for_timeout(100)
                    cdp.send("Network.emulateNetworkConditions", {"offline": False, "latency": 0, "downloadThroughput": -1, "uploadThroughput": -1})
                    pg.keyboard.press("Escape"); pg.wait_for_timeout(500)
                    # confirm delete
                    pg.click(".slot:nth-child(2) .btn--del"); pg.wait_for_selector(".sheet-root.open .btn--danger"); pg.wait_for_timeout(500)
                    pg.screenshot(path=OUT / f"{pre}-5-confirm.png")
                    pg.click(".sheet .btn:not(.btn--danger)"); pg.wait_for_timeout(500)
                    # clear menu
                    pg.click('.tabbar [data-act="clear-menu"]' if mobile else '.navbtn--danger'); pg.wait_for_selector(".pick"); pg.wait_for_timeout(500)
                    pg.screenshot(path=OUT / f"{pre}-6-clearmenu.png")
                    pg.keyboard.press("Escape"); pg.wait_for_timeout(500)
                    # search
                    pg.fill("#q", "会议"); pg.wait_for_timeout(500); pg.screenshot(path=OUT / f"{pre}-7-search.png"); pg.fill("#q", "")
                    # empty
                    post("/clear_clipboard", {"command": "clear"}); pg.evaluate("window.__clip.refresh()"); pg.wait_for_selector("#empty:not([hidden])"); pg.wait_for_timeout(700)
                    pg.screenshot(path=OUT / f"{pre}-4-empty.png")
                    ctx.close()
            br.close()
    finally:
        srv.terminate()

main()
