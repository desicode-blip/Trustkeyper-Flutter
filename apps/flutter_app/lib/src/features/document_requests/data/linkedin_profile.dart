String? normalizeLinkedInProfile(String input) {
  final text = input.trim();
  if (text.isEmpty || text.length > 500) return null;
  final uri = Uri.tryParse(
    RegExp(r'^https?://', caseSensitive: false).hasMatch(text)
        ? text
        : 'https://$text',
  );
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      !['linkedin.com', 'www.linkedin.com'].contains(uri.host.toLowerCase()) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !RegExp(
        r'^/in/[a-z0-9_%.-]+/?$',
        caseSensitive: false,
      ).hasMatch(uri.path)) {
    return null;
  }
  return 'https://www.linkedin.com${uri.path.replaceFirst(RegExp(r'/$'), '')}';
}

const linkedInProfileError =
    'This is not a LinkedIn link. It should start with linkedin.com/in/';
