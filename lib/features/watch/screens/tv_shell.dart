import 'package:flutter/material.dart';

import 'catalog_screen.dart';

/// The whole app on platforms with the Watch feature: the catalog with its
/// rail, no collections, tier lists or other Tonkatsu Box sections.
class TvShell extends StatelessWidget {
  const TvShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SafeArea(child: CatalogScreen(embedded: true)));
  }
}
