"""压缩包目录预览：zip / tar.gz / 加密 / 损坏 / zip-slip 文件名 / 权限 / 分享"""
import io
import tarfile
import zipfile

import pytest
from fastapi.testclient import TestClient
from app.main import create_app, preview_kind


@pytest.fixture()
def client(tmp_path):
    c = TestClient(create_app(data_dir=str(tmp_path), allow_register=True))
    assert c.post("/api/register", json={"username": "alice", "password": "demo123"}).status_code == 200
    return c


def up(c, name, data, vis="private"):
    r = c.post("/upload_file", data={"visibility": vis, "expires_in": "0"}, files={"file": (name, data)})
    assert r.status_code == 200, r.text
    return r.json()["uuid"]


def make_zip(entries, encrypted_flag=False):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in entries:
            z.writestr(name, data)
    b = buf.getvalue()
    if encrypted_flag:  # 把所有条目的「加密」标志位置 1（列目录不需要密码；条目内容我们永不读取）
        b = bytearray(b)
        for sig, off in ((b"PK\x03\x04", 6), (b"PK\x01\x02", 8)):
            i = 0
            while (i := b.find(sig, i)) != -1:
                b[i + off] |= 1
                i += 4
        b = bytes(b)
    return b


def make_tgz(entries, mode="w:gz"):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode=mode) as tf:
        for name, data in entries:
            if name.endswith("/"):
                ti = tarfile.TarInfo(name.rstrip("/"))
                ti.type = tarfile.DIRTYPE
                tf.addfile(ti)
            else:
                ti = tarfile.TarInfo(name)
                ti.size = len(data)
                tf.addfile(ti, io.BytesIO(data))
    return buf.getvalue()


def test_kind_is_archive():
    for n in ["a.zip", "a.JAR", "a.apk", "a.tar", "a.tar.gz", "a.tgz", "a.tar.bz2", "a.tar.xz", "a.7z", "a.rar"]:
        assert preview_kind(n) == "archive", n
    assert preview_kind("a.docx") is None and preview_kind("a.gz") is None


def test_zip_listing(client):
    uid = up(client, "pkg.zip", make_zip([("docs/", b""), ("docs/a.txt", b"hello"), ("b.bin", b"x" * 1000)]))
    r = client.get(f"/api/items/{uid}/archive")
    assert r.status_code == 200
    d = r.json()
    assert d["type"] == "zip" and d["total"] == 3 and d["truncated"] is False and d["total_size"] == 1005
    by = {e["path"]: e for e in d["entries"]}
    assert by["docs/"]["is_dir"] is True and by["docs/a.txt"]["size"] == 5 and by["b.bin"]["size"] == 1000
    assert d["encrypted"] is False


def test_tar_gz_and_variants(client):
    entries = [("src/", b""), ("src/main.py", b"print(1)"), ("README", b"hi")]
    for name, mode in (("a.tar.gz", "w:gz"), ("a.tgz", "w:gz"), ("a.tar.bz2", "w:bz2"), ("a.tar.xz", "w:xz"), ("a.tar", "w")):
        uid = up(client, name, make_tgz(entries, mode))
        d = client.get(f"/api/items/{uid}/archive").json()
        assert d["type"] == "tar" and d["total"] == 3, name
        assert {e["path"] for e in d["entries"]} == {"src", "src/main.py", "README"}, name
        assert next(e for e in d["entries"] if e["path"] == "src")["is_dir"] is True


def test_truncation_at_2000(client):
    uid = up(client, "many.zip", make_zip([(f"f{i}.txt", b"") for i in range(2105)]))
    d = client.get(f"/api/items/{uid}/archive").json()
    assert d["truncated"] is True and len(d["entries"]) == 2000 and d["total"] == 2105
    uid = up(client, "many.tar.gz", make_tgz([(f"f{i}.txt", b"") for i in range(2105)]))
    d = client.get(f"/api/items/{uid}/archive").json()
    assert d["truncated"] is True and len(d["entries"]) == 2000


def test_encrypted_zip_flagged(client):
    uid = up(client, "enc.zip", make_zip([("secret.txt", b"top secret")], encrypted_flag=True))
    d = client.get(f"/api/items/{uid}/archive").json()
    assert d["encrypted"] is True and d["entries"][0]["encrypted"] is True and d["entries"][0]["path"] == "secret.txt"


@pytest.mark.parametrize("name", ["bad.zip", "bad.tar.gz", "bad.tar", "bad.tar.xz"])
def test_corrupt_is_graceful(client, name):
    uid = up(client, name, b"this is definitely not an archive" * 20)
    r = client.get(f"/api/items/{uid}/archive")
    assert r.status_code == 422 and "损坏" in r.text


def test_truncated_zip_graceful(client):
    uid = up(client, "cut.zip", make_zip([("a.txt", b"x" * 100)])[:40])
    assert client.get(f"/api/items/{uid}/archive").status_code == 422


def test_7z_rar_not_supported_message(client):
    for n in ("a.7z", "a.rar"):
        uid = up(client, n, b"Rar!\x1a\x07\x00")
        r = client.get(f"/api/items/{uid}/archive")
        assert r.status_code == 415 and "暂不支持" in r.text


def test_zip_slip_names_are_displayed_not_used(client, tmp_path):
    evil = [("../../etc/passwd", b"x"), ("/abs/path.txt", b"y"), ("a/../../b.txt", b"z"), ("e\u202etxt.exe", b"w"), ("<img src=x onerror=alert(1)>", b"v")]
    uid = up(client, "evil.zip", make_zip(evil))
    d = client.get(f"/api/items/{uid}/archive").json()
    paths = [e["path"] for e in d["entries"]]
    assert "../../etc/passwd" in paths and "/abs/path.txt" in paths      # 原样展示（纯文本）
    assert all("\u202e" not in p for p in paths)                          # bidi 覆盖字符被剔除
    assert "<img src=x onerror=alert(1)>" in paths                        # 前端用 textContent，不会当 HTML
    # 不会写出任何文件：数据目录里只有我们上传的那个文件
    assert not (tmp_path.parent / "etc").exists()
    assert sorted(p.name for p in (tmp_path / "uploads").iterdir()) == ["evil.zip"]


def test_private_access_blocked(client):
    uid = up(client, "p.zip", make_zip([("a.txt", b"1")]), vis="private")
    pub = up(client, "pub.zip", make_zip([("a.txt", b"1")]), vis="public")
    client.post("/api/logout")
    assert client.get(f"/api/items/{uid}/archive").status_code == 403
    assert client.get(f"/api/items/{pub}/archive").status_code == 200   # 公共的访客可看目录
    client.post("/api/register", json={"username": "bob", "password": "demo123"})
    assert client.get(f"/api/items/{uid}/archive").status_code == 403
    assert client.get("/api/items/doesnotexist/archive").status_code == 404


def test_text_item_has_no_archive(client):
    uid = client.post("/content", json={"content": "hi", "visibility": "private"}).json()["uuid"]
    assert client.get(f"/api/items/{uid}/archive").status_code == 404


def test_share_token_archive_and_expiry(client):
    uid = up(client, "s.zip", make_zip([("a.txt", b"1")]), vis="private")
    token = client.post(f"/api/items/{uid}/share", json={"hours": 1}).json()["token"]
    client.post("/api/logout")
    d = client.get(f"/s/{token}/archive").json()
    assert d["total"] == 1
    assert client.get("/s/nope/archive").status_code == 404
    assert client.get(f"/api/share/{token}").json()["preview"] == "archive"


def test_expired_share_archive_404(client):
    uid = up(client, "s.zip", make_zip([("a.txt", b"1")]))
    token = client.post(f"/api/items/{uid}/share", json={"hours": 1}).json()["token"]
    client.app.state.store.update_item(uid, share_expires_at=1.0)
    client.post("/api/logout")
    assert client.get(f"/s/{token}/archive").status_code == 404


def test_no_entry_content_endpoint(client):
    uid = up(client, "x.zip", make_zip([("a.txt", b"SECRET-CONTENT")]))
    r = client.get(f"/api/items/{uid}/archive")
    assert "SECRET-CONTENT" not in r.text
    assert client.get(f"/api/items/{uid}/archive/a.txt").status_code == 404
