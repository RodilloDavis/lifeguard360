// lib/shared/widgets/photo_avatar.dart
//
// Renders a stored PhotoUrl value regardless of which of the two formats
// it's in on this account:
//   - `data:image/...;base64,...`  — legacy uploads (any photo picked
//     before the Cloudinary migration — see CloudinaryService). Decoded via
//     PhotoCache, same as every call site already did: zero network, and
//     the same decoded Uint8List instance on repeat calls so Image.memory
//     hits Flutter's image cache instead of re-decoding on every rebuild.
//   - `https://...`                — a Cloudinary upload, or a Google
//     Sign-In photo (already stored as a plain URL, see
//     registerWithGoogle). Rendered via CachedNetworkImage, which persists
//     the decoded bytes to disk — fetched at most once per device, not on
//     every poll/rebuild the way a bare Image.network would. Cloudinary
//     URLs are additionally rewritten (CloudinaryService.deliveryUrl) to
//     request an auto-optimized, size-capped variant instead of the
//     original full-resolution upload.
//
// Falls back to [initials] for an empty, malformed, or failed-to-load
// value — exactly what every call site already did for a bad base64
// string, now covering a bad/unreachable URL the same way.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/utils/photo_cache.dart';
import '../../services/cloudinary_service.dart';

class PhotoAvatar extends StatelessWidget {
  final String photoUrl;
  final double size;
  final Widget initials;

  const PhotoAvatar({
    super.key,
    required this.photoUrl,
    required this.size,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isEmpty) return initials;

    // Decode/fetch near the size actually drawn (~3x density) rather than
    // at the source photo's full resolution — matches what each call site
    // already did for the base64 path (cacheWidth/cacheHeight ~3x size).
    final targetPx = (size * 3).round();

    if (photoUrl.startsWith('data:')) {
      final bytes = PhotoCache.decode(photoUrl);
      if (bytes == null) return initials;
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: targetPx,
        cacheHeight: targetPx,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => initials,
      );
    }

    if (photoUrl.startsWith('http')) {
      final url = CloudinaryService.deliveryUrl(photoUrl, size: targetPx);
      return CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        placeholder: (_, __) => initials,
        errorWidget: (_, __, ___) => initials,
      );
    }

    return initials;
  }
}
