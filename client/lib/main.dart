import 'package:flutter/material.dart';

import 'app.dart';
import 'services/menubar.dart';
import 'services/notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // macOS：窗口 + 菜单栏图标（其它平台为空操作）
  await MenuBarController.instance.init();
  await Notifier.instance.init();
  runApp(const ClipboardApp());
}
