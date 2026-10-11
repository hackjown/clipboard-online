"""多用户 + 分享/过期/收藏 接口测试"""
import time
import pytest
from fastapi.testclient import TestClient
from app.main import create_app, sanitize_filename, hash_password, verify_password


@pytest.fixture()
def client(tmp_path):
    return TestClient(create_app(data_dir=str(tmp_path), allow_register=True))


def reg(c, user, pw="demo123"):
    r = c.post("/api/register", json={"username": user, "password": pw})
    assert r.status_code == 200, r.text
    return r.json()["user"]


def items(c, **params):
    return c.get("/api/items", params=params).json()


def test_password_hash():
    h = hash_password("secret!")
    assert verify_password("secret!", h) and not verify_password("wrong", h)


def test_register_login_guest_isolation(client):
    reg(client, "alice")
    client.post("/content", json={"content": "secret", "visibility": "private"})
    client.post("/content", json={"content": "pub", "visibility": "public", "expires_in": 0})
    client.post("/api/logout")
    assert client.post("/content", json={"content": "x"}).status_code == 401
    pubs = items(client, scope="public")["items"]
    assert all(i["visibility"] == "public" for i in pubs)
    assert not any(i.get("content") == "secret" for i in pubs)
    assert items(client, scope="private")["need_auth"] is True


def test_only_owner_delete(client):
    reg(client, "alice")
    uid = client.post("/content", json={"content": "x", "visibility": "public", "expires_in": 0}).json()["uuid"]
    client.post("/api/logout")
    reg(client, "bob")
    assert client.post("/delete", json={"uuid": uid}).status_code == 403
    client.post("/api/logout")
    client.post("/api/login", json={"username": "alice", "password": "demo123"})
    assert client.post("/delete", json={"uuid": uid}).status_code == 200


def test_share_link_public_peek(client):
    reg(client, "alice")
    uid = client.post("/content", json={"content": "hello share", "visibility": "private", "expires_in": 0}).json()["uuid"]
    # private download blocked for guest
    client.post("/api/logout")
    # create share while logged in
    client.post("/api/login", json={"username": "alice", "password": "demo123"})
    r = client.post(f"/api/items/{uid}/share", json={"hours": 24})
    assert r.status_code == 200
    token = r.json()["token"]
    client.post("/api/logout")
    # guest can read via share
    s = client.get(f"/api/share/{token}")
    assert s.status_code == 200 and s.json()["content"] == "hello share"
    assert client.get(f"/s/{token}").status_code == 200
    assert client.get(f"/api/share/{token}/qr").status_code == 200
    # revoke
    client.post("/api/login", json={"username": "alice", "password": "demo123"})
    assert client.delete(f"/api/items/{uid}/share").status_code == 200
    client.post("/api/logout")
    assert client.get(f"/api/share/{token}").status_code == 404


def test_share_file_download(client):
    reg(client, "alice")
    up = client.post("/upload_file", data={"visibility": "private", "expires_in": "0"},
                     files={"file": ("secret.txt", b"TOPSECRET")})
    uid = up.json()["uuid"]
    token = client.post(f"/api/items/{uid}/share", json={"hours": 1}).json()["token"]
    client.post("/api/logout")
    assert client.get("/download/secret.txt").status_code == 403
    assert client.get(f"/s/{token}/file").content == b"TOPSECRET"


def test_expiry_purge(client, tmp_path):
    reg(client, "alice")
    uid = client.post("/content", json={"content": "temp", "visibility": "public", "expires_in": 1}).json()["uuid"]
    assert any(i["uuid"] == uid for i in items(client, scope="public")["items"])
    # force expire
    store = client.app.state.store
    store.update_item(uid, expires_at=time.time() - 10)
    store.purge_expired()
    assert not any(i["uuid"] == uid for i in items(client, scope="public")["items"])


def test_default_expiry(client):
    reg(client, "alice")
    pub = client.post("/content", json={"content": "p", "visibility": "public"}).json()
    priv = client.post("/content", json={"content": "v", "visibility": "private"}).json()
    assert pub["expires_at"] is not None and pub["expires_at"] > time.time()
    assert priv["expires_at"] is None


def test_favorite_pin_tags(client):
    reg(client, "alice")
    pub = client.post("/content", json={"content": "public note", "visibility": "public", "expires_in": 0}).json()["uuid"]
    priv = client.post("/content", json={"content": "mine", "visibility": "private", "expires_in": 0}).json()["uuid"]
    assert client.post(f"/api/items/{pub}/favorite").json()["favorite"] is True
    assert client.post(f"/api/items/{priv}/pin").json()["pinned"] is True
    assert client.post(f"/api/items/{priv}/tags", json={"tags": ["工作", "紧急"]}).json()["tags"] == ["工作", "紧急"]
    # bob cannot pin alice's
    client.post("/api/logout")
    reg(client, "bob")
    assert client.post(f"/api/items/{priv}/pin").status_code == 403
    # bob can favorite public
    assert client.post(f"/api/items/{pub}/favorite").json()["favorite"] is True
    starred = items(client, scope="public", starred="1")["items"]
    assert any(i["uuid"] == pub for i in starred)
    client.post("/api/logout")
    client.post("/api/login", json={"username": "alice", "password": "demo123"})
    pinned = items(client, scope="private")["items"]
    assert pinned[0]["uuid"] == priv and pinned[0]["pinned"] is True
    tagged = items(client, scope="private", tag="工作")["items"]
    assert len(tagged) == 1


def test_image_upload_name(client):
    reg(client, "alice")
    r = client.post("/upload_file", data={"visibility": "private", "expires_in": "0"},
                    files={"file": ("blob", b"\x89PNG\r\n", "image/png")})
    assert r.status_code == 200
    assert r.json()["filename"].startswith("screenshot-") and r.json()["filename"].endswith(".png")


def test_og_endpoint(client):
    r = client.get("/api/og", params={"url": "https://example.com"})
    assert r.status_code == 200
    assert r.json()["domain"] == "example.com"


def test_sanitize():
    assert sanitize_filename("../x.txt") == "x.txt"


def test_bearer_token_auth(tmp_path):
    c = TestClient(create_app(data_dir=str(tmp_path), allow_register=True))
    r = c.post("/api/register", json={"username": "bearer1", "password": "demo123"})
    token = r.json()["token"]
    c2 = TestClient(create_app(data_dir=str(tmp_path), allow_register=True))
    assert c2.get("/api/me").json()["user"] is None
    me = c2.get("/api/me", headers={"Authorization": f"Bearer {token}"})
    assert me.json()["user"]["username"] == "bearer1"
    assert c2.post("/content", headers={"Authorization": f"Bearer {token}"},
                   json={"content": "via bearer", "visibility": "private", "expires_in": 0}).status_code == 200
