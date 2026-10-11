import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';
import '../theme/ink_theme.dart';
import 'ink.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onDelete,
    required this.onShareLink,
    required this.onSystemShare,
    required this.onFavorite,
    required this.onPin,
    required this.onOpen,
    this.onReveal,
    this.imageUrl,
    this.headers,
  });

  final ClipItem item;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

  /// 生成分享链接与二维码
  final VoidCallback? onShareLink;

  /// 系统分享面板（微信等）
  final VoidCallback? onSystemShare;
  final VoidCallback? onFavorite;
  final VoidCallback? onPin;

  /// 打开预览 / 详情页
  final VoidCallback onOpen;

  /// macOS：在访达中显示
  final VoidCallback? onReveal;
  final String? imageUrl;
  final Map<String, String>? headers;

  String _time(double ts) {
    final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '今天 ${DateFormat('HH:mm').format(d)}';
    return DateFormat('MM-dd HH:mm').format(d);
  }

  String? _expiry() {
    if (item.expiresAt == null) return null;
    final left = item.expiresAt! - DateTime.now().millisecondsSinceEpoch / 1000;
    if (left <= 0) return '已过期';
    if (left < 3600) return '${(left / 60).ceil()} 分钟后过期';
    if (left < 86400) return '${(left / 3600).ceil()} 小时后过期';
    return '${(left / 86400).ceil()} 天后过期';
  }

  String _size(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final exp = _expiry();
    final kind = item.mediaKind;
    final looksCode = item.isText &&
        (item.looksMd || RegExp(r'[{};=<>]|^\s{2,}', multiLine: true).hasMatch(item.content ?? ''));
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：类型胶囊 + 可见性 + 过期 + 元信息（等宽）
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              InkChip(item.isText ? '文本' : '文件', color: item.isText ? t.lime : t.sky),
              InkChip(item.isPublic ? '公共' : '私有', color: item.isPublic ? t.sun : t.pink),
              if (exp != null) InkChip(exp, color: t.pink),
              Text(
                [
                  _time(item.created),
                  if (item.ownerUsername != null) '@${item.ownerUsername}',
                  if (item.isFile) _size(item.size),
                ].join('  ·  '),
                style: t.monoStyle(12, color: t.muted).copyWith(height: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 内容
          if (item.isFile && kind == MediaKind.image && imageUrl != null)
            GestureDetector(
              onTap: onOpen,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.line, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl!,
                    headers: headers,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 80,
                      color: t.paper2,
                      alignment: Alignment.center,
                      child: Icon(Icons.broken_image_outlined, color: t.muted),
                    ),
                  ),
                ),
              ),
            )
          else if (item.isFile)
            GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Row(children: [
                _FileTile(kind: kind),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.filename ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.35)),
                    const SizedBox(height: 3),
                    Text(
                      switch (kind) {
                        MediaKind.video => '视频 · 点击播放',
                        MediaKind.audio => '音频 · 点击播放',
                        MediaKind.pdf => 'PDF · 点击查看',
                        MediaKind.text => '文本文件 · 点击预览',
                        MediaKind.archive => '压缩包 · 点击查看目录',
                        _ => '点击查看 / 分享',
                      },
                      style: t.monoStyle(12.5, color: t.muted).copyWith(height: 1.3),
                    ),
                  ]),
                ),
              ]),
            )
          else
            GestureDetector(
              onTap: onOpen,
              child: Container(
                width: double.infinity,
                padding: looksCode ? const EdgeInsets.fromLTRB(12, 10, 12, 10) : EdgeInsets.zero,
                decoration: looksCode
                    ? BoxDecoration(
                        color: t.paper2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.ink.withValues(alpha: 0.35), width: 1.5),
                      )
                    : null,
                child: Text(
                  item.content ?? '',
                  maxLines: looksCode ? 7 : 6,
                  overflow: TextOverflow.fade,
                  style: looksCode
                      ? t.monoStyle(13.5)
                      : const TextStyle(fontSize: 15.5, height: 1.62),
                ),
              ),
            ),
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: item.tags
                  .map((x) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.paper2,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: t.line.withValues(alpha: 0.5), width: 1.5),
                        ),
                        child: Text('#$x', style: t.monoStyle(11.5).copyWith(height: 1.2)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.isText)
                InkButton(label: '复制', icon: Icons.copy_rounded, onPressed: onCopy)
              else
                InkButton(label: '预览', icon: Icons.visibility_outlined, onPressed: onOpen),
              if (onSystemShare != null)
                InkButton(label: '分享', icon: Icons.ios_share, variant: InkVariant.ink, onPressed: onSystemShare),
              if (onReveal != null)
                InkButton(label: '在访达中显示', icon: Icons.folder_open, onPressed: onReveal),
              if (onShareLink != null)
                InkIconButton(icon: Icons.qr_code_2, tooltip: '链接 / 二维码', onPressed: onShareLink),
              if (onFavorite != null)
                InkIconButton(
                  icon: item.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: item.favorite ? const Color(0xFFE0A800) : null,
                  tooltip: '收藏',
                  onPressed: onFavorite,
                ),
              if (onPin != null && item.mine)
                InkIconButton(
                  icon: item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  tooltip: '置顶',
                  onPressed: onPin,
                ),
              if (onDelete != null)
                InkIconButton(icon: Icons.delete_outline, color: t.danger, tooltip: '删除', onPressed: onDelete),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.kind});
  final MediaKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    final (icon, color) = switch (kind) {
      MediaKind.video => (Icons.play_circle_outline_rounded, t.pink),
      MediaKind.audio => (Icons.graphic_eq_rounded, t.lime),
      MediaKind.pdf => (Icons.picture_as_pdf_outlined, t.pink),
      MediaKind.text => (Icons.description_outlined, t.sun),
      MediaKind.image => (Icons.image_outlined, t.sky),
      MediaKind.archive => (Icons.folder_zip_outlined, t.lime),
      _ => (Icons.insert_drive_file_outlined, t.sky),
    };
    return Container(
      width: 52,
      height: 62,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.line, width: 2),
        boxShadow: t.hardShadow(2),
      ),
      child: Icon(icon, size: 28, color: InkTokens.onColor),
    );
  }
}
