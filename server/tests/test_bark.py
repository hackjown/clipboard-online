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
    assert body["url"].startswith("clipboard://item/")


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


# ---- SSRF：官方 api.day.app 放行（fake-IP / 内网 DNS），其它域名仍拦 ----
import socket


def fake_dns(monkeypatch, mapping):
    real = socket.getaddrinfo

    def gai(host, port, *a, **k):
        if host in mapping:
            return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (mapping[host], port or 0))]
        return real(host, port, *a, **k)
    monkeypatch.setattr(socket, "getaddrinfo", gai)


@pytest.mark.parametrize("ip", ["198.18.0.7", "198.19.255.1", "192.168.1.1", "10.1.2.3", "127.0.0.1"])
def test_official_host_allowed_even_if_dns_is_private(monkeypatch, ip):
    fake_dns(monkeypatch, {"api.day.app": ip, "push.api.day.app": ip})
    assert check_bark_url("https://api.day.app/KEY/", False) == "https://api.day.app/KEY"
    assert check_bark_url("https://API.DAY.APP./KEY", False)
    assert check_bark_url("https://push.api.day.app/KEY", False)


@pytest.mark.parametrize("bad", [
    "https://api.day.app.evil.com/KEY", "https://evilapi.day.app/KEY", "https://notapi.day.app/KEY",
    "https://day.app/KEY", "https://other.example.com/KEY",
])
def test_lookalike_hosts_still_blocked(monkeypatch, bad):
    fake_dns(monkeypatch, {"api.day.app.evil.com": "198.18.0.9", "evilapi.day.app": "198.18.0.9",
                           "notapi.day.app": "198.18.0.9", "day.app": "198.18.0.9", "other.example.com": "198.18.0.9"})
    with pytest.raises(ValueError):
        check_bark_url(bad, False)


def test_error_message_names_host_ip_and_env_example(monkeypatch):
    fake_dns(monkeypatch, {"bark.lan.example": "192.168.50.9"})
    with pytest.raises(ValueError) as ei:
        check_bark_url("https://bark.lan.example/KEY", False)
    m = str(ei.value)
    assert "bark.lan.example" in m and "192.168.50.9" in m
    assert "CLIP_BARK_ALLOW_PRIVATE=1" in m and "docker run" in m


@pytest.mark.parametrize("lit", ["https://198.18.0.1/KEY", "http://192.168.1.2/KEY", "http://[fd00::1]/KEY"])
def test_ip_literals_in_private_ranges_blocked_even_for_fake_ip(lit):
    with pytest.raises(ValueError) as ei:
        check_bark_url(lit, False)
    assert "CLIP_BARK_ALLOW_PRIVATE=1" in str(ei.value)
    assert check_bark_url(lit, True)   # 显式开启后允许


def test_only_official_host_gets_fake_ip_pass(monkeypatch):
    fake_dns(monkeypatch, {"api.day.app": "198.18.0.7", "mybark.example.org": "198.18.0.7"})
    assert check_bark_url("https://api.day.app/K", False)
    with pytest.raises(ValueError):
        check_bark_url("https://mybark.example.org/K", False)


def test_test_endpoint_works_for_official_host_behind_fake_ip(tmp_path, monkeypatch):
    fake_dns(monkeypatch, {"api.day.app": "198.18.0.7"})
    app = create_app(data_dir=str(tmp_path), allow_register=True, bark_allow_private=False)
    fake = FakeBark()
    app.state.bark_transport = fake.transport
    with TestClient(app) as c:
        c.post("/api/register", json={"username": "alice", "password": "demo123"})
        assert c.put("/api/settings/bark", json={"bark_url": "https://api.day.app/KEY9"}).status_code == 200
        assert c.post("/api/settings/bark/test", json={}).status_code == 200
        assert fake.calls[0][0] == "https://api.day.app/KEY9"


# ---- 点击推送打开 App（深链） ----
def test_open_in_app_default_true_and_deeplink_uses_uuid(env):
    c, fake, _ = env
    assert c.get("/api/settings/bark").json()["open_in_app"] is True       # 未配置时默认 true
    assert put(c).status_code == 200
    assert c.get("/api/settings/bark").json()["open_in_app"] is True
    uid = c.post("/content", json={"content": "hi", "visibility": "private"}).json()["uuid"]
    _, body = fake.wait(1)[0]
    assert body["url"] == f"clipboard://item/{uid}"
    fid = c.post("/upload_file", data={"visibility": "private"}, files={"file": ("a.pdf", b"%PDF-1")}).json()["uuid"]
    _, body2 = fake.wait(2)[1]
    assert body2["url"] == f"clipboard://item/{fid}"


def test_open_in_app_off_keeps_site_link_and_persists(env):
    c, fake, _ = env
    r = c.put("/api/settings/bark", json={"bark_url": BARK, "open_in_app": False})
    assert r.status_code == 200 and r.json()["open_in_app"] is False
    assert c.get("/api/settings/bark").json()["open_in_app"] is False
    # 只改地址不带 open_in_app：保持原值
    c.put("/api/settings/bark", json={"bark_url": BARK + "2"})
    assert c.get("/api/settings/bark").json()["open_in_app"] is False
    c.post("/content", json={"content": "hi", "visibility": "private"})
    _, body = fake.wait(1)[0]
    assert body["url"].startswith("http") and "clipboard://" not in body["url"]
    # 重新打开
    c.put("/api/settings/bark", json={"bark_url": BARK, "open_in_app": True})
    assert c.get("/api/settings/bark").json()["open_in_app"] is True


def test_open_in_app_validation_and_test_endpoint_fallback_link(env):
    c, fake, _ = env
    assert c.put("/api/settings/bark", json={"bark_url": BARK, "open_in_app": "yes"}).status_code == 400
    assert c.post("/api/settings/bark/test", json={"bark_url": BARK}).status_code == 200
    assert fake.calls[-1][1]["url"] == "clipboard://home/private"           # 测试推送：没有条目 → 回落到首页
    assert c.post("/api/settings/bark/test", json={"bark_url": BARK, "open_in_app": False}).status_code == 200
    assert fake.calls[-1][1]["url"].startswith("http")


def test_open_in_app_not_leaked_to_other_users(env):
    c, fake, _ = env
    c.put("/api/settings/bark", json={"bark_url": BARK, "open_in_app": False})
    c.post("/api/logout")
    c.post("/api/register", json={"username": "bobby", "password": "demo123"})
    assert c.get("/api/settings/bark").json()["open_in_app"] is True        # 别人的设置不影响我
