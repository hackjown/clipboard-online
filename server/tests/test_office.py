"""Office 文档结构化预览：docx / xlsx / xls / pptx、嵌入图片、加密、XXE、损坏、旧版 415、鉴权、分享"""
import io
import zipfile
from datetime import datetime

import openpyxl
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app, preview_kind


@pytest.fixture()
def client(tmp_path):
    c = TestClient(create_app(data_dir=str(tmp_path), allow_register=True))
    assert c.post("/api/register", json={"username": "alice", "password": "demo123"}).status_code == 200
    return c


def up(c, name, data, vis="private"):
    r = c.post("/upload_file", data={"visibility": vis, "expires_in": "0"}, files={"file": (name, data)})
    assert r.status_code == 200, r.text
    return r.json()["uuid"]


def _png_bytes(color=(220, 80, 40), size=(32, 24)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="PNG")
    return buf.getvalue()


def make_docx(body_xml: str, *, styles_xml: str | None = None, rels_xml: str | None = None,
              title: str = "", extra: dict[str, bytes] | None = None) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        doc = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
            ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
            ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            f'<w:body>{body_xml}</w:body></w:document>'
        )
        z.writestr("word/document.xml", doc)
        if styles_xml:
            z.writestr("word/styles.xml", styles_xml)
        if rels_xml:
            z.writestr("word/_rels/document.xml.rels", rels_xml)
        if title:
            z.writestr(
                "docProps/core.xml",
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"'
                ' xmlns:dc="http://purl.org/dc/elements/1.1/">'
                f'<dc:title>{title}</dc:title></cp:coreProperties>',
            )
        for k, v in (extra or {}).items():
            z.writestr(k, v)
    return buf.getvalue()


def make_xlsx(sheets: list[tuple[str, list[list]]]) -> bytes:
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    for name, rows in sheets:
        ws = wb.create_sheet(title=name)
        for r in rows:
            ws.append(r)
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def make_pptx() -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        # 故意把 slide2 排在 slide1 前面，验证按 presentation.xml 的 sldIdLst 顺序输出
        z.writestr(
            "ppt/presentation.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
            ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<p:sldIdLst><p:sldId id="257" r:id="rId2"/><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
            '</p:presentation>',
        )
        z.writestr(
            "ppt/_rels/presentation.xml.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>'
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/>'
            '</Relationships>',
        )
        z.writestr(
            "ppt/slides/slide2.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
            ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"'
            ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<p:cSld><p:spTree>'
            '<p:sp><p:nvSpPr><p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr>'
            '<p:txBody><a:p><a:r><a:t>封面标题</a:t></a:r></a:p></p:txBody></p:sp>'
            '<p:sp><p:nvSpPr><p:nvPr/></p:nvSpPr>'
            '<p:txBody>'
            '<a:p><a:pPr lvl="0"/><a:r><a:t>第一要点</a:t></a:r></a:p>'
            '<a:p><a:pPr lvl="1"/><a:r><a:t>二级要点</a:t></a:r></a:p>'
            '</p:txBody></p:sp>'
            '<p:pic><p:blipFill><a:blip r:embed="rImg1"/></p:blipFill></p:pic>'
            '</p:spTree></p:cSld></p:sld>',
        )
        z.writestr(
            "ppt/slides/_rels/slide2.xml.rels",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rImg1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/chart.png"/>'
            '<Relationship Id="rNote1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" Target="../notesSlides/notesSlide1.xml"/>'
            '</Relationships>',
        )
        z.writestr(
            "ppt/notesSlides/notesSlide1.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<p:notes xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
            ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<p:cSld><p:spTree>'
            '<p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>'
            '<p:txBody><a:p><a:r><a:t>这里是演讲者备注</a:t></a:r></a:p></p:txBody></p:sp>'
            '<p:sp><p:nvSpPr><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr>'
            '<p:txBody><a:p><a:r><a:t>1</a:t></a:r></a:p></p:txBody></p:sp>'
            '</p:spTree></p:cSld></p:notes>',
        )
        z.writestr("ppt/media/chart.png", _png_bytes())
        z.writestr(
            "ppt/slides/slide1.xml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
            ' xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<p:cSld><p:spTree>'
            '<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
            '<p:txBody><a:p><a:r><a:t>数据表页</a:t></a:r></a:p></p:txBody></p:sp>'
            '<p:graphicFrame><a:graphic><a:graphicData><a:tbl>'
            '<a:tr><a:tc><a:txBody><a:p><a:r><a:t>指标</a:t></a:r></a:p></a:txBody></a:tc>'
            '<a:tc><a:txBody><a:p><a:r><a:t>数值</a:t></a:r></a:p></a:txBody></a:tc></a:tr>'
            '<a:tr><a:tc><a:txBody><a:p><a:r><a:t>DAU</a:t></a:r></a:p></a:txBody></a:tc>'
            '<a:tc><a:txBody><a:p><a:r><a:t>1024</a:t></a:r></a:p></a:txBody></a:tc></a:tr>'
            '</a:tbl></a:graphicData></a:graphic></p:graphicFrame>'
            '</p:spTree></p:cSld></p:sld>',
        )
    return buf.getvalue()


def test_preview_kind_office():
    for n in ["a.docx", "A.DOCX", "b.xlsx", "c.xlsm", "d.xls", "e.pptx", "f.doc", "g.ppt"]:
        assert preview_kind(n) == "office", n


def test_docx_preview_blocks_tables_images_and_security(client):
    styles = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:styleId="H1"><w:name w:val="标题 1"/></w:style>'
        '</w:styles>'
    )
    rels = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdImg" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/pic.png"/>'
        '</Relationships>'
    )
    body = (
        '<w:p><w:pPr><w:pStyle w:val="H1"/></w:pPr><w:r><w:t>第一章 总览</w:t></w:r></w:p>'
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>加粗</w:t></w:r><w:r><w:t>与&lt;script&gt;x&lt;/script&gt;\u202e</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/></w:numPr></w:pPr><w:r><w:t>列表项</w:t></w:r></w:p>'
        '<w:tbl><w:tr>'
        '<w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:p><w:r><w:t>合并标题</w:t></w:r></w:p></w:tc>'
        '</w:tr><w:tr>'
        '<w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>B1</w:t></w:r></w:p></w:tc>'
        '</w:tr></w:tbl>'
        '<w:p><w:r><w:drawing><a:blip r:embed="rIdImg"/></w:drawing></w:r></w:p>'
    )
    data = make_docx(body, styles_xml=styles, rels_xml=rels, title="年度报告", extra={"word/media/pic.png": _png_bytes()})
    uid = up(client, "report.docx", data)

    r = client.get(f"/api/items/{uid}/office")
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["ok"] is True and d["type"] == "docx" and d["title"] == "年度报告"
    assert d["meta"]["tables"] == 1 and d["meta"]["images"] == 1
    blocks = d["blocks"]
    assert blocks[0] == {"kind": "heading", "level": 1, "text": "第一章 总览"}
    assert blocks[1]["kind"] == "paragraph" and blocks[1]["runs"][0] == {"t": "加粗", "b": True}
    assert "\u202e" not in blocks[1]["text"]  # bidi 覆盖字符已剔除
    assert "<script>x</script>" in blocks[1]["text"]  # 原样文本，由前端 textContent 渲染
    assert blocks[2]["list"] is True and blocks[2]["indent"] == 1
    assert blocks[3]["kind"] == "table" and blocks[3]["rows"][0][0] == {"text": "合并标题", "colspan": 2}
    assert blocks[4]["kind"] == "image" and blocks[4]["src"].startswith("data:image/")

    # 原文件下载依然强制 attachment，不会内联
    dl = client.get("/download/report.docx?inline=1")
    assert dl.headers["content-disposition"].startswith("attachment")


def test_xlsx_preview_multisheet_and_truncation(client):
    big_rows = [["编号", "名称", "日期", "布尔"]] + [
        [i, f"项{i}", datetime(2026, 11, 23), i % 2 == 0] for i in range(520)
    ]
    data = make_xlsx([
        ("汇总", [["项目", "金额"], ["服务器", 1280.0], ["", ""], ["", ""]]),
        ("明细", big_rows),
    ])
    uid = up(client, "budget.xlsx", data)
    r = client.get(f"/api/items/{uid}/office")
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["type"] == "xlsx" and d["meta"]["total_sheets"] == 2 and d["truncated"] is True
    s0 = d["sheets"][0]
    assert s0["name"] == "汇总" and s0["rows"] == [["项目", "金额"], ["服务器", "1280"]]
    s1 = d["sheets"][1]
    assert s1["truncated_rows"] is True and len(s1["rows"]) == 500
    assert s1["rows"][1] == ["0", "项0", "2026-11-23", "TRUE"]


def test_pptx_preview_order_table_image_notes(client):
    uid = up(client, "deck.pptx", make_pptx())
    r = client.get(f"/api/items/{uid}/office")
    assert r.status_code == 200, r.text
    d = r.json()
    assert d["type"] == "pptx" and d["meta"]["total_slides"] == 2 and d["meta"]["images"] == 1
    sl1, sl2 = d["slides"]
    assert sl1["index"] == 1 and sl1["title"] == "封面标题"
    assert sl1["notes"] == "这里是演讲者备注"
    assert any(b["kind"] == "paragraph" and b.get("indent") == 1 and b["text"] == "二级要点" for b in sl1["blocks"])
    assert any(b["kind"] == "image" and b["src"].startswith("data:image/") for b in sl1["blocks"])
    assert sl2["index"] == 2 and sl2["title"] == "数据表页"
    assert sl2["blocks"][0]["kind"] == "table" and sl2["blocks"][0]["rows"][1][1]["text"] == "1024"


def test_legacy_doc_ppt_415(client):
    for n in ("old.doc", "old.ppt"):
        uid = up(client, n, b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"\0" * 32)
        r = client.get(f"/api/items/{uid}/office")
        assert r.status_code == 415 and "暂不支持" in r.text


def test_encrypted_and_corrupt_and_xxe_rejected(client):
    # 加密 OOXML（OLE2 魔数）
    uid_enc = up(client, "enc.docx", b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1" + b"\0" * 64)
    r_enc = client.get(f"/api/items/{uid_enc}/office")
    assert r_enc.status_code == 422 and "加密" in r_enc.text

    # XXE / DOCTYPE 拒绝
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("word/document.xml", '<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><w:document/>')
    uid_xxe = up(client, "xxe.docx", buf.getvalue())
    assert client.get(f"/api/items/{uid_xxe}/office").status_code == 422

    # 损坏文件
    for bad in ("bad.docx", "bad.xlsx", "bad.xls", "bad.pptx"):
        uid = up(client, bad, b"not an office file" * 10)
        assert client.get(f"/api/items/{uid}/office").status_code == 422, bad


def test_office_auth_and_share_and_features(client):
    assert "office" in client.get("/api/version").json()["features"]

    data = make_docx('<w:p><w:r><w:t>私密内容</w:t></w:r></w:p>')
    uid_priv = up(client, "secret.docx", data, vis="private")
    uid_pub = up(client, "pub.docx", data, vis="public")
    token = client.post(f"/api/items/{uid_priv}/share", json={"hours": 1}).json()["token"]

    client.post("/api/logout")
    assert client.get(f"/api/items/{uid_priv}/office").status_code == 403
    assert client.get(f"/api/items/{uid_pub}/office").status_code == 200
    assert client.get(f"/api/share/{token}").json()["preview"] == "office"
    sh = client.get(f"/s/{token}/office")
    assert sh.status_code == 200 and sh.json()["blocks"][0]["text"] == "私密内容"
    assert client.get("/s/nope/office").status_code == 404

    # 过期分享不可预览
    client.app.state.store.update_item(uid_priv, share_expires_at=1.0)
    assert client.get(f"/s/{token}/office").status_code == 404
