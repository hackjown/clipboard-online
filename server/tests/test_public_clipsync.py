"""v0.1.12：公共区上传回归 + 多设备剪贴板同步（clipsync / devices）。"""
import asyncio
import time

import pytest
from fastapi.testclient import TestClient

from app.main import Hub, create_app

D1 = "dev-aaaaaaaa-1111"
D2 = "dev-bbbbbbbb-2222"


@pytest.fixture()
def c(tmp_path):
    app = create_app(data_dir=str(tmp_path), allow_register=True)
    with TestClient(app) as cl:
        assert cl.post("/api/register", json={"username": "alice", "password": "pass1234"}).status_code == 200
        yield cl


def guest_public(tmp_client):
    tmp_client.cookies.clear()
    return tmp_client.get("/api/items", params={"scope": "public"}).json()["items"]


# ---------- 公共区上传 ----------
def test_public_text_and_file_upload_visible_to_guests(c):
    r = c.post("/content", json={"content": "公共文本", "visibility": "public"})
    assert r.status_code == 200 and r.json()["visibility"] == "public"
    assert r.json()["expires_at"] and r.json()["expires_at"] - time.time() > 86000  # 公共默认 24h
    r2 = c.post("/upload_file", data={"visibility": "public", "expires_in": "3600"}, files={"file": ("p.txt", b"pub")})
    assert r2.status_code == 200 and r2.json()["visibility"] == "public"
    # 客户端常见的大小写 / 空白
    r3 = c.post("/upload_file", data={"visibility": " Public "}, files={"file": ("q.txt", b"q")})
    assert r3.json()["visibility"] == "public"
    items = guest_public(c)
    names = {i.get("content") or i.get("filename") for i in items}
    assert {"公共文本", "p.txt", "q.txt"} <= names


def test_public_upload_not_blocked_by_stuck_websocket():
    """一个卡死的 WebSocket（如睡眠手机的半开连接）不能让公共广播 / 上传请求挂住或失败。"""
    hub = Hub()

    class Stuck:
        async def send_json(self, _):
            await asyncio.sleep(30)

    class Ok:
        def __init__(self):
            self.got = []

        async def send_json(self, e):
            self.got.append(e)

    class Boom:
        async def send_json(self, _):
            raise RuntimeError("closed")

    ok = Ok()
    hub.clients = [(Stuck(), None), (ok, None), (Boom(), "u1")]
    t0 = time.time()
    asyncio.run(hub.broadcast({"type": "create"}, public=True))
    assert time.time() - t0 < 5
    assert ok.got == [{"type": "create"}]
    assert len(hub.clients) == 1  # 卡死与报错的连接都被清理


def test_web_add_sheet_defaults_follow_scope():
    js = open("app/static/app.js", encoding="utf-8").read()
    assert "const defVis = scopeVis();" in js and "visToggle(defVis)" in js
    assert "fd.append('visibility', u.vis === 'public' ? 'public' : 'private')" in js


# ---------- 设备 ----------
def test_devices_register_list_direction_delete(c):
    h1 = {"X-Device-Id": D1}
    r = c.put(f"/api/devices/{D1}", json={"name": "MacBook", "platform": "macos", "direction": "both"}, headers=h1)
    assert r.status_code == 200 and r.json()["device"]["current"] is True
    c.put(f"/api/devices/{D2}", json={"name": "iPhone", "platform": "ios", "direction": "recv"})
    devs = c.get("/api/devices", headers=h1).json()["devices"]
    assert [d["name"] for d in devs][0] == "MacBook"
    assert {d["device_id"]: d["direction"] for d in devs} == {D1: "both", D2: "recv"}
    assert c.put(f"/api/devices/{D1}", json={"direction": "sideways"}).status_code == 400
    assert c.put("/api/devices/bad id", json={}).status_code in (400, 404)
    # 名字不传则保留
    c.put(f"/api/devices/{D1}", json={"direction": "send"})
    d1 = [d for d in c.get("/api/devices").json()["devices"] if d["device_id"] == D1][0]
    assert d1["name"] == "MacBook" and d1["direction"] == "send"
    assert c.delete(f"/api/devices/{D2}").status_code == 200
    assert c.delete(f"/api/devices/{D2}").status_code == 404


def test_devices_are_per_user(c):
    c.put(f"/api/devices/{D1}", json={"name": "A"})
    c.post("/api/logout")
    c.post("/api/register", json={"username": "bobby", "password": "pass1234"})
    assert c.get("/api/devices").json()["devices"] == []
    c.cookies.clear()
    assert c.get("/api/devices").status_code == 401


def test_online_flag_via_websocket(c):
    c.put(f"/api/devices/{D1}", json={"name": "A"})
    with c.websocket_connect(f"/ws?device={D1}") as ws:
        assert ws.receive_json()["type"] == "hello"
        devs = c.get("/api/devices").json()["devices"]
        assert devs[0]["online"] is True
    time.sleep(0.2)
    assert c.get("/api/devices").json()["devices"][0]["online"] is False


# ---------- 剪贴板同步 ----------
def test_clipsync_broadcast_dedup_history_and_direction(c):
    c.put(f"/api/devices/{D1}", json={"name": "Mac", "direction": "both"})
    c.put(f"/api/devices/{D2}", json={"name": "Phone", "direction": "recv"})
    with c.websocket_connect(f"/ws?device={D2}") as ws:
        ws.receive_json()  # hello
        r = c.post("/api/clipsync", json={"text": "复制的内容"}, headers={"X-Device-Id": D1})
        assert r.status_code == 200 and r.json()["duplicate"] is False and r.json()["uuid"]
        evs = [ws.receive_json(), ws.receive_json()]
        clip = [e for e in evs if e["type"] == "clip"][0]
        assert clip["text"] == "复制的内容" and clip["origin"] == D1 and clip["origin_name"] == "Mac"
        create = [e for e in evs if e["type"] == "create"][0]
        assert create["source"] == "clipsync" and create["visibility"] == "private"
    # 同内容再次复制：不重复传播、不重复记历史
    r2 = c.post("/api/clipsync", json={"text": "复制的内容"}, headers={"X-Device-Id": D1})
    assert r2.json()["duplicate"] is True
    priv = c.get("/api/items", params={"scope": "private"}).json()["items"]
    assert [i["content"] for i in priv].count("复制的内容") == 1
    # 只接收的设备不能发送
    assert c.post("/api/clipsync", json={"text": "x"}, headers={"X-Device-Id": D2}).status_code == 403
    # 最新一条（LWW：后写覆盖）
    c.post("/api/clipsync", json={"text": "第二条", "save_history": False}, headers={"X-Device-Id": D1})
    latest = c.get("/api/clipsync").json()["clip"]
    assert latest["text"] == "第二条" and latest["origin"] == D1
    assert "第二条" not in [i["content"] for i in c.get("/api/items", params={"scope": "private"}).json()["items"]]


def test_clipsync_validation_and_isolation(c):
    assert c.post("/api/clipsync", json={"text": "x"}).status_code == 400  # 缺 X-Device-Id
    h = {"X-Device-Id": D1}
    assert c.post("/api/clipsync", json={"text": "  "}, headers=h).status_code == 400
    assert c.post("/api/clipsync", json={"text": "a" * (512 * 1024 + 1)}, headers=h).status_code == 413
    c.post("/api/clipsync", json={"text": "alice secret"}, headers=h)
    # 公共区看不到同步历史
    assert "alice secret" not in [i.get("content") for i in c.get("/api/items", params={"scope": "public"}).json()["items"]]
    c.post("/api/logout")
    c.post("/api/register", json={"username": "bobby", "password": "pass1234"})
    assert c.get("/api/clipsync").json()["clip"] is None
    with c.websocket_connect("/ws") as ws:  # bob 收不到 alice 的 clip
        ws.receive_json()
        c.post("/api/clipsync", json={"text": "bob 的"}, headers={"X-Device-Id": D2})
        e = ws.receive_json()
        assert e["type"] in ("clip", "create") and (e.get("text") in (None, "bob 的"))
