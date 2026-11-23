"""E2EE 密码保险箱服务端接口：鉴权、用户隔离、乐观锁冲突(409)、格式校验、账号密码确认重置"""
import base64

import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture()
def client(tmp_path):
    return TestClient(create_app(data_dir=str(tmp_path), allow_register=True))


def reg(c, user, pw="demo123"):
    r = c.post("/api/register", json={"username": user, "password": pw})
    assert r.status_code == 200, r.text


def sample_env(ct_bytes=b"0123456789abcdef_cipher", expected_rev=0, item_count=2):
    return {
        "version": 1,
        "kdf": "PBKDF2-SHA256",
        "iterations": 200000,
        "salt": base64.b64encode(b"S" * 16).decode(),
        "iv": base64.b64encode(b"I" * 12).decode(),
        "ct": base64.b64encode(ct_bytes).decode(),
        "item_count": item_count,
        "expected_rev": expected_rev,
    }


def test_vault_requires_auth(client):
    assert client.get("/api/vault").status_code == 401
    assert client.put("/api/vault", json=sample_env()).status_code == 401
    assert client.request("DELETE", "/api/vault", json={"password": "x"}).status_code == 401


def test_vault_crud_conflict_and_isolation(client):
    assert "vault" in client.get("/api/version").json()["features"]
    assert client.get("/static/vault.js").status_code == 200
    assert "/static/vault.js" in client.get("/").text

    reg(client, "alice")
    r0 = client.get("/api/vault")
    assert r0.status_code == 200 and r0.json()["exists"] is False

    # 创建 rev=1
    r1 = client.put("/api/vault", json=sample_env(expected_rev=0, item_count=3))
    assert r1.status_code == 200, r1.text
    v1 = r1.json()["vault"]
    assert v1["rev"] == 1 and v1["item_count"] == 3

    # 过期 expected_rev 触发 409 冲突，不覆盖数据
    rc = client.put("/api/vault", json=sample_env(b"stale_data_1234567890", expected_rev=0, item_count=99))
    assert rc.status_code == 409 and rc.json()["vault"]["rev"] == 1 and rc.json()["vault"]["item_count"] == 3

    # 正确 rev=1 更新到 rev=2
    r2 = client.put("/api/vault", json=sample_env(b"updated_cipher_123456", expected_rev=1, item_count=4))
    assert r2.status_code == 200 and r2.json()["vault"]["rev"] == 2 and r2.json()["vault"]["item_count"] == 4

    # 其他用户完全隔离
    client.post("/api/logout")
    reg(client, "bob")
    assert client.get("/api/vault").json()["exists"] is False


def test_vault_validation(client):
    reg(client, "alice")
    bad_cases = [
        {**sample_env(), "version": 2},
        {**sample_env(), "kdf": "PLAIN"},
        {**sample_env(), "iterations": 1000},
        {**sample_env(), "iterations": 9_999_999},
        {**sample_env(), "iv": base64.b64encode(b"short").decode()},
        {**sample_env(), "salt": base64.b64encode(b"tiny").decode()},
        {**sample_env(), "ct": base64.b64encode(b"too_short").decode()},
        {**sample_env(), "ct": "!!!not-base64!!!"},
    ]
    for payload in bad_cases:
        assert client.put("/api/vault", json=payload).status_code == 400, payload


def test_vault_delete_requires_account_password(client):
    reg(client, "alice", pw="alicePass99")
    assert client.put("/api/vault", json=sample_env()).status_code == 200

    # 账号密码错 -> 403 且数据仍在
    r_bad = client.request("DELETE", "/api/vault", json={"password": "wrong"})
    assert r_bad.status_code == 403
    assert client.get("/api/vault").json()["exists"] is True

    # 账号密码对 -> 200 删除成功
    r_ok = client.request("DELETE", "/api/vault", json={"password": "alicePass99"})
    assert r_ok.status_code == 200 and r_ok.json()["deleted"] is True
    assert client.get("/api/vault").json()["exists"] is False
