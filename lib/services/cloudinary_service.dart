// lib/services/cloudinary_service.dart
//
// Uploads profile photos to Cloudinary instead of embedding them as
// base64 text inside the Firebase Realtime Database (see edit_profile_
// screen.dart, which used to do `'data:image/jpeg;base64,${base64Encode(
// bytes)}'` and save that whole string as PhotoUrl). Two effects on data
// usage:
//
//   1. Upload: the photo crosses the network once, to Cloudinary — instead
//      of being re-embedded as ~33%-inflated base64 text inside the same
//      Account JSON node the dashboard's presence poll re-fetches.
//   2. Delivery: every future VIEW of that photo requests Cloudinary's
//      auto-optimized, size-capped variant (see deliveryUrl) — a small
//      WebP/AVIF thumbnail sized for how it's actually displayed, not the
//      original full-resolution upload — and PhotoAvatar's
//      CachedNetworkImage caches that variant to disk, so it's fetched at
//      most once per device rather than on every rebuild/poll.
//
// Account: cloud name mm21duqn, unsigned upload preset
// lifeguard360_profile_photos (Settings → Upload → Upload presets).
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class CloudinaryService {
  CloudinaryService._();

  static const String cloudName = 'mm21duqn';
  static const String uploadPreset = 'lifeguard360_profile_photos';

  static Uri get _uploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  /// Uploads [file] to Cloudinary and returns its `secure_url`. [folder]
  /// only groups the upload in Cloudinary's media library for browsing —
  /// it has no effect on delivery. Throws on a failed upload; callers
  /// should surface that to the user rather than silently falling back,
  /// since there'd be no photo to save either way.
  static Future<String> uploadImage(
    File file, {
    String folder = 'lifeguard360/profile_photos',
  }) async {
    final request = http.MultipartRequest('POST', _uploadUri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Cloudinary upload failed: ${response.statusCode} ${response.body}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final url = decoded['secure_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Cloudinary upload succeeded but returned no secure_url');
    }
    return url;
  }

  /// Rewrites a Cloudinary `secure_url` to request an auto-optimized
  /// delivery variant — capped to [size]px, automatic format (WebP/AVIF
  /// where the viewing device supports it) and automatic quality —
  /// instead of the original full-resolution upload. A URL that isn't
  /// Cloudinary's (e.g. a Google Sign-In photo, which is stored as a plain
  /// https URL on the account too) passes through unchanged.
  static String deliveryUrl(String url, {int size = 200}) {
    if (!url.contains('res.cloudinary.com') || !url.contains('/upload/')) {
      return url;
    }
    const marker = '/upload/';
    final idx = url.indexOf(marker);
    if (idx == -1) return url;
    final insertAt = idx + marker.length;
    final transform = 'q_auto,f_auto,w_$size,h_$size,c_fill,g_face/';
    return url.substring(0, insertAt) + transform + url.substring(insertAt);
  }
}
