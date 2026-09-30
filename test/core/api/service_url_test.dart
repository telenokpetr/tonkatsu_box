import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/core/api/service_url.dart';

void main() {
  group('normalizeServiceUrl', () {
    test('adds http:// to a bare host:port', () {
      expect(
        normalizeServiceUrl('192.168.1.5:9117'),
        'http://192.168.1.5:9117',
      );
    });

    test('keeps an explicit scheme', () {
      expect(
        normalizeServiceUrl('https://jacred.lan:8443'),
        'https://jacred.lan:8443',
      );
    });

    test('strips trailing slashes and surrounding spaces', () {
      expect(normalizeServiceUrl('  http://host:8090//  '), 'http://host:8090');
    });

    test('empty and blank input stay empty', () {
      expect(normalizeServiceUrl(''), isEmpty);
      expect(normalizeServiceUrl('   '), isEmpty);
    });
  });
}
