/// Turns typed input such as `192.168.1.5:9117/` into `http://192.168.1.5:9117`.
/// Empty input stays empty so callers can treat it as "not configured".
String normalizeServiceUrl(String input) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final String withScheme = trimmed.contains('://')
      ? trimmed
      : 'http://$trimmed';
  return withScheme.replaceAll(RegExp(r'/+$'), '');
}
