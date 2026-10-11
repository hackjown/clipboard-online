import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/clipboard_watch.dart';
import '../services/file_transfer.dart';
import '../services/menubar.dart';
import '../theme/ink_theme.dart';
import 'ink.dart';

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
    MenuBarController.instance.busy++;
    final FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    } finally {
      MenuBarController.instance.busy--;
    }
    if (r == null) return;
    for (final f in r.files) {
      if (f.bytes == null) continue;
      _queue.add(FileTransferService.fromBytes(f.bytes!, f.name));
    }
    setState(() {});
  }

  Future<void> _pickImages() async {
    MenuBarController.instance.busy++;
    final List<XFile> imgs;
    try {
      imgs = await ImagePicker().pickMultiImage();
    } finally {
      MenuBarController.instance.busy--;
    }
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
    final t = context.ink;
    return InkCard(
      margin: EdgeInsets.zero,
      color: _dragging ? t.sun : t.paper,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: t.line, width: 2),
                ),
                child: const Icon(Icons.bolt, size: 18, color: InkTokens.onColor),
              ),
              const SizedBox(width: 10),
              Text('快传', style: t.serifStyle(22)),
              const Spacer(),
              Flexible(
                child: Text(
                  _isDesktop ? '拖放文件到此处' : '选文件后发送到私有区',
                  overflow: TextOverflow.ellipsis,
                  style: t.monoStyle(11.5, color: t.muted).copyWith(height: 1.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '默认上传为「私有」· 登录同一账号的手机 / Mac 会经 WebSocket 实时看到',
            style: TextStyle(fontSize: 12.5, color: t.muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              InkButton(label: '选文件', icon: Icons.attach_file, dense: true, onPressed: _sending ? null : _pickFiles),
              InkButton(label: '选图片', icon: Icons.image_outlined, dense: true, onPressed: _sending ? null : _pickImages),
              InkButton(
                  label: _isIOS ? '从剪贴板导入' : '粘贴',
                  icon: Icons.paste,
                  dense: true,
                  onPressed: _sending ? null : _fromClipboard),
              InkButton(
                label: '发送到我的设备',
                icon: Icons.send,
                variant: InkVariant.accent,
                dense: true,
                busy: _sending,
                onPressed: (_sending || _queue.isEmpty) ? null : _sendAll,
              ),
            ],
          ),
          if (_queue.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._queue.asMap().entries.map((e) {
              final i = e.key;
              final it = e.value;
              final label = it.isText
                  ? '文本 ${(it.textContent?.length ?? 0)} 字'
                  : '${it.filename} · ${_fmt(it.size)}';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  color: t.paper2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.line.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Row(children: [
                  Icon(it.isText ? Icons.notes : Icons.insert_drive_file_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.monoStyle(12.5)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _sending ? null : () => setState(() => _queue.removeAt(i)),
                  ),
                ]),
              );
            }),
          ],
          if (_status != null) ...[
            const SizedBox(height: 6),
            Text(_status!, style: TextStyle(color: t.danger, fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.fromLTRB(14, 10, 21, 8),
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
