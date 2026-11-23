import 'dart:convert';
import 'dart:typed_data';

import 'package:clipboard_client/services/vault_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WebCrypto -> Dart 跨端加解密互通向量', () async {
    // 由浏览器/Node 原生 WebCrypto (PBKDF2-SHA256 + AES-256-GCM) 生成的固定密文向量
    final env = VaultEnvelope(
      version: 1,
      kdf: 'PBKDF2-SHA256',
      iterations: 10000,
      salt: 'AQIDBAUGBwgJCgsMDQ4PEA==',
      iv: '5yBUymYpoM9S2a0E',
      ct: 'RlSAv1PVY30TVk1NgVQJe6NlNQfbjGk4x7/xmfb1TT5ViPyh/DLWlg7MyHr1t+nP9NqNOfNlkoXuh7lUtVA+cl6WKbc0CU3Dnx0cKDomR9qPtWj3Vu526h1dxpURi+nZ8tKhK4XmX7ZcewOoNsDcK83SEfIgFGMmaZl1WptEXP2FQvVfs82aHr8ZLDHBiGpO8reeVmXtaA==',
    );
    final salt = Uint8List.fromList(base64Decode(env.salt));
    final key = await VaultCrypto.deriveKey('MasterPass#2026', salt, env.iterations);
    final dec = await VaultCrypto.decryptPayload(env, key);
    expect(dec.items.length, 1);
    expect(dec.items.single.title, 'GitHub');
    expect(dec.items.single.username, 'hackjown');
    expect(dec.items.single.password, 's3cr3t!密码');

    // 错误主密码必须拒绝解密
    final badKey = await VaultCrypto.deriveKey('WrongPass', salt, env.iterations);
    await expectLater(VaultCrypto.decryptPayload(env, badKey), throwsA(isA<FormatException>()));
  });

  test('Dart 加密 -> 解密往返', () async {
    final salt = VaultCrypto.randomBytes(16);
    final key = await VaultCrypto.deriveKey('MyVaultKey#99', salt, 10000);
    final payload = VaultPayload(items: [
      VaultItem(id: 'a1', title: '阿里云', username: 'admin', password: 'p@ss!word', totp: 'JBSWY3DPEHPK3PXP'),
    ]);
    final env = await VaultCrypto.encryptPayload(payload, key, salt, 10000);
    final dec = await VaultCrypto.decryptPayload(env, key);
    expect(dec.items.single.title, '阿里云');
    expect(dec.items.single.password, 'p@ss!word');
  });

  test('RFC 6238 TOTP 测试向量', () {
    final r8 = VaultCrypto.totpCode('otpauth://totp/Test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8&period=30', nowSec: 59);
    final r6 = VaultCrypto.totpCode('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', nowSec: 59);
    expect(r8?.code, '94287082');
    expect(r6?.code, '287082');
    expect(r6?.remaining, 1);
  });

  test('强密码生成与 1Password CSV 导入', () {
    final pw = VaultCrypto.genPassword(length: 24);
    expect(pw.length, 24);

    final items = VaultCrypto.importFromCsv(
      'Title,Website,Username,Password,OTPAuth,Notes\n'
      '"My, GitHub",https://github.com,u1,p1,JBSWY3DPEHPK3PXP,"line1\nline2"',
    );
    expect(items.length, 1);
    expect(items.single.title, 'My, GitHub');
    expect(items.single.totp, 'JBSWY3DPEHPK3PXP');
    expect(items.single.notes, 'line1\nline2');
  });
}
