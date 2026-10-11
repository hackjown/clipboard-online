import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/api.dart';
import '../theme/ink_theme.dart';
import '../widgets/ink.dart';

/// 编辑文本条目（仅所有者）。保存成功后 pop(true)，列表会刷新；其它设备经 WebSocket 同步。
class EditTextScreen extends StatefulWidget {
  const EditTextScreen({super.key, required this.api, required this.item});
  final ClipApi api;
  final ClipItem item;

  @override
  State<EditTextScreen> createState() => _EditTextScreenState();
}

class _EditTextScreenState extends State<EditTextScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.item.content ?? '');
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _c.text;
    if (v.trim().isEmpty) {
      setState(() => _err = '内容不能为空');
      return;
    }
    if (v == widget.item.content) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await widget.api.editText(widget.item.uuid, v);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，其他设备将同步')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _err = e is ApiException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Scaffold(
      appBar: AppBar(title: const Text('编辑文本')),
      body: PaperBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(hintText: '内容'),
                ),
              ),
              if (_err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_err!, style: TextStyle(color: t.danger)),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: InkButton(label: '取消', onPressed: _busy ? null : () => Navigator.pop(context, false))),
                const SizedBox(width: 12),
                Expanded(
                  child: InkButton(
                    label: '保存',
                    icon: Icons.check,
                    variant: InkVariant.accent,
                    busy: _busy,
                    onPressed: _busy ? null : _save,
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
