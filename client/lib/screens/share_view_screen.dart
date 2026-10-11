import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';

/// Deep link `/s/Deep link /s/<token>lt;tokenDeep link /s/<token>gt;` 原生查看页
class ShareViewScreen extends StatefulWidget {
  const ShareViewScreen({super.key, required this.api, required this.token});
  final ClipApi api;
  final String token;

  @override
  State<ShareViewScreen> createState() => _ShareViewScreenState();
}

class _ShareViewScreenState extends State<ShareViewScreen> {
  Map<String, dynamic>? _data;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.sharePeek(widget.token);
      setState(() => _data = d);
    } catch (e) {
      setState(() => _err = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分享预览')),
      body: _err != null
          ? Center(child: Text(_err!))
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_data!['owner_username'] != null)
                      Text('来自 @${_data!['owner_username']}'),
                    const SizedBox(height: 12),
                    if (_data!['type'] == 'text') ...[
                      SelectableText('${_data!['content']}', style: const TextStyle(fontSize: 16, height: 1.5)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: '${_data!['content']}'));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                          }
                        },
                        child: const Text('复制文本'),
                      ),
                    ] else ...[
                      Text('${_data!['filename']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          final url = '${widget.api.base}/s/${widget.token}/file';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        child: const Text('下载文件'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
