"""Office 文档结构化在线预览（纯 Python，无需 LibreOffice）。

支持：
  - Word：.docx（标题、段落/内联粗斜体、列表层级、表格、嵌入图片）
  - Excel：.xlsx / .xlsm（openpyxl）、.xls（xlrd）（多工作表、日期/数值格式化）
  - PowerPoint：.pptx（按放映顺序提取每页标题、正文/缩进要点、表格、嵌入图片、演讲者备注）
不支持：
  - 旧版二进制 .doc / .ppt（返回 415 与说明）

安全限制：
  - 仅按扩展名白名单判定；绝不输出原始 HTML（全部结构化纯文本 + Pillow 重新编码的光栅图）
  - 限制单文件大小、ZIP 解压总大小、单 XML 大小，拒绝 DOCTYPE/ENTITY（防 XXE / zip bomb）
  - 剔除控制字符与 bidi 覆盖字符；表格/段落/幻灯片/图片均有上限，超出标记 truncated
"""
from __future__ import annotations

import base64
import csv
import io
import posixpath
import re
import zipfile
from datetime import date, datetime, time as dt_time
from io import BytesIO
from pathlib import Path
from typing import Any, Optional
import xml.etree.ElementTree as ET

import openpyxl
import xlrd
from PIL import Image, UnidentifiedImageError

MAX_OFFICE_BYTES = 50 * 1024 * 1024        # 单文件上限 50 MB
MAX_ZIP_UNCOMPRESSED = 120 * 1024 * 1024   # OOXML 解压后总大小上限 120 MB（防 zip bomb）
MAX_XML_BYTES = 20 * 1024 * 1024           # 单 XML 部件上限 20 MB

MAX_DOC_BLOCKS = 2000
MAX_TABLE_ROWS = 200
MAX_TABLE_COLS = 50
MAX_SHEETS = 30
MAX_SHEET_ROWS = 500
MAX_SHEET_COLS = 50
MAX_SLIDES = 100
MAX_CELL_LEN = 2000
MAX_PARA_LEN = 12000

MAX_IMAGES = 20
MAX_IMAGE_RAW_BYTES = 8 * 1024 * 1024
MAX_IMAGES_TOTAL_B64 = 3 * 1024 * 1024
MAX_IMAGE_DIM = 960

DOCX_EXTS = {"docx"}
XLSX_EXTS = {"xlsx", "xlsm"}
XLS_EXTS = {"xls"}
CSV_EXTS = {"csv", "tsv"}
PPTX_EXTS = {"pptx"}
UNSUPPORTED_EXTS = {"doc": "DOC", "ppt": "PPT"}
RASTER_IMG_EXTS = {"png", "jpg", "jpeg", "gif", "webp", "bmp"}

_OLE2_MAGIC = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"
_CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]")
_XML_DANGEROUS = re.compile(rb"<!(?:DOCTYPE|ENTITY)\b", re.I)

_NS_W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
_NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
_NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main"
_NS_P = "http://schemas.openxmlformats.org/presentationml/2006/main"
_NS_V = "urn:schemas-microsoft-com:vml"
_NS_DC = "http://purl.org/dc/elements/1.1/"
_NS_REL = "http://schemas.openxmlformats.org/package/2006/relationships"

_W = f"{{{_NS_W}}}"
_R = f"{{{_NS_R}}}"
_A = f"{{{_NS_A}}}"
_P = f"{{{_NS_P}}}"
_V = f"{{{_NS_V}}}"


class OfficeError(Exception):
    def __init__(self, message: str, status: int = 422):
        super().__init__(message)
        self.message = message
        self.status = status


def office_type(filename: str) -> Optional[str]:
    """docx / xlsx / xls / csv / pptx / unsupported / None。仅按文件名后缀判断。"""
    n = (filename or "").lower()
    ext = n.rpartition(".")[2] if "." in n else ""
    if ext in DOCX_EXTS:
        return "docx"
    if ext in XLSX_EXTS:
        return "xlsx"
    if ext in XLS_EXTS:
        return "xls"
    if ext in CSV_EXTS:
        return "csv"
    if ext in PPTX_EXTS:
        return "pptx"
    if ext in UNSUPPORTED_EXTS:
        return "unsupported"
    return None


def is_office(filename: str) -> bool:
    return office_type(filename) is not None


def _clean(s: Any, limit: int = MAX_PARA_LEN) -> str:
    txt = _CTRL.sub("", str(s))
    return txt[:limit]


def _check_ole2_encrypted(path: Path) -> None:
    """加密的 OOXML（docx/xlsx/pptx）外壳为 OLE2 复合文档，给出明确提示。"""
    try:
        with open(path, "rb") as f:
            head = f.read(8)
    except OSError:
        return
    if head == _OLE2_MAGIC:
        raise OfficeError("该文档已加密保护（或为旧版二进制格式），无法在线预览，请下载后查看", 422)


def _open_ooxml_zip(path: Path) -> zipfile.ZipFile:
    _check_ole2_encrypted(path)
    try:
        zf = zipfile.ZipFile(path, "r")
    except zipfile.BadZipFile:
        raise OfficeError("文档已损坏，或不是有效的 Office 文件", 422)
    except (OSError, EOFError, NotImplementedError, RuntimeError) as e:
        raise OfficeError(f"无法读取文档：{type(e).__name__}", 422)
    total_uncompressed = 0
    for zi in zf.infolist():
        if zi.flag_bits & 0x1:
            zf.close()
            raise OfficeError("该文档已加密保护，无法在线预览，请下载后查看", 422)
        total_uncompressed += max(0, zi.file_size)
        if total_uncompressed > MAX_ZIP_UNCOMPRESSED:
            zf.close()
            raise OfficeError("文档内部解压体积过大，已拒绝解析以保护服务器", 422)
    return zf


def _read_zip_bytes(zf: zipfile.ZipFile, member: str, limit: int = MAX_XML_BYTES) -> Optional[bytes]:
    norm = member.lstrip("/")
    try:
        info = zf.getinfo(norm)
    except KeyError:
        return None
    if info.file_size > limit:
        raise OfficeError("文档内容过大，无法在线预览，请下载后查看", 413)
    with zf.open(info, "r") as f:
        data = f.read(limit + 1)
    if len(data) > limit:
        raise OfficeError("文档内容过大，无法在线预览，请下载后查看", 413)
    return data


def _parse_xml(zf: zipfile.ZipFile, member: str) -> Optional[ET.Element]:
    raw = _read_zip_bytes(zf, member, MAX_XML_BYTES)
    if raw is None:
        return None
    if _XML_DANGEROUS.search(raw[:4096]) or _XML_DANGEROUS.search(raw):
        raise OfficeError("文档包含不受支持的 XML 声明，已拒绝解析", 422)
    try:
        return ET.fromstring(raw)
    except ET.ParseError:
        raise OfficeError("文档 XML 结构已损坏，无法预览", 422)


def _read_rels(zf: zipfile.ZipFile, rels_path: str, base_dir: str) -> dict[str, tuple[str, str]]:
    """返回 {rId: (resolved_zip_path, rel_type)}，忽略外部链接。"""
    root = _parse_xml(zf, rels_path)
    if root is None:
        return {}
    out: dict[str, tuple[str, str]] = {}
    for rel in root:
        if not rel.tag.endswith("Relationship"):
            continue
        rid = rel.attrib.get("Id") or ""
        target = rel.attrib.get("Target") or ""
        mode = (rel.attrib.get("TargetMode") or "").lower()
        rtype = rel.attrib.get("Type") or ""
        if not rid or not target or mode == "external":
            continue
        if target.startswith("/"):
            resolved = posixpath.normpath(target.lstrip("/"))
        else:
            resolved = posixpath.normpath(posixpath.join(base_dir, target))
        if resolved.startswith(".."):
            continue
        out[rid] = (resolved, rtype)
    return out


def _read_core_title(zf: zipfile.ZipFile) -> str:
    try:
        root = _parse_xml(zf, "docProps/core.xml")
    except OfficeError:
        return ""
    if root is None:
        return ""
    el = root.find(f"{{{_NS_DC}}}title")
    if el is not None and el.text:
        return _clean(el.text.strip(), 300)
    return ""


class _ImageBudget:
    """安全提取并重编码嵌入光栅图（Pillow 验证 + 缩放 + 数量/字节上限）。"""

    def __init__(self, zf: zipfile.ZipFile):
        self.zf = zf
        self.count = 0
        self.omitted = 0
        self.total_b64 = 0
        self._cache: dict[str, Optional[str]] = {}

    def extract(self, member: str) -> Optional[str]:
        if member in self._cache:
            return self._cache[member]
        ext = member.rpartition(".")[2].lower() if "." in member else ""
        if ext not in RASTER_IMG_EXTS:
            self._cache[member] = None
            return None
        if self.count >= MAX_IMAGES or self.total_b64 >= MAX_IMAGES_TOTAL_B64:
            self.omitted += 1
            return None
        try:
            raw = _read_zip_bytes(self.zf, member, MAX_IMAGE_RAW_BYTES)
        except OfficeError:
            self.omitted += 1
            return None
        if not raw:
            self._cache[member] = None
            return None
        try:
            old_max = Image.MAX_IMAGE_PIXELS
            Image.MAX_IMAGE_PIXELS = 40_000_000
            try:
                with Image.open(BytesIO(raw)) as im:
                    im.load()
                    im.thumbnail((MAX_IMAGE_DIM, MAX_IMAGE_DIM))
                    buf = BytesIO()
                    has_alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
                    if has_alpha:
                        im.convert("RGBA").save(buf, format="PNG", optimize=True)
                        mime = "image/png"
                    else:
                        im.convert("RGB").save(buf, format="JPEG", quality=82, optimize=True)
                        mime = "image/jpeg"
            finally:
                Image.MAX_IMAGE_PIXELS = old_max
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
            self._cache[member] = None
            return None
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        if self.total_b64 + len(b64) > MAX_IMAGES_TOTAL_B64:
            self.omitted += 1
            return None
        uri = f"data:{mime};base64,{b64}"
        self.count += 1
        self.total_b64 += len(b64)
        self._cache[member] = uri
        return uri


# ============================ Word (.docx) ============================

_HEADING_RE = re.compile(r"^(?:heading|标题|title)\s*([1-6])?$", re.I)


def _docx_heading_map(zf: zipfile.ZipFile) -> dict[str, int]:
    """从 word/styles.xml 构建 styleId -> heading level (1..6)。"""
    out: dict[str, int] = {}
    try:
        root = _parse_xml(zf, "word/styles.xml")
    except OfficeError:
        return out
    if root is None:
        return out
    for st in root.findall(f"{_W}style"):
        if st.attrib.get(f"{_W}type") != "paragraph":
            continue
        sid = st.attrib.get(f"{_W}styleId") or ""
        if not sid:
            continue
        lvl: Optional[int] = None
        ppr = st.find(f"{_W}pPr")
        if ppr is not None:
            ol = ppr.find(f"{_W}outlineLvl")
            if ol is not None:
                v = ol.attrib.get(f"{_W}val")
                if v is not None and v.isdigit() and int(v) <= 5:
                    lvl = int(v) + 1
        if lvl is None:
            nm = st.find(f"{_W}name")
            name_val = (nm.attrib.get(f"{_W}val") or "").strip() if nm is not None else ""
            m = _HEADING_RE.match(name_val) or _HEADING_RE.match(sid)
            if m:
                if name_val.lower() == "title" or sid.lower() == "title":
                    lvl = 1
                elif m.group(1):
                    lvl = int(m.group(1))
        if lvl is not None:
            out[sid] = lvl
    return out


def _docx_bool_prop(rpr: Optional[ET.Element], tag: str) -> bool:
    if rpr is None:
        return False
    el = rpr.find(f"{_W}{tag}")
    if el is None:
        return False
    v = (el.attrib.get(f"{_W}val") or "").lower()
    return v not in ("0", "false", "none", "off")


def _docx_extract_run(r_el: ET.Element, rels: dict[str, tuple[str, str]], imgs: _ImageBudget,
                      runs_out: list[dict[str, Any]], img_blocks: list[dict[str, Any]]) -> None:
    rpr = r_el.find(f"{_W}rPr")
    bold = _docx_bool_prop(rpr, "b")
    italic = _docx_bool_prop(rpr, "i")
    underline = _docx_bool_prop(rpr, "u")
    strike = _docx_bool_prop(rpr, "strike")
    parts: list[str] = []
    for child in r_el:
        tag = child.tag
        if tag == f"{_W}t" and child.text:
            parts.append(child.text)
        elif tag == f"{_W}tab":
            parts.append("\t")
        elif tag in (f"{_W}br", f"{_W}cr"):
            parts.append("\n")
        elif tag in (f"{_W}drawing", f"{_W}pict"):
            for blip in child.iter(f"{_A}blip"):
                rid = blip.attrib.get(f"{_R}embed")
                if rid and rid in rels:
                    target = rels[rid][0]
                    uri = imgs.extract(target)
                    if uri:
                        img_blocks.append({"kind": "image", "src": uri, "alt": posixpath.basename(target)})
            for vimg in child.iter(f"{_V}imagedata"):
                rid = vimg.attrib.get(f"{_R}id")
                if rid and rid in rels:
                    target = rels[rid][0]
                    uri = imgs.extract(target)
                    if uri:
                        img_blocks.append({"kind": "image", "src": uri, "alt": posixpath.basename(target)})
    text = _clean("".join(parts))
    if not text:
        return
    # 合并相邻同样式 run，减小 JSON 体积
    if runs_out:
        prev = runs_out[-1]
        if (prev.get("b", False) == bold and prev.get("i", False) == italic
                and prev.get("u", False) == underline and prev.get("s", False) == strike):
            prev["t"] = (prev["t"] + text)[:MAX_PARA_LEN]
            return
    run: dict[str, Any] = {"t": text}
    if bold:
        run["b"] = True
    if italic:
        run["i"] = True
    if underline:
        run["u"] = True
    if strike:
        run["s"] = True
    runs_out.append(run)


def _docx_parse_paragraph(p_el: ET.Element, hmap: dict[str, int],
                          rels: dict[str, tuple[str, str]], imgs: _ImageBudget) -> list[dict[str, Any]]:
    ppr = p_el.find(f"{_W}pPr")
    heading: Optional[int] = None
    is_list = False
    indent = 0
    if ppr is not None:
        ps = ppr.find(f"{_W}pStyle")
        if ps is not None:
            sid = ps.attrib.get(f"{_W}val") or ""
            if sid in hmap:
                heading = hmap[sid]
            else:
                m = _HEADING_RE.match(sid)
                if m:
                    heading = 1 if sid.lower() == "title" else (int(m.group(1)) if m.group(1) else None)
        if heading is None:
            ol = ppr.find(f"{_W}outlineLvl")
            if ol is not None:
                v = ol.attrib.get(f"{_W}val")
                if v is not None and v.isdigit() and int(v) <= 5:
                    heading = int(v) + 1
        numpr = ppr.find(f"{_W}numPr")
        if numpr is not None:
            is_list = True
            ilvl = numpr.find(f"{_W}ilvl")
            if ilvl is not None:
                v = ilvl.attrib.get(f"{_W}val")
                if v and v.isdigit():
                    indent = min(int(v), 5)

    runs: list[dict[str, Any]] = []
    img_blocks: list[dict[str, Any]] = []
    for child in p_el:
        if child.tag == f"{_W}r":
            _docx_extract_run(child, rels, imgs, runs, img_blocks)
        elif child.tag in (f"{_W}hyperlink", f"{_W}ins", f"{_W}smartTag", f"{_W}sdt"):
            for r in child.iter(f"{_W}r"):
                _docx_extract_run(r, rels, imgs, runs, img_blocks)

    full_text = _clean("".join(r["t"] for r in runs))
    out: list[dict[str, Any]] = []
    if full_text.strip():
        if heading is not None:
            out.append({"kind": "heading", "level": max(1, min(heading, 6)), "text": full_text.strip()})
        else:
            blk: dict[str, Any] = {"kind": "paragraph", "text": full_text}
            if is_list:
                blk["list"] = True
                if indent:
                    blk["indent"] = indent
            # 仅当存在富文本样式时附带 runs，保持 JSON 简洁
            if any(r.get("b") or r.get("i") or r.get("u") or r.get("s") for r in runs):
                blk["runs"] = runs
            out.append(blk)
    out.extend(img_blocks)
    return out


def _docx_parse_table(tbl_el: ET.Element) -> Optional[dict[str, Any]]:
    rows: list[list[dict[str, Any]]] = []
    truncated = False
    for tr in tbl_el.findall(f"{_W}tr"):
        if len(rows) >= MAX_TABLE_ROWS:
            truncated = True
            break
        cells: list[dict[str, Any]] = []
        for tc in tr.findall(f"{_W}tc"):
            if len(cells) >= MAX_TABLE_COLS:
                truncated = True
                break
            colspan = 1
            tcpr = tc.find(f"{_W}tcPr")
            if tcpr is not None:
                gs = tcpr.find(f"{_W}gridSpan")
                if gs is not None:
                    v = gs.attrib.get(f"{_W}val")
                    if v and v.isdigit():
                        colspan = max(1, min(int(v), MAX_TABLE_COLS))
            p_texts: list[str] = []
            for p in tc.findall(f"{_W}p"):
                t = "".join(x.text for x in p.iter(f"{_W}t") if x.text)
                p_texts.append(t)
            cell_txt = _clean("\n".join(p_texts).strip(), MAX_CELL_LEN)
            cell: dict[str, Any] = {"text": cell_txt}
            if colspan > 1:
                cell["colspan"] = colspan
            cells.append(cell)
        if cells:
            rows.append(cells)
    if not rows:
        return None
    out: dict[str, Any] = {"kind": "table", "rows": rows}
    if truncated:
        out["truncated"] = True
    return out


def _parse_docx(path: Path) -> dict[str, Any]:
    with _open_ooxml_zip(path) as zf:
        doc = _parse_xml(zf, "word/document.xml")
        if doc is None:
            raise OfficeError("文档缺少 word/document.xml，无法预览", 422)
        body = doc.find(f"{_W}body")
        if body is None:
            raise OfficeError("文档正文为空或格式异常", 422)
        hmap = _docx_heading_map(zf)
        rels = _read_rels(zf, "word/_rels/document.xml.rels", "word")
        title = _read_core_title(zf)
        imgs = _ImageBudget(zf)

        blocks: list[dict[str, Any]] = []
        truncated = False
        para_count = 0
        table_count = 0

        def walk(container: ET.Element) -> None:
            nonlocal truncated, para_count, table_count
            for child in container:
                if len(blocks) >= MAX_DOC_BLOCKS:
                    truncated = True
                    return
                if child.tag == f"{_W}p":
                    for b in _docx_parse_paragraph(child, hmap, rels, imgs):
                        if len(blocks) >= MAX_DOC_BLOCKS:
                            truncated = True
                            return
                        if b["kind"] in ("heading", "paragraph"):
                            para_count += 1
                        blocks.append(b)
                elif child.tag == f"{_W}tbl":
                    tb = _docx_parse_table(child)
                    if tb:
                        table_count += 1
                        blocks.append(tb)
                elif child.tag == f"{_W}sdt":
                    sc = child.find(f"{_W}sdtContent")
                    if sc is not None:
                        walk(sc)

        walk(body)
        return {
            "type": "docx",
            "title": title,
            "blocks": blocks,
            "truncated": truncated,
            "meta": {
                "paragraphs": para_count,
                "tables": table_count,
                "images": imgs.count,
                "omitted_images": imgs.omitted,
            },
        }


# ============================ Excel (.xlsx / .xlsm / .xls) ============================

def _fmt_cell(v: Any) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, datetime):
        if v.hour == 0 and v.minute == 0 and v.second == 0:
            return v.strftime("%Y-%m-%d")
        return v.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(v, date):
        return v.strftime("%Y-%m-%d")
    if isinstance(v, dt_time):
        return v.strftime("%H:%M:%S")
    if isinstance(v, float):
        if v.is_integer() and abs(v) < 1e15:
            return str(int(v))
        return f"{v:.10g}"
    return _clean(v, MAX_CELL_LEN)


def _trim_grid(rows: list[list[str]]) -> list[list[str]]:
    """裁掉末尾完全为空的行和列，保持网格紧凑。"""
    while rows and all(c == "" for c in rows[-1]):
        rows.pop()
    if not rows:
        return []
    max_col = 0
    for r in rows:
        for i in range(len(r) - 1, -1, -1):
            if r[i] != "":
                if i + 1 > max_col:
                    max_col = i + 1
                break
    if max_col == 0:
        return []
    return [r[:max_col] + [""] * max(0, max_col - len(r)) for r in rows]


def _parse_xlsx(path: Path) -> dict[str, Any]:
    # 先做 zip 安全校验（加密/zip bomb/损坏）
    with _open_ooxml_zip(path):
        pass
    wb = None
    try:
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    except Exception as e:
        raise OfficeError(f"无法解析 Excel 文件：{type(e).__name__}", 422)
    try:
        names = list(wb.sheetnames)
        total_sheets = len(names)
        truncated = total_sheets > MAX_SHEETS
        sheets: list[dict[str, Any]] = []
        for sname in names[:MAX_SHEETS]:
            ws = wb[sname]
            raw_rows: list[list[str]] = []
            total_rows = 0
            max_seen_cols = 0
            trunc_rows = False
            trunc_cols = False
            for row in ws.iter_rows(values_only=True):
                total_rows += 1
                row_len = len(row)
                if row_len > max_seen_cols:
                    max_seen_cols = row_len
                if row_len > MAX_SHEET_COLS:
                    trunc_cols = True
                if len(raw_rows) < MAX_SHEET_ROWS:
                    raw_rows.append([_fmt_cell(c) for c in row[:MAX_SHEET_COLS]])
                else:
                    trunc_rows = True
                    # 最多再扫到 5000 行估算总数，避免超大稀疏表耗时过久
                    if total_rows >= 5000:
                        break
            grid = _trim_grid(raw_rows)
            if trunc_rows or trunc_cols:
                truncated = True
            sheets.append({
                "name": _clean(sname, 120),
                "rows": grid,
                "total_rows": max(len(grid), total_rows if trunc_rows else len(grid)),
                "total_cols": max(len(grid[0]) if grid else 0, min(max_seen_cols, MAX_SHEET_COLS) if not trunc_cols else max_seen_cols),
                "truncated_rows": trunc_rows,
                "truncated_cols": trunc_cols,
            })
        return {
            "type": "xlsx",
            "title": "",
            "sheets": sheets,
            "truncated": truncated,
            "meta": {"sheets": len(sheets), "total_sheets": total_sheets},
        }
    except OfficeError:
        raise
    except Exception as e:
        raise OfficeError(f"读取工作表失败：{type(e).__name__}", 422)
    finally:
        if wb is not None:
            try:
                wb.close()
            except Exception:
                pass


def _parse_xls(path: Path) -> dict[str, Any]:
    try:
        wb = xlrd.open_workbook(str(path), on_demand=True)
    except xlrd.XLRDError as e:
        msg = str(e)
        if "encrypt" in msg.lower():
            raise OfficeError("该表格已加密保护，无法在线预览，请下载后查看", 422)
        raise OfficeError("表格已损坏，或不是有效的 .xls 文件", 422)
    except Exception as e:
        raise OfficeError(f"无法读取 .xls 文件：{type(e).__name__}", 422)
    try:
        total_sheets = wb.nsheets
        truncated = total_sheets > MAX_SHEETS
        sheets: list[dict[str, Any]] = []
        for idx in range(min(total_sheets, MAX_SHEETS)):
            sh = wb.sheet_by_index(idx)
            try:
                r_total = sh.nrows
                c_total = sh.ncols
                trunc_rows = r_total > MAX_SHEET_ROWS
                trunc_cols = c_total > MAX_SHEET_COLS
                if trunc_rows or trunc_cols:
                    truncated = True
                r_lim = min(r_total, MAX_SHEET_ROWS)
                c_lim = min(c_total, MAX_SHEET_COLS)
                raw_rows: list[list[str]] = []
                for r in range(r_lim):
                    row_vals: list[str] = []
                    for c in range(c_lim):
                        cell = sh.cell(r, c)
                        ctype = cell.ctype
                        val = cell.value
                        if ctype == xlrd.XL_CELL_EMPTY or ctype == xlrd.XL_CELL_BLANK:
                            row_vals.append("")
                        elif ctype == xlrd.XL_CELL_DATE:
                            try:
                                dt = xlrd.xldate_as_datetime(val, wb.datemode)
                                row_vals.append(_fmt_cell(dt))
                            except Exception:
                                row_vals.append(_fmt_cell(val))
                        elif ctype == xlrd.XL_CELL_BOOLEAN:
                            row_vals.append("TRUE" if val else "FALSE")
                        elif ctype == xlrd.XL_CELL_ERROR:
                            row_vals.append(xlrd.error_text_from_code.get(val, "#ERR"))
                        else:
                            row_vals.append(_fmt_cell(val))
                    raw_rows.append(row_vals)
                grid = _trim_grid(raw_rows)
                sheets.append({
                    "name": _clean(sh.name, 120),
                    "rows": grid,
                    "total_rows": r_total if trunc_rows else len(grid),
                    "total_cols": c_total if trunc_cols else (len(grid[0]) if grid else 0),
                    "truncated_rows": trunc_rows,
                    "truncated_cols": trunc_cols,
                })
            finally:
                wb.unload_sheet(idx)
        return {
            "type": "xls",
            "title": "",
            "sheets": sheets,
            "truncated": truncated,
            "meta": {"sheets": len(sheets), "total_sheets": total_sheets},
        }
    finally:
        try:
            wb.release_resources()
        except Exception:
            pass


# ============================ PowerPoint (.pptx) ============================

_SLIDE_NUM_RE = re.compile(r"slide(\d+)\.xml$", re.I)


def _pptx_slide_paths(zf: zipfile.ZipFile) -> list[str]:
    """按 ppt/presentation.xml 里的 sldIdLst 顺序返回幻灯片路径；缺失时按编号排序兜底。"""
    pres = _parse_xml(zf, "ppt/presentation.xml")
    if pres is not None:
        rels = _read_rels(zf, "ppt/_rels/presentation.xml.rels", "ppt")
        sld_lst = pres.find(f"{_P}sldIdLst")
        if sld_lst is not None:
            paths = []
            for sid in sld_lst.findall(f"{_P}sldId"):
                rid = sid.attrib.get(f"{_R}id")
                if rid and rid in rels:
                    paths.append(rels[rid][0])
            if paths:
                return paths
    # 兜底：直接找 ppt/slides/slide*.xml
    found = [n for n in zf.namelist() if n.startswith("ppt/slides/slide") and n.endswith(".xml")]
    found.sort(key=lambda s: int(m.group(1)) if (m := _SLIDE_NUM_RE.search(s)) else 0)
    return found


def _pptx_extract_txbody(tx_el: ET.Element) -> list[dict[str, Any]]:
    paras: list[dict[str, Any]] = []
    for p in tx_el.findall(f"{_A}p"):
        parts: list[str] = []
        for child in p:
            if child.tag == f"{_A}r":
                t = child.find(f"{_A}t")
                if t is not None and t.text:
                    parts.append(t.text)
            elif child.tag == f"{_A}br":
                parts.append("\n")
            elif child.tag == f"{_A}fld":
                t = child.find(f"{_A}t")
                if t is not None and t.text:
                    parts.append(t.text)
        txt = _clean("".join(parts).strip())
        if not txt:
            continue
        indent = 0
        ppr = p.find(f"{_A}pPr")
        if ppr is not None:
            lvl = ppr.attrib.get("lvl")
            if lvl and lvl.isdigit():
                indent = min(int(lvl), 5)
        item: dict[str, Any] = {"kind": "paragraph", "text": txt}
        if indent:
            item["indent"] = indent
        paras.append(item)
    return paras


def _pptx_extract_table(tbl_el: ET.Element) -> Optional[dict[str, Any]]:
    rows: list[list[dict[str, Any]]] = []
    truncated = False
    for tr in tbl_el.findall(f"{_A}tr"):
        if len(rows) >= MAX_TABLE_ROWS:
            truncated = True
            break
        cells: list[dict[str, Any]] = []
        for tc in tr.findall(f"{_A}tc"):
            if tc.attrib.get("hMerge") == "1":
                continue
            if len(cells) >= MAX_TABLE_COLS:
                truncated = True
                break
            colspan = 1
            gs = tc.attrib.get("gridSpan")
            if gs and gs.isdigit():
                colspan = max(1, min(int(gs), MAX_TABLE_COLS))
            tx = tc.find(f"{_A}txBody")
            txt = "\n".join(p["text"] for p in _pptx_extract_txbody(tx)) if tx is not None else ""
            cell: dict[str, Any] = {"text": _clean(txt, MAX_CELL_LEN)}
            if colspan > 1:
                cell["colspan"] = colspan
            cells.append(cell)
        if cells:
            rows.append(cells)
    if not rows:
        return None
    out: dict[str, Any] = {"kind": "table", "rows": rows}
    if truncated:
        out["truncated"] = True
    return out


def _pptx_read_notes(zf: zipfile.ZipFile, slide_rels: dict[str, tuple[str, str]]) -> str:
    for target, rtype in slide_rels.values():
        if "notesSlide" not in rtype and "notesSlides/" not in target:
            continue
        root = _parse_xml(zf, target)
        if root is None:
            return ""
        lines: list[str] = []
        for sp in root.iter(f"{_P}sp"):
            # 跳过页码占位符
            ph = sp.find(f".//{_P}ph")
            if ph is not None and ph.attrib.get("type") in ("sldNum", "sldImg"):
                continue
            tx = sp.find(f"{_P}txBody")
            if tx is not None:
                for p in _pptx_extract_txbody(tx):
                    lines.append(p["text"])
        return _clean("\n".join(lines).strip(), 4000)
    return ""


def _parse_pptx(path: Path) -> dict[str, Any]:
    with _open_ooxml_zip(path) as zf:
        slide_paths = _pptx_slide_paths(zf)
        if not slide_paths:
            raise OfficeError("未找到任何幻灯片内容，或文件不是有效的 .pptx", 422)
        total_slides = len(slide_paths)
        truncated = total_slides > MAX_SLIDES
        title = _read_core_title(zf)
        imgs = _ImageBudget(zf)
        slides: list[dict[str, Any]] = []

        for idx, spath in enumerate(slide_paths[:MAX_SLIDES], start=1):
            sroot = _parse_xml(zf, spath)
            if sroot is None:
                continue
            sdir = posixpath.dirname(spath)
            sbase = posixpath.basename(spath)
            srels = _read_rels(zf, posixpath.join(sdir, "_rels", sbase + ".rels"), sdir)
            slide_title = ""
            blocks: list[dict[str, Any]] = []

            def walk_tree(node: ET.Element) -> None:
                nonlocal slide_title
                for child in node:
                    if child.tag == f"{_P}sp":
                        ph = child.find(f".//{_P}ph")
                        ph_type = (ph.attrib.get("type") or "") if ph is not None else ""
                        if ph_type in ("sldNum", "ftr", "dt"):
                            continue
                        tx = child.find(f"{_P}txBody")
                        if tx is None:
                            continue
                        paras = _pptx_extract_txbody(tx)
                        if not paras:
                            continue
                        if ph_type in ("title", "ctrTitle") and not slide_title:
                            slide_title = " ".join(p["text"] for p in paras).strip()
                        else:
                            blocks.extend(paras)
                    elif child.tag == f"{_P}graphicFrame":
                        for tbl in child.iter(f"{_A}tbl"):
                            tb = _pptx_extract_table(tbl)
                            if tb:
                                blocks.append(tb)
                    elif child.tag == f"{_P}pic":
                        blip = child.find(f".//{_A}blip")
                        if blip is not None:
                            rid = blip.attrib.get(f"{_R}embed")
                            if rid and rid in srels:
                                target = srels[rid][0]
                                uri = imgs.extract(target)
                                if uri:
                                    blocks.append({"kind": "image", "src": uri, "alt": posixpath.basename(target)})
                    elif child.tag == f"{_P}grpSp":
                        walk_tree(child)

            sptree = sroot.find(f".//{_P}spTree")
            if sptree is not None:
                walk_tree(sptree)

            notes = _pptx_read_notes(zf, srels)
            slide_obj: dict[str, Any] = {
                "index": idx,
                "title": slide_title,
                "blocks": blocks,
            }
            if notes:
                slide_obj["notes"] = notes
            slides.append(slide_obj)

        return {
            "type": "pptx",
            "title": title,
            "slides": slides,
            "truncated": truncated,
            "meta": {
                "slides": len(slides),
                "total_slides": total_slides,
                "images": imgs.count,
                "omitted_images": imgs.omitted,
            },
        }


def _parse_csv(path: Path, filename: str) -> dict[str, Any]:
    delim = "\t" if filename.lower().endswith(".tsv") else ","
    try:
        raw = path.read_bytes()[:4 * 1024 * 1024]  # 最多读取前 4 MB
    except OSError:
        raise OfficeError("文件不存在", 404)
    text = None
    for enc in ("utf-8-sig", "utf-8", "gb18030"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        text = raw.decode("utf-8", errors="replace")
    reader = csv.reader(io.StringIO(text), delimiter=delim)
    raw_rows: list[list[str]] = []
    total_rows = 0
    max_cols = 0
    trunc_rows = False
    trunc_cols = False
    try:
        for row in reader:
            total_rows += 1
            if len(row) > max_cols:
                max_cols = len(row)
            if len(row) > MAX_SHEET_COLS:
                trunc_cols = True
            if len(raw_rows) < MAX_SHEET_ROWS:
                raw_rows.append([_clean(c, MAX_CELL_LEN) for c in row[:MAX_SHEET_COLS]])
            else:
                trunc_rows = True
                if total_rows >= 5000:
                    break
    except csv.Error as e:
        raise OfficeError(f"表格解析失败：{e}", 422)
    grid = _trim_grid(raw_rows)
    return {
        "type": "csv",
        "title": "",
        "sheets": [{
            "name": _clean(filename, 120),
            "rows": grid,
            "total_rows": total_rows if trunc_rows else len(grid),
            "total_cols": max_cols if trunc_cols else (len(grid[0]) if grid else 0),
            "truncated_rows": trunc_rows,
            "truncated_cols": trunc_cols,
        }],
        "truncated": trunc_rows or trunc_cols,
        "meta": {"sheets": 1, "total_sheets": 1},
    }


def parse_office(path: Path, filename: str) -> dict[str, Any]:
    kind = office_type(filename)
    if kind is None:
        raise OfficeError("不是支持预览的 Office 文档类型", 415)
    if kind == "unsupported":
        ext = filename.rpartition(".")[2].upper()
        raise OfficeError(
            f"暂不支持预览旧版 {ext} 文档（支持 docx / xlsx / xls / csv / pptx），请下载后查看",
            415,
        )
    try:
        size = path.stat().st_size
    except OSError:
        raise OfficeError("文件不存在", 404)
    if size > MAX_OFFICE_BYTES:
        raise OfficeError("文档超过 50 MB，不支持在线预览，请下载后查看", 413)
    if kind == "docx":
        out = _parse_docx(path)
    elif kind == "xlsx":
        out = _parse_xlsx(path)
    elif kind == "xls":
        out = _parse_xls(path)
    elif kind == "csv":
        out = _parse_csv(path, filename)
    else:
        out = _parse_pptx(path)
    out["ok"] = True
    return out
