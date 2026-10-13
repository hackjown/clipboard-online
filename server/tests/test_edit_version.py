"""文本编辑 PATCH /api/items/{uuid}、版本 / features、Bark 地址形式与回退"""
import json
import time
from pathlib import Path

import httpx
import pytest
from fastapi.testclient import TestClient
from app.main import create_app, VERSION, FEATURES, bark_attempts


@pytest.fixture()
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("CLIP_MAX_TEXT_KB", "1")
    c = TestClient(create_app(data_dir=str(tmp_path), allow_register=True))
    assert c.post("/api/register", json={"username": "alice", "password": "demo123"}).status_code == 200
    return c


def mk(c, content="hello", vis="private", **kw):
    r = c.post("/content", json={"content": content, "visibility": vis, **kw})
    assert r.status_code == 200, r.text
    return r.json()["uuid"]


def test_version_and_features(env):
    assert VERSION == Path(__file__).resolve().parents[1].joinpath("app/VERSION").read_text().strip() == "0.1.16"
    for path in ("/api/version", "/api/config"):
        j = env.get(path).json()
        assert j["version"] == VERSION and {"bark", "archive", "edit"} <= set(j["features"])
    assert env.get("/openapi.json").json()["info"]["version"] == VERSION
    assert "edit" in FEATURES


def test_owner_can_edit_and_share_token_kept(env):
    uid = mk(env, "v1")
    tok = env.post(f"/api/items/{uid}/share", json={"hours": 1}).json()["token"]
    before = time.time()
    r = env.patch(f"/api/items/{uid}", json={"content": "v2 内容", "tags": ["a", "b"]})
    assert r.status_code == 200
    it = r.json()["item"]
    assert it["content"] == "v2 内容" and it["size"] == len("v2 内容".encode()) and it["tags"] == ["a", "b"]
    assert it["updated"] >= before and it["share_token"] == tok
    assert env.get(f"/api/share/{tok}").json()["content"] == "v2 内容"
    got = [i for i in env.get("/api/items").json()["items"] if i["uuid"] == uid][0]
    assert got["content"] == "v2 内容"


def test_edit_visibility_and_expiry(env):
    uid = mk(env, "x", "private")
    r = env.patch(f"/api/items/{uid}", json={"visibility": "public"}).json()["item"]
    assert r["visibility"] == "public" and r["expires_at"] is not None     # 公共默认 1 天
    r = env.patch(f"/api/items/{uid}", json={"expires_in": 0}).json()["item"]
    assert r["expires_at"] is None
    r = env.patch(f"/api/items/{uid}", json={"expires_in": 3600}).json()["item"]
    assert 3500 < r["expires_at"] - time.time() <= 3600


def test_edit_validation(env):
    uid = mk(env, "x")
    assert env.patch(f"/api/items/{uid}", json={"content": "   "}).status_code == 400
    assert env.patch(f"/api/items/{uid}", json={"content": "a" * 1025}).status_code == 413   # CLIP_MAX_TEXT_KB=1
    assert env.patch(f"/api/items/{uid}", json={}).status_code == 400
    assert env.patch(f"/api/items/{uid}", content=b"not json").status_code == 400
    assert env.get("/api/items").json()["items"][0]["content"] == "x"                         # 失败不改内容
    f = env.post("/upload_file", data={"visibility": "private"}, files={"file": ("a.bin", b"1")}).json()["uuid"]
    assert env.patch(f"/api/items/{f}", json={"content": "x"}).status_code == 400            # 文件不可编辑


def test_edit_permissions(env, tmp_path):
    uid = mk(env, "mine", "public")
    env.post("/api/logout")
    assert env.patch(f"/api/items/{uid}", json={"content": "hack"}).status_code == 401
    env.post("/api/register", json={"username": "bobby", "password": "demo123"})
    assert env.patch(f"/api/items/{uid}", json={"content": "hack"}).status_code == 403
    assert env.patch("/api/items/nope", json={"content": "x"}).status_code == 404
    env.post("/api/logout")
    env.post("/api/login", json={"username": "alice", "password": "demo123"})
    assert env.get("/api/items").json()["items"][0]["content"] == "mine"


def test_edit_expired_is_404(env):
    uid = mk(env, "soon", expires_in=3600)
    env.app.state.store.update_item(uid, expires_at=1.0)
    assert env.patch(f"/api/items/{uid}", json={"content": "late"}).status_code == 404


def test_edit_broadcasts_ws_update(env):
    uid = mk(env, "ws")
    with env.websocket_connect("/ws") as ws:
        assert ws.receive_json()["type"] == "hello"
        assert env.patch(f"/api/items/{uid}", json={"content": "ws2"}).status_code == 200
        msg = ws.receive_json()
        assert msg["type"] == "update" and msg["uuid"] == uid


# ---- Bark 地址形式 ----
class Rec:
    def __init__(self, plan):
        self.plan = plan   # {path: (status, json)}
        self.calls = []
        self.transport = httpx.MockTransport(self.h)

    def h(self, req):
        body = json.loads(req.content or b"{}")
        self.calls.append((req.url.path, body))
        st, js = self.plan.get(req.url.path, (404, {"code": 404, "message": "page not found"}))
        return httpx.Response(st, json=js)


def bark_env(tmp_path, plan):
    app = create_app(data_dir=str(tmp_path), allow_register=True, bark_allow_private=True)
    rec = Rec(plan)
    app.state.bark_transport = rec.transport
    c = TestClient(app)
    c.post("/api/register", json={"username": "alice", "password": "demo123"})
    return c, rec


@pytest.mark.parametrize("pasted", [
    "https://api.day.app/KEY1", "https://api.day.app/KEY1/", "https://api.day.app/KEY1/测试内容",
    "https://api.day.app/KEY1/标题/内容?group=x", "https://bark.self.host:8443/KEY1",
])
def test_pasted_forms_post_to_key(tmp_path, pasted):
    c, rec = bark_env(tmp_path, {"/KEY1": (200, {"code": 200, "message": "success"})})
    assert c.post("/api/settings/bark/test", json={"bark_url": pasted}).status_code == 200
    path, body = rec.calls[0]
    assert path == "/KEY1" and body["group"] == "clipboard" and "device_key" not in body


def test_fallback_to_push_endpoint_on_404(tmp_path):
    c, rec = bark_env(tmp_path, {"/push": (200, {"code": 200, "message": "success"})})
    assert c.post("/api/settings/bark/test", json={"bark_url": "https://api.day.app/KEY1"}).status_code == 200
    assert [p for p, _ in rec.calls] == ["/KEY1", "/push"]
    assert rec.calls[1][1]["device_key"] == "KEY1"


def test_bark_own_error_is_shown_not_retried(tmp_path):
    c, rec = bark_env(tmp_path, {"/KEY1": (400, {"code": 400, "message": "failed to get device token: bad key"})})
    r = c.post("/api/settings/bark/test", json={"bark_url": "https://api.day.app/KEY1"})
    assert r.status_code == 502
    assert "400" in r.json()["error"] and "failed to get device token" in r.json()["error"]
    assert len(rec.calls) == 1


def test_all_404_reports_bark_message(tmp_path):
    c, rec = bark_env(tmp_path, {})
    r = c.post("/api/settings/bark/test", json={"bark_url": "https://api.day.app/KEY1"})
    assert r.status_code == 502 and "404" in r.json()["error"] and "page not found" in r.json()["error"]


def test_bark_attempts_unit():
    a = bark_attempts("https://h.example/pre/KEY", {"title": "t"})
    assert [u for u, _ in a] == ["https://h.example/pre", "https://h.example/pre/KEY", "https://h.example/push"]
    assert bark_attempts("https://h.example", {"x": 1}) == [("https://h.example", {"x": 1})]


def test_unknown_route_detail_is_bare_not_found(env):
    """旧版服务器缺少路由时返回的就是这个裸文案；客户端据此提示「服务器版本过旧」。"""
    r = env.post("/api/settings/bark/nonexistent", json={})
    assert r.status_code == 404 and r.json()["detail"] == "Not Found"
