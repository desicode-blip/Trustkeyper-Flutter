Future<String?> readyMessagingToken({
  required bool requiresApns,
  required Future<String?> Function() readApnsToken,
  required Future<String?> Function() readMessagingToken,
  required bool Function() isActive,
  Future<void> Function(Duration)? wait,
  int attempts = 20,
}) async {
  final pause = wait ?? Future<void>.delayed;
  if (!isActive()) return null;
  if (requiresApns) {
    var ready = false;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (!isActive()) return null;
      final token = await readApnsToken();
      if (!isActive()) return null;
      if (token != null && token.isNotEmpty) {
        ready = true;
        break;
      }
      if (attempt + 1 < attempts) {
        await pause(const Duration(milliseconds: 500));
      }
    }
    if (!ready) return null;
  }
  if (!isActive()) return null;
  final token = await readMessagingToken();
  return isActive() ? token : null;
}
