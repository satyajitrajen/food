/// Resolves a media URL for display.
///
/// Menu photos uploaded through the backend come back as relative paths
/// (`/media/menu/…`) that are served by the same server. When no backend is
/// configured (offline demo) relative paths render as empty so cards fall back
/// to their icon. Absolute http(s) URLs (e.g. seeded stock photos) pass
/// through untouched.
String resolveMediaUrl(String? raw, {required String apiBase}) {
  if (raw == null || raw.isEmpty) return '';
  if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('data:')) {
    return raw;
  }
  if (raw.startsWith('/')) {
    final base = apiBase.replaceAll(RegExp(r'/+$'), '');
    return base.isEmpty ? '' : '$base$raw';
  }
  return raw;
}
