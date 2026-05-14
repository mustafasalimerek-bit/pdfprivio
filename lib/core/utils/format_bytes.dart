/// Human-friendly byte size like "1.4 MB" or "850 KB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  final mb = bytes / (1024 * 1024);
  if (mb < 10) return '${mb.toStringAsFixed(1)} MB';
  return '${mb.toStringAsFixed(0)} MB';
}
