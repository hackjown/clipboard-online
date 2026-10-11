"""演示数据：图片、标签、过期公共条目、Markdown、分享。"""
import json, os, sys, time
from pathlib import Path
from io import BytesIO
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app.main import create_app
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont

data = Path(os.environ.get("CLIP_DATA_DIR") or (ROOT / "data"))
for p in list(data.glob("*")):
    if p.is_file():
        p.unlink()
    elif p.name == "uploads":
        for f in p.iterdir():
            f.unlink()
data.mkdir(parents=True, exist_ok=True)
(data / "uploads").mkdir(exist_ok=True)

app = create_app(data_dir=str(data), allow_register=True)
c = TestClient(app)

def reg(u, p="demo123"):
    r = c.post("/api/register", json={"username": u, "password": p})
    assert r.status_code == 200, r.text

def png_bytes(text, color=(255, 79, 43)):
    im = Image.new("RGB", (640, 360), (250, 246, 236))
    d = ImageDraw.Draw(im)
    d.rectangle([20, 20, 620, 340], outline=(23, 20, 15), width=4)
    d.rectangle([40, 40, 200, 100], fill=color)
    d.text((60, 140), text, fill=(23, 20, 15))
    buf = BytesIO(); im.save(buf, format="PNG"); return buf.getvalue()

now = time.time()
reg("demo1")
c.post("/content", json={"content": "【公共】周五评审会：首页改版通过。\n\n## 待办\n- 整理访谈\n- 更新设计规范\n\n**注意**：演示数据。", "visibility": "public", "expires_in": 86400})
c.post("/content", json={"content": "https://example.com", "visibility": "public", "expires_in": 86400})
c.post("/content", json={"content": "docker run -d --name demo -p 8080:80 nginx:alpine", "visibility": "public", "expires_in": 0})
c.post("/content", json={"content": "我的私密备忘：demo_token_aaaa_bbbb_cccc（假数据）", "visibility": "private", "expires_in": 0})
c.post("/upload_file", data={"visibility": "public", "expires_in": "86400", "tags": "设计,演示"},
       files={"file": ("screenshot-demo.png", png_bytes("Clipboard Demo Shot"), "image/png")})
c.post("/upload_file", data={"visibility": "public", "expires_in": "0"},
       files={"file": ("report.pdf", b"%PDF-1.4 demo " * 100, "application/pdf")})
c.post("/upload_file", data={"visibility": "private", "expires_in": "0", "tags": "私密"},
       files={"file": ("notes-private.txt", b"private notes", "text/plain")})
# tag + pin + favorite
items = c.get("/api/items?scope=mine").json()["items"]
for it in items:
    if it["type"] == "text" and it["visibility"] == "private":
        c.post(f"/api/items/{it['uuid']}/pin")
        c.post(f"/api/items/{it['uuid']}/tags", json={"tags": ["备忘", "重要"]})
    if it.get("is_image"):
        c.post(f"/api/items/{it['uuid']}/favorite")
        c.post(f"/api/items/{it['uuid']}/share", json={"hours": 168})
c.post("/api/logout")

reg("demo2")
c.post("/content", json={"content": "【公共】demo2：下周对一下接口契约。", "visibility": "public", "expires_in": 3600})
c.post("/content", json={"content": "demo2 私有购物清单", "visibility": "private", "expires_in": 0})
c.post("/upload_file", data={"visibility": "public", "expires_in": "86400"},
       files={"file": ("cover.webp", png_bytes("demo2 cover", (205, 242, 107)), "image/png")})
c.post("/api/logout")

reg("alice")
c.post("/content", json={"content": "alice 公共提示：粘贴截图可直接上传。", "visibility": "public", "expires_in": 604800})
c.post("/content", json={"content": "alice 私有日记", "visibility": "private", "expires_in": 0})
c.post("/api/logout")

raw = json.loads((data / "items.json").read_text())
for i, it in enumerate(raw):
    it["created"] = now - [120, 400, 900, 3600, 7200, 10000, 20000, 40000, 80000, 100000, 120000][i % 11]
(data / "items.json").write_text(json.dumps(raw, ensure_ascii=False))
print("seeded", len(raw), "items,", len(json.loads((data/"users.json").read_text())), "users")
