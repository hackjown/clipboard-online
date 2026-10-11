from playwright.sync_api import sync_playwright
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "shots"
OUT.mkdir(exist_ok=True)
BASE = "http://127.0.0.1:8099"
for p in OUT.glob("*.png"):
    p.unlink()

def shot(pg, name):
    pg.screenshot(path=OUT / name)
    ov = pg.evaluate("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    print(name, "ov=", ov)

CHROME = "/usr/bin/google-chrome"

with sync_playwright() as p:
    br = p.chromium.launch(executable_path=CHROME, args=["--no-sandbox"])
    views = [("mobile", (390, 844), True), ("desktop", (1280, 800), False)]
    for vname, vp, mobile in views:
        ctx = br.new_context(
            viewport={"width": vp[0], "height": vp[1]},
            color_scheme="light",
            device_scale_factor=2 if mobile else 1,
            is_mobile=mobile,
            has_touch=mobile,
            locale="zh-CN",
        )
        pg = ctx.new_page()
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(BASE)
        pg.wait_for_function("() => window.__clip && window.__clip.state.loaded")
        pg.evaluate("window.__clip.setScope('public', {force:true})")
        pg.wait_for_selector(".card")
        pg.wait_for_timeout(700)
        shot(pg, f"{vname}-public.png")
        pg.evaluate("window.__clip.openAuth('login')")
        pg.fill("#authUser", "demo1")
        pg.fill("#authPw", "demo123")
        pg.click(".auth-form button[type=submit]")
        pg.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username==='demo1'")
        pg.wait_for_timeout(500)
        pg.evaluate("window.__clip.setScope('private', {force:true})")
        pg.wait_for_timeout(800)
        shot(pg, f"{vname}-private.png")
        pg.evaluate("window.__clip.setScope('public', {force:true})")
        pg.wait_for_timeout(800)
        shot(pg, f"{vname}-images.png")
        pg.evaluate("window.__clip.openAdd('text')")
        pg.wait_for_selector(".exprow")
        pg.click(".vistog-btn[data-vis='public']")
        pg.wait_for_timeout(300)
        shot(pg, f"{vname}-add-expiry.png")
        pg.fill(".sheet textarea", "sk-abcdefghijklmnopqrstuvwxyz0123456789")
        pg.click(".sheet .row-between .btn--accent")
        pg.wait_for_timeout(500)
        print(vname, "sheet:", pg.inner_text(".sheet h2"))
        shot(pg, f"{vname}-sensitive.png")
        pg.keyboard.press("Escape")
        pg.wait_for_timeout(400)
        pg.evaluate("window.__clip.setScope('public', {force:true})")
        pg.wait_for_timeout(600)
        if pg.locator(".md-toggle").count():
            pg.locator(".md-toggle").first.click()
            pg.wait_for_timeout(400)
            shot(pg, f"{vname}-markdown.png")
        pg.evaluate("""async () => {
          const it = window.__clip.state.items.find(i => i.mine && i.is_image) || window.__clip.state.items.find(i => i.mine);
          if (it) await window.__clip.openShare(it);
        }""")
        pg.wait_for_selector(".qr-wrap")
        pg.wait_for_timeout(700)
        shot(pg, f"{vname}-share-qr.png")
        pg.keyboard.press("Escape")
        pg.wait_for_timeout(300)
        pg.evaluate("window.__clip.setStarred(true)")
        pg.wait_for_timeout(700)
        shot(pg, f"{vname}-favorites.png")
        if errs:
            print(vname, "pageerrors", errs[:3])
        ctx.close()
    br.close()
print("done")
