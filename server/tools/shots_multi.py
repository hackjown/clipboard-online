"""多用户演示截图。"""
import os, time
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:8099"
OUT = Path(__file__).resolve().parent.parent / "shots"
OUT.mkdir(exist_ok=True)
CHROME = "/usr/bin/google-chrome"

def shot(page, name):
    page.screenshot(path=OUT / name)
    ov = page.evaluate("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    print(name, "overflowX=", ov)

with sync_playwright() as p:
    br = p.chromium.launch(executable_path=CHROME, args=["--no-sandbox"])
    for vname, vp, mobile in (("mobile", (390, 844), True), ("desktop", (1280, 800), False)):
        ctx = br.new_context(viewport={"width": vp[0], "height": vp[1]}, color_scheme="light",
                             device_scale_factor=2 if mobile else 1, is_mobile=mobile, has_touch=mobile,
                             locale="zh-CN", timezone_id="Asia/Shanghai")
        pg = ctx.new_page()
        # guest public
        pg.goto(BASE)
        pg.wait_for_function("() => window.__clip && window.__clip.state.loaded")
        pg.evaluate("window.__clip.setScope('public', {force:true})")
        pg.wait_for_selector(".card")
        pg.wait_for_timeout(800)
        shot(pg, f"{vname}-light-public-guest.png")
        # login sheet
        pg.evaluate("window.__clip.openAuth('login')")
        pg.wait_for_selector(".auth-form")
        pg.wait_for_timeout(500)
        shot(pg, f"{vname}-light-login.png")
        # register sheet
        pg.evaluate("window.__clip.openAuth('register')")
        pg.wait_for_selector(".auth-form")
        pg.wait_for_timeout(500)
        shot(pg, f"{vname}-light-register.png")
        pg.keyboard.press("Escape")
        pg.wait_for_timeout(400)
        # login as demo1 via UI
        pg.evaluate("window.__clip.openAuth('login')")
        pg.fill("#authUser", "demo1")
        pg.fill("#authPw", "demo123")
        pg.click(".auth-form button[type=submit]")
        pg.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username === 'demo1'")
        pg.wait_for_timeout(500)
        # private
        pg.evaluate("window.__clip.setScope('private', {force:true})")
        pg.wait_for_timeout(800)
        shot(pg, f"{vname}-light-private-user.png")
        # public as logged-in (shows delete on own)
        pg.evaluate("window.__clip.setScope('public', {force:true})")
        pg.wait_for_selector(".card")
        pg.wait_for_timeout(700)
        shot(pg, f"{vname}-light-public-user.png")
        # add sheet with visibility
        pg.evaluate("window.__clip.openAdd('text')")
        pg.wait_for_selector(".vistog")
        pg.fill(".sheet textarea", "登录后添加的示例文本")
        pg.wait_for_timeout(500)
        shot(pg, f"{vname}-light-add.png")
        pg.keyboard.press("Escape")
        ctx.close()
    br.close()
print("done")
