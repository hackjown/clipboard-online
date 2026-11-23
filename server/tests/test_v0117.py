"""v0.1.17 综合功能测试：分享提取码/阅后即焚、图片缩略图、图片剪贴板同步、扫码配对、回收站/批量/ZIP、文件改名备注/CSV预览、空间统计/备份ZIP/E2EE条目"""
import base64
import io
import json
import zipfile

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app, preview_kind


@pytest.fixture()
def client(tmp_path):
    c = TestClient(create_app(data_dir=str(tmp_path), allow_register=True))
    assert c.post("/api/register", json={"username": "alice", "password": "demo123"}).status_code == 200
    return c


def _png_bytes(size=(800, 600), color=(40, 140, 220)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return buf.getvalue()


def test_share_password_and_burn_after_reading(client):
    uid = client.post("/content", json={"content": "机密口令-XYZ", "visibility": "private"}).json()["uuid"]
    sh = client.post(f"/api/items/{uid}/share", json={"hours": 1, "password": "8888", "max_views": 1}).json()
    tok = sh["token"]
    assert sh["has_password"] is True and sh["max_views"] == 1

    client.post("/api/logout")
    # 无密码 / 错密码：锁定且绝不泄漏正文
    r0 = client.get(f"/api/share/{tok}").json()
    assert r0["locked"] is True and "content" not in r0
    r_bad = client.get(f"/api/share/{tok}", headers={"X-Share-Password": "0000"}).json()
    assert r_bad["locked"] is True and "content" not in r_bad

    # 正确提取码：成功查看并消耗唯一 1 次
    r_ok = client.get(f"/api/share/{tok}", headers={"X-Share-Password": "8888"})
    assert r_ok.status_code == 200 and r_ok.json()["content"] == "机密口令-XYZ" and r_ok.json()["views_left"] == 0

    # 再次访问已焚毁
    assert client.get(f"/api/share/{tok}", headers={"X-Share-Password": "8888"}).status_code == 404

    # 文件分享提取码 + 限 1 次下载
    client.post("/api/login", json={"username": "alice", "password": "demo123"})
    fid = client.post("/upload_file", data={"visibility": "private"}, files={"file": ("doc.txt", b"secret-file")}).json()["uuid"]
    ftok = client.post(f"/api/items/{fid}/share", json={"hours": 1, "password": "ab12", "max_views": 1}).json()["token"]
    client.post("/api/logout")
    assert client.get(f"/s/{ftok}/file").status_code == 403
    dl1 = client.get(f"/s/{ftok}/file?p=ab12")
    assert dl1.status_code == 200 and dl1.content == b"secret-file"
    assert client.get(f"/s/{ftok}/file?p=ab12").status_code == 404


def test_image_thumbnail_and_image_clipsync(client):
    png = _png_bytes((1000, 800))
    uid = client.post("/upload_file", data={"visibility": "private"}, files={"file": ("photo.png", png)}).json()["uuid"]
    it = client.get("/api/items", params={"scope": "private"}).json()["items"][0]
    assert it["thumb_url"] == f"/api/items/{uid}/thumb"

    tr = client.get(f"/api/items/{uid}/thumb")
    assert tr.status_code == 200 and tr.headers["content-type"].startswith("image/webp")
    im = Image.open(io.BytesIO(tr.content))
    assert max(im.size) <= 480

    # 私有缩略图他人不可访问
    client.post("/api/logout")
    assert client.get(f"/api/items/{uid}/thumb").status_code == 403

    # 图片剪贴板同步
    client.post("/api/login", json={"username": "alice", "password": "demo123"})
    hdr = {"X-Device-Id": "mac_dev_001"}
    r1 = client.post("/api/clipsync", headers=hdr, json={"kind": "image", "image_b64": base64.b64encode(png).decode()})
    assert r1.status_code == 200 and r1.json()["duplicate"] is False and r1.json()["clip"]["kind"] == "image"
    r2 = client.post("/api/clipsync", headers=hdr, json={"kind": "image", "image_b64": base64.b64encode(png).decode()})
    assert r2.status_code == 200 and r2.json()["duplicate"] is True
    img_resp = client.get("/api/clipsync/image")
    assert img_resp.status_code == 200 and img_resp.headers["content-type"].startswith("image/png")


def test_qr_pair_login_single_use(client):
    p = client.post("/api/pair/create")
    assert p.status_code == 200
    d = p.json()
    assert d["uri"].startswith("clipboard://pair?server=") and d["code"] in d["uri"]
    qr = client.get(d["qr_url"])
    assert qr.status_code == 200 and qr.headers["content-type"].startswith("image/png")

    # 登出后用配对码认领登录
    client.post("/api/logout")
    assert client.get("/api/me").json()["user"] is None
    cl = client.post("/api/pair/claim", json={"code": d["code"]})
    assert cl.status_code == 200 and cl.json()["user"]["username"] == "alice" and cl.json()["token"]
    assert client.get("/api/me").json()["user"]["username"] == "alice"

    # 一次性失效
    assert client.post("/api/pair/claim", json={"code": d["code"]}).status_code == 404


def test_trash_restore_batch_and_zip(client):
    u1 = client.post("/content", json={"content": "hello one", "visibility": "private"}).json()["uuid"]
    u2 = client.post("/upload_file", data={"visibility": "private"}, files={"file": ("a.txt", b"file-body")}).json()["uuid"]

    # 软删除 -> 进回收站 -> 撤销恢复
    dr = client.post("/delete", json={"uuid": u1})
    assert dr.status_code == 200 and dr.json()["trashed"] is True
    assert all(x["uuid"] != u1 for x in client.get("/api/items", params={"scope": "private"}).json()["items"])
    tr = client.get("/api/trash").json()["items"]
    assert len(tr) == 1 and tr[0]["uuid"] == u1

    rr = client.post(f"/api/trash/{u1}/restore")
    assert rr.status_code == 200
    assert any(x["uuid"] == u1 for x in client.get("/api/items", params={"scope": "private"}).json()["items"])

    # 批量加标签 + 打包下载 ZIP
    bt = client.post("/api/items/batch", json={"action": "tag", "uuids": [u1, u2], "tags": ["项目A"]})
    assert bt.status_code == 200 and bt.json()["affected"] == 2
    zr = client.post("/api/items/zip", json={"uuids": [u1, u2]})
    assert zr.status_code == 200 and zr.headers["content-type"].startswith("application/zip")
    with zipfile.ZipFile(io.BytesIO(zr.content)) as zf:
        names = zf.namelist()
        assert "a.txt" in names and any(n.endswith(".txt") and n != "a.txt" for n in names)

    # 批量删除 + 清空回收站
    assert client.post("/api/items/batch", json={"action": "delete", "uuids": [u1, u2]}).json()["affected"] == 2
    assert client.post("/api/trash/empty").json()["removed"] == 2
    assert client.get("/api/trash").json()["items"] == []


def test_file_rename_note_and_csv_preview(client):
    assert preview_kind("data.csv") == "office" and preview_kind("data.tsv") == "office"
    csv_bytes = "姓名,分数\n张三,98\n李四,92\n".encode("utf-8-sig")
    uid = client.post("/upload_file", data={"visibility": "private"}, files={"file": ("scores.csv", csv_bytes)}).json()["uuid"]

    pv = client.get(f"/api/items/{uid}/office").json()
    assert pv["type"] == "csv" and pv["sheets"][0]["rows"] == [["姓名", "分数"], ["张三", "98"], ["李四", "92"]]

    # 文件重命名 + 备注 + 搜索备注
    ed = client.patch(f"/api/items/{uid}", json={"filename": "期末成绩.csv", "note": "2026秋季统计"})
    assert ed.status_code == 200 and ed.json()["item"]["filename"] == "期末成绩.csv" and ed.json()["item"]["note"] == "2026秋季统计"
    found = client.get("/api/items", params={"scope": "private", "q": "秋季统计"}).json()["items"]
    assert len(found) == 1 and found[0]["uuid"] == uid


def test_account_stats_export_and_e2ee_item(client):
    client.post("/content", json={"content": '{"v":1,"ct":"abc"}', "visibility": "private", "encrypted": True})
    client.post("/upload_file", data={"visibility": "private"}, files={"file": ("note.bin", b"123456")})
    client.put("/api/vault", json={
        "version": 1, "kdf": "PBKDF2-SHA256", "iterations": 200000,
        "salt": base64.b64encode(b"S" * 16).decode(), "iv": base64.b64encode(b"I" * 12).decode(),
        "ct": base64.b64encode(b"C" * 32).decode(), "item_count": 5, "expected_rev": 0,
    })

    st = client.get("/api/account/stats").json()
    assert st["total_items"] == 2 and st["text_items"] == 1 and st["file_items"] == 1
    assert st["vault_exists"] is True and st["vault_items"] == 5

    exp = client.get("/api/account/export")
    assert exp.status_code == 200 and exp.headers["content-type"].startswith("application/zip")
    with zipfile.ZipFile(io.BytesIO(exp.content)) as zf:
        names = set(zf.namelist())
        assert {"items.json", "vault_encrypted.json", "files/note.bin"} <= names
        meta = json.loads(zf.read("items.json"))
        assert any(i.get("encrypted") is True for i in meta["items"])
