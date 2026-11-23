import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as std_crypto;
import 'package:cryptography/cryptography.dart';

/// 端到端加密密码保险箱（与 Web 端 vault.js 字节级兼容）：
///   - KDF：PBKDF2-HMAC-SHA256，随机 16 字节 salt，默认 200,000 次迭代，输出 256 位密钥
///   - 加密：AES-256-GCM，随机 12 字节 IV，密文末尾附 16 字节认证标签
class VaultEnvelope {
  VaultEnvelope({
    required this.version,
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.iv,
    required this.ct,
    this.rev = 0,
    this.itemCount = 0,
    this.updatedAt = 0,
  });

  final int version;
  final String kdf;
  final int iterations;
  final String salt;
  final String iv;
  final String ct;
  final int rev;
  final int itemCount;
  final double updatedAt;

  factory VaultEnvelope.fromJson(Map<String, dynamic> j) => VaultEnvelope(
        version: (j['version'] as num?)?.toInt() ?? 1,
        kdf: (j['kdf'] ?? 'PBKDF2-SHA256').toString(),
        iterations: (j['iterations'] as num?)?.toInt() ?? VaultCrypto.defaultIterations,
        salt: (j['salt'] ?? '').toString(),
        iv: (j['iv'] ?? '').toString(),
        ct: (j['ct'] ?? '').toString(),
        rev: (j['rev'] as num?)?.toInt() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toPutJson({required int expectedRev}) => {
        'version': version,
        'kdf': kdf,
        'iterations': iterations,
        'salt': salt,
        'iv': iv,
        'ct': ct,
        'item_count': itemCount,
        'expected_rev': expectedRev,
      };
}

class VaultField {
  VaultField({required this.label, required this.value, this.secret = false});
  String label;
  String value;
  bool secret;

  factory VaultField.fromJson(Map<String, dynamic> j) => VaultField(
        label: (j['label'] ?? '').toString(),
        value: (j['value'] ?? '').toString(),
        secret: j['secret'] == true,
      );

  Map<String, dynamic> toJson() => {'label': label, 'value': value, 'secret': secret};
}

class VaultItem {
  VaultItem({
    required this.id,
    this.kind = 'login',
    this.title = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.totp = '',
    this.notes = '',
    this.fields = const [],
    this.tags = const [],
    this.favorite = false,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  String kind; // login | note | card | idcard | apikey
  String title;
  String username;
  String password;
  String url;
  String totp;
  String notes;
  List<VaultField> fields;
  List<String> tags;
  bool favorite;
  int createdAt;
  int updatedAt;

  factory VaultItem.fromJson(Map<String, dynamic> j) => VaultItem(
        id: (j['id'] ?? VaultCrypto.randomId()).toString(),
        kind: (j['kind'] ?? 'login').toString(),
        title: (j['title'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        password: (j['password'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        totp: (j['totp'] ?? '').toString(),
        notes: (j['notes'] ?? '').toString(),
        fields: ((j['fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => VaultField.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
        favorite: j['favorite'] == true,
        createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'totp': totp,
        'notes': notes,
        'fields': fields.map((f) => f.toJson()).toList(),
        'tags': tags,
        'favorite': favorite,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

class VaultPayload {
  VaultPayload({this.v = 1, required this.items});
  final int v;
  final List<VaultItem> items;

  factory VaultPayload.fromJson(Map<String, dynamic> j) => VaultPayload(
        v: (j['v'] as num?)?.toInt() ?? 1,
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => VaultItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'v': v,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class TotpResult {
  const TotpResult({required this.code, required this.remaining, required this.period, required this.digits});
  final String code;
  final int remaining;
  final int period;
  final int digits;

  String get formatted => code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}

class VaultDeriveArgs {
  const VaultDeriveArgs({required this.password, required this.salt, required this.iterations});
  final String password;
  final Uint8List salt;
  final int iterations;
}

/// 顶层函数，方便通过 Flutter `compute()` 在独立 Isolate 中执行 PBKDF2，避免主线程卡顿
Future<Uint8List> deriveVaultKeyIsolate(VaultDeriveArgs args) =>
    VaultCrypto.deriveKey(args.password, args.salt, args.iterations);

class VaultCrypto {
  static const int defaultIterations = 200000;
  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  static String randomId() {
    final b = randomBytes(16);
    final sb = StringBuffer();
    for (final v in b) {
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Future<Uint8List> deriveKey(String password, Uint8List salt, int iterations) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final sk = await pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
    final bytes = await sk.extractBytes();
    return Uint8List.fromList(bytes);
  }

  static Future<VaultEnvelope> encryptPayload(
    VaultPayload payload,
    Uint8List keyBytes,
    Uint8List salt,
    int iterations,
  ) async {
    final iv = randomBytes(12);
    final plain = utf8.encode(jsonEncode(payload.toJson()));
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      plain,
      secretKey: SecretKey(keyBytes),
      nonce: iv,
    );
    final combined = Uint8List(box.cipherText.length + box.mac.bytes.length);
    combined.setRange(0, box.cipherText.length, box.cipherText);
    combined.setRange(box.cipherText.length, combined.length, box.mac.bytes);
    return VaultEnvelope(
      version: 1,
      kdf: 'PBKDF2-SHA256',
      iterations: iterations,
      salt: base64Encode(salt),
      iv: base64Encode(iv),
      ct: base64Encode(combined),
      itemCount: payload.items.length,
    );
  }

  static Future<Map<String, dynamic>> decryptRawJson(VaultEnvelope env, Uint8List keyBytes) async {
    final iv = base64Decode(env.iv);
    final raw = base64Decode(env.ct);
    if (iv.length != 12 || raw.length < 16) {
      throw const FormatException('密文格式异常');
    }
    final cipherText = raw.sublist(0, raw.length - 16);
    final mac = Mac(raw.sublist(raw.length - 16));
    final aes = AesGcm.with256bits();
    final List<int> plain;
    try {
      plain = await aes.decrypt(
        SecretBox(cipherText, nonce: iv, mac: mac),
        secretKey: SecretKey(keyBytes),
      );
    } catch (_) {
      throw const FormatException('主密码错误或数据已被篡改');
    }
    final obj = jsonDecode(utf8.decode(plain));
    if (obj is! Map) {
      throw const FormatException('密码库数据结构异常');
    }
    return Map<String, dynamic>.from(obj);
  }

  static Future<VaultPayload> decryptPayload(VaultEnvelope env, Uint8List keyBytes) async {
    final obj = await decryptRawJson(env, keyBytes);
    if (obj['items'] is! List) {
      throw const FormatException('密码库数据结构异常');
    }
    return VaultPayload.fromJson(obj);
  }

  // ---- RFC 6238 TOTP（支持 otpauth:// 与裸 Base32 密钥）----
  static const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List? _base32Decode(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    if (s.isEmpty) return null;
    var bits = 0;
    var val = 0;
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      final idx = _b32.indexOf(s[i]);
      if (idx < 0) continue;
      val = (val << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((val >> bits) & 0xff);
      }
    }
    return out.isEmpty ? null : Uint8List.fromList(out);
  }

  static TotpResult? totpCode(String raw, {int? nowSec}) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    var secret = s;
    var digits = 6;
    var period = 30;
    var algo = 'SHA1';
    if (s.toLowerCase().startsWith('otpauth://')) {
      final u = Uri.tryParse(s);
      if (u == null) return null;
      secret = u.queryParameters['secret'] ?? '';
      digits = int.tryParse(u.queryParameters['digits'] ?? '6') ?? 6;
      period = int.tryParse(u.queryParameters['period'] ?? '30') ?? 30;
      algo = (u.queryParameters['algorithm'] ?? 'SHA1').toUpperCase();
    }
    final key = _base32Decode(secret);
    if (key == null) return null;
    digits = digits.clamp(6, 8);
    period = period.clamp(10, 120);
    final t = nowSec ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final counter = t ~/ period;
    final msg = Uint8List(8);
    final bd = ByteData.view(msg.buffer);
    bd.setUint32(0, counter >> 32, Endian.big);
    bd.setUint32(4, counter & 0xffffffff, Endian.big);
    final hash = algo == 'SHA256' ? std_crypto.sha256 : std_crypto.sha1;
    final mac = std_crypto.Hmac(hash, key).convert(msg).bytes;
    final off = mac.last & 0x0f;
    final bin = ((mac[off] & 0x7f) << 24) |
        ((mac[off + 1] & 0xff) << 16) |
        ((mac[off + 2] & 0xff) << 8) |
        (mac[off + 3] & 0xff);
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    final code = (bin % mod).toString().padLeft(digits, '0');
    return TotpResult(code: code, remaining: period - (t % period), period: period, digits: digits);
  }

  // ---- 随机强密码生成器 ----
  static String genPassword({
    int length = 20,
    bool upper = true,
    bool lower = true,
    bool digits = true,
    bool symbols = true,
  }) {
    final len = length.clamp(8, 64);
    final pools = <String>[
      if (upper) 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      if (lower) 'abcdefghijklmnopqrstuvwxyz',
      if (digits) '0123456789',
      if (symbols) r'!@#$%^&*()-_=+[]{}',
    ];
    if (pools.isEmpty) pools.add('abcdefghijklmnopqrstuvwxyz0123456789');
    final all = pools.join();
    final chars = <String>[
      for (final p in pools) p[_rng.nextInt(p.length)],
    ];
    while (chars.length < len) {
      chars.add(all[_rng.nextInt(all.length)]);
    }
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join();
  }

  // ---- 1Password / Chrome CSV 导入 ----
  static List<List<String>> _parseCsvRows(String input) {
    final s = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final rows = <List<String>>[];
    var row = <String>[];
    final cur = StringBuffer();
    var inQ = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (inQ) {
        if (ch == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            cur.write('"');
            i++;
          } else {
            inQ = false;
          }
        } else {
          cur.write(ch);
        }
      } else {
        if (ch == '"') {
          inQ = true;
        } else if (ch == ',') {
          row.add(cur.toString());
          cur.clear();
        } else if (ch == '\r') {
          if (i + 1 < s.length && s[i + 1] == '\n') i++;
          row.add(cur.toString());
          rows.add(row);
          row = <String>[];
          cur.clear();
        } else if (ch == '\n') {
          row.add(cur.toString());
          rows.add(row);
          row = <String>[];
          cur.clear();
        } else {
          cur.write(ch);
        }
      }
    }
    if (cur.isNotEmpty || row.isNotEmpty) {
      row.add(cur.toString());
      rows.add(row);
    }
    return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  }

  static List<VaultItem> importFromCsv(String text) {
    final rows = _parseCsvRows(text);
    if (rows.length < 2) return const [];
    final hdr = rows.first.map((c) => c.trim().toLowerCase()).toList();
    int col(List<String> names) {
      for (final n in names) {
        final idx = hdr.indexOf(n);
        if (idx >= 0) return idx;
      }
      return -1;
    }

    final iTitle = col(['title', 'name', '名称', '标题']);
    final iUrl = col(['url', 'website', 'login_uri', '网址', '网站']);
    final iUser = col(['username', 'login_username', 'user', '用户名', '账号']);
    final iPass = col(['password', 'login_password', 'pass', '密码']);
    final iOtp = col(['otpauth', 'one-time password', 'totp', 'login_totp', 'otp', '2fa', '一次性密码']);
    final iNotes = col(['notes', 'note', '备注']);
    final iTags = col(['tags', 'tag', '标签']);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final out = <VaultItem>[];
    for (var r = 1; r < rows.length; r++) {
      final cells = rows[r];
      String get(int idx) => (idx >= 0 && idx < cells.length) ? cells[idx].trim() : '';
      final u = get(iUser);
      final p = get(iPass);
      final url = get(iUrl);
      final notes = get(iNotes);
      final title = get(iTitle).isNotEmpty
          ? get(iTitle)
          : (url.isNotEmpty ? url : (u.isNotEmpty ? u : '条目 $r'));
      final kind = (u.isEmpty && p.isEmpty && url.isEmpty && notes.isNotEmpty) ? 'note' : 'login';
      final rawTags = get(iTags);
      final tags = rawTags.isEmpty
          ? <String>[]
          : rawTags.split(RegExp(r'[;,，]')).map((e) => e.trim()).where((e) => e.isNotEmpty).take(8).toList();
      out.add(VaultItem(
        id: randomId(),
        kind: kind,
        title: title,
        username: u,
        password: p,
        url: url,
        totp: get(iOtp),
        notes: notes,
        tags: tags,
        createdAt: now,
        updatedAt: now,
      ));
    }
    return out;
  }
}
