import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/shared/constants/platform_features.dart';
import 'package:tonkatsu_box/features/watch/catalog_shelves.dart';
import 'package:tonkatsu_box/features/watch/screens/catalog_screen.dart';
import 'package:tonkatsu_box/features/watch/screens/tv_shell.dart';

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

  group('Movix rail item', () {
    testWidgets('opens the panel and explains a missing browser', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(const CatalogScreen(), overrides: overrides());
      await tester.pumpAndSettle();
      expect(find.text('Movix'), findsOneWidget);

      await tester.tap(find.text('Movix'));
      await tester.pump();
      // Without WebView2 the init never answers; the panel gives up by itself.
      await tester.pump(const Duration(seconds: 25));
      await tester.pump();

      // No WebView2 plugin under flutter test: the panel must say so, not crash.
      expect(find.textContaining('WebView2'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    }, skip: !kIsWindowsApp);
  });

  group('TvShell', () {
    testWidgets('is the catalog alone, with settings in the rail', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(const TvShell(), overrides: overrides());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.byIcon(Icons.key_outlined), findsOneWidget);
    });
  });
}
