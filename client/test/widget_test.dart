import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_client/app.dart';

void main() {
  testWidgets('App builds', (tester) async {
    await tester.pumpWidget(const ClipboardApp());
    await tester.pump();
    expect(find.byType(ClipboardApp), findsOneWidget);
  });
}
