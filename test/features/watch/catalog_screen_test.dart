import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/features/watch/catalog_shelves.dart';
import 'package:tonkatsu_box/features/watch/screens/catalog_screen.dart';

import '../../helpers/test_helpers.dart';

CatalogItem item(String title, {double rating = 8.1, int year = 1999}) =>
    CatalogItem(title: title, rating: rating, year: year, isSerial: false);

void main() {
  List<Override> overrides({Map<String, List<CatalogItem>>? shelves}) {
    return <Override>[
      shelfProvider.overrideWith(
        (Ref ref, String id) async =>
            shelves?[id] ?? <CatalogItem>[item('Shelf $id')],
      ),
      catalogSearchProvider.overrideWith(
        (Ref ref, String query) async => <CatalogItem>[item('Found $query')],
      ),
    ];
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpApp(const CatalogScreen(), overrides: overrides());
    await tester.pumpAndSettle();
  }

  group('CatalogScreen', () {
    testWidgets('renders the rail and the first shelf on a wide window', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(1400, 900));

      expect(tester.takeException(), isNull);
      expect(find.text('Shelf recs'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('collapses the rail without overflow on a narrow window', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(600, 800));

      expect(tester.takeException(), isNull);
      expect(find.text('Shelf recs'), findsOneWidget);
    });

    testWidgets('a rail item switches the shelf', (WidgetTester tester) async {
      await pumpAt(tester, const Size(1400, 900));

      await tester.tap(find.byIcon(Icons.history).first);
      await tester.pumpAndSettle();

      expect(find.text('Shelf old_cartoons'), findsOneWidget);
      expect(find.text('Shelf recs'), findsNothing);
    });

    testWidgets('search shows results and clearing brings the shelf back', (
      WidgetTester tester,
    ) async {
      await pumpAt(tester, const Size(1400, 900));

      await tester.enterText(find.byType(TextField), 'matrix');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Found matrix'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Found matrix'), findsNothing);
      expect(find.text('Shelf recs'), findsOneWidget);
    });
  });
}
