import 'package:clipboard_client/widgets/expiry_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('选项与默认值：公共 1 天、私有永不过期', () {
    expect(kExpiryOptions.map((e) => e.$2).toList(), ['1小时', '1天', '7天', '30天', '永不过期']);
    expect(kExpiryOptions.map((e) => e.$1).toList(), [3600, 86400, 604800, 2592000, 0]);
    expect(defaultExpiryFor('public'), 86400);
    expect(defaultExpiryFor('private'), 0);
    expect(expiryLabel(0), '永不过期');
  });

  testWidgets('ExpiryPicker 切换', (tester) async {
    var v = 86400;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (c, setS) => ExpiryPicker(value: v, onChanged: (x) => setS(() => v = x)))),
    ));
    await tester.tap(find.text('永不过期'));
    await tester.pump();
    expect(v, 0);
    await tester.tap(find.text('30天'));
    await tester.pump();
    expect(v, 2592000);
  });
}
