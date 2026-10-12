import 'package:flutter/material.dart';

/// 有效期选项（秒；0 = 永不过期），与网页 / 服务器一致
const List<(int, String)> kExpiryOptions = [
  (3600, '1小时'),
  (86400, '1天'),
  (604800, '7天'),
  (2592000, '30天'),
  (0, '永不过期'),
];

/// 默认有效期：公共 1 天（每次都重置为 1 天，不记忆），私有永不过期
int defaultExpiryFor(String visibility) => visibility == 'public' ? 86400 : 0;

String expiryLabel(int sec) =>
    kExpiryOptions.firstWhere((e) => e.$1 == sec, orElse: () => (sec, '${(sec / 3600).round()} 小时')).$2;

/// 有效期选择（纸与墨主题下的 ChoiceChip 行）
class ExpiryPicker extends StatelessWidget {
  const ExpiryPicker({super.key, required this.value, required this.onChanged, this.label = '有效期'});
  final int value;
  final ValueChanged<int> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (label.isNotEmpty) Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final e in kExpiryOptions)
          ChoiceChip(
            label: Text(e.$2),
            selected: value == e.$1,
            onSelected: (_) => onChanged(e.$1),
          ),
      ]),
    ]);
  }
}

/// 确认对话框 + 有效期选择；取消返回 null，确认返回所选秒数
Future<int?> confirmWithExpiry(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = '上传',
  int initial = 0,
}) {
  var exp = initial;
  return showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message),
            const SizedBox(height: 12),
            ExpiryPicker(value: exp, onChanged: (v) => setS(() => exp = v)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, exp), child: Text(okLabel)),
        ],
      ),
    ),
  );
}

/// 选图片 / 选文件之后：选择可见性 + 有效期
Future<({String visibility, int expiresIn})?> askUploadOptions(
  BuildContext context, {
  required String title,
  required String initialVisibility,
}) {
  var vis = initialVisibility;
  var exp = defaultExpiryFor(vis);
  return showModalBottomSheet<({String visibility, int expiresIn})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'private', label: Text('私有'), icon: Icon(Icons.lock_outline)),
                ButtonSegment(value: 'public', label: Text('公共'), icon: Icon(Icons.public)),
              ],
              selected: {vis},
              onSelectionChanged: (s) => setS(() {
                vis = s.first;
                exp = defaultExpiryFor(vis); // 切换可见性时重置为该区默认
              }),
            ),
            const SizedBox(height: 10),
            ExpiryPicker(value: exp, onChanged: (v) => setS(() => exp = v)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (visibility: vis, expiresIn: exp)),
              child: const Text('上传'),
            ),
          ]),
        ),
      ),
    ),
  );
}
