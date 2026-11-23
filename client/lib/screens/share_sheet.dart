import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/item.dart';
import '../services/api.dart';

Future<void> showShareSheet(BuildContext context, {required ClipApi api, required ClipItem item}) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ShareBody(api: api, item: item),
  );
}

class _ShareBody extends StatefulWidget {
  const _ShareBody({required this.api, required this.item});
  final ClipApi api;
  final ClipItem item;

  @override
  State<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends State<_ShareBody> {
  String? _url;
  String? _err;
  bool _loading = true;
  bool _hasPassword = false;
  int _maxViews = 0; // 0 = 不限
  final _pwCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await widget.api.createShare(
        widget.item.uuid,
        hours: 168,
        password: _pwCtrl.text.trim(),
        maxViews: _maxViews,
      );
      final token = r['token'] as String;
      if (!mounted) return;
      setState(() {
        _url = widget.api.sharePageUrl(token);
        _hasPassword = r['has_password'] == true;
        _maxViews = (r['max_views'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('分享', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              widget.item.isPublic
                  ? '公共内容分享链接，可附加提取码或阅后即焚。'
                  : '私有内容临时分享链接：可附加提取码或设为阅后即焚。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_loading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
            if (_err != null) Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_url != null && !_loading) ...[
              QrImageView(data: _url!, size: 180, backgroundColor: Colors.white),
              const SizedBox(height: 10),
              if (_hasPassword || _maxViews > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    [
                      if (_hasPassword) '🔒 需提取码',
                      if (_maxViews == 1) '🔥 1 次（阅后即焚）' else if (_maxViews > 1) '🔥 限 $_maxViews 次',
                    ].join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              SelectableText(_url!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
              const SizedBox(height: 12),
              TextField(
                controller: _pwCtrl,
                decoration: const InputDecoration(
                  labelText: '提取码（可选，留空=免密）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final (v, lbl) in const [(0, '不限次数'), (1, '🔥 阅后即焚'), (3, '限 3 次'), (5, '限 5 次')])
                  ChoiceChip(
                    label: Text(lbl),
                    selected: _maxViews == v,
                    onSelected: (_) => setState(() => _maxViews = v),
                  ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _create,
                    child: const Text('更新安全设置'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _url!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('复制链接'),
                  ),
                ),
              ]),
              TextButton(
                onPressed: () async {
                  await widget.api.revokeShare(widget.item.uuid);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('撤销分享链接'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
