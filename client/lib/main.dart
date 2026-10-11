import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: Size(980, 720),
      minimumSize: Size(420, 560),
      title: '剪贴板',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  await Notifier.instance.init();
  runApp(const ClipboardApp());
}
