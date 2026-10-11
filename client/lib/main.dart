import 'package:flutter/material.dart';

import 'app.dart';
import 'services/menubar.dart';
import 'services/notifier.dart';
import 'services/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // macOS：窗口 + 菜单栏图标（其它平台为空操作）
  await ThemeController.instance.load();
  await MenuBarController.instance.init();
  await Notifier.instance.init();
  runApp(const ClipboardApp());
}
