import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/api.dart';
import '../theme/ink_theme.dart';
import 'ink.dart';

String fmtBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1073741824).toStringAsFixed(2)} GB';
}

/// 压缩包目录树节点（纯显示用；路径里的 `..` 之类只当作普通文字）
class ArchiveNode {
  ArchiveNode(this.name, {this.isDir = true});
  final String name;
  bool isDir;
  int size = 0;
  int count = 0;
  bool encrypted = false;
  final Map<String, ArchiveNode> kids = {};

  /// 把条目列表构造成目录树
  static ArchiveNode build(List<ArchiveEntry> entries) {
    final root = ArchiveNode('');
    for (final e in entries) {
      final parts = e.path.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      var n = root;
      for (var i = 0; i < parts.length; i++) {
        final last = i == parts.length - 1;
        final isDir = !last || e.isDir;
        final key = isDir ? '${parts[i]}/' : parts[i];
        n = n.kids.putIfAbsent(key, () => ArchiveNode(parts[i], isDir: isDir));
        if (last && !e.isDir) {
          n.size = e.size;
          n.encrypted = e.encrypted;
        }
      }
    }
    _sum(root);
    return root;
  }

  static void _sum(ArchiveNode n) {
    for (final c in n.kids.values) {
      _sum(c);
      n.size += c.size;
      n.count += c.isDir ? c.count : 1;
    }
  }

  List<ArchiveNode> sortedKids() {
    final l = kids.values.toList();
    l.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return l;
  }
}

/// 压缩包目录查看器：调用服务端 `GET /api/items/<uuid>/archive`，不下载、不解压。
class ArchiveView extends StatefulWidget {
  const ArchiveView({super.key, required this.api, required this.item});
  final ClipApi api;
  final ClipItem item;

  @override
  State<ArchiveView> createState() => _ArchiveViewState();
}

class _ArchiveViewState extends State<ArchiveView> {
  ArchiveListing? _data;
  ArchiveNode? _root;
  String? _err;
  final Set<ArchiveNode> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.archiveListing(widget.item.uuid);
      final root = ArchiveNode.build(d.entries);
      if (!mounted) return;
      setState(() {
        _data = d;
        _root = root;
        _open.addAll(root.kids.values.where((k) => k.isDir)); // 顶层目录默认展开
      });
    } catch (e) {
      if (mounted) setState(() => _err = e is ApiException ? e.message : '$e');
    }
  }

  List<(ArchiveNode, int)> _flatten(ArchiveNode n, int depth) {
    final out = <(ArchiveNode, int)>[];
    for (final c in n.sortedKids()) {
      out.add((c, depth));
      if (c.isDir && _open.contains(c)) out.addAll(_flatten(c, depth + 1));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    if (_err != null) {
      return Center(
        child: InkCard(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_zip_outlined, size: 56, color: t.ink),
            const SizedBox(height: 10),
            Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: t.danger)),
          ]),
        ),
      );
    }
    final d = _data;
    final root = _root;
    if (d == null || root == null) return const Center(child: CircularProgressIndicator());
    final rows = _flatten(root, 0);
    final bits = <String>[
      '${d.total} 项',
      '解压后约 ${fmtBytes(d.totalSize)}',
      if (d.encrypted) '含加密文件（只显示目录）',
      if (d.truncated) '仅显示前 ${d.entries.length} 项',
    ];
    return Column(children: [
      Container(
        width: double.infinity,
        color: t.paper2,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(bits.join(' · '), style: t.monoStyle(12.5)),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text('（空压缩包）', style: TextStyle(color: t.muted)))
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final (n, depth) = rows[i];
                  final open = _open.contains(n);
                  return InkWell(
                    onTap: n.isDir
                        ? () => setState(() => open ? _open.remove(n) : _open.add(n))
                        : null,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(14 + depth * 18.0, 7, 14, 7),
                      child: Row(children: [
                        Icon(
                          n.isDir
                              ? (open ? Icons.folder_open : Icons.folder_outlined)
                              : (n.encrypted ? Icons.lock_outline : Icons.insert_drive_file_outlined),
                          size: 20,
                          color: n.isDir ? t.accent : t.ink,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(n.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.monoStyle(13.5).copyWith(fontWeight: n.isDir ? FontWeight.w700 : FontWeight.w500)),
                        ),
                        const SizedBox(width: 8),
                        Text(n.isDir ? '${n.count} 项 · ${fmtBytes(n.size)}' : fmtBytes(n.size),
                            style: t.monoStyle(12, color: t.muted)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
