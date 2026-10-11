import 'package:clipboard_client/services/api.dart';
import 'package:clipboard_client/services/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeBaseUrl', () {
    expect(AuthStore.normalizeBaseUrl(' 192.168.50.188:8100/ \n'), 'http://192.168.50.188:8100');
    expect(AuthStore.normalizeBaseUrl('https://clip.example.com//'), 'https://clip.example.com');
    expect(AuthStore.normalizeBaseUrl(''), AuthStore.defaultBase);
  });
  test('cleanPassword only strips CR/LF', () {
    expect(ClipApi.cleanPassword(' pa ss\r\n'), ' pa ss');
  });
}
