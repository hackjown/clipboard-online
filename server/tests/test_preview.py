"""文件预览：Range/206、白名单内联、危险类型强制下载、私有鉴权、分享链接预览"""
import pytest
from fastapi.testclient import TestClient
from app.main import create_app, preview_kind


@pytest.fixture()
def client(tmp_path):
    return TestClient(create_app(data_dir=str(tmp_path), allow_register=True))


def reg(c, user):
    r = c.post("/api/register", json={"username": user, "password": "demo123"})
    assert r.status_code == 200, r.text


def up(c, name, data, vis="private"):
    r = c.post("/upload_file", data={"visibility": vis, "expires_in": "0"}, files={"file": (name, data)})
    assert r.status_code == 200, r.text
    return r.json()


def test_preview_kind_whitelist():
    assert preview_kind("a.PNG") == "image" and preview_kind("a.mp4") == "video"
    assert preview_kind("a.mp3") == "audio" and preview_kind("a.pdf") == "pdf" and preview_kind("a.json") == "text"
    assert preview_kind("a.html") is None and preview_kind("a.svg") is None and preview_kind("a") is None


def test_range_returns_206(client):
    reg(client, "alice")
    data = bytes(range(256)) * 40
    up(client, "clip.mp4", data)
    r = client.get("/download/clip.mp4?inline=1", headers={"Range": "bytes=10-19"})
    assert r.status_code == 206
    assert r.content == data[10:20]
    assert r.headers["content-range"] == f"bytes 10-19/{len(data)}"
    assert r.headers["content-type"].startswith("video/mp4")
    assert r.headers["content-disposition"].startswith("inline")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers.get("accept-ranges") == "bytes"
    full = client.get("/download/clip.mp4?inline=1")
    assert full.status_code == 200 and full.content == data


def test_audio_and_pdf_inline(client):
    reg(client, "alice")
    up(client, "a.mp3", b"ID3" + b"\0" * 50)
    up(client, "d.pdf", b"%PDF-1.4 test")
    a = client.get("/download/a.mp3?inline=1")
    assert a.headers["content-type"].startswith("audio/mpeg") and a.headers["content-disposition"].startswith("inline")
    p = client.get("/download/d.pdf?inline=1")
    assert p.headers["content-type"].startswith("application/pdf") and p.headers["content-disposition"].startswith("inline")
    assert "frame-ancestors 'self'" in p.headers["content-security-policy"]
    assert p.headers["x-frame-options"] == "SAMEORIGIN"


@pytest.mark.parametrize("name", ["x.svg", "x.html", "x.htm", "x.xhtml", "x.exe"])
def test_dangerous_types_forced_attachment(client, name):
    reg(client, "alice")
    up(client, name, b"<script>alert(1)</script>")
    for q in ("", "?inline=1"):
        r = client.get(f"/download/{name}{q}")
        assert r.status_code == 200
        assert r.headers["content-disposition"].startswith("attachment"), (name, q)
        ct = r.headers["content-type"]
        assert "html" not in ct and "svg" not in ct
        assert r.headers["x-content-type-options"] == "nosniff"
        assert "sandbox" in r.headers["content-security-policy"]


def test_client_declared_mime_not_trusted(client):
    reg(client, "alice")
    r = client.post("/upload_file", data={"visibility": "private", "expires_in": "0"},
                    files={"file": ("evil.bin", b"<html>", "text/html")})
    assert r.status_code == 200
    d = client.get("/download/evil.bin?inline=1")
    assert d.headers["content-disposition"].startswith("attachment") and "html" not in d.headers["content-type"]


def test_text_served_as_plain(client):
    reg(client, "alice")
    up(client, "note.txt", b"<img src=x onerror=alert(1)>")
    up(client, "cfg.json", b'{"a":1}')
    r = client.get("/download/note.txt?inline=1")
    assert r.headers["content-type"].startswith("text/plain")
    assert r.headers["content-disposition"].startswith("inline")
    assert "sandbox" in r.headers["content-security-policy"]
    assert client.get("/download/cfg.json?inline=1").headers["content-type"].startswith("text/plain")


def test_private_inline_blocked_for_others(client):
    reg(client, "alice")
    up(client, "p.png", b"\x89PNG\r\n\x1a\n" + b"0" * 20, vis="private")
    up(client, "pub.png", b"\x89PNG\r\n\x1a\n" + b"1" * 20, vis="public")
    assert client.get("/download/p.png?inline=1").status_code == 200
    client.post("/api/logout")
    assert client.get("/download/p.png?inline=1").status_code == 403
    assert client.get("/download/p.png?inline=1", headers={"Range": "bytes=0-3"}).status_code == 403
    assert client.get("/download/pub.png?inline=1").status_code == 200  # 公共对访客可预览
    reg(client, "bob")
    assert client.get("/download/p.png?inline=1").status_code == 403
    assert client.get("/download/pub.png?inline=1").status_code == 200


def test_items_expose_preview_kind(client):
    reg(client, "alice")
    up(client, "v.mp4", b"0" * 10)
    up(client, "z.zip", b"PK")
    its = {i["filename"]: i for i in client.get("/api/items", params={"scope": "private"}).json()["items"]}
    assert its["v.mp4"]["preview"] == "video" and its["z.zip"]["preview"] is None


def test_share_link_preview(client):
    reg(client, "alice")
    uid = up(client, "clip.mp4", b"A" * 100)["uuid"]
    token = client.post(f"/api/items/{uid}/share", json={"hours": 1}).json()["token"]
    client.post("/api/logout")
    meta = client.get(f"/api/share/{token}").json()
    assert meta["preview"] == "video"
    r = client.get(f"/s/{token}/file?inline=1", headers={"Range": "bytes=0-9"})
    assert r.status_code == 206 and r.content == b"A" * 10
    assert r.headers["content-type"].startswith("video/mp4")
    assert client.get("/s/badtoken/file?inline=1").status_code == 404


def test_expired_share_not_previewable(client):
    reg(client, "alice")
    uid = up(client, "pic.png", b"\x89PNG" + b"0" * 10)["uuid"]
    token = client.post(f"/api/items/{uid}/share", json={"hours": 1}).json()["token"]
    # 手动让分享过期
    client.app.state.store.update_item(uid, share_expires_at=1.0)
    client.post("/api/logout")
    assert client.get(f"/s/{token}/file?inline=1").status_code == 404
    assert client.get(f"/api/share/{token}").status_code == 404


def test_static_preview_assets(client):
    assert client.get("/static/preview.js").status_code == 200
    assert client.get("/static/share.js").status_code == 200
    html = client.get("/").text
    assert "/static/preview.js" in html
