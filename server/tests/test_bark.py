"""Bark 推送：设置、测试推送、私有条目触发、设备排除、SSRF 防护（mock Bark 端点）"""
import json
import time

import httpx
import pytest
from fastapi.testclient import TestClient
from app.main import create_app, check_bark_url


class FakeBark:
    def __init__(self, status=200):
        self.calls = []
        self.status = status
        self.transport = httpx.MockTransport(self._h)

    def _h(self, req: httpx.Request) -> httpx.Response:
        self.calls.append((str(req.url), json.loads(req.content or b"{}")))
        return httpx.Response(self.status, json={"code": self.status, "message": "success"})

    def wait(self, n=1, t=3.0):
        end = time.time() + t
        while time.time() < end and len(self.calls) < n:
            time.sleep(0.05)
        return self.calls


BARK = "https://bark.example.com/KEY123"


@pytest.fixture()
def env(tmp_path):
    app = create_app(data_dir=str(tmp_path), allow_register=True, bark_allow_private=True)
    fake = FakeBark()
    app.state.bark_transport = fake.transport
    with TestClient(app) as c:
        r = c.post("/api/register", json={"username": "alice", "password": "demo123"})
        assert r.status_code == 200
        yield c, fake, app


def put(c, url=BARK, exclude=""):
    return c.put("/api/settings/bark", json={"bark_url": url, "bark_exclude_device": exclude})


def test_requires_auth(tmp_path):
    with TestClient(create_app(data_dir=str(tmp_path), allow_register=True)) as c:
        assert c.get("/api/settings/bark").status_code == 401
        assert c.put("/api/settings/bark", json={"bark_url": BARK}).status_code == 401
        assert c.post("/api/settings/bark/test", json={}).status_code == 401


def test_settings_roundtrip_and_privacy(env, tmp_path):
    c, fake, app = env
    assert c.get("/api/settings/bark").json()["configured"] is False
    assert put(c, BARK + "/", "devA").status_code == 200
    g = c.get("/api/settings/bark").json()
    assert g["bark_url"] == BARK and g["bark_exclude_device"] == "devA" and g["configured"]
    # 其他用户看不到，也不出现在 /api/me 与条目里
    c.post("/api/logout")
    c.post("/api/register", json={"username": "bob", "password": "demo123"})
    assert c.get("/api/settings/bark").json()["configured"] is False
    assert "KEY123" not in c.get("/api/me").text and "KEY123" not in c.get("/api/items").text
    # 清空
    c.post("/api/logout")
    c.post("/api/login", json={"username": "alice", "password": "demo123"})
    assert put(c, "").json()["configured"] is False


def test_invalid_urls_rejected(tmp_path):
    with TestClient(create_app(data_dir=str(tmp_path), allow_register=True)) as c:  # 默认不允许内网
        c.post("/api/register", json={"username": "alice", "password": "demo123"})
        for bad in ["ftp://x.com/k", "javascript:alert(1)", "not a url", "http://user:pw@8.8.8.8/k",
                    "http://127.0.0.1:8000/k", "http://localhost/k", "http://10.0.0.5/k", "http://192.168.1.2/k",
                    "http://169.254.169.254/latest", "http://[::1]/k", "http://0.0.0.0/k"]:
            r = put(c, bad)
            assert r.status_code == 400, bad
        assert put(c, "https://8.8.8.8/KEY").status_code == 200  # 公网 IP 通过（不发请求）


def test_allow_private_env(tmp_path):
    with pytest.raises(ValueError):
        check_bark_url("http://192.168.1.10:8080/k", False)
    assert check_bark_url("http://192.168.1.10:8080/k", True) == "http://192.168.1.10:8080/k"


def test_test_endpoint_sends_push(env):
    c, fake, _ = env
    r = c.post("/api/settings/bark/test", json={"bark_url": BARK})
    assert r.status_code == 200
    url, body = fake.calls[0]
    assert url == BARK and body["group"] == "clipboard" and "测试" in body["title"]
    # 没配置也没传 → 400
    assert c.post("/api/settings/bark/test", json={}).status_code == 400


def test_test_endpoint_reports_failure(tmp_path):
    app = create_app(data_dir=str(tmp_path), allow_register=True, bark_allow_private=True)
    app.state.bark_transport = FakeBark(status=400).transport
    with TestClient(app) as c:
        c.post("/api/register", json={"username": "alice", "password": "demo123"})
        r = c.post("/api/settings/bark/test", json={"bark_url": BARK})
        assert r.status_code == 502 and "400" in r.json().get("error", r.text)


def test_private_text_triggers_push(env):
    c, fake, _ = env
    put(c)
    long = "这是一条很长的文本" * 20
    assert c.post("/content", json={"content": long, "visibility": "private"}).status_code == 200
    calls = fake.wait(1)
    assert len(calls) == 1
    url, body = calls[0]
    assert url == BARK
    assert body["title"] == "剪贴板：收到新内容" and body["group"] == "clipboard"
    assert body["body"].startswith("这是一条很长的文本") and len(body["body"]) <= 61 and body["body"].endswith("…")
    assert body["url"].startswith("http")


def test_private_file_triggers_push_with_filename(env):
    c, fake, _ = env
    put(c)
    c.post("/upload_file", data={"visibility": "private", "expires_in": "0"}, files={"file": ("photo.png", b"\x89PNG0")})
    calls = fake.wait(1)
    assert calls and calls[0][1]["body"] == "photo.png"


def test_public_item_no_push(env):
    c, fake, _ = env
    put(c)
    c.post("/content", json={"content": "pub", "visibility": "public", "expires_in": 0})
    time.sleep(0.4)
    assert fake.calls == []


def test_exclude_sending_device(env):
    c, fake, _ = env
    put(c, exclude="mac-1")
    c.post("/content", json={"content": "from mac", "visibility": "private"}, headers={"X-Device-Id": "mac-1"})
    time.sleep(0.4)
    assert fake.calls == []
    c.post("/content", json={"content": "from phone", "visibility": "private"}, headers={"X-Device-Id": "phone-2"})
    assert len(fake.wait(1)) == 1
    c.post("/content", json={"content": "no header", "visibility": "private"})
    assert len(fake.wait(2)) == 2


def test_push_failure_does_not_break_write(tmp_path):
    app = create_app(data_dir=str(tmp_path), allow_register=True, bark_allow_private=True)

    def boom(req):
        raise httpx.ConnectError("down")
    app.state.bark_transport = httpx.MockTransport(boom)
    with TestClient(app) as c:
        c.post("/api/register", json={"username": "alice", "password": "demo123"})
        put(c)
        r = c.post("/content", json={"content": "x", "visibility": "private"})
        assert r.status_code == 200
        time.sleep(0.3)
        assert c.get("/api/items").status_code == 200
