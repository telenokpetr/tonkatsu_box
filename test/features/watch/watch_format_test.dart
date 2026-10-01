import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/features/watch/watch_format.dart';

void main() {
  group('formatBytes', () {
    test('zero and negative sizes read as 0 B', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
    });

    test('bytes stay whole', () {
      expect(formatBytes(512), '512 B');
    });

    test('one decimal below 100, none above', () {
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
    });

    test('gigabytes and the top unit', () {
      expect(formatBytes(19810536652), '18.4 GB');
      expect(formatBytes(3 * 1024 * 1024 * 1024 * 1024), '3.0 TB');
    });
  });

  group('naturalCompare', () {
    test('orders episode numbers numerically', () {
      final List<String> names = <String>['Ep10', 'Ep2', 'Ep1']
        ..sort(naturalCompare);
      expect(names, <String>['Ep1', 'Ep2', 'Ep10']);
    });

    test('is case-insensitive', () {
      expect(naturalCompare('abc', 'ABD'), lessThan(0));
      expect(naturalCompare('ABC', 'abc'), 0);
    });

    test('a prefix sorts before the longer name', () {
      expect(naturalCompare('S01', 'S01E01'), lessThan(0));
    });

    test('sorts a season pack by season then episode', () {
      final List<String> paths = <String>[
        'Show/S02E01.mkv',
        'Show/S01E10.mkv',
        'Show/S01E02.mkv',
      ]..sort(naturalCompare);
      expect(paths, <String>[
        'Show/S01E02.mkv',
        'Show/S01E10.mkv',
        'Show/S02E01.mkv',
      ]);
    });
  });

  group('isMagnetLink', () {
    test('accepts a magnet URI with surrounding spaces and any case', () {
      expect(isMagnetLink('  magnet:?xt=urn:btih:abc  '), isTrue);
      expect(isMagnetLink('MAGNET:?xt=urn:btih:abc'), isTrue);
    });

    test('rejects titles, urls and an empty string', () {
      expect(isMagnetLink('The Matrix'), isFalse);
      expect(isMagnetLink('https://example.com/x.torrent'), isFalse);
      expect(isMagnetLink('magnet'), isFalse);
      expect(isMagnetLink(''), isFalse);
    });
  });
}
