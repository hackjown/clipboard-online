import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/clipboard_watch.dart';
import '../services/file_transfer.dart';

/// 「快传」：默认上传到 **私有区**，对端经 WebSocket 实时同步。
class QuickTransferPanel extends StatefulWidget {
  const QuickTransferPanel({
    super.key,
    required this.api,
    required this.onSent,
  });

  final ClipApi api;
  final VoidCallback onSent;

  @override
  State<QuickTransferPanel> createState() => _QuickTransferPanelState();
}

class _QuickTransferPanelState extends State<QuickTransferPanel> {
  final List<PendingTransfer> _queue = [];
  bool _dragging = false;
  bool _sending = false;
  String? _status;
  final _clip = ClipboardWatch();

  bool get _isDesktop => !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  Future<void> _addXFiles(List<XFile> files) async {
    for (final f in files) {
      final bytes = await f.readAsBytes();
      final name = f.name.isNotEmpty ? f.name : 'file-${DateTime.now().millisecondsSinceEpoch}';
      _queue.add(FileTransferService.fromBytes(
        Uint8List.fromList(bytes),
        name,
        contentType: f.mimeType,
      ));
    }
    setState(() {});
  }

  Future<void> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (r == null) return;
    for (final f in r.files) {
      if (f.bytes == null) continue;
      _queue.add(FileTransferService.fromBytes(f.bytes!, f.name));
    }
    setState(() {});
  }

  Future<void> _pickImages() async {
    final imgs = await ImagePicker().pickMultiImage();
    for (final x in imgs) {
      final bytes = await x.readAsBytes();
      _queue.add(FileTransferService.fromBytes(
        bytes,
        x.name,
        contentType: x.mimeType,
      ));
    }
    setState(() {});
  }

  Future<void> _fromClipboard() async {
    _clip.onText = (t) {
      _queue.add(FileTransferService.fromText(t));
      setState(() {});
    };
    _clip.onImage = (b, n) {
      _queue.add(FileTransferService.fromBytes(b, n, contentType: 'image/png'));
      setState(() {});
    };
    await _clip.importOnce();
  }

  Future<void> _sendAll() async {
    if (_queue.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _status = '正在发送…';
    });
    var ok = 0;
    try {
      for (final item in List<PendingTransfer>.from(_queue)) {
        if (item.isText && (item.textContent?.trim().isNotEmpty ?? false)) {
          await widget.api.addText(item.textContent!, visibility: 'private', expiresIn: 0);
        } else {
          await widget.api.uploadFile(
            bytes: item.bytes,
            filename: item.filename,
            visibility: 'private',
            expiresIn: 0,
            contentType: item.contentType,
          );
        }
        ok++;
      }
      _queue.clear();
      if (mounted) {
        setState(() => _status = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok > 1 ? '已发送 $ok 项，其他设备将同步' : '已发送，其他设备将同步'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSent();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$e'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _dropInner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _dragging ? cs.primaryContainer.withValues(alpha: 0.55) : cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _dragging ? cs.primary : cs.outlineVariant,
          width: _dragging ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: cs.primary),
              const SizedBox(width: 8),
              Text('快传', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const Spacer(),
              Text(
                _isDesktop ? '拖放文件到此处' : '选文件后发送到本账号私有区',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '默认上传为「私有」· 登录同一账号的手机 / Mac 会经 WebSocket 实时看到',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _sending ? null : _pickFiles,
                icon: const Icon(Icons.attach_file),
                label: const Text('选文件'),
              ),
              FilledButton.tonalIcon(
                onPressed: _sending ? null : _pickImages,
                icon: const Icon(Icons.image_outlined),
                label: const Text('选图片'),
              ),
              FilledButton.tonalIcon(
                onPressed: _sending ? null : _fromClipboard,
                icon: const Icon(Icons.paste),
                label: Text(_isIOS ? '从剪贴板导入' : '粘贴'),
              ),
              FilledButton.icon(
                onPressed: (_sending || _queue.isEmpty) ? null : _sendAll,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('发送到我的设备'),
              ),
            ],
          ),
          if (_queue.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._queue.asMap().entries.map((e) {
              final i = e.key;
              final it = e.value;
              final label = it.isText
                  ? '文本 ${(it.textContent?.length ?? 0)} 字'
                  : '${it.filename} · ${_fmt(it.size)}';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(it.isText ? Icons.notes : Icons.insert_drive_file_outlined),
                title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _sending
                      ? null
                      : () => setState(() => _queue.removeAt(i)),
                ),
              );
            }),
          ],
          if (_status != null) ...[
            const SizedBox(height: 6),
            Text(_status!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: _dropInner(context),
    );
    if (!_isDesktop) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        await _addXFiles(detail.files);
      },
      child: child,
    );
  }
}
