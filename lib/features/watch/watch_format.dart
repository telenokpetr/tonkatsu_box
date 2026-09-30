/// 1536 -> `1.5 KB`; torrent sizes top out in the hundreds of GB.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text = unit == 0 || value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Orders `Ep2` before `Ep10`: digit runs compare as numbers, the rest as
/// case-insensitive text. A season pack is unreadable in plain string order.
int naturalCompare(String a, String b) {
  final RegExp chunk = RegExp(r'(\d+)|(\D+)');
  final List<String> left = chunk
      .allMatches(a.toLowerCase())
      .map((RegExpMatch m) => m.group(0) ?? '')
      .toList();
  final List<String> right = chunk
      .allMatches(b.toLowerCase())
      .map((RegExpMatch m) => m.group(0) ?? '')
      .toList();
  final int shared = left.length < right.length ? left.length : right.length;
  for (int i = 0; i < shared; i++) {
    final String x = left[i];
    final String y = right[i];
    final int? nx = int.tryParse(x);
    final int? ny = int.tryParse(y);
    final int result = nx != null && ny != null
        ? nx.compareTo(ny)
        : x.compareTo(y);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}
