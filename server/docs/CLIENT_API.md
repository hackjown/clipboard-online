# Clipboard Online · 客户端 API 指南

本文面向 iOS / Android / Mac / 第三方脚本，说明如何对接本服务的 HTTP 与 WebSocket 接口。  
交互式文档：服务运行后打开 `/docs`（Swagger）或 `/redoc`；机器可读规范见同目录 `openapi.json` 与线上 `/openapi.json`。

**基址示例**：`https://clip.example.com`（下文用 `{BASE}`）

---

## 1. 认证

### 1.1 注册 / 登录

```http
POST /api/register
POST /api/login
Content-Type: application/json

{"username":"<用户名>","password":"<密码>"}
```

成功响应：

```json
{
  "ok": true,
  "user": {"id":"…","username":"alice","created_at": 1710000000},
  "token": "<签名会话令牌>"
}
```

同时会设置 **httpOnly Cookie** `clip_session`（Web 浏览器最省事）。

### 1.2 移动端推荐：Bearer

原生 App 请保存登录返回的 `token`，之后每个请求带：

```http
Authorization: Bearer <token>
```

Cookie 与 Bearer **二选一即可**；优先级：Cookie → Bearer。

WebSocket：

```
WS {BASE}/ws?token=<token>
```

（浏览器也可依赖 Cookie，无需 query。）

### 1.3 其它

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/me` | 当前用户或 `{"user":null}` |
| GET | `/api/config` | `register` / `max_upload` / `user` 等 |
| POST | `/api/logout` | 清 Cookie（Bearer 客户端本地删 token 即可） |

用户名：2–32 位，字母数字汉字、`_` `.` `-`。密码：6–128 位。  
注册可用环境变量 `CLIP_REGISTER=0` 关闭。登录失败有简单限流。

---

## 2. 分区规则（必读）

| 可见性 | 访客 | 登录用户 |
| --- | --- | --- |
| **public** | 可列表、复制、下载 | 同左；**仅上传者可删** |
| **private** | 不可见 | 仅本人可见、可增删改 |

- 访客 **不能** `POST /content` / `/upload_file` / `/delete` / clear。  
- 清空接口 **只清自己的**，绝不碰别人的公共内容。  
- 私有文件下载需本人认证；公共文件访客可下。

---

## 3. 条目列表

```http
GET /api/items?scope=public|private|all|mine&type=all|text|file&q=&tag=&starred=1
Authorization: Bearer …
```

响应摘要：

```json
{
  "items": [{
    "uuid": "…", "type": "text|file", "visibility": "public|private",
    "content": "…", "filename": "…", "ext": "png", "is_image": true,
    "size": 123, "created": 1710000000, "expires_at": null,
    "owner_username": "alice", "mine": true,
    "favorite": false, "pinned": true, "tags": ["工作"],
    "has_share": true, "share_token": "…", "looks_md": true, "is_url": false
  }],
  "counts": {"total":10,"public":8,"private":2,"text":5,"file":5,"bytes":1000,"starred":1},
  "tags": ["工作","备忘"],
  "need_auth": false
}
```

- `scope=private` 且未登录 → `need_auth: true`，`items: []`  
- 列表已按「置顶优先 + 时间倒序」排好  
- 过期条目会在读取时惰性删除

---

## 4. 添加文本 / 上传文件

### 文本

```http
POST /content
Authorization: Bearer …
Content-Type: application/json

{
  "content": "hello",
  "visibility": "private",
  "expires_in": 0,
  "tags": ["备忘"]
}
```

`expires_in`（秒）：`0` 不过期；`3600` / `86400` / `604800`；省略时 **公共默认 86400（24h），私有默认 0**。

### 文件（含截图）

```http
POST /upload_file
Authorization: Bearer …
Content-Type: multipart/form-data

file: <binary>
visibility: public|private
expires_in: 86400
tags: 设计,演示
```

图片且文件名为空/`blob` 时，服务端会生成 `screenshot-YYYYMMDD-HHMMSS.png`。  
下载：`GET /download/{filename}`（私有需认证；图片可 inline 预览）。

---

## 5. 删除与清空

```http
POST /delete
{"uuid":"…"}

POST /api/clear
{"command":"clear","scope":"private|public|all"}
```

`scope` 只作用于 **当前用户** 的内容。  
兼容旧路径：`/clear_text` `/clear_files` `/clear_clipboard`（均只清本人私有）。

---

## 6. 分享链接

```http
POST /api/items/{uuid}/share
{"hours": 168}

DELETE /api/items/{uuid}/share

GET /api/share/{token}          # 访客可读 JSON
GET /s/{token}                  # 访客 HTML 页
GET /s/{token}/file             # 访客下文件
GET /api/share/{token}/qr       # PNG 二维码
```

私有条目生成分享后，**任何人凭 token 可查看/下载**，直到过期或撤销。UI 中需明确告知用户。

Deep link 建议：`{BASE}/s/{token}`（App 可注册 Universal Link / App Link）。

---

## 7. 收藏 / 置顶 / 标签

| 接口 | 规则 |
| --- | --- |
| `POST /api/items/{uuid}/favorite` | 任意**对自己可见**的条目；返回 `{favorite:bool}` |
| `POST /api/items/{uuid}/pin` | **仅本人内容**；返回 `{pinned:bool}` |
| `POST /api/items/{uuid}/tags` | **仅本人**；body `{"tags":["a","b"]}` 最多 8 个，每个 ≤32 字 |

筛选：`GET /api/items?starred=1`、`?tag=工作`。

---

## 8. 其它

| 接口 | 说明 |
| --- | --- |
| `GET /api/og?url=` | 链接预览（title/domain/image）；失败仍返回 domain |
| `WS /ws` | 事件：`hello` / `create` / `update` / `delete` / `clear`；公共事件广播，私有仅推给主人 |

敏感内容检测目前在 **Web 前端**完成（密钥/JWT/`sk-` 等），客户端可自行复刻同一套启发规则。

---

## 9. 错误格式

HTTP 4xx/5xx，body 统一：

```json
{"ok": false, "error": "中文说明", "detail": "中文说明"}
```

常见码：`400` 参数错误 · `401` 未登录 · `403` 无权限/关闭注册 · `404` 不存在 · `409` 用户名占用 · `413` 超大小 · `429` 限流。

---

## 10. curl 示例

```bash
BASE=http://127.0.0.1:8099

# 登录拿 token
TOKEN=$(curl -s -X POST $BASE/api/login -H 'Content-Type: application/json' \
  -d '{"username":"<用户名>","password":"<密码>"}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')

# 列表公共
curl -s "$BASE/api/items?scope=public" | python3 -m json.tool | head

# 添加私有文本
curl -s -X POST $BASE/content -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"content":"from curl","visibility":"private","expires_in":0}'

# 上传图片
curl -s -X POST $BASE/upload_file -H "Authorization: Bearer $TOKEN" \
  -F "file=@shot.png" -F "visibility=public" -F "expires_in=86400"

# 分享
UUID=……
curl -s -X POST $BASE/api/items/$UUID/share -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"hours":24}'
```

---

## 11. Flutter / Dart 速写

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class ClipApi {
  ClipApi(this.base);
  final String base;
  String? token;

  Map<String, String> get _h => {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<void> login(String user, String pass) async {
    final r = await http.post(Uri.parse('$base/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': user, 'password': pass}));
    final j = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(j['error']);
    token = j['token'] as String;
  }

  Future<List<dynamic>> items({String scope = 'all'}) async {
    final r = await http.get(Uri.parse('$base/api/items?scope=$scope'), headers: _h);
    return jsonDecode(r.body)['items'] as List<dynamic>;
  }

  Future<void> addText(String content, {String visibility = 'private', int expiresIn = 0}) async {
    final r = await http.post(Uri.parse('$base/content'),
        headers: _h,
        body: jsonEncode({
          'content': content,
          'visibility': visibility,
          'expires_in': expiresIn,
        }));
    if (r.statusCode != 200) throw Exception(jsonDecode(r.body)['error']);
  }
}

// WebSocket: WebSocketChannel.connect(Uri.parse('wss://host/ws?token=$token'));
```

完整字段以 `/openapi.json` 为准。更多产品规划见 [CLIENT_ROADMAP.md](./CLIENT_ROADMAP.md)。
