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
    assert r.json()["expires_at"] and r.json()["expires_at"] - time.time() > 86000  # 公共默认 1 天
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


# ---------- v0.1.13：上传时选择过期时间 ----------
@pytest.mark.parametrize("vis", ["public", "private"])
@pytest.mark.parametrize("sec", [3600, 86400, 604800, 2592000])
def test_expiry_param_on_text_and_file(c, vis, sec):
    r = c.post("/content", json={"content": f"t{sec}{vis}", "visibility": vis, "expires_in": sec}).json()
    assert r["visibility"] == vis and abs(r["expires_at"] - time.time() - sec) < 10
    f = c.post("/upload_file", data={"visibility": vis, "expires_in": str(sec)}, files={"file": (f"f{sec}.txt", b"x")}).json()
    assert f["visibility"] == vis and abs(f["expires_at"] - time.time() - sec) < 10


def test_defaults_public_1day_private_never_and_explicit_never(c):
    for raw in (None, "", -1):
        pb = {"content": f"p{raw}", "visibility": "public"}
        vb = {"content": f"v{raw}", "visibility": "private"}
        if raw is not None:
            pb["expires_in"] = vb["expires_in"] = raw
        e = c.post("/content", json=pb).json()["expires_at"]
        assert 86300 < e - time.time() <= 86400
        assert c.post("/content", json=vb).json()["expires_at"] is None
    e = c.post("/upload_file", data={"visibility": "public"}, files={"file": ("d.txt", b"x")}).json()["expires_at"]
    assert 86300 < e - time.time() <= 86400
    # 公共也可以明确选「永不过期」
    assert c.post("/content", json={"content": "pn", "visibility": "public", "expires_in": 0}).json()["expires_at"] is None
    assert c.post("/upload_file", data={"visibility": "public", "expires_in": "0"}, files={"file": ("n.txt", b"x")}).json()["expires_at"] is None


def test_expiry_capped_and_config_presets(c):
    r = c.post("/content", json={"content": "long", "visibility": "public", "expires_in": 10 ** 9}).json()
    assert r["expires_at"] - time.time() <= 366 * 86400 + 5
    cfg = c.get("/api/config").json()
    assert cfg["expiry_default"] == {"public": 86400, "private": 0}
    assert [p["sec"] for p in cfg["expiry_presets"]] == [3600, 86400, 604800, 2592000, 0]




# ---------- v0.1.14：心跳 / 实例 ID / 跨设备可见 ----------
def test_ws_ping_pong_and_hello_device(c):
    c.put(f"/api/devices/{D1}", json={"name": "Mac"})
    with c.websocket_connect(f"/ws?device={D1}") as ws:
        h = ws.receive_json()
        assert h["type"] == "hello" and h["device"] == D1 and h["user_id"]
        ws.send_text("ping")
        assert ws.receive_json()["type"] == "pong"


def test_instance_id_stable_and_in_devices(tmp_path):
    app1 = create_app(data_dir=str(tmp_path), allow_register=True)
    with TestClient(app1) as cl:
        cl.post("/api/register", json={"username": "alice", "password": "pass1234"})
        i1 = cl.get("/api/version").json()["instance"]
        d = cl.get("/api/devices").json()
        assert d["instance"] == i1 and d["user"] == "alice" and len(i1) == 8
    with TestClient(create_app(data_dir=str(tmp_path), allow_register=True)) as cl2:
        assert cl2.get("/api/version").json()["instance"] == i1  # 同一数据目录：实例 ID 不变
    other = tmp_path / "other"
    with TestClient(create_app(data_dir=str(other), allow_register=True)) as cl3:
        assert cl3.get("/api/version").json()["instance"] != i1  # 另一份数据：不同


def test_three_devices_same_account_see_each_other_and_ios_to_mac(c):
    """复现用户场景：Mac 在线收、iOS 发、Android 登记；同账号同实例时三台互相可见，Mac 收到 iOS 的复制。"""
    mac, ios, android = "m" * 32, "i" * 32, "a" * 32
    for d, n, plat in ((mac, "我的 Mac", "macos"), (ios, "tuo的 iPhone", "ios"), (android, "zumin的 Android", "android")):
        assert c.put(f"/api/devices/{d}", json={"name": n, "platform": plat, "direction": "both"}, headers={"X-Device-Id": d}).status_code == 200
    names_from_mac = {x["name"] for x in c.get("/api/devices", headers={"X-Device-Id": mac}).json()["devices"]}
    assert names_from_mac == {"我的 Mac", "tuo的 iPhone", "zumin的 Android"}
    with c.websocket_connect(f"/ws?device={mac}") as ws:
        ws.receive_json()
        c.post("/api/clipsync", json={"text": "iOS 复制"}, headers={"X-Device-Id": ios})
        got = [ws.receive_json(), ws.receive_json()]
        assert any(e["type"] == "clip" and e["text"] == "iOS 复制" and e["origin"] == ios for e in got)
    # 断线期间错过推送 → 客户端重连后 GET /api/clipsync 能补到
    assert c.get("/api/clipsync").json()["clip"]["text"] == "iOS 复制"


def test_other_account_does_not_see_devices(c):
    c.put(f"/api/devices/{D1}", json={"name": "Mac"})
    c.post("/api/logout")
    c.post("/api/register", json={"username": "zumin2", "password": "pass1234"})
    c.put(f"/api/devices/{D2}", json={"name": "Android"})
    assert [d["name"] for d in c.get("/api/devices").json()["devices"]] == ["Android"]  # 账号不同 = 互不可见（用户现场现象）
