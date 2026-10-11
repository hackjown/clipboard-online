# Clipboard Online · 多用户在线剪贴板（增强版）

跨设备、跨账号的在线剪贴板：**私有区 + 公共区**，支持截图粘贴、分享二维码、自动过期、实时同步、Markdown、收藏标签等。

**视觉：软粗野主义 · 纸与墨。** 后端 FastAPI（文件存储），前端原生 HTML/CSS/JS（无构建；二维码库已本地 vendor）。

## 分区规则

| | 访客 | 登录用户 |
| --- | --- | --- |
| 公共内容 | 浏览 / 复制 / 下载 | 同左；**仅本人可删自己发的** |
| 私有内容 | 不可见 | 仅本人可见可管 |
| 添加 | 需登录 | 可选私有/公共（默认私有） |
| 临时分享 | 凭 `/s/<token>` 可查看 | 可为私有内容生成限时公开链接 + 二维码 |

## 增强功能

1. **截图/图片粘贴**：Ctrl/Cmd+V 或拖拽图片 → 自动命名 `screenshot-时间戳.png`，卡片缩略图 + 灯箱预览  
2. **分享链接 + 二维码**：每条可生成 `/s/<token>`；私有内容分享为临时公开预览，可撤销  
3. **敏感内容提醒**：公开前检测密钥/JWT/`sk-`/`AKIA`/私钥头等，确认「仍要公开 / 改为私有」  
4. **自动过期**：不过期 / 1小时 / 24小时 / 7天；**公共默认 24 小时**，私有默认不过期；过期惰性清理  
5. **WebSocket 实时**：`/ws` 推送增删改；失败自动回退 4 秒轮询  
6. **Markdown + 链接预览**：Markdown 安全子集预览；纯 URL 尝试抓取 OG（失败则显示域名）  
7. **收藏 / 标签 / 置顶**：收藏任意可见条目；标签与置顶仅限自己的内容；置顶排在当前分区最前  


## 客户端与 OpenAPI

- 在线文档：服务启动后访问 [`/docs`](http://127.0.0.1:8099/docs)（Swagger）、[`/redoc`](http://127.0.0.1:8099/redoc)、[`/openapi.json`](http://127.0.0.1:8099/openapi.json)
- 仓库内静态导出：[`docs/openapi.json`](docs/openapi.json)
- 中文对接指南：[`docs/CLIENT_API.md`](docs/CLIENT_API.md)（Cookie / **Bearer**、分区规则、分享、WS、curl 与 Flutter 速写）
- 原生规划（尚未开发）：[`docs/CLIENT_ROADMAP.md`](docs/CLIENT_ROADMAP.md)（Flutter 优先 · iOS/Android/Mac 剪贴板限制与 Deep link）

登录/注册响应含 `token` 字段，移动端请用 `Authorization: Bearer <token>`；WebSocket 可用 `/ws?token=`。

## 快速运行

```bash
./run.sh
PORT=9000 CLIP_REGISTER=0 ./run.sh
```

依赖见 `requirements.txt`（含 `qrcode`、`pillow`、`httpx`）。

```bash
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8099
CLIP_DATA_DIR=./data python tools/seed_demo.py   # 可选：灌示例数据（仅本地开发）
```

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `CLIP_REGISTER` | 开 | `0` 关闭注册 |
| `CLIP_MAX_UPLOAD_MB` | 200 | 单文件上限 |
| `CLIP_BARK_ALLOW_PRIVATE` | 关 | `1` 允许 Bark 地址指向内网 / 本机（自建 Bark 用；默认为防 SSRF 而拒绝） |
| `CLIP_MAX_TEXT_KB` | 1024 | 单条文本上限 |
| `CLIP_DATA_DIR` | `./data` | users / items / user_meta / uploads |

## 主要接口

- `POST /api/register|login` · `POST /api/logout` · `GET /api/me`
- `GET /api/items?scope=&tag=&starred=`
- `POST /content` `{content, visibility, expires_in}` · `POST /upload_file`（multipart + visibility + expires_in）
- `POST /api/items/{id}/share` · `DELETE .../share` · `GET /api/share/{token}` · `GET /s/{token}`
- `POST /api/items/{id}/favorite|pin` · `POST /api/items/{id}/tags`
- `GET /api/og?url=` · `WS /ws`

## 测试

```bash
pytest tests -v
./tests/smoke.sh http://127.0.0.1:8099
```

## 限制

- 单进程文件存储，非高并发多实例  
- OG 抓取依赖外网，可能失败（仍显示域名卡片）  
- 无邮箱验证 / 找回密码  
- Markdown 为安全子集，非完整 CommonMark  
- 分享链接知悉者可访问，勿分享真正机密  

## Bark 推送

每个用户可设置自己的 Bark 地址（`GET/PUT /api/settings/bark`，`POST /api/settings/bark/test`），其**私有**条目创建后异步推送到该地址（短超时，失败只记日志，不影响写入）。地址仅本人可读，不会出现在条目或其他用户数据里。写入请求可带 `X-Device-Id`，与设置里的 `bark_exclude_device` 相同则不推送。
