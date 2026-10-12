/// 多设备剪贴板同步的数据模型（服务器 /api/devices、/api/clipsync）
class SyncDevice {
  SyncDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.direction,
    required this.online,
    required this.current,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final String direction; // both | send | recv | off
  final bool online;
  final bool current;
  final double? lastSeen;

  factory SyncDevice.fromJson(Map<String, dynamic> j) => SyncDevice(
        id: (j['device_id'] ?? '').toString(),
        name: (j['name'] ?? '未命名设备').toString(),
        platform: (j['platform'] ?? '').toString(),
        direction: (j['direction'] ?? 'both').toString(),
        online: j['online'] == true,
        current: j['current'] == true,
        lastSeen: (j['last_seen'] as num?)?.toDouble(),
      );
}

class SyncClip {
  SyncClip({required this.text, required this.ts, required this.origin, required this.originName});
  final String text;
  final double ts;
  final String origin;
  final String originName;

  factory SyncClip.fromJson(Map<String, dynamic> j) => SyncClip(
        text: (j['text'] ?? '').toString(),
        ts: (j['ts'] as num?)?.toDouble() ?? 0,
        origin: (j['origin'] ?? '').toString(),
        originName: (j['origin_name'] ?? '其他设备').toString(),
      );
}

const kDirectionLabels = {'both': '双向', 'send': '只发送', 'recv': '只接收', 'off': '关闭'};

bool directionSends(String d) => d == 'both' || d == 'send';
bool directionReceives(String d) => d == 'both' || d == 'recv';

class DeviceList {
  DeviceList({required this.devices, required this.user, required this.instance});
  final List<SyncDevice> devices;
  final String user; // 服务器认定的账号
  final String instance; // 服务器实例 ID（每份数据目录一个）：几台设备应当一致
}
