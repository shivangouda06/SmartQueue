import 'package:flutter_test/flutter_test.dart';

import 'package:smartqueue/main.dart';

void main() {
  testWidgets('App loads with the home greeting without the stray square marker', (
    WidgetTester tester,
  ) async {
    final store = await AppStore.load();
    await tester.pumpWidget(SmartQueueApp(store: store));

    expect(find.text('Good day, there'), findsOneWidget);
    expect(find.textContaining('■'), findsNothing);
  });
}
