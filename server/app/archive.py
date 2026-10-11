"""压缩包内容预览：只读取目录（文件名 / 大小 / 时间），绝不解压、绝不提供条目内容。

支持：zip（含 jar / apk / ipa / aar / war）、tar、tar.gz / tgz、tar.bz2 / tbz2、tar.xz / txz。
不支持：7z / rar（需要额外依赖，返回 415 与说明）。
"""
from __future__ import annotations

import re
import tarfile
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

MAX_ENTRIES = 2000
MAX_ARCHIVE_BYTES = 2 * 1024 ** 3   # 超过则不检查
TAR_TIME_BUDGET = 8.0               # 压缩 tar 流式读取的时间预算（秒）
MAX_NAME_LEN = 500

ZIP_EXTS = {"zip", "jar", "apk", "ipa", "aar", "war"}
TAR_SUFFIXES = (".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tbz", ".tar.xz", ".txz")
UNSUPPORTED_EXTS = {"7z": "7z", "rar": "RAR"}

_CTRL = re.compile(r"[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]")  # 控制字符与 bidi 覆盖字符


class ArchiveError(Exception):
    def __init__(self, message: str, status: int = 422):
        super().__init__(message)
        self.message = message
        self.status = status


def archive_type(filename: str) -> Optional[str]:
    """zip / tar / unsupported / None（不是压缩包）。仅按文件名后缀判断。"""
    n = (filename or "").lower()
    if any(n.endswith(s) for s in TAR_SUFFIXES):
        return "tar"
    ext = n.rpartition(".")[2] if "." in n else ""
    if ext in ZIP_EXTS:
        return "zip"
    if ext in UNSUPPORTED_EXTS:
        return "unsupported"
    return None


def is_archive(filename: str) -> bool:
    return archive_type(filename) is not None


def clean_name(s: str) -> str:
    """仅用于显示：去掉控制 / bidi 字符并截断。保留 '../' 等原样文本（前端用 textContent 渲染），不做任何路径解析。"""
    s = _CTRL.sub("", str(s))
    return s[:MAX_NAME_LEN]


def _fmt_dt(ts: float | None) -> Optional[str]:
    if ts is None:
        return None
    try:
        return datetime.fromtimestamp(float(ts), tz=timezone.utc).strftime("%Y-%m-%d %H:%M")
    except (OverflowError, OSError, ValueError):
        return None


def _list_zip(path: Path) -> dict[str, Any]:
    try:
        zf = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        raise ArchiveError("压缩包已损坏，或不是有效的 zip 文件")
    except (OSError, EOFError, NotImplementedError, RuntimeError) as e:
        raise ArchiveError(f"无法读取压缩包：{type(e).__name__}")
    with zf:
        infos = zf.infolist()
        total = len(infos)
        entries = []
        encrypted = False
        total_size = 0
        for zi in infos:
            total_size += zi.file_size
            if zi.flag_bits & 0x1:
                encrypted = True
        for zi in infos[:MAX_ENTRIES]:
            try:
                mod = datetime(*zi.date_time).strftime("%Y-%m-%d %H:%M")
            except (ValueError, TypeError):
                mod = None
            entries.append({
                "path": clean_name(zi.filename),
                "size": zi.file_size,
                "compressed": zi.compress_size,
                "is_dir": zi.is_dir(),
                "modified": mod,
                "encrypted": bool(zi.flag_bits & 0x1),
            })
    return {"type": "zip", "entries": entries, "total": total, "total_size": total_size,
            "truncated": total > MAX_ENTRIES, "encrypted": encrypted}


def _list_tar(path: Path, filename: str) -> dict[str, Any]:
    compressed = not filename.lower().endswith(".tar")
    mode = "r|*" if compressed else "r:"
    entries: list[dict[str, Any]] = []
    total = 0
    total_size = 0
    truncated = False
    start = time.monotonic()
    try:
        with tarfile.open(path, mode) as tf:
            for ti in tf:
                total += 1
                if len(entries) < MAX_ENTRIES:
                    size = 0 if ti.isdir() else int(ti.size)
                    total_size += size
                    entries.append({
                        "path": clean_name(ti.name),
                        "size": size,
                        "compressed": None,
                        "is_dir": ti.isdir(),
                        "modified": _fmt_dt(ti.mtime),
                        "encrypted": False,
                    })
                else:
                    truncated = True
                    break
                if compressed and time.monotonic() - start > TAR_TIME_BUDGET:
                    truncated = True
                    break
    except (tarfile.TarError, EOFError, OSError, zlib_error, lzma_error) as e:
        if not entries:
            raise ArchiveError("压缩包已损坏，或不是有效的 tar 归档")
        truncated = True  # 读到一半损坏：返回已读部分
    return {"type": "tar", "entries": entries, "total": total, "total_size": total_size,
            "truncated": truncated, "encrypted": False}


try:  # 不同压缩格式的底层异常
    from zlib import error as zlib_error
except ImportError:  # pragma: no cover
    zlib_error = OSError
try:
    from lzma import LZMAError as lzma_error
except ImportError:  # pragma: no cover
    lzma_error = OSError


def list_archive(path: Path, filename: str) -> dict[str, Any]:
    kind = archive_type(filename)
    if kind is None:
        raise ArchiveError("不是支持预览的压缩包类型", 415)
    if kind == "unsupported":
        ext = filename.rpartition(".")[2].upper()
        raise ArchiveError(f"暂不支持预览 {ext} 压缩包的内容（支持 zip / tar / tar.gz / tar.bz2 / tar.xz），请下载后查看", 415)
    try:
        size = path.stat().st_size
    except OSError:
        raise ArchiveError("文件不存在", 404)
    if size > MAX_ARCHIVE_BYTES:
        raise ArchiveError("压缩包超过 2 GB，不支持在线预览目录", 413)
    out = _list_zip(path) if kind == "zip" else _list_tar(path, filename)
    out["ok"] = True
    out["limit"] = MAX_ENTRIES
    return out
