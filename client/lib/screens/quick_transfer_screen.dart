import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/ink_theme.dart';
import '../widgets/ink.dart';
import '../widgets/quick_transfer.dart';

/// 「快传」独立页面（iOS / Android / macOS 主窗口）：选文件 / 拖入 / 粘贴 → 发送到「我的私有」。
/// 首页不再内嵌快传面板，避免占用列表空间；菜单栏浮窗仍保留自己的紧凑投放区。
class QuickTransferScreen extends StatelessWidget {
  const QuickTransferScreen({super.key, required this.api, required this.onSent});

  final ClipApi api;
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final t = context.ink;
    return Scaffold(
      appBar: AppBar(title: const Text('快传')),
      body: PaperBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              QuickTransferPanel(api: api, onSent: onSent),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Text(
                  '发送的内容默认进入「我的私有」，你登录的其他设备会实时收到。',
                  style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
