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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.createShare(widget.item.uuid, hours: 168);
      final token = r['token'] as String;
      setState(() {
        _url = widget.api.sharePageUrl(token);
        _loading = false;
      });
    } catch (e) {
      setState(() { _err = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('分享', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            widget.item.isPublic
                ? '公共内容分享链接，访客无需登录即可打开。'
                : '私有内容的临时分享链接：任何人凭链接可查看/下载，直到过期或撤销。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_loading) const CircularProgressIndicator(),
          if (_err != null) Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_url != null) ...[
            QrImageView(data: _url!, size: 200, backgroundColor: Colors.white),
            const SizedBox(height: 12),
            SelectableText(_url!, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _url!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制链接'),
            ),
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
    );
  }
}
