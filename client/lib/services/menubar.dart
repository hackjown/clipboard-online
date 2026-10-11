import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// macOS 菜单栏（状态栏）应用：托盘图标 + 点击弹出 360×520 小窗（compact 模式）+ 右键菜单。
/// 关闭窗口 = 隐藏（App 继续运行）；可选隐藏 Dock 图标、开机自启。
class MenuBarController with TrayListener, WindowListener {
  MenuBarController._();
  static final MenuBarController instance = MenuBarController._();

  static const popoverSize = Size(360, 520);
  static const mainSize = Size(980, 720);
  static const _loginChannel = MethodChannel('clipboard/login_item');

  static bool get supported => !kIsWeb && Platform.isMacOS;

  /// 小窗模式（HomeScreen 保持挂载但隐藏，WebSocket 与通知继续工作）
  final ValueNotifier<bool> compact = ValueNotifier(false);

  /// 有新事件时 +1，小窗据此刷新列表
  final ValueNotifier<int> pulse = ValueNotifier(0);
  final ValueNotifier<bool> watchOn = ValueNotifier(false);
  final ValueNotifier<bool> showDock = ValueNotifier(true);
  final ValueNotifier<bool> launchAtLogin = ValueNotifier(false);

  bool loggedIn = false;
  bool visible = true;
  bool focused = true;

  /// 文件选择对话框等会让窗口失焦；>0 时失焦不隐藏小窗
  int busy = 0;
  bool _ready = false;
  bool pinned = false;

  VoidCallback? onOpenSettings;
  Future<void> Function(bool on)? onToggleWatch;

  Future<void> init() async {
    if (!supported || _ready) return;
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      size: mainSize,
      minimumSize: Size(420, 520),
      title: '剪贴板',
      titleBarStyle: TitleBarStyle.normal,
    );
    final sp = await SharedPreferences.getInstance();
    showDock.value = sp.getBool('mb_show_dock') ?? true;
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    if (!showDock.value) await windowManager.setSkipTaskbar(true);
    try {
      await trayManager.setIcon('assets/tray/tray_icon@2x.png', isTemplate: true);
      await trayManager.setToolTip('剪贴板');
      trayManager.addListener(this);
      await _buildMenu();
    } catch (e) {
      debugPrint('tray init failed: $e');
    }
    try {
      launchAtLogin.value = (await _loginChannel.invokeMethod<bool>('isEnabled')) ?? false;
    } catch (_) {}
    _ready = true;
  }

  Future<void> _buildMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'main', label: '打开主窗口'),
      MenuItem(key: 'quick', label: '快传'),
      MenuItem.separator(),
      MenuItem.checkbox(key: 'watch', label: '监听剪贴板', checked: watchOn.value),
      MenuItem(key: 'settings', label: '设置'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ]));
  }

  Future<void> setWatch(bool on) async {
    watchOn.value = on;
    if (_ready) await _buildMenu();
  }

  Future<void> toggleWatch() async {
    final next = !watchOn.value;
    if (onToggleWatch != null) {
      await onToggleWatch!(next);
    } else {
      await setWatch(next);
    }
  }

  // ---- 窗口模式 ----
  Future<void> openMain() async {
    compact.value = false;
    pinned = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(420, 520));
    await windowManager.setSize(mainSize);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    visible = true;
  }

  Future<void> openPopover({bool focusDrop = false}) async {
    if (!loggedIn) return openMain();
    compact.value = true;
    pulse.value++;
    await windowManager.setMinimumSize(popoverSize);
    await windowManager.setResizable(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setSize(popoverSize);
    await windowManager.setAlwaysOnTop(true);
    Rect? b;
    try {
      b = await trayManager.getBounds();
    } catch (_) {}
    if (b != null) {
      // 托盘坐标：左上为原点；窗口水平居中于图标，紧贴菜单栏下方
      var x = b.center.dx - popoverSize.width / 2;
      if (x < 8) x = 8;
      await windowManager.setPosition(Offset(x, b.bottom + 4));
    } else {
      await windowManager.setAlignment(Alignment.topRight);
    }
    await windowManager.show();
    await windowManager.focus();
    visible = true;
  }

  Future<void> togglePopover() async {
    if (compact.value && visible) {
      await hide();
    } else {
      await openPopover();
    }
  }

  Future<void> hide() async {
    visible = false;
    await windowManager.hide();
  }

  Future<void> quit() async {
    await windowManager.setPreventClose(false);
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.destroy();
    exit(0);
  }

  // ---- 设置 ----
  Future<void> setShowDock(bool v) async {
    showDock.value = v;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('mb_show_dock', v);
    await windowManager.setSkipTaskbar(!v);
    if (v) {
      await windowManager.show();
    }
  }

  /// 返回 null 表示成功，否则为错误提示
  Future<String?> setLaunchAtLogin(bool v) async {
    try {
      final r = await _loginChannel.invokeMethod<bool>('setEnabled', {'enabled': v});
      launchAtLogin.value = r ?? v;
      return null;
    } on PlatformException catch (e) {
      launchAtLogin.value = false;
      return '无法设置开机自启：${e.message ?? e.code}（未签名的 App 可能不被系统允许，可在「系统设置 → 通用 → 登录项」手动添加）';
    } catch (e) {
      return '无法设置开机自启：$e';
    }
  }

  // ---- 托盘事件 ----
  @override
  void onTrayIconMouseDown() {
    togglePopover();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'main':
        openMain();
      case 'quick':
        openPopover(focusDrop: true);
      case 'watch':
        toggleWatch();
      case 'settings':
        openMain().then((_) => onOpenSettings?.call());
      case 'quit':
        quit();
    }
  }

  // ---- 窗口事件 ----
  @override
  void onWindowClose() {
    // 关闭 = 隐藏，App 常驻菜单栏
    compact.value = false;
    hide();
  }

  @override
  void onWindowBlur() {
    focused = false;
    if (compact.value && !pinned && busy == 0) hide();
  }

  @override
  void onWindowFocus() {
    focused = true;
    visible = true;
  }
}
