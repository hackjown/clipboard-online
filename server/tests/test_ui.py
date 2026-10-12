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


def test_preview_modal_and_share_page(page, server):
    """上传两张图 + 一个文本：弹出预览、左右切换、Esc 关闭；分享页脚本可运行（CSP 无内联脚本）。"""
    page.evaluate("window.__clip.openAuth('register')")
    page.wait_for_selector("#authUser")
    page.fill("#authUser", "pvuser")
    page.fill("#authPw", "demo1234")
    page.click(".auth-form button[type=submit]")
    page.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username === 'pvuser'")
    png = ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==")
    res = page.evaluate("""async (b64) => {
      const bin = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
      const out = [];
      for (const n of ['a.png','b.png']) {
        const fd = new FormData(); fd.append('file', new Blob([bin], {type:'image/png'}), n);
        fd.append('visibility','public'); fd.append('expires_in','0');
        out.push((await (await fetch('/upload_file',{method:'POST',body:fd,credentials:'same-origin'})).json()).uuid);
      }
      const fd = new FormData(); fd.append('file', new Blob(['<b>hi</b> & code'], {type:'text/plain'}), 'n.txt');
      fd.append('visibility','public'); fd.append('expires_in','0');
      await fetch('/upload_file',{method:'POST',body:fd,credentials:'same-origin'});
      await window.__clip.refreshScoped();
      const r = await fetch('/api/items/'+out[0]+'/share',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},body:'{"hours":1}'});
      return (await r.json()).token;
    }""", png)
    page.evaluate("window.__clip.setScope('public', {force:true})")
    page.wait_for_selector(".thumb")
    page.click(".thumb >> nth=0")
    page.wait_for_selector(".pv .pv-img")
    first = page.inner_text(".pv-title")
    page.keyboard.press("ArrowRight")
    assert page.inner_text(".pv-title") != first
    page.keyboard.press("Escape")
    assert page.locator(".pv").count() == 0
    # 文本文件预览：纯文本，不解析 HTML
    page.click("text=预览 >> nth=0")
    page.wait_for_selector(".pv")
    page.keyboard.press("Escape")
    # 分享页
    page.goto(f"{server}/s/{res}")
    page.wait_for_selector("#pvimg")
    assert page.locator(".share-card .fname").count() == 1


def test_file_input_has_no_accept_and_archive_viewer(page, server):
    """上传面板的 <input type=file>：无 accept、可多选；压缩包预览显示目录树（纯文本渲染）。"""
    page.evaluate("window.__clip.openAuth('register')")
    page.wait_for_selector("#authUser")
    page.fill("#authUser", "arcuser")
    page.fill("#authPw", "demo1234")
    page.click(".auth-form button[type=submit]")
    page.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username === 'arcuser'")
    page.evaluate("window.__clip.openAdd('file')")
    page.wait_for_selector("#fileInput", state="attached")
    assert page.get_attribute("#fileInput", "accept") is None
    assert page.get_attribute("#fileInput", "multiple") is not None
    # 静态检查：源码里不应再出现带 accept 的 file input
    src = (ROOT / "app/static/app.js").read_text()
    assert "type: 'file'" in src and "accept:" not in src.split("type: 'file'")[1].split("\n")[0]
    # 上传一个 zip（含类 XSS 文件名）并在预览里看到目录
    import io, zipfile
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("docs/readme.txt", "hi")
        z.writestr("<img src=x onerror=window.__xss=1>", "x")
    page.evaluate("""async (arr) => {
      const fd = new FormData(); fd.append('file', new Blob([new Uint8Array(arr)]), 'pack.zip');
      fd.append('visibility','private'); fd.append('expires_in','0');
      await fetch('/upload_file',{method:'POST',body:fd,credentials:'same-origin'});
      await window.__clip.refreshScoped();
    }""", list(buf.getvalue()))
    page.click("#sheet .scrim", position={"x": 5, "y": 5})
    page.wait_for_function("() => document.querySelector('#sheet').hidden")
    page.evaluate("window.__clip.setScope('private', {force:true})")
    page.wait_for_selector("text=pack.zip")
    page.click(".card--file >> text=预览")
    page.wait_for_selector(".pv-arch .pv-nm")
    txt = page.inner_text(".pv-arch")
    assert "readme.txt" in txt and "<img src=x" in txt and "2 项" in txt
    assert page.evaluate("window.__xss") is None
    page.keyboard.press("Escape")
    assert page.locator(".pv").count() == 0


def test_edit_text_via_ui(page, server):
    page.evaluate("window.__clip.openAuth('register')")
    page.wait_for_selector("#authUser")
    page.fill("#authUser", "edituser")
    page.fill("#authPw", "demo1234")
    page.click(".auth-form button[type=submit]")
    page.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username === 'edituser'")
    page.evaluate("""async () => {
      await fetch('/content',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({content:'旧内容',visibility:'private'})});
      await window.__clip.refreshScoped();
    }""")
    page.evaluate("window.__clip.setScope('private', {force:true})")
    page.wait_for_selector(".card--text")
    page.click(".card--text .btn--edit")
    page.wait_for_selector(".edit-ta")
    assert page.input_value(".edit-ta") == "旧内容"
    page.fill(".edit-ta", "新内容 v2")
    page.press(".edit-ta", "Control+Enter")
    page.wait_for_function("() => document.body.innerText.includes('新内容 v2')")
    assert "旧内容" not in page.inner_text(".card--text")


def test_public_scope_add_and_upload_go_public(page, server):
    """回归：在「公共」区打开添加面板，默认就是公共；上传的文件也进公共区（之前总默认私有并跳去私有区）。"""
    page.evaluate("window.__clip.openAuth('register')")
    page.wait_for_selector("#authUser")
    page.fill("#authUser", "pubuser")
    page.fill("#authPw", "demo1234")
    page.click(".auth-form button[type=submit]")
    page.wait_for_function("() => window.__clip.state.user && window.__clip.state.user.username === 'pubuser'")
    page.evaluate("window.__clip.setScope('public', {force:true})")
    page.evaluate("window.__clip.openAdd('text')")
    page.wait_for_selector(".vistog-btn[data-vis=public][aria-checked=true]")
    labels = page.eval_on_selector_all(".exprow button", "els => els.map(e => e.textContent)")
    assert labels == ["1小时", "1天", "7天", "30天", "永不过期"]
    assert page.inner_text(".exprow button[aria-checked=true]") == "1天"  # 公共默认 1 天
    page.wait_for_timeout(500)
    page.eval_on_selector(".vistog-btn[data-vis=private]", "e => e.click()")
    assert page.inner_text(".exprow button[aria-checked=true]") == "永不过期"  # 私有默认永不过期
    page.eval_on_selector(".vistog-btn[data-vis=public]", "e => e.click()")
    page.evaluate("() => [...document.querySelectorAll('.exprow button')].find((b) => b.textContent === '7天').click()")
    page.fill("textarea.ta", "公共区回归文本")
    page.keyboard.press("Control+Enter")
    page.wait_for_function("() => document.body.innerText.includes('公共区回归文本')")
    assert page.evaluate("window.__clip.state.scope") == "public"
    page.evaluate("window.__clip.openAdd('file')")
    page.set_input_files("#fileInput", files=[{"name": "pub-reg.txt", "mimeType": "text/plain", "buffer": b"hi"}])
    page.wait_for_timeout(300)
    page.evaluate("() => { const b = [...document.querySelectorAll('.btn--block')].find((x) => !x.hidden && x.textContent.trim() === '上传'); if (b) b.click(); }")
    page.wait_for_function("() => document.body.innerText.includes('pub-reg.txt')", timeout=10000)
    items = api(server, "/api/items?scope=public")[0]["items"]
    vis = {(i.get("content") or i.get("filename")): i["visibility"] for i in items}
    assert vis.get("公共区回归文本") == "public" and vis.get("pub-reg.txt") == "public"
    exp = {(i.get("content") or i.get("filename")): i["expires_at"] for i in items}
    import time as _t
    assert 6.9 * 86400 < exp["公共区回归文本"] - _t.time() <= 7 * 86400  # 选了 7 天
