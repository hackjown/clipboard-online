/// 客户端版本号（与 pubspec.yaml 的 version 保持一致；有单元测试校验）。
const String kClientVersion = '0.1.9';

/// 官方镜像（更新服务器用）
const String kServerImage = 'ghcr.io/hackjown/clipboard-online/clipboard-online:latest';

/// 比较 "x.y.z"：a<b 返回负数，相等 0，a>b 正数；无法解析的段按 0。
int compareVersions(String a, String b) {
  List<int> parse(String s) =>
      s.split('+').first.split('.').map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p - q;
  }
  return 0;
}

/// 服务器更新命令（可复制）
String serverUpdateCommands() => '''# docker run 方式（容器名 / 端口 / 数据卷按你的实际情况修改）
docker pull $kServerImage
docker stop clipboard && docker rm clipboard
docker run -d --name clipboard --restart unless-stopped -p 8100:8099 -v clip-data:/data $kServerImage

# docker compose 方式
docker compose pull && docker compose up -d''';
