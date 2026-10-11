import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:window_manager/window_manager.dart';

import '../models/item.dart';
import '../models/user.dart';
import '../services/api.dart';
import '../services/file_transfer.dart';
import '../services/menubar.dart';
import '../theme/ink_theme.dart';
import '../widgets/ink.dart';
import '../widgets/quick_transfer.dart';

/// 菜单栏小窗（360×520）：快传拖放区 + 最新条目 + 底部按钮。
class PopoverView extends StatefulWidget {
  const PopoverView({super.key, required this.api, required this.user});
  final ClipApi api;
  final ClipUser user;

  @override
  State<PopoverView> createState() => _PopoverViewState();
}

class _PopoverViewState extends State<PopoverView> {
  final _mb = MenuBarController.instance;
  late final FileTransferService _xfer = FileTransferService(widget.api);
  List<ClipItem> _items = [];
  String _scope = 'private'; // 默认「我的私有」
  bool _loading = true;
  String? _err;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _mb.pulse.addListener(_schedule);
    _load();
  }

  @override
  void dispose() {
    _mb.pulse.removeListener(_schedule);
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.items(scope: _scope);
      if (!mounted) return;
      setState(() {
        _items = r.items.take(8).toList();
        _loading = false;
        _err = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = '$e';
        });
      }
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), duration: const Duration(seconds: 2)));
  }

  Future<void> _tap(ClipItem it) async {
    try {
      if (it.isText) {
        await Clipboard.setData(ClipboardData(text: it.content ?? ''));
        _toast('已复制');
      } else if (it.filename != null) {
        _mb.busy++;
        try {
          final f = await _xfer.downloadToCache(filename: it.filename!, remoteUrl: widget.api.downloadUrl(it.filename!));
          await _xfer.revealOrOpen(f);
        } finally {
          _mb.busy--;
        }
      }
    } catch (e) {
      _toast('操作失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Scaffold(
      backgroundColor: t.bg,
      body: PaperBackground(
        child: Column(children: [
          // 顶栏（无标题栏窗口：这里可拖动）
          DragToMoveArea(child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: t.paper,
              border: Border(bottom: BorderSide(color: t.line, width: 2)),
            ),
            child: Row(children: [
              const BrandMark(size: 26),
              const SizedBox(width: 8),
              Text('剪贴板', style: t.serifStyle(17)),
              const SizedBox(width: 6),
              Flexible(child: Text('@${widget.user.username}', overflow: TextOverflow.ellipsis, style: t.monoStyle(11, color: t.muted))),
              const Spacer(),
              InkIconButton(
                plain: true,
                size: 34,
                tooltip: _mb.pinned ? '取消固定' : '固定（失焦不隐藏）',
                icon: _mb.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                onPressed: () => setState(() => _mb.pinned = !_mb.pinned),
              ),
            ]),
          )),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              children: [
                QuickTransferPanel(api: widget.api, onSent: () {
                  _scope = 'private';
                  _load();
                }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  child: InkSegment(
                    labels: const ['我的私有', '公共'],
                    counts: const ['', ''],
                    index: _scope == 'private' ? 0 : 1,
                    onChanged: (i) {
                      setState(() {
                        _scope = i == 0 ? 'private' : 'public';
                        _loading = true;
                      });
                      _load();
                    },
                  ),
                ),
                if (_err != null) Padding(padding: const EdgeInsets.all(12), child: Text(_err!, style: TextStyle(color: t.danger, fontSize: 12))),
                if (_loading && _items.isEmpty)
                  const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                else if (_items.isEmpty)
                  Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('暂无内容', style: TextStyle(color: t.muted))))
                else
                  for (final it in _items) _row(context, it),
              ],
            ),
          ),
          // 底部按钮
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(
              color: t.paper,
              border: Border(top: BorderSide(color: t.line, width: 2)),
            ),
            child: Row(children: [
              Expanded(child: InkButton(label: '主窗口', icon: Icons.open_in_new, dense: true, onPressed: _mb.openMain)),
              const SizedBox(width: 8),
              ValueListenableBuilder<bool>(
                valueListenable: _mb.watchOn,
                builder: (_, on, __) => InkIconButton(
                  size: 36,
                  tooltip: on ? '关闭剪贴板监听' : '监听剪贴板',
                  icon: on ? Icons.content_paste_go : Icons.content_paste,
                  color: on ? t.accent : null,
                  onPressed: _mb.toggleWatch,
                ),
              ),
              const SizedBox(width: 8),
              InkIconButton(
                size: 36,
                tooltip: '设置',
                icon: Icons.settings_outlined,
                onPressed: () => _mb.openMain().then((_) => _mb.onOpenSettings?.call()),
              ),
              const SizedBox(width: 8),
              InkIconButton(size: 36, tooltip: '退出', icon: Icons.power_settings_new, color: t.danger, onPressed: _mb.quit),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, ClipItem it) {
    final t = context.ink;
    final kind = it.mediaKind;
    final icon = it.isText
        ? Icons.notes
        : switch (kind) {
            MediaKind.image => Icons.image_outlined,
            MediaKind.video => Icons.play_circle_outline,
            MediaKind.audio => Icons.graphic_eq,
            _ => Icons.insert_drive_file_outlined,
          };
    final title = it.isText ? (it.content ?? '').replaceAll('\n', ' ') : (it.filename ?? '');
    return GestureDetector(
      onTap: () => _tap(it),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 18, 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: t.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.line, width: 2),
          boxShadow: t.hardShadow(2),
        ),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: it.isText ? t.lime : t.sky,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.line, width: 1.5),
            ),
            child: Icon(icon, size: 17, color: InkTokens.onColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
          const SizedBox(width: 6),
          Icon(it.isText ? Icons.copy_rounded : Icons.folder_open, size: 16, color: t.muted),
        ]),
      ),
    );
  }
}
