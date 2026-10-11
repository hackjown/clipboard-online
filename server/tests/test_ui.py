"""浏览器端到端（需 playwright + Chrome）。"""
import json, os, subprocess, sys, time, urllib.request
from pathlib import Path
import pytest

pw = pytest.importorskip("playwright.sync_api")
ROOT = Path(__file__).resolve().parent.parent
CHROME = next((p for p in ("/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser") if os.path.exists(p)), None)
PORT = 8130


@pytest.fixture(scope="module")
def server(tmp_path_factory):
    d = tmp_path_factory.mktemp("uidata")
    p = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app", "--port", str(PORT), "--log-level", "warning"],
                         cwd=ROOT, env=dict(os.environ, CLIP_DATA_DIR=str(d)))
    for _ in range(50):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{PORT}/api/config"); break
        except Exception:
            time.sleep(.2)
    yield f"http://127.0.0.1:{PORT}"
    p.terminate()


def api(server, path, body=None, cookie=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(server + path, data=data, headers={"Content-Type": "application/json"} if body is not None else {}, method="POST" if body is not None else "GET")
    if cookie:
        req.add_header("Cookie", cookie)
    with urllib.request.urlopen(req) as r:
        ck = r.headers.get("Set-Cookie")
        return json.load(r), ck


@pytest.fixture()
def page(server):
    with pw.sync_playwright() as p:
        b = p.chromium.launch(executable_path=CHROME, args=["--no-sandbox"]) if CHROME else p.chromium.launch()
        ctx = b.new_context(viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True,
                            permissions=["clipboard-read", "clipboard-write"])
        pg = ctx.new_page()
        pg.goto(server)
        pg.wait_for_function("() => window.__clip && window.__clip.state")
        yield pg
        b.close()


def test_guest_sees_public_login_cta(page, server):
    # seed via API
    _, ck = api(server, "/api/register", {"username": "seedguest", "password": "demo1234"})
    cookie = ck.split(";")[0]
    api(server, "/content", {"content": "公开演示文本", "visibility": "public"}, cookie)
    api(server, "/content", {"content": "我的私密", "visibility": "private"}, cookie)
    page.goto(server)
    page.wait_for_function("() => window.__clip && window.__clip.state.loaded")
    page.evaluate("window.__clip.setScope('public', {force:true})")
    page.wait_for_selector(".card--text")
    assert "公开演示" in page.inner_text("#list")
    assert "我的私密" not in page.content()
    page.evaluate("window.__clip.setScope('private')")
    page.wait_for_selector("#empty:not([hidden])")
    assert "登录" in page.inner_text("#empty")
    page.evaluate("window.__clip.openAdd('text')")
    page.wait_for_selector(".auth-form")
    assert "登录" in page.inner_text(".sheet h2")


def test_owner_delete_visibility(page, server):
    page.evaluate("window.__clip.openAuth('register')")
    page.wait_for_selector("#authUser")
    page.fill("#authUser", "owner1")
    page.fill("#authPw", "demo1234")
    page.click(".auth-form button[type=submit]")
    page.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username === 'owner1'")
    page.evaluate("""async () => {
      await fetch('/content',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({content:'可删内容',visibility:'public'})});
      await window.__clip.refreshScoped();
    }""")
    page.wait_for_selector(".card--text")
    assert page.locator(".card--text .btn--del").count() >= 1
    page.click(".card--text .btn--del")
    page.click(".sheet .btn--danger")
    page.wait_for_function("() => !document.querySelector('.card--text') || !document.body.innerText.includes('可删内容')")
