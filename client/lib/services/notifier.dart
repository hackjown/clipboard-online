import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知（无 APNs）：App 运行中 / 刚退到后台时，WebSocket 收到其他设备上传的新私有内容后提醒，
/// 并在 iOS/macOS 上设置未读角标。后台被系统挂起后无法收到（需要 APNs，本版不含）。
class Notifier {
  Notifier._();
  static final Notifier instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int unread = 0;
  int _nextId = 1;

  bool get _supported =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid);

  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      // 启动时请求通知权限
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notifier init failed: $e');
    }
  }

  /// 收到其他设备的新内容：弹本地通知并累加未读角标
  Future<void> notifyIncoming({required bool isFile, required String detail}) async {
    if (!_ready) return;
    unread += 1;
    final title = isFile ? '收到新文件' : '收到新文本';
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: detail,
        notificationDetails: NotificationDetails(
          android: const AndroidNotificationDetails(
            'incoming',
            '新内容',
            channelDescription: '其他设备发送到本账号的新文件/文本',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(badgeNumber: unread),
          macOS: DarwinNotificationDetails(badgeNumber: unread),
        ),
      );
    } catch (e) {
      debugPrint('notify failed: $e');
    }
  }

  /// 打开列表 / 回到前台后清除未读：清通知中心 + 角标归零
  Future<void> clearUnread() async {
    if (!_ready) return;
    final had = unread > 0;
    unread = 0;
    try {
      await _plugin.cancelAll();
      if (had && !kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        // 静默通知把角标设为 0
        await _plugin.show(
          id: 0,
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentSound: false,
              presentBadge: true,
              badgeNumber: 0,
            ),
            macOS: DarwinNotificationDetails(
              presentAlert: false,
              presentSound: false,
              presentBadge: true,
              badgeNumber: 0,
            ),
          ),
        );
        await _plugin.cancel(id: 0);
      }
    } catch (e) {
      debugPrint('clear unread failed: $e');
    }
  }
}
