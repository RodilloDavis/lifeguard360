/// Android can reclaim a GoogleMap's native rendering surface after the app
/// sits backgrounded a while (memory pressure, split-screen, long sleep),
/// leaving it stuck black on resume with no Dart-side error to catch. There's
/// no reliable way to detect a stuck surface directly, so this uses how long
/// the app was backgrounded as a heuristic: past [_staleAfter], the screen
/// should force the map widget to rebuild from scratch (via a fresh key)
/// rather than trust the existing native view.
///
/// Deliberately NOT triggered on every resume — recreating the map on a
/// quick app-switch-and-back would cause a visible flicker and reset the
/// camera position for no benefit, since a few seconds backgrounded is not
/// enough for Android to reclaim GPU resources.
class MapSurfaceGuard {
  DateTime? _backgroundedAt;
  int generation = 0;

  static const _staleAfter = Duration(seconds: 60);

  void onPaused() => _backgroundedAt = DateTime.now();

  /// Call on resume. Returns true if the caller should force-recreate its
  /// GoogleMap widget (bump the key it's keyed with to [generation]).
  bool onResumedShouldRecreate() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return false;
    final wasStale = DateTime.now().difference(since) > _staleAfter;
    if (wasStale) generation++;
    return wasStale;
  }
}
