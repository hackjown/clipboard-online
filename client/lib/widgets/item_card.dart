import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onDelete,
    required this.onShare,
    required this.onFavorite,
    required this.onPin,
    this.imageUrl,
  });

  final ClipItem item;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;
  final VoidCallback? onFavorite;
  final VoidCallback? onPin;
  final String? imageUrl;

  String _time(double ts) {
    final d = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    final now = DateTime.now();
    final diff = now.difference(d);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final exp = _expiry();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(context, item.isText ? '文本' : '文件', cs.primaryContainer),
                _chip(context, item.isPublic ? '公共' : '私有',
                    item.isPublic ? cs.tertiaryContainer : cs.secondaryContainer),
                if (exp != null) _chip(context, exp, cs.errorContainer),
                Text(_time(item.created), style: Theme.of(context).textTheme.bodySmall),
                if (item.ownerUsername != null)
                  Text('@${item.ownerUsername}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            if (item.isImage && imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(imageUrl!, height: 160, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            if (item.isText)
              SelectableText(
                item.content ?? '',
                maxLines: 8,
                style: TextStyle(
                  fontFamily: item.looksMd || (item.content ?? '').contains('{') ? 'monospace' : null,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              )
            else
              Text(item.filename ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (item.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: item.tags
                    .map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (item.isText)
                  FilledButton.tonalIcon(onPressed: onCopy, icon: const Icon(Icons.copy, size: 18), label: const Text('复制')),
                if (item.isFile)
                  FilledButton.tonalIcon(onPressed: onCopy, icon: const Icon(Icons.download, size: 18), label: const Text('打开')),
                if (onShare != null)
                  IconButton(tooltip: '分享', onPressed: onShare, icon: const Icon(Icons.ios_share)),
                if (onFavorite != null)
                  IconButton(
                    tooltip: '收藏',
                    onPressed: onFavorite,
                    icon: Icon(item.favorite ? Icons.star : Icons.star_border,
                        color: item.favorite ? Colors.amber : null),
                  ),
                if (onPin != null && item.mine)
                  IconButton(
                    tooltip: '置顶',
                    onPressed: onPin,
                    icon: Icon(item.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  ),
                if (onDelete != null)
                  IconButton(tooltip: '删除', onPressed: onDelete, icon: Icon(Icons.delete_outline, color: cs.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}
