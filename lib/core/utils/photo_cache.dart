// lib/core/utils/photo_cache.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// DECODED PROFILE-PHOTO CACHE
// ═══════════════════════════════════════════════════════════════════════════════
//
// Profile photos are stored as `data:image/...;base64,...` strings on the
// account record, and screens were calling base64Decode() inline in their
// build path. That cost the UI thread twice over on every rebuild:
//
//   1. base64Decode() itself re-ran for every member, every rebuild. The
//      family list rebuilds on a 10-second presence poll (and on every other
//      setState), so a five-member family re-decoded five photos every tick
//      for pixels that had not changed.
//
//   2. Worse, it handed Image.memory a BRAND NEW Uint8List each time.
//      MemoryImage's equality is identity-based on that byte list, so every
//      rebuild missed Flutter's image cache and re-decoded the actual
//      JPEG/PNG too — the genuinely expensive half, and a classic source of
//      scroll stutter.
//
// Returning the SAME Uint8List instance for the same source string fixes
// both: the base64 work happens once, and MemoryImage now hits the image
// cache instead of re-decoding.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class PhotoCache {
  PhotoCache._();

  // Bounded so a large family circle (or a long session scrolling past many
  // members) can't grow this without limit. Photos are small and few in
  // practice; this is a backstop, not a tuning knob.
  static const int _maxEntries = 64;

  // Insertion-ordered, which Dart's LinkedHashMap gives us for free — so
  // evicting `keys.first` evicts the least recently ADDED entry.
  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};

  /// Decodes a `data:image/...;base64,...` photo string into raw bytes,
  /// returning the identical [Uint8List] instance on repeat calls for the
  /// same string so Flutter's image cache can hit.
  ///
  /// Returns null for empty or malformed input — callers fall back to an
  /// initials avatar. Null results are cached too, so a corrupt photo
  /// string doesn't retry a doomed decode on every single rebuild.
  static Uint8List? decode(String photo) {
    if (photo.isEmpty) return null;

    // containsKey rather than a null check, so cached FAILURES are honoured
    // instead of being retried forever.
    if (_cache.containsKey(photo)) return _cache[photo];

    Uint8List? bytes;
    try {
      final commaIndex = photo.indexOf(',');
      final data = commaIndex == -1 ? photo : photo.substring(commaIndex + 1);
      bytes = base64Decode(data);
    } catch (_) {
      bytes = null; // malformed — cached below so we don't keep retrying
    }

    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[photo] = bytes;
    return bytes;
  }

  /// Drops everything. Only needed if photos are edited in-session and the
  /// same string could map to different bytes — which can't happen here,
  /// since the string IS the image data. Exposed for tests/memory pressure.
  @visibleForTesting
  static void clear() => _cache.clear();
}
