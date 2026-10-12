"""Clipboard Online — 多用户 + 分享/过期/实时/收藏等增强版。"""
from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import logging
import socket
import hmac
import html
import json
import os
import re
import secrets
import tempfile
import threading
import time
import unicodedata
import uuid as uuidlib
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path
from typing import Any, Optional
from urllib.parse import urlparse

import httpx
import qrcode
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from .archive import ArchiveError, is_archive, list_archive

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"

def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default

def _env_bool(name: str, default: bool = True) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.strip().lower() not in ("0", "false", "off", "no", "")

_SCRYPT = dict(n=2**14, r=8, p=1, maxmem=64 * 1024 * 1024)

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode("utf-8"), salt=salt, dklen=32, **_SCRYPT)
    return f"scrypt${salt.hex()}${dk.hex()}"

def verify_password(password: str, stored: str) -> bool:
    try:
        algo, salt_h, hash_h = stored.split("$", 2)
        if algo != "scrypt":
            return False
        salt, expected = bytes.fromhex(salt_h), bytes.fromhex(hash_h)
        got = hashlib.scrypt(password.encode("utf-8"), salt=salt, dklen=len(expected), **_SCRYPT)
        return hmac.compare_digest(got, expected)
    except Exception:
        return False

_FORBIDDEN = re.compile(r'[\x00-\x1f\x7f/\\:*?"<>|]')
_USER_RE = re.compile(r"^[\w\u4e00-\u9fff.-]{2,32}$")
_URL_ONLY = re.compile(r"^https?://[^\s]+$", re.I)
IMAGE_EXTS = {"png", "jpg", "jpeg", "webp", "gif", "bmp", "heic", "avif"}

# ---- 在线预览白名单：仅按扩展名（不信任客户端 mime）。html/svg/js 等可执行类型永不内联 ----
_PREVIEW_IMAGE = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                  "webp": "image/webp", "bmp": "image/bmp", "avif": "image/avif"}
_PREVIEW_VIDEO = {"mp4": "video/mp4", "m4v": "video/mp4", "webm": "video/webm", "mov": "video/quicktime",
                  "ogv": "video/ogg"}
_PREVIEW_AUDIO = {"mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac", "wav": "audio/wav",
                  "ogg": "audio/ogg", "oga": "audio/ogg", "opus": "audio/ogg", "flac": "audio/flac"}
_PREVIEW_TEXT = {"txt", "md", "markdown", "json", "log", "csv", "tsv", "yaml", "yml", "ini", "toml", "conf",
                 "py", "js", "ts", "css", "sh", "c", "h", "cpp", "java", "go", "rs", "sql", "xml", "rb", "php"}


def preview_kind(filename: str) -> Optional[str]:
    """image / video / audio / pdf / text；不在白名单返回 None（只能下载）。"""
    ext = filename.rpartition(".")[2].lower() if "." in (filename or "") else ""
    if ext in _PREVIEW_IMAGE:
        return "image"
    if ext in _PREVIEW_VIDEO:
        return "video"
    if ext in _PREVIEW_AUDIO:
        return "audio"
    if ext == "pdf":
        return "pdf"
    if ext in _PREVIEW_TEXT:
        return "text"
    if is_archive(filename or ""):
        return "archive"  # 只列目录，不解压（见 archive.py）
    return None


def preview_mime(filename: str) -> Optional[str]:
    ext = filename.rpartition(".")[2].lower() if "." in (filename or "") else ""
    for m in (_PREVIEW_IMAGE, _PREVIEW_VIDEO, _PREVIEW_AUDIO):
        if ext in m:
            return m[ext]
    if ext == "pdf":
        return "application/pdf"
    if ext in _PREVIEW_TEXT:
        return "text/plain; charset=utf-8"
    return None


_UNSAFE_MIME = re.compile(r"(html|svg|xml|javascript|ecmascript|xhtml)", re.I)


def serve_file(path: Path, filename: str, item_mime: Optional[str], inline: bool) -> Response:
    """统一文件响应：Range(206) 由 FileResponse 提供；白名单类型才可内联，其余强制 attachment；始终 nosniff。"""
    kind = preview_kind(filename)
    pm = preview_mime(filename)
    headers = {"X-Content-Type-Options": "nosniff", "Accept-Ranges": "bytes",
               "X-Frame-Options": "SAMEORIGIN",  # 允许同源页面用 iframe 预览 PDF
               "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; sandbox; frame-ancestors 'self'"}
    if pm and (inline or kind == "image"):
        # 白名单类型：使用服务端映射的 MIME（文本一律 text/plain，绝不当 HTML 解析）
        if kind == "pdf":
            headers["Content-Security-Policy"] = "frame-ancestors 'self'"  # 浏览器内置 PDF 查看器不能被 sandbox
        return FileResponse(path, filename=filename, media_type=pm, content_disposition_type="inline", headers=headers)
    media = item_mime or guess_mime(filename)
    if _UNSAFE_MIME.search(media or ""):
        media = "application/octet-stream"
    return FileResponse(path, filename=filename, media_type=media, content_disposition_type="attachment", headers=headers)


EXPIRY_PRESETS = {0: None, 3600: 3600, 86400: 86400, 604800: 604800, 2592000: 2592000}
EXPIRY_MAX = 366 * 86400  # 自定义秒数上限

def sanitize_filename(name: str | None) -> str:
    name = unicodedata.normalize("NFC", name or "")
    name = name.replace("\\", "/").split("/")[-1]
    name = _FORBIDDEN.sub("_", name).strip().strip(".")
    name = re.sub(r"\s+", " ", name)
    if not name:
        return "file"
    stem, dot, ext = name.rpartition(".")
    if not dot or not stem:
        stem, ext = name, ""
    else:
        ext = "." + ext[:16]
    limit = 200 - len(ext.encode("utf-8"))
    while len(stem.encode("utf-8")) > limit:
        stem = stem[:-1]
    return (stem or "file") + ext

def guess_mime(filename: str) -> str:
    ext = filename.rpartition(".")[2].lower() if "." in filename else ""
    return {
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp",
        "gif": "image/gif", "pdf": "application/pdf", "txt": "text/plain", "json": "application/json",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "zip": "application/zip", "mp4": "video/mp4",
    }.get(ext, "application/octet-stream")


DEVICE_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


class Hub:
    """WebSocket 广播：公共事件全员；私有事件仅所属用户。"""
    def __init__(self):
        self.lock = threading.Lock()
        self.clients: list[tuple[WebSocket, Optional[str]]] = []  # (ws, user_id|None)
        self.devices: dict[int, str] = {}  # id(ws) -> 设备 ID（客户端在 /ws?device=… 上报，用于「在线设备」）

    async def connect(self, ws: WebSocket, user_id: Optional[str], device_id: str = ""):
        await ws.accept()
        with self.lock:
            self.clients.append((ws, user_id))
            if device_id:
                self.devices[id(ws)] = device_id

    def disconnect(self, ws: WebSocket):
        with self.lock:
            self.clients = [(w, u) for w, u in self.clients if w is not ws]
            self.devices.pop(id(ws), None)

    def online_devices(self, user_id: str) -> set[str]:
        with self.lock:
            return {self.devices[id(w)] for w, u in self.clients if u == user_id and id(w) in self.devices}

    async def broadcast(self, event: dict, *, public: bool, owner_id: Optional[str] = None):
        dead = []
        with self.lock:
            targets = list(self.clients)
        # 公共事件要发给所有连接（含访客、已睡眠手机的半开连接）：并发发送 + 每个 2 秒超时，
        # 一个卡住的连接不能把上传请求本身拖住 / 拖失败。
        async def one(ws):
            try:
                await asyncio.wait_for(ws.send_json(event), timeout=2.0)
            except Exception:
                dead.append(ws)
        sel = [ws for ws, uid in targets if public or (owner_id and uid == owner_id)]
        if sel:
            await asyncio.gather(*(one(w) for w in sel), return_exceptions=True)
        for ws in dead:
            self.disconnect(ws)


class Store:
    def __init__(self, data_dir: Path):
        self.dir = data_dir
        self.uploads = data_dir / "uploads"
        self.items_path = data_dir / "items.json"
        self.users_path = data_dir / "users.json"
        self.meta_path = data_dir / "user_meta.json"
        self.og_path = data_dir / "og_cache.json"
        self.bark_path = data_dir / "bark.json"
        self.devices_path = data_dir / "devices.json"
        self.clipsync_path = data_dir / "clipsync.json"
        self.lock = threading.RLock()
        self.uploads.mkdir(parents=True, exist_ok=True)
        for p, default in ((self.items_path, []), (self.users_path, []), (self.meta_path, {}), (self.og_path, {}), (self.bark_path, {})):
            if not p.exists():
                self._write_json(p, default)
        self._migrate()

    def _write_json(self, path: Path, data: Any) -> None:
        fd, tmp = tempfile.mkstemp(dir=self.dir, prefix=".tmp-", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False)
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except OSError:
                    pass

    def _read_json(self, path: Path) -> Any:
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def _migrate(self) -> None:
        with self.lock:
            items = self._read_json(self.items_path)
            if not isinstance(items, list):
                self._write_json(self.items_path, [])
                return
            dirty = False
            out = []
            for i in items:
                if not isinstance(i, dict) or "uuid" not in i:
                    dirty = True
                    continue
                if "owner_id" not in i:
                    i["owner_id"] = "system"
                    i["owner_username"] = "system"
                    i["visibility"] = "public"
                    dirty = True
                i.setdefault("visibility", "public")
                i.setdefault("expires_at", None)
                i.setdefault("share_token", None)
                i.setdefault("share_expires_at", None)
                out.append(i)
            if dirty or len(out) != len(items):
                self._write_json(self.items_path, out)

    # users
    def list_users(self) -> list[dict]:
        with self.lock:
            data = self._read_json(self.users_path)
            return data if isinstance(data, list) else []

    def find_user(self, *, uid: str | None = None, username: str | None = None) -> Optional[dict]:
        for u in self.list_users():
            if uid and u.get("id") == uid:
                return u
            if username and u.get("username", "").lower() == username.lower():
                return u
        return None

    def create_user(self, username: str, password: str) -> dict:
        with self.lock:
            users = self._read_json(self.users_path) or []
            if not isinstance(users, list):
                users = []
            if any(u.get("username", "").lower() == username.lower() for u in users):
                raise ValueError("用户名已被占用")
            user = {"id": uuidlib.uuid4().hex, "username": username,
                    "password_hash": hash_password(password), "created_at": time.time()}
            users.append(user)
            self._write_json(self.users_path, users)
            return {"id": user["id"], "username": user["username"], "created_at": user["created_at"]}

    # meta
    def get_meta(self, user_id: str) -> dict:
        with self.lock:
            allm = self._read_json(self.meta_path)
            if not isinstance(allm, dict):
                allm = {}
            m = allm.get(user_id) or {}
            return {
                "favorites": list(m.get("favorites") or []),
                "pins": list(m.get("pins") or []),
                "tags": dict(m.get("tags") or {}),
            }

    def save_meta(self, user_id: str, meta: dict) -> None:
        with self.lock:
            allm = self._read_json(self.meta_path)
            if not isinstance(allm, dict):
                allm = {}
            allm[user_id] = {
                "favorites": list(meta.get("favorites") or []),
                "pins": list(meta.get("pins") or []),
                "tags": dict(meta.get("tags") or {}),
            }
            self._write_json(self.meta_path, allm)

    # bark（每个用户一条；仅本人可读，绝不出现在 items / 其他用户数据里）
    # ---- 多设备剪贴板同步（设计参考 lanecho，MIT；此处为独立重写）----
    def get_devices(self, user_id: str) -> dict:
        with self.lock:
            d = self._read_json(self.devices_path)
            u = d.get(user_id) if isinstance(d, dict) else None
            return dict(u) if isinstance(u, dict) else {}

    def put_device(self, user_id: str, device_id: str, info: Optional[dict]) -> None:
        """info=None 表示删除。"""
        with self.lock:
            d = self._read_json(self.devices_path)
            if not isinstance(d, dict):
                d = {}
            u = d.get(user_id) if isinstance(d.get(user_id), dict) else {}
            if info is None:
                u.pop(device_id, None)
            else:
                u[device_id] = info
            if u:
                d[user_id] = u
            else:
                d.pop(user_id, None)
            self._write_json(self.devices_path, d)

    def get_clip(self, user_id: str) -> Optional[dict]:
        with self.lock:
            d = self._read_json(self.clipsync_path)
            c = d.get(user_id) if isinstance(d, dict) else None
            return dict(c) if isinstance(c, dict) else None

    def set_clip(self, user_id: str, clip: dict) -> None:
        with self.lock:
            d = self._read_json(self.clipsync_path)
            if not isinstance(d, dict):
                d = {}
            d[user_id] = clip
            self._write_json(self.clipsync_path, d)

    def get_bark(self, user_id: str) -> dict:
        with self.lock:
            allb = self._read_json(self.bark_path)
            b = (allb.get(user_id) if isinstance(allb, dict) else None) or {}
            return {"url": str(b.get("url") or ""), "exclude_device": str(b.get("exclude_device") or ""),
                    "open_in_app": bool(b.get("open_in_app", True))}  # 默认：点击推送打开 App（深链）

    def set_bark(self, user_id: str, url: str, exclude_device: str, open_in_app: Optional[bool] = None) -> None:
        with self.lock:
            allb = self._read_json(self.bark_path)
            if not isinstance(allb, dict):
                allb = {}
            if url:
                old = allb.get(user_id) or {}
                oia = open_in_app if open_in_app is not None else bool(old.get("open_in_app", True))
                allb[user_id] = {"url": url, "exclude_device": exclude_device, "open_in_app": oia}
            else:
                allb.pop(user_id, None)
            self._write_json(self.bark_path, allb)

    # items
    def _raw_items(self) -> list[dict]:
        data = self._read_json(self.items_path)
        return data if isinstance(data, list) else []

    def purge_expired(self) -> int:
        now = time.time()
        with self.lock:
            items = self._raw_items()
            keep, gone = [], []
            for i in items:
                exp = i.get("expires_at")
                sex = i.get("share_expires_at")
                # revoke expired share tokens
                if sex and sex <= now and i.get("share_token"):
                    i["share_token"] = None
                    i["share_expires_at"] = None
                if exp and exp <= now:
                    gone.append(i)
                else:
                    keep.append(i)
            for i in gone:
                self._unlink(i)
            if gone or len(keep) != len(items):
                self._write_json(self.items_path, keep)
            return len(gone)

    def list_items(self) -> list[dict]:
        self.purge_expired()
        with self.lock:
            items = self._raw_items()
        return sorted(items, key=lambda i: i.get("created", 0), reverse=True)

    def get_item(self, uid: str) -> Optional[dict]:
        self.purge_expired()
        for i in self.list_items():
            if i.get("uuid") == uid:
                return i
        return None

    def find_by_share(self, token: str) -> Optional[dict]:
        self.purge_expired()
        now = time.time()
        for i in self.list_items():
            if i.get("share_token") == token:
                sex = i.get("share_expires_at")
                if sex and sex <= now:
                    continue
                return i
        return None

    def add_item(self, item: dict) -> None:
        with self.lock:
            items = self._raw_items()
            items.append(item)
            self._write_json(self.items_path, items)

    def update_item(self, uid: str, **fields) -> Optional[dict]:
        with self.lock:
            items = self._raw_items()
            for i in items:
                if i.get("uuid") == uid:
                    i.update(fields)
                    self._write_json(self.items_path, items)
                    return i
            return None

    def file_path(self, name: str) -> Optional[Path]:
        p = (self.uploads / name).resolve()
        try:
            p.relative_to(self.uploads.resolve())
        except ValueError:
            return None
        return p

    def unique_name(self, safe: str) -> str:
        with self.lock:
            used = {i.get("filename") for i in self._raw_items() if i.get("type") == "file"}
            if safe not in used and not (self.uploads / safe).exists():
                return safe
            stem, dot, ext = safe.rpartition(".")
            if not dot or not stem:
                stem, ext = safe, ""
            else:
                ext = "." + ext
            n = 1
            while True:
                cand = f"{stem} ({n}){ext}"
                if cand not in used and not (self.uploads / cand).exists():
                    return cand
                n += 1

    def _unlink(self, item: dict) -> None:
        if item.get("type") == "file" and item.get("filename"):
            p = self.file_path(item["filename"])
            if p and p.is_file():
                try:
                    p.unlink()
                except OSError:
                    pass

    def delete(self, uid: str, *, owner_id: str) -> bool:
        with self.lock:
            items = self._raw_items()
            keep, gone = [], []
            for i in items:
                (gone if i.get("uuid") == uid and i.get("owner_id") == owner_id else keep).append(i)
            if not gone:
                return False
            for i in gone:
                self._unlink(i)
            self._write_json(self.items_path, keep)
            return True

    def clear_own(self, owner_id: str, visibility: Optional[str] = None) -> int:
        with self.lock:
            items = self._raw_items()
            keep, gone = [], []
            for i in items:
                mine = i.get("owner_id") == owner_id
                match = visibility is None or i.get("visibility") == visibility
                (gone if mine and match else keep).append(i)
            for i in gone:
                self._unlink(i)
            self._write_json(self.items_path, keep)
            return len(gone)

    def og_get(self, url: str) -> Optional[dict]:
        with self.lock:
            cache = self._read_json(self.og_path)
            if isinstance(cache, dict) and url in cache:
                ent = cache[url]
                if time.time() - ent.get("ts", 0) < 86400 * 7:
                    return ent.get("data")
        return None

    def og_set(self, url: str, data: dict) -> None:
        with self.lock:
            cache = self._read_json(self.og_path)
            if not isinstance(cache, dict):
                cache = {}
            cache[url] = {"ts": time.time(), "data": data}
            # cap
            if len(cache) > 500:
                oldest = sorted(cache.items(), key=lambda x: x[1].get("ts", 0))[:100]
                for k, _ in oldest:
                    cache.pop(k, None)
            self._write_json(self.og_path, cache)


# ---- Bark 推送（SSRF 防护：仅 http/https，默认拒绝内网 / 回环 / 链路本地地址）----
log = logging.getLogger("clipboard.bark")

try:
    VERSION = (Path(__file__).parent / "VERSION").read_text().strip() or "dev"
except OSError:  # pragma: no cover
    VERSION = "dev"
# 功能清单：客户端据此判断服务器是否过旧（旧镜像没有这些路由时会返回裸的 404 Not Found）
FEATURES = ["bark", "archive", "edit", "preview", "share", "ws", "tags", "version", "clipsync", "devices"]


def _ip_blocked(ip: str) -> bool:
    try:
        a = ipaddress.ip_address(ip.split("%")[0])
    except ValueError:
        return True
    return (a.is_private or a.is_loopback or a.is_link_local or a.is_multicast or a.is_reserved
            or a.is_unspecified or (a.version == 6 and a.ipv4_mapped is not None and _ip_blocked(str(a.ipv4_mapped))))


BARK_OFFICIAL_HOST = "api.day.app"

DOCKER_HINT = ("docker run -d -p 8100:8099 -e CLIP_BARK_ALLOW_PRIVATE=1 -v clip-data:/data "
               "ghcr.io/hackjown/clipboard-online/clipboard-online:latest")


def is_official_bark_host(host: str) -> bool:
    """官方 Bark 主机：api.day.app 及其子域名（精确匹配后缀，api.day.app.evil.com 不算）。"""
    h = (host or "").lower().rstrip(".")
    return h == BARK_OFFICIAL_HOST or h.endswith("." + BARK_OFFICIAL_HOST)


def _is_ip_literal(host: str) -> bool:
    try:
        ipaddress.ip_address(host.split("%")[0])
        return True
    except ValueError:
        return False


def check_bark_url(raw: str, allow_private: bool) -> str:
    """校验并规范化 Bark 地址；不合法抛 ValueError（文案可直接给用户看）。"""
    u = (raw or "").strip()
    if len(u) > 512:
        raise ValueError("地址过长")
    pu = urlparse(u)
    if pu.scheme not in ("http", "https") or not pu.hostname:
        raise ValueError("Bark 地址必须以 http:// 或 https:// 开头，例如 https://api.day.app/你的Key")
    if pu.username or pu.password:
        raise ValueError("地址里不要包含用户名/密码")
    host = pu.hostname
    # 用户输入的是官方公网域名：即使本机 DNS 被代理解析成内网 / fake-IP（198.18.0.0/15、192.168.x.x…）也放行。
    # 注意：这只对「域名」生效，IP 字面量仍按下面的规则检查。
    if not allow_private and not (is_official_bark_host(host) and not _is_ip_literal(host)):
        try:
            infos = socket.getaddrinfo(host, pu.port or (443 if pu.scheme == "https" else 80), proto=socket.IPPROTO_TCP)
        except OSError as e:
            raise ValueError(f"无法解析 Bark 服务器域名 {host}（{e}）")
        ips = sorted({i[4][0] for i in infos})
        bad = [ip for ip in ips if _ip_blocked(ip)]
        if not ips or bad:
            what = f"{host} 解析到 {', '.join(bad or ips)}" if not _is_ip_literal(host) else f"地址 {host} 是内网 / 本机 IP"
            raise ValueError(
                f"出于安全考虑，不允许推送到内网 / 本机地址：{what}。"
                f"若你的服务器在 OpenClash / fake-IP 之类的代理环境下，或 Bark 是自建在内网的，请给服务器设置环境变量 CLIP_BARK_ALLOW_PRIVATE=1，"
                f"例如：{DOCKER_HINT}"
            )
    return u.rstrip("/") if not pu.query else u


def bark_msg(r: "httpx.Response") -> str:
    """提取 Bark 自己的错误文案（{"code":400,"message":"..."}），否则取响应前 120 字。"""
    try:
        j = r.json()
        if isinstance(j, dict) and j.get("message"):
            return str(j["message"])[:160]
    except Exception:  # noqa: BLE001
        pass
    return (r.text or "")[:120]


def bark_attempts(url: str, payload: dict) -> list[tuple[str, dict]]:
    """把用户粘贴的各种形式规范成待尝试的 (目标URL, JSON)。
    支持：https://api.day.app/KEY、…/KEY/、…/KEY/内容、自建服务器；末尾内容/查询串被忽略（推送内容由我们自己填）。"""
    pu = urlparse(url)
    base = f"{pu.scheme}://{pu.netloc}"
    segs = [s for s in pu.path.split("/") if s]
    if not segs:
        return [(url, payload)]
    key = segs[0]
    out: list[tuple[str, dict]] = [(f"{base}/{key}", payload)]
    if len(segs) > 1:  # 可能是带前缀的反代部署：…/prefix/KEY，也试原样地址
        full = f"{base}/" + "/".join(segs)
        out.append((full, payload))
    out.append((f"{base}/push", {**payload, "device_key": key}))
    seen, uniq = set(), []
    for tgt, pl in out:
        if tgt not in seen:
            seen.add(tgt)
            uniq.append((tgt, pl))
    return uniq


def create_app(data_dir: Optional[str] = None, allow_register: Optional[bool] = None,
               max_upload_mb: Optional[int] = None, bark_allow_private: Optional[bool] = None) -> FastAPI:
    data_path = Path(data_dir or os.environ.get("CLIP_DATA_DIR") or (BASE_DIR.parent / "data"))
    store = Store(data_path)
    # 实例 ID：每个数据目录一个（持久化），用于在客户端「同步状态」里确认几台设备连的是不是同一个服务器 / 同一份数据
    try:
        _iid_path = Path(data_path) / "instance_id"
        if _iid_path.exists():
            instance_id = _iid_path.read_text().strip()[:16]
        else:
            Path(data_path).mkdir(parents=True, exist_ok=True)
            instance_id = secrets.token_hex(4)
            _iid_path.write_text(instance_id)
    except Exception:  # noqa: BLE001
        instance_id = "unknown"
    hub = Hub()
    allow_reg = allow_register if allow_register is not None else _env_bool("CLIP_REGISTER", True)
    max_upload = (max_upload_mb if max_upload_mb is not None else _env_int("CLIP_MAX_UPLOAD_MB", 200)) * 1024 * 1024
    max_text = _env_int("CLIP_MAX_TEXT_KB", 1024) * 1024
    bark_private = bark_allow_private if bark_allow_private is not None else _env_bool("CLIP_BARK_ALLOW_PRIVATE", False)

    secret_file = data_path / ".secret"
    if not secret_file.exists():
        secret_file.write_text(secrets.token_hex(32))
        try:
            secret_file.chmod(0o600)
        except OSError:
            pass
    sign_key = secret_file.read_text().encode()
    COOKIE = "clip_session"
    TTL = 30 * 24 * 3600

    def make_token(user_id: str) -> str:
        exp = str(int(time.time()) + TTL)
        payload = f"{user_id}.{exp}"
        sig = hmac.new(sign_key, payload.encode(), hashlib.sha256).hexdigest()
        return f"{payload}.{sig}"

    def parse_token(tok: Optional[str]) -> Optional[str]:
        if not tok or tok.count(".") != 2:
            return None
        uid, exp, sig = tok.split(".", 2)
        good = hmac.new(sign_key, f"{uid}.{exp}".encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig, good):
            return None
        try:
            if int(exp) <= time.time():
                return None
        except ValueError:
            return None
        return uid

    def current_user(request: Request) -> Optional[dict]:
        tok = request.cookies.get(COOKIE)
        if not tok:
            auth = request.headers.get("authorization") or ""
            if auth.lower().startswith("bearer "):
                tok = auth[7:].strip()
        uid = parse_token(tok)
        if not uid:
            return None
        u = store.find_user(uid=uid)
        if not u:
            return None
        return {"id": u["id"], "username": u["username"], "created_at": u.get("created_at")}

    def require_user(request: Request) -> dict:
        u = current_user(request)
        if not u:
            raise HTTPException(401, "请先登录")
        return u

    def user_from_cookie_header(cookie: str) -> Optional[str]:
        # parse clip_session=...
        for part in cookie.split(";"):
            part = part.strip()
            if part.startswith(COOKIE + "="):
                return parse_token(part.split("=", 1)[1])
        return None

    fails: dict[str, list[float]] = {}
    app = FastAPI(title="Clipboard Online", version=VERSION, docs_url="/docs", redoc_url="/redoc", openapi_url="/openapi.json")
    app.state.store = store
    app.state.hub = hub
    app.state.bark_transport = None  # 测试注入 httpx.MockTransport

    CSP = ("default-src 'self'; img-src 'self' data: https: http:; style-src 'self' 'unsafe-inline'; "
           "script-src 'self'; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")

    @app.middleware("http")
    async def headers_mw(request: Request, call_next):
        if request.method == "POST" and request.url.path == "/upload_file":
            cl = request.headers.get("content-length")
            if cl and cl.isdigit() and int(cl) > max_upload + 1024 * 1024:
                return JSONResponse({"ok": False, "error": f"文件超过 {max_upload // 1048576} MB 限制"}, status_code=413)
        resp = await call_next(request)
        resp.headers.setdefault("Content-Security-Policy", CSP)
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("Referrer-Policy", "same-origin")
        resp.headers.setdefault("X-Frame-Options", "DENY")
        path = request.url.path
        if path in ("/", "/add_content", "/upload_file") or path.startswith("/api/") or path.startswith("/download/") or path.startswith("/s/"):
            resp.headers["Cache-Control"] = "no-store"
        return resp

    def page() -> FileResponse:
        return FileResponse(STATIC_DIR / "index.html")

    @app.get("/")
    def index():
        return page()

    @app.get("/add_content")
    def add_content_page():
        return page()

    @app.get("/upload_file")
    def upload_page():
        return page()

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/favicon.ico")
    def favicon():
        return FileResponse(STATIC_DIR / "favicon.svg", media_type="image/svg+xml")

    # ---- auth ----
    @app.get("/api/config")
    def config(request: Request):
        u = current_user(request)
        return {"auth": True, "authed": u is not None, "user": u, "register": allow_reg,
                "version": VERSION, "features": FEATURES,
                "max_upload": max_upload, "max_text": max_text,
                "expiry_default": {"public": 86400, "private": 0},
                "expiry_presets": [{"sec": 3600, "label": "1小时"}, {"sec": 86400, "label": "1天"},
                                   {"sec": 604800, "label": "7天"}, {"sec": 2592000, "label": "30天"},
                                   {"sec": 0, "label": "永不过期"}]}

    @app.get("/api/version")
    def api_version():
        return {"version": VERSION, "features": FEATURES, "instance": instance_id}

    @app.get("/api/me")
    def me(request: Request):
        return {"user": current_user(request)}

    def _rate_ok(ip: str) -> bool:
        now = time.time()
        recent = [t for t in fails.get(ip, []) if now - t < 60]
        fails[ip] = recent
        return len(recent) < 8

    def _rate_fail(ip: str) -> None:
        fails.setdefault(ip, []).append(time.time())

    def _set_session(resp: Response, request: Request, user_id: str) -> None:
        secure = request.headers.get("x-forwarded-proto", request.url.scheme) == "https"
        resp.set_cookie(COOKIE, make_token(user_id), max_age=TTL, httponly=True, samesite="lax", secure=secure, path="/")

    @app.post("/api/register")
    async def register(request: Request):
        if not allow_reg:
            raise HTTPException(403, "当前已关闭注册")
        ip = request.client.host if request.client else "?"
        if not _rate_ok(ip):
            raise HTTPException(429, "尝试次数过多，请一分钟后再试")
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        username = str((body or {}).get("username", "")).strip()
        password = str((body or {}).get("password", ""))
        if not _USER_RE.match(username):
            raise HTTPException(400, "用户名需 2–32 位，仅字母数字汉字、下划线、点、短横线")
        if len(password) < 6 or len(password) > 128:
            raise HTTPException(400, "密码需 6–128 位")
        try:
            user = store.create_user(username, password)
        except ValueError as e:
            _rate_fail(ip)
            raise HTTPException(409, str(e))
        token = make_token(user["id"])
        resp = JSONResponse({"ok": True, "user": user, "token": token})
        _set_session(resp, request, user["id"])
        return resp

    @app.post("/api/login")
    async def login(request: Request):
        ip = request.client.host if request.client else "?"
        if not _rate_ok(ip):
            raise HTTPException(429, "尝试次数过多，请一分钟后再试")
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        username = str((body or {}).get("username", "")).strip()
        password = str((body or {}).get("password", ""))
        u = store.find_user(username=username)
        if not u or not verify_password(password, u["password_hash"]):
            _rate_fail(ip)
            raise HTTPException(401, "用户名或密码不正确")
        fails.pop(ip, None)
        user = {"id": u["id"], "username": u["username"], "created_at": u.get("created_at")}
        token = make_token(u["id"])
        resp = JSONResponse({"ok": True, "user": user, "token": token})
        _set_session(resp, request, u["id"])
        return resp

    @app.post("/api/logout")
    def logout():
        resp = JSONResponse({"ok": True})
        resp.delete_cookie(COOKIE, path="/")
        return resp

    @app.post("/login")
    async def login_legacy(request: Request):
        return await login(request)

    @app.post("/logout")
    def logout_legacy():
        return logout()

    # ---- helpers ----
    def parse_visibility(raw: Any) -> str:
        return "public" if str(raw or "private").strip().lower() == "public" else "private"

    def parse_expires(raw: Any, visibility: str) -> Optional[float]:
        try:
            sec = int(raw) if raw is not None and raw != "" else (-1)
        except (TypeError, ValueError):
            sec = -1
        # 未指定（缺省 / 空 / 负数）：公共默认 1 天，私有默认永不过期；0 = 用户明确选择「永不过期」
        if sec < 0:
            sec = 86400 if visibility == "public" else 0
        if sec == 0:
            return None
        return time.time() + min(sec, EXPIRY_MAX)

    def public_item(i: dict, me: Optional[dict], meta: Optional[dict] = None) -> dict:
        uid = i["uuid"]
        out = {
            "uuid": uid, "type": i["type"], "created": i.get("created", 0), "size": i.get("size", 0),
            "visibility": i.get("visibility", "public"), "owner_id": i.get("owner_id"),
            "owner_username": i.get("owner_username") or "",
            "mine": bool(me and i.get("owner_id") == me["id"]),
            "expires_at": i.get("expires_at"),
            "share_token": i.get("share_token") if (me and i.get("owner_id") == me["id"]) else None,
            "share_expires_at": i.get("share_expires_at") if (me and i.get("owner_id") == me["id"]) else None,
            "has_share": bool(i.get("share_token")),
            "updated": i.get("updated"),
            "mime": i.get("mime") or (guess_mime(i.get("filename", "")) if i["type"] == "file" else "text/plain"),
            "is_image": False,
            "favorite": False, "pinned": False, "tags": [],
        }
        if i["type"] == "text":
            out["content"] = i.get("content", "")
            out["is_url"] = bool(_URL_ONLY.match((i.get("content") or "").strip()))
            out["looks_md"] = looks_like_md(i.get("content") or "")
        else:
            out["filename"] = i.get("filename", "")
            fn = i.get("filename", "")
            out["ext"] = fn.rpartition(".")[2].lower() if "." in fn else ""
            out["is_image"] = out["ext"] in IMAGE_EXTS or (out["mime"] or "").startswith("image/")
            out["preview"] = preview_kind(fn)
        if me and meta:
            out["favorite"] = uid in meta.get("favorites", [])
            out["pinned"] = uid in meta.get("pins", []) and out["mine"]
            out["tags"] = list((meta.get("tags") or {}).get(uid) or []) if out["mine"] else []
        return out

    def looks_like_md(t: str) -> bool:
        if not t or len(t) < 3:
            return False
        return bool(re.search(r"(^#{1,3}\s|^\*\s|^\-\s|^\d+\.\s|\*\*[^*]+\*\*|`[^`]+`|\[.+\]\(.+\))", t, re.M))

    def visible_to(i: dict, me: Optional[dict]) -> bool:
        if i.get("visibility") == "public":
            return True
        return bool(me and i.get("owner_id") == me["id"])

    async def emit(kind: str, item: Optional[dict] = None, owner_id: Optional[str] = None, visibility: Optional[str] = None):
        pub = (visibility or (item or {}).get("visibility")) == "public"
        oid = owner_id or (item or {}).get("owner_id")
        ev = {"type": kind, "uuid": (item or {}).get("uuid"), "visibility": visibility or (item or {}).get("visibility"),
              "owner_id": oid, "ts": time.time()}
        if (item or {}).get("source"):
            ev["source"] = item["source"]  # clipsync：客户端据此不弹「收到新内容」通知
        try:  # 实时通知失败只记日志，绝不让写入请求失败（内容已经落库）
            await hub.broadcast(ev, public=pub, owner_id=oid)
        except Exception:  # noqa: BLE001
            log.exception("ws broadcast failed")

    # ---- Bark ----
    bark_tasks: set = set()

    async def bark_send(url: str, title: str, body: str, open_url: Optional[str] = None) -> tuple[bool, str]:
        """发送一次 Bark 推送。返回 (成功, 说明)。短超时、不跟随重定向，发送前再次校验目的地。
        依次尝试：POST {base}/{key}（JSON），404 时再试 POST {base}/push（JSON，带 device_key）。"""
        try:
            url = await asyncio.to_thread(check_bark_url, url, bark_private)
        except ValueError as e:
            return False, str(e)
        payload = {"title": title, "body": body, "group": "clipboard"}
        if open_url:
            payload["url"] = open_url
        attempts = bark_attempts(url, payload)
        last = "未发送"
        try:
            kw = {"transport": app.state.bark_transport} if getattr(app.state, "bark_transport", None) else {}
            async with httpx.AsyncClient(timeout=4.0, follow_redirects=False, **kw) as c:
                for target, pl in attempts:
                    r = await c.post(target, json=pl)
                    if 200 <= r.status_code < 300:
                        return True, "ok"
                    last = f"Bark 服务器返回 HTTP {r.status_code}：{bark_msg(r)}"
                    if r.status_code != 404:
                        break  # 非 404：Bark 自己的错误（如 key 无效），直接展示
            return False, last
        except Exception as e:  # noqa: BLE001
            return False, f"请求 Bark 失败：{type(e).__name__}: {e}"[:200]

    def bark_open_url(cfg: dict, uuid: Optional[str], site: str) -> Optional[str]:
        """点击推送后打开什么：open_in_app（默认）→ App 深链 clipboard://item/<uuid>（无 uuid 时 clipboard://home/private）；
        关闭时保持旧行为：站点 https 链接。"""
        if cfg.get("open_in_app", True):
            return f"clipboard://item/{uuid}" if uuid else "clipboard://home/private"
        return site or None

    async def bark_notify_item(user_id: str, item: dict, device_id: str, base_url: str) -> None:
        try:
            cfg = store.get_bark(user_id)
            if not cfg["url"]:
                return
            if device_id and cfg["exclude_device"] and device_id == cfg["exclude_device"]:
                return
            if item["type"] == "text":
                txt = (item.get("content") or "").strip().replace("\n", " ")
                body = txt[:60] + ("…" if len(txt) > 60 else "")
            else:
                body = item.get("filename") or "文件"
            ok, msg = await bark_send(cfg["url"], "剪贴板：收到新内容", body, bark_open_url(cfg, item.get("uuid"), base_url))
            if not ok:
                log.warning("bark push failed for user %s: %s", user_id, msg)
        except Exception:  # noqa: BLE001
            log.exception("bark push crashed")

    def bark_schedule(me: dict, item: dict, request: Request) -> None:
        """私有条目创建后异步推送（失败只记日志）。"""
        if item.get("visibility") != "private" or item.get("source") == "clipsync":
            return  # 剪贴板自动同步产生的历史不推送（否则每复制一次就响一次）
        dev = (request.headers.get("x-device-id") or "").strip()[:64]
        base = str(request.base_url).rstrip("/") + "/"
        task = asyncio.get_running_loop().create_task(bark_notify_item(me["id"], item, dev, base))
        bark_tasks.add(task)
        task.add_done_callback(bark_tasks.discard)

    @app.get("/api/settings/bark")
    def get_bark_settings(request: Request):
        me = require_user(request)
        b = store.get_bark(me["id"])
        return {"ok": True, "bark_url": b["url"], "bark_exclude_device": b["exclude_device"], "configured": bool(b["url"]),
                "open_in_app": b["open_in_app"]}

    @app.put("/api/settings/bark")
    async def put_bark_settings(request: Request):
        me = require_user(request)
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        if not isinstance(body, dict):
            raise HTTPException(400, "请求格式错误")
        raw = str(body.get("bark_url") or "").strip()
        url = ""
        if raw:
            try:
                url = await asyncio.to_thread(check_bark_url, raw, bark_private)
            except ValueError as e:
                raise HTTPException(400, str(e))
        exclude = str(body.get("bark_exclude_device") or body.get("exclude_device") or "").strip()[:64]
        oia = body.get("open_in_app")
        if oia is not None and not isinstance(oia, bool):
            raise HTTPException(400, "open_in_app 须为布尔值")
        store.set_bark(me["id"], url, exclude, oia)
        cur = store.get_bark(me["id"])
        return {"ok": True, "bark_url": url, "bark_exclude_device": exclude, "configured": bool(url),
                "open_in_app": cur["open_in_app"] if url else True}

    @app.post("/api/settings/bark/test")
    async def test_bark(request: Request):
        me = require_user(request)
        try:
            body = await request.json()
        except Exception:
            body = {}
        raw = str((body or {}).get("bark_url") or "").strip() if isinstance(body, dict) else ""
        cur = store.get_bark(me["id"])
        url = raw or cur["url"]
        if not url:
            raise HTTPException(400, "还没有设置 Bark 地址")
        oia = body.get("open_in_app") if isinstance(body, dict) else None
        cfg = {"open_in_app": oia if isinstance(oia, bool) else cur["open_in_app"]}
        ok, msg = await bark_send(url, "剪贴板：测试推送", f"@{me['username']} 的 Bark 推送已连通",
                                  bark_open_url(cfg, None, str(request.base_url).rstrip("/") + "/"))
        if not ok:
            raise HTTPException(502, msg)
        return {"ok": True}

    # ---- items list ----
    @app.get("/api/items")
    def api_items(request: Request, q: str = "", type: str = "all", scope: str = "all",
                  tag: str = "", starred: str = ""):
        me = current_user(request)
        meta = store.get_meta(me["id"]) if me else None
        all_items = store.list_items()
        visible = [i for i in all_items if visible_to(i, me)]
        counts = {
            "total": len(visible),
            "text": sum(1 for i in visible if i["type"] == "text"),
            "file": sum(1 for i in visible if i["type"] == "file"),
            "bytes": sum(i.get("size", 0) for i in visible if i["type"] == "file"),
            "public": sum(1 for i in visible if i.get("visibility") == "public"),
            "private": sum(1 for i in visible if i.get("visibility") == "private"),
            "starred": sum(1 for i in visible if meta and i["uuid"] in meta.get("favorites", [])),
        }
        items = visible
        if scope == "public":
            items = [i for i in items if i.get("visibility") == "public"]
        elif scope == "private":
            if not me:
                return {"items": [], "counts": counts, "need_auth": True}
            items = [i for i in items if i.get("visibility") == "private" and i.get("owner_id") == me["id"]]
        elif scope == "mine":
            if not me:
                return {"items": [], "counts": counts, "need_auth": True}
            items = [i for i in items if i.get("owner_id") == me["id"]]
        if type in ("text", "file"):
            items = [i for i in items if i["type"] == type]
        if starred in ("1", "true", "yes") and meta:
            fav = set(meta.get("favorites") or [])
            items = [i for i in items if i["uuid"] in fav]
        if tag and meta:
            items = [i for i in items if tag in (meta.get("tags") or {}).get(i["uuid"], [])]
        ql = q.strip().lower()
        if ql:
            items = [i for i in items if ql in (i.get("content") or i.get("filename") or i.get("owner_username") or "").lower()
                     or (meta and any(ql in t.lower() for t in (meta.get("tags") or {}).get(i["uuid"], [])))]

        # pin sort: pinned first (personal), then created desc
        pins = set((meta or {}).get("pins") or [])
        decorated = [public_item(i, me, meta) for i in items]
        decorated.sort(key=lambda x: (0 if x["pinned"] else 1, -x["created"]))
        tags_all = sorted({t for ts in ((meta or {}).get("tags") or {}).values() for t in ts}) if meta else []
        return {"items": decorated, "counts": counts, "need_auth": False, "tags": tags_all}

    @app.post("/content")
    async def post_content(request: Request):
        me = require_user(request)
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        content = body.get("content") if isinstance(body, dict) else None
        if not isinstance(content, str) or not content.strip():
            raise HTTPException(400, "内容不能为空")
        size = len(content.encode("utf-8"))
        if size > max_text:
            raise HTTPException(413, f"文本超过 {max_text // 1024} KB 限制")
        vis = parse_visibility(body.get("visibility") if isinstance(body, dict) else None)
        exp = parse_expires(body.get("expires_in") if isinstance(body, dict) else None, vis)
        uid = uuidlib.uuid4().hex
        item = {"uuid": uid, "type": "text", "content": content, "size": size, "created": time.time(),
                "owner_id": me["id"], "owner_username": me["username"], "visibility": vis,
                "expires_at": exp, "share_token": None, "share_expires_at": None, "mime": "text/plain"}
        store.add_item(item)
        # optional tags on create
        tags = body.get("tags") if isinstance(body, dict) else None
        if isinstance(tags, list) and tags:
            meta = store.get_meta(me["id"])
            meta["tags"][uid] = [str(t).strip()[:32] for t in tags if str(t).strip()][:8]
            store.save_meta(me["id"], meta)
        await emit("create", item)
        bark_schedule(me, item, request)
        return {"ok": True, "uuid": uid, "visibility": vis, "expires_at": exp}

    @app.post("/upload_file")
    async def post_upload(request: Request, file: UploadFile = File(...),
                          visibility: str = Form("private"), expires_in: str = Form(""),
                          tags: str = Form("")):
        me = require_user(request)
        vis = parse_visibility(visibility)
        try:
            exp_raw = int(expires_in) if expires_in not in ("", None) else -1
        except ValueError:
            exp_raw = -1
        exp = parse_expires(exp_raw, vis)
        fname = file.filename or "file"
        # screenshots often come as image/png blob with empty or blob name
        if not fname or fname in ("blob", "image.png", "image"):
            ct = (file.content_type or "").lower()
            ext = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"}.get(ct, "")
            if ext:
                fname = datetime.now().strftime(f"screenshot-%Y%m%d-%H%M%S.{ext}")
        safe = sanitize_filename(fname)
        name = store.unique_name(safe)
        dest = store.file_path(name)
        if dest is None:
            raise HTTPException(400, "文件名无效")
        size = 0
        try:
            with open(dest, "xb") as out:
                while chunk := file.file.read(1024 * 1024):
                    size += len(chunk)
                    if size > max_upload:
                        raise HTTPException(413, f"文件超过 {max_upload // 1048576} MB 限制")
                    out.write(chunk)
        except FileExistsError:
            raise HTTPException(409, "文件名冲突，请重试")
        except HTTPException:
            dest.unlink(missing_ok=True)
            raise
        except Exception:
            dest.unlink(missing_ok=True)
            raise HTTPException(500, "保存失败")
        uid = uuidlib.uuid4().hex
        mime = file.content_type or guess_mime(name)
        item = {"uuid": uid, "type": "file", "filename": name, "size": size, "created": time.time(),
                "owner_id": me["id"], "owner_username": me["username"], "visibility": vis,
                "expires_at": exp, "share_token": None, "share_expires_at": None, "mime": mime}
        store.add_item(item)
        if tags.strip():
            meta = store.get_meta(me["id"])
            meta["tags"][uid] = [t.strip()[:32] for t in tags.split(",") if t.strip()][:8]
            store.save_meta(me["id"], meta)
        await emit("create", item)
        bark_schedule(me, item, request)
        return {"ok": True, "uuid": uid, "filename": name, "size": size, "visibility": vis, "expires_at": exp}

    @app.post("/delete")
    async def post_delete(request: Request):
        me = require_user(request)
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        uid = body.get("uuid") if isinstance(body, dict) else None
        if not isinstance(uid, str):
            raise HTTPException(400, "缺少 uuid")
        item = store.get_item(uid)
        if not item:
            raise HTTPException(404, "条目不存在")
        if item.get("owner_id") != me["id"]:
            raise HTTPException(403, "只能删除自己上传的内容")
        vis, oid = item.get("visibility"), item.get("owner_id")
        if not store.delete(uid, owner_id=me["id"]):
            raise HTTPException(404, "条目不存在")
        # cleanup meta refs
        meta = store.get_meta(me["id"])
        meta["favorites"] = [x for x in meta["favorites"] if x != uid]
        meta["pins"] = [x for x in meta["pins"] if x != uid]
        meta["tags"].pop(uid, None)
        store.save_meta(me["id"], meta)
        await emit("delete", {"uuid": uid, "visibility": vis, "owner_id": oid})
        return {"ok": True}

    async def _clear_body(request: Request) -> None:
        try:
            body = await request.json()
        except Exception:
            body = None
        if not isinstance(body, dict) or body.get("command") != "clear":
            raise HTTPException(400, "缺少 command=clear")

    @app.post("/clear_text")
    async def clear_text(request: Request):
        me = require_user(request)
        await _clear_body(request)
        with store.lock:
            items = store._raw_items()
            keep, gone = [], []
            for i in items:
                if i.get("owner_id") == me["id"] and i.get("visibility") == "private" and i.get("type") == "text":
                    gone.append(i)
                else:
                    keep.append(i)
            for i in gone:
                store._unlink(i)
            store._write_json(store.items_path, keep)
        await emit("clear", owner_id=me["id"], visibility="private")
        return {"ok": True, "removed": len(gone)}

    @app.post("/clear_files")
    async def clear_files(request: Request):
        me = require_user(request)
        await _clear_body(request)
        with store.lock:
            items = store._raw_items()
            keep, gone = [], []
            for i in items:
                if i.get("owner_id") == me["id"] and i.get("visibility") == "private" and i.get("type") == "file":
                    gone.append(i)
                else:
                    keep.append(i)
            for i in gone:
                store._unlink(i)
            store._write_json(store.items_path, keep)
        await emit("clear", owner_id=me["id"], visibility="private")
        return {"ok": True, "removed": len(gone)}

    @app.post("/clear_clipboard")
    async def clear_clipboard(request: Request):
        me = require_user(request)
        await _clear_body(request)
        n = store.clear_own(me["id"], "private")
        await emit("clear", owner_id=me["id"], visibility="private")
        return {"ok": True, "removed": n}

    @app.post("/api/clear")
    async def api_clear(request: Request):
        me = require_user(request)
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        if not isinstance(body, dict) or body.get("command") != "clear":
            raise HTTPException(400, "缺少 command=clear")
        scope = str(body.get("scope") or "private").lower()
        if scope == "private":
            n = store.clear_own(me["id"], "private")
        elif scope == "public":
            n = store.clear_own(me["id"], "public")
        elif scope == "all":
            n = store.clear_own(me["id"], None)
        else:
            raise HTTPException(400, "scope 须为 private / public / all")
        await emit("clear", owner_id=me["id"], visibility=scope if scope != "all" else "public")
        return {"ok": True, "removed": n}

    @app.get("/download/{filename}")
    def download(request: Request, filename: str, inline: int = 0):
        me = current_user(request)
        item = next((i for i in store.list_items() if i["type"] == "file" and i.get("filename") == filename), None)
        if not item:
            raise HTTPException(404, "文件不存在")
        if item.get("visibility") != "public" and (not me or item.get("owner_id") != me["id"]):
            raise HTTPException(403, "无权下载此文件")
        path = store.file_path(filename)
        if not path or not path.is_file():
            raise HTTPException(404, "文件不存在")
        return serve_file(path, filename, item.get("mime"), bool(inline))

    # ---- share ----
    @app.patch("/api/items/{uid}")
    async def edit_item(request: Request, uid: str):
        """编辑文本条目（仅所有者）：content / visibility / expires_in / tags；保留分享令牌。"""
        me = require_user(request)
        item = store.get_item(uid)
        if not item:
            raise HTTPException(404, "条目不存在或已过期")
        if item.get("owner_id") != me["id"]:
            raise HTTPException(403, "只能编辑自己的内容")
        if item.get("type") != "text":
            raise HTTPException(400, "只有文本条目可以编辑")
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        if not isinstance(body, dict):
            raise HTTPException(400, "请求格式错误")
        fields: dict[str, Any] = {}
        if "content" in body:
            content = body["content"]
            if not isinstance(content, str) or not content.strip():
                raise HTTPException(400, "内容不能为空")
            size = len(content.encode("utf-8"))
            if size > max_text:
                raise HTTPException(413, f"文本超过 {max_text // 1024} KB 限制")
            fields["content"] = content
            fields["size"] = size
        vis = item.get("visibility", "private")
        if "visibility" in body:
            vis = parse_visibility(body.get("visibility"))
            fields["visibility"] = vis
        if "expires_in" in body:
            fields["expires_at"] = parse_expires(body.get("expires_in"), vis)
        elif vis != item.get("visibility"):
            fields["expires_at"] = parse_expires(-1, vis)  # 换可见性且没指定：用新可见性的默认过期
        if "tags" in body:
            tags = body["tags"]
            if not isinstance(tags, list):
                raise HTTPException(400, "tags 须为数组")
            clean: list[str] = []
            for tg in tags:
                s = str(tg).strip()[:32]
                if s and s not in clean:
                    clean.append(s)
                if len(clean) >= 8:
                    break
            meta = store.get_meta(me["id"])
            if clean:
                meta["tags"][uid] = clean
            else:
                meta["tags"].pop(uid, None)
            store.save_meta(me["id"], meta)
        if not fields and "tags" not in body:
            raise HTTPException(400, "没有可更新的字段")
        fields["updated"] = time.time()
        old_vis = item.get("visibility")
        new = store.update_item(uid, **fields)
        if new is None:
            raise HTTPException(404, "条目不存在或已过期")
        # 可见性变化：公共↔私有订阅者都要刷新
        if old_vis != new.get("visibility"):
            await emit("update", new, visibility=old_vis)
        await emit("update", new)
        meta = store.get_meta(me["id"])
        return {"ok": True, "item": public_item(new, me, meta)}

    @app.post("/api/items/{uid}/share")
    async def create_share(request: Request, uid: str):
        me = require_user(request)
        item = store.get_item(uid)
        if not item or item.get("owner_id") != me["id"]:
            raise HTTPException(404, "条目不存在")
        try:
            body = await request.json()
        except Exception:
            body = {}
        hours = body.get("hours", 24 * 7)
        try:
            hours = float(hours)
        except (TypeError, ValueError):
            hours = 24 * 7
        if hours <= 0:
            share_exp = None
        else:
            share_exp = time.time() + hours * 3600
        token = secrets.token_urlsafe(18)
        store.update_item(uid, share_token=token, share_expires_at=share_exp)
        await emit("update", store.get_item(uid))
        return {"ok": True, "token": token, "url": f"/s/{token}", "share_expires_at": share_exp}

    @app.delete("/api/items/{uid}/share")
    async def revoke_share(request: Request, uid: str):
        me = require_user(request)
        item = store.get_item(uid)
        if not item or item.get("owner_id") != me["id"]:
            raise HTTPException(404, "条目不存在")
        store.update_item(uid, share_token=None, share_expires_at=None)
        await emit("update", store.get_item(uid))
        return {"ok": True}

    @app.get("/api/share/{token}")
    def api_share(token: str):
        item = store.find_by_share(token)
        if not item:
            raise HTTPException(404, "分享不存在或已过期")
        out = {
            "uuid": item["uuid"], "type": item["type"], "created": item.get("created"),
            "size": item.get("size"), "owner_username": item.get("owner_username"),
            "visibility": item.get("visibility"), "expires_at": item.get("expires_at"),
            "share_expires_at": item.get("share_expires_at"),
            "mime": item.get("mime") or guess_mime(item.get("filename", "")),
        }
        if item["type"] == "text":
            out["content"] = item.get("content", "")
        else:
            out["filename"] = item.get("filename")
            out["ext"] = (item.get("filename") or "").rpartition(".")[2].lower()
            out["is_image"] = out["ext"] in IMAGE_EXTS
            out["preview"] = preview_kind(item.get("filename") or "")
            out["download_url"] = f"/s/{token}/file"
        return out

    # ---- 压缩包目录预览（不解压、不提供条目内容）----
    def _archive_response(item: dict) -> dict:
        path = store.file_path(item["filename"])
        if not path or not path.is_file():
            raise HTTPException(404, "文件不存在")
        try:
            return list_archive(path, item["filename"])
        except ArchiveError as e:
            raise HTTPException(e.status, e.message)

    @app.get("/api/items/{uid}/archive")
    def item_archive(request: Request, uid: str):
        me = current_user(request)
        item = store.get_item(uid)
        if not item or item.get("type") != "file":
            raise HTTPException(404, "条目不存在")
        if not visible_to(item, me):
            raise HTTPException(403, "无权查看此文件")
        return _archive_response(item)

    @app.get("/s/{token}/archive")
    def share_archive(token: str):
        item = store.find_by_share(token)
        if not item or item.get("type") != "file":
            raise HTTPException(404, "分享不存在或已过期")
        return _archive_response(item)

    @app.get("/s/{token}/file")
    def share_file(token: str, inline: int = 0):
        item = store.find_by_share(token)
        if not item or item.get("type") != "file":
            raise HTTPException(404, "分享不存在或已过期")
        path = store.file_path(item["filename"])
        if not path or not path.is_file():
            raise HTTPException(404, "文件不存在")
        return serve_file(path, item["filename"], item.get("mime"), bool(inline))

    @app.get("/api/share/{token}/qr")
    def share_qr(request: Request, token: str):
        item = store.find_by_share(token)
        if not item:
            raise HTTPException(404, "分享不存在或已过期")
        # absolute-ish URL from request
        base = str(request.base_url).rstrip("/")
        url = f"{base}/s/{token}"
        img = qrcode.make(url, border=2, box_size=8)
        buf = BytesIO()
        img.save(buf, format="PNG")
        return Response(buf.getvalue(), media_type="image/png")

    @app.get("/s/{token}", response_class=HTMLResponse)
    def share_page(token: str):
        item = store.find_by_share(token)
        if not item:
            return HTMLResponse("<!doctype html><meta charset=utf-8><title>分享无效</title>"
                                "<body style='font-family:sans-serif;padding:2rem'><h1>分享不存在或已过期</h1>"
                                "<p><a href='/'>返回剪贴板</a></p>", status_code=404)
        # serve SPA share view via static share.html or inline
        return FileResponse(STATIC_DIR / "share.html")

    # ---- favorites / pins / tags ----
    @app.post("/api/items/{uid}/favorite")
    async def toggle_favorite(request: Request, uid: str):
        me = require_user(request)
        item = store.get_item(uid)
        if not item or not visible_to(item, me):
            raise HTTPException(404, "条目不存在")
        meta = store.get_meta(me["id"])
        fav = set(meta["favorites"])
        if uid in fav:
            fav.remove(uid)
            on = False
        else:
            fav.add(uid)
            on = True
        meta["favorites"] = list(fav)
        store.save_meta(me["id"], meta)
        return {"ok": True, "favorite": on}

    @app.post("/api/items/{uid}/pin")
    async def toggle_pin(request: Request, uid: str):
        me = require_user(request)
        item = store.get_item(uid)
        if not item or item.get("owner_id") != me["id"]:
            raise HTTPException(403, "只能置顶自己的内容")
        meta = store.get_meta(me["id"])
        pins = set(meta["pins"])
        if uid in pins:
            pins.remove(uid)
            on = False
        else:
            pins.add(uid)
            on = True
        meta["pins"] = list(pins)
        store.save_meta(me["id"], meta)
        return {"ok": True, "pinned": on}

    @app.post("/api/items/{uid}/tags")
    async def set_tags(request: Request, uid: str):
        me = require_user(request)
        item = store.get_item(uid)
        if not item or item.get("owner_id") != me["id"]:
            raise HTTPException(403, "只能给自己的内容打标签")
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        tags = body.get("tags") if isinstance(body, dict) else None
        if not isinstance(tags, list):
            raise HTTPException(400, "tags 须为数组")
        clean = []
        for t in tags:
            s = str(t).strip()[:32]
            if s and s not in clean:
                clean.append(s)
            if len(clean) >= 8:
                break
        meta = store.get_meta(me["id"])
        if clean:
            meta["tags"][uid] = clean
        else:
            meta["tags"].pop(uid, None)
        store.save_meta(me["id"], meta)
        return {"ok": True, "tags": clean}

    # ---- OG preview ----
    @app.get("/api/og")
    def og_preview(url: str):
        url = (url or "").strip()
        if not _URL_ONLY.match(url) or len(url) > 2000:
            raise HTTPException(400, "无效链接")
        cached = store.og_get(url)
        if cached:
            return cached
        domain = urlparse(url).netloc
        data = {"url": url, "title": domain or url, "description": "", "image": "", "domain": domain, "ok": False}
        try:
            with httpx.Client(timeout=3.0, follow_redirects=True, headers={"User-Agent": "ClipboardOnline/1.0"}) as client:
                r = client.get(url)
                if r.status_code < 400 and "text/html" in r.headers.get("content-type", ""):
                    text = r.text[:200000]
                    def meta(prop):
                        m = re.search(rf'<meta[^>]+(?:property|name)=["\']{re.escape(prop)}["\'][^>]+content=["\']([^"\']+)["\']', text, re.I)
                        if not m:
                            m = re.search(rf'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']{re.escape(prop)}["\']', text, re.I)
                        return html.unescape(m.group(1).strip()) if m else ""
                    title = meta("og:title") or meta("twitter:title")
                    if not title:
                        tm = re.search(r"<title[^>]*>([^<]+)</title>", text, re.I)
                        title = html.unescape(tm.group(1).strip()) if tm else domain
                    data.update({
                        "title": title[:200], "description": (meta("og:description") or meta("description"))[:300],
                        "image": meta("og:image")[:500], "domain": domain, "ok": True,
                    })
        except Exception:
            pass
        store.og_set(url, data)
        return data

    # ---- websocket ----
    # ================= 多设备剪贴板同步 =================
    # 思路参考 lanecho（https://github.com/zlx2019/lanecho ，MIT）：一处复制、处处可粘贴；
    # 每台设备可选同步方向（双向 / 只发送 / 只接收 / 关闭）；一次复制只传播一次（内容哈希去重 + 客户端回声抑制）；
    # 冲突按「最后写入者胜」(LWW)。区别：lanecho 是局域网 P2P（mDNS + mTLS），这里经由本服务器 + WebSocket 中转，
    # 因此跨网络也能用，传输安全依赖 HTTPS。
    CLIP_MAX = 512 * 1024  # 与 lanecho 文本单条上限一致
    DIRECTIONS = ("both", "send", "recv", "off")

    def _dev_id(request: Request) -> str:
        d = (request.headers.get("x-device-id") or "").strip()
        return d if DEVICE_RE.match(d) else ""

    def _dev_public(did: str, info: dict, online: set, current: str) -> dict:
        return {"device_id": did, "name": info.get("name") or "未命名设备", "platform": info.get("platform") or "",
                "direction": info.get("direction") or "both", "last_seen": info.get("last_seen"),
                "created": info.get("created"), "online": did in online, "current": did == current}

    @app.get("/api/devices")
    def list_devices(request: Request):
        me = require_user(request)
        online = hub.online_devices(me["id"])
        cur = _dev_id(request)
        devs = [_dev_public(k, v, online, cur) for k, v in store.get_devices(me["id"]).items()]
        devs.sort(key=lambda d: (not d["current"], not d["online"], -(d["last_seen"] or 0)))
        return {"ok": True, "devices": devs, "user": me["username"], "instance": instance_id,
                "online_count": len(online)}

    @app.put("/api/devices/{device_id}")
    async def put_device(device_id: str, request: Request):
        me = require_user(request)
        if not DEVICE_RE.match(device_id):
            raise HTTPException(400, "设备 ID 无效")
        try:
            body = await request.json()
        except Exception:
            body = {}
        if not isinstance(body, dict):
            raise HTTPException(400, "请求格式错误")
        devs = store.get_devices(me["id"])
        old = devs.get(device_id) or {}
        if not old and len(devs) >= 50:
            raise HTTPException(400, "设备数量已达上限（50），请先移除不用的设备")
        direction = str(body.get("direction") or old.get("direction") or "both")
        if direction not in DIRECTIONS:
            raise HTTPException(400, "direction 须为 both / send / recv / off")
        info = {"name": str(body.get("name") or old.get("name") or "未命名设备").strip()[:40] or "未命名设备",
                "platform": str(body.get("platform") or old.get("platform") or "")[:20],
                "direction": direction, "created": old.get("created") or time.time(), "last_seen": time.time()}
        store.put_device(me["id"], device_id, info)
        await hub.broadcast({"type": "devices", "ts": time.time()}, public=False, owner_id=me["id"])
        return {"ok": True, "device": _dev_public(device_id, info, hub.online_devices(me["id"]), _dev_id(request))}

    @app.delete("/api/devices/{device_id}")
    async def delete_device(device_id: str, request: Request):
        me = require_user(request)
        if device_id not in store.get_devices(me["id"]):
            raise HTTPException(404, "没有这个设备")
        store.put_device(me["id"], device_id, None)
        await hub.broadcast({"type": "devices", "ts": time.time()}, public=False, owner_id=me["id"])
        return {"ok": True}

    def _clip_public(c: Optional[dict]) -> dict:
        if not c:
            return {"ok": True, "clip": None}
        return {"ok": True, "clip": {k: c.get(k) for k in ("text", "hash", "ts", "origin", "origin_name")}}

    @app.get("/api/clipsync")
    def get_clipsync(request: Request):
        me = require_user(request)
        return _clip_public(store.get_clip(me["id"]))

    @app.post("/api/clipsync")
    async def post_clipsync(request: Request):
        """某台设备的本机复制。按方向放行 → 去重 → LWW 覆盖 → 只推给本人的其他设备（WebSocket type=clip）。"""
        me = require_user(request)
        dev = _dev_id(request)
        if not dev:
            raise HTTPException(400, "缺少 X-Device-Id")
        try:
            body = await request.json()
        except Exception:
            raise HTTPException(400, "请求格式错误")
        text = body.get("text") if isinstance(body, dict) else None
        if not isinstance(text, str) or not text.strip():
            raise HTTPException(400, "内容不能为空")
        if len(text.encode("utf-8")) > CLIP_MAX:
            raise HTTPException(413, "剪贴板文本超过 512 KB，未同步")
        devs = store.get_devices(me["id"])
        info = devs.get(dev)
        if info and info.get("direction") in ("recv", "off"):
            raise HTTPException(403, "此设备的同步方向不允许发送")
        if info:  # 顺便刷新 last_seen
            info = dict(info, last_seen=time.time())
            store.put_device(me["id"], dev, info)
        h = hashlib.sha256(text.encode("utf-8")).hexdigest()
        cur = store.get_clip(me["id"])
        if cur and cur.get("hash") == h:
            return {"ok": True, "duplicate": True, **_clip_public(cur)}  # 一次复制只传播一次
        now = time.time()
        # LWW：以服务器收到的时间为准（避免设备时钟不一致）；客户端可带 base_ts 表示「基于哪一版」，仅作诊断返回
        clip = {"text": text, "hash": h, "ts": now, "origin": dev,
                "origin_name": (info or {}).get("name") or "未命名设备"}
        store.set_clip(me["id"], clip)
        ev = {"type": "clip", **{k: clip[k] for k in ("text", "hash", "ts", "origin", "origin_name")}}
        await hub.broadcast(ev, public=False, owner_id=me["id"])
        uid = None
        if not isinstance(body.get("save_history"), bool) or body.get("save_history"):
            uid = uuidlib.uuid4().hex
            item = {"uuid": uid, "type": "text", "content": text, "size": len(text.encode("utf-8")), "created": now,
                    "owner_id": me["id"], "owner_username": me["username"], "visibility": "private",
                    "expires_at": None, "share_token": None, "share_expires_at": None, "source": "clipsync"}
            store.add_item(item)
            await emit("create", item)
        return {"ok": True, "duplicate": False, "uuid": uid, **_clip_public(clip)}

    @app.websocket("/ws")
    async def ws_endpoint(ws: WebSocket):
        uid = None
        cookie = ws.cookies.get(COOKIE) or ""
        if cookie:
            uid = parse_token(cookie)
        if not uid:
            qtok = ws.query_params.get("token")
            if qtok:
                uid = parse_token(qtok)
        dev = (ws.query_params.get("device") or "").strip()
        await hub.connect(ws, uid, dev if DEVICE_RE.match(dev) else "")
        try:
            await ws.send_json({"type": "hello", "user_id": uid, "device": dev if DEVICE_RE.match(dev) else ""})
            while True:
                # 心跳：客户端每 ~20 秒发 "ping"，服务器回 pong；客户端据此发现「看似连着、实际已断」的半开连接并重连
                msg = await ws.receive_text()
                if msg.strip().lower() in ("ping", '{"type":"ping"}'):
                    try:
                        await asyncio.wait_for(ws.send_json({"type": "pong", "ts": time.time()}), timeout=5)
                    except Exception:
                        break
        except WebSocketDisconnect:
            pass
        except Exception:
            pass
        finally:
            hub.disconnect(ws)

    @app.exception_handler(HTTPException)
    async def http_exc(_: Request, exc: HTTPException):
        return JSONResponse({"ok": False, "error": exc.detail, "detail": exc.detail}, status_code=exc.status_code)

    return app


app = create_app()
