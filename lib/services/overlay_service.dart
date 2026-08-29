// lib/services/overlay_service.dart
//
// LifeGuard360 — Floating SOS Bubble controller.
//
// Wraps flutter_overlay_window so the rest of the app never has to deal with
// the plugin directly. Handles:
//   • the Android "Display over other apps" (SYSTEM_ALERT_WINDOW) permission
//   • showing / hiding the bubble
//   • remembering the user's preference so the bubble can be restored on the
//     next app launch
//
// The bubble UI itself lives in
// lib/features/overlay/screens/sos_bubble_overlay.dart and runs in a separate
// Flutter engine whose entry point is `overlayMain()` in lib/main.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OverlayService {
  /// SharedPreferences key holding the user's on/off choice.
  static const String kEnabledKey = 'sosBubbleEnabled';

  /// Live, in-process view of whether the bubble is on.
  ///
  /// The Settings toggle is a [ValueListenableBuilder] on this instead of
  /// re-reading SharedPreferences on its own, because the bubble can also be
  /// turned off from OUTSIDE the app — dragging it onto the close (X)
  /// target — and the persisted preference alone gives Settings no way to
  /// hear about that change while it's already on screen. [setEnabled] and
  /// [markDismissedByDrag] both write here, so any listener updates the
  /// instant either happens.
  static final ValueNotifier<bool> enabledNotifier = ValueNotifier<bool>(
    false,
  );

  /// Overlay window size, in DEVICE PIXELS (not logical pixels).
  /// SosBubbleOverlay derives every dimension (ring, bubble, icon, text)
  /// from this via LayoutBuilder, so changing it scales the whole bubble
  /// proportionally — nothing else needs to change to resize it.
  static const int kOverlayWidth = 205;
  static const int kOverlayHeight = 205;

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Whether "Display over other apps" has been granted.
  static Future<bool> isPermissionGranted() async {
    if (kIsWeb) return false;
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (e) {
      debugPrint('⚠️ OverlayService.isPermissionGranted: $e');
      return false;
    }
  }

  /// Opens the system settings page so the user can grant the permission.
  /// Returns true if the permission is granted once the user returns.
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    try {
      if (await FlutterOverlayWindow.isPermissionGranted()) return true;
      final granted = await FlutterOverlayWindow.requestPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('⚠️ OverlayService.requestPermission: $e');
      return false;
    }
  }

  // ── Show / hide ────────────────────────────────────────────────────────────

  /// Whether the bubble is currently on screen.
  static Future<bool> isActive() async {
    if (kIsWeb) return false;
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (e) {
      debugPrint('⚠️ OverlayService.isActive: $e');
      return false;
    }
  }

  /// Shows the floating SOS bubble over other apps.
  ///
  /// Requests the overlay permission first if it has not been granted.
  /// Returns true if the bubble is on screen when this completes.
  static Future<bool> show() async {
    if (kIsWeb) return false;

    if (!await requestPermission()) {
      debugPrint('⚠️ Overlay permission not granted — bubble not shown');
      return false;
    }

    try {
      if (await FlutterOverlayWindow.isActive()) return true;

      await FlutterOverlayWindow.showOverlay(
        // AssistiveTouch-style behaviour: free drag anywhere on screen, then
        // glide to rest against the nearest edge on release.
        //
        //   enableDrag: true            → Android moves the window during the drag.
        //   alignment: topLeft          → window x/y are measured from the
        //                                 screen's top-left corner.
        //   positionGravity: auto       → on release, animates to whichever
        //                                 edge (left/right) the bubble is
        //                                 closer to, keeping its y position.
        //
        // The earlier version used the default `alignment: center` together
        // with `positionGravity.none`. That combination is what caused the
        // long-standing "stuck at 53% of screen width" bug: the plugin's
        // native snap animation (and the startPosition below) always treats
        // x as an offset from the LEFT EDGE, but `alignment: center` makes
        // Android interpret the very same x as an offset from the screen's
        // HORIZONTAL CENTRE instead. The two disagreed, so any snap/position
        // logic fought against where the window actually was. Pairing
        // `topLeft` with `auto` puts both sides of that math in the same
        // coordinate system, so dragging and edge-snapping now agree.
        //
        // Placement is owned by the native layer. SosBubbleOverlay contains no
        // moveOverlay calls or position polling, which is what keeps the
        // overlay window stable.
        enableDrag: true,
        alignment: OverlayAlignment.topLeft,
        overlayTitle: 'LifeGuard360 SOS',
        overlayContent: 'Tap the bubble 5× to alert your family',
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.auto,
        height: kOverlayHeight,
        width: kOverlayWidth,
        // Where the bubble first appears, before the user has moved it.
        // Left-edge based now that alignment is topLeft.
        startPosition: const OverlayPosition(0, 240),
      );

      debugPrint('🫧 SOS bubble shown');

      // Hand the bubble the current session as soon as its engine is up, so
      // it never has to read SharedPreferences from inside the overlay
      // isolate. The short delay gives that engine time to attach its
      // overlayListener.
      Future.delayed(const Duration(milliseconds: 800), pushSession);

      return true;
    } catch (e) {
      debugPrint('❌ OverlayService.show: $e');
      return false;
    }
  }

  /// Sends the current session (userId / userName / familyCode) to the running
  /// overlay.
  ///
  /// The bubble lives in its own Flutter engine with its own SharedPreferences
  /// cache. On some devices that plugin is not registered in the overlay
  /// engine at all, in which case the bubble cannot read the session for
  /// itself and an SOS would fail with "No active session".
  ///
  /// Pushing the values from the main isolate — where prefs is guaranteed to
  /// work — removes that dependency. The bubble caches whatever arrives and
  /// falls back to reading prefs itself only if nothing was ever pushed.
  ///
  /// Safe to call at any time; it no-ops when the overlay is not showing.
  static Future<void> pushSession() async {
    if (kIsWeb) return;
    try {
      if (!await FlutterOverlayWindow.isActive()) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      await FlutterOverlayWindow.shareData({
        'event': 'session',
        'userId': prefs.getString('userId') ?? '',
        'userName': prefs.getString('userName') ?? '',
        'familyCode': prefs.getString('familyCode') ?? '',
      });

      debugPrint('Overlay session pushed to bubble');
    } catch (e) {
      debugPrint('OverlayService.pushSession: $e');
    }
  }

  /// Keeps the persisted on/off preference in sync after the user dismisses
  /// the bubble by dragging it onto the close (X) target.
  ///
  /// The native side has already torn the overlay window down itself by the
  /// time this fires, so this must NOT call [hide] — the plugin's
  /// closeOverlay() never resolves its result once OverlayService is no
  /// longer running, which would leave the caller awaiting forever.
  static Future<void> markDismissedByDrag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kEnabledKey, false);
      enabledNotifier.value = false;
      debugPrint('🫧 SOS bubble dismissed by drag — preference updated');
    } catch (e) {
      debugPrint('⚠️ OverlayService.markDismissedByDrag: $e');
    }
  }

  /// Removes the bubble from the screen.
  ///
  /// Safe to call even when the bubble isn't currently showing — the native
  /// closeOverlay() handler now always replies either way (see
  /// FlutterOverlayWindowPlugin.java), which matters because this runs on
  /// every app-foreground transition (see _LifecycleWrapper in main.dart),
  /// not just when the user actually had it on screen.
  static Future<void> hide() async {
    if (kIsWeb) return;
    try {
      await FlutterOverlayWindow.closeOverlay();
      debugPrint('🫧 SOS bubble hidden');
    } catch (e) {
      debugPrint('⚠️ OverlayService.hide: $e');
    }
  }

  /// Shows the bubble only if the user has it enabled AND the overlay
  /// permission is already granted.
  ///
  /// This is what _LifecycleWrapper calls when the app leaves the
  /// foreground. It must never fall through to [requestPermission]'s
  /// settings-screen prompt — that flow belongs to the moment the user
  /// deliberately flips the Settings toggle, not to the app being
  /// backgrounded, where an unexpected system settings screen popping up
  /// would be a jarring surprise rather than something the user asked for.
  static Future<void> showIfEnabledAndPermitted() async {
    if (kIsWeb) return;
    try {
      if (!await isEnabled()) return;
      if (!await isPermissionGranted()) return;
      if (await isActive()) return;
      await show();
    } catch (e) {
      debugPrint('⚠️ OverlayService.showIfEnabledAndPermitted: $e');
    }
  }

  // ── Persisted preference ───────────────────────────────────────────────────

  /// Whether the user has switched the bubble on.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kEnabledKey) ?? false;
    } catch (e) {
      debugPrint('⚠️ OverlayService.isEnabled: $e');
      return false;
    }
  }

  /// Turns the bubble on or off and remembers the choice.
  /// Returns the state actually achieved — turning it on can fail if the user
  /// declines the overlay permission.
  ///
  /// Deliberately does NOT put the bubble on screen when turning it on. The
  /// app is the foreground app at the moment this runs (the user is looking
  /// at the Settings switch), and the bubble is only ever supposed to appear
  /// once the app is backgrounded — see _LifecycleWrapper in main.dart. This
  /// only settles the permission (prompting if needed) and persists the
  /// choice; [showIfEnabledAndPermitted] handles actually showing it later.
  static Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      await hide();
      await prefs.setBool(kEnabledKey, false);
      enabledNotifier.value = false;
      return false;
    }

    final granted = await requestPermission();
    await prefs.setBool(kEnabledKey, granted);
    enabledNotifier.value = granted;
    return granted;
  }

  /// Seeds [enabledNotifier] from the persisted preference on app start.
  ///
  /// Deliberately does NOT show the bubble — the app is about to render its
  /// UI (i.e. be in the foreground) the moment this returns, and the bubble
  /// must stay off screen until the app is actually backgrounded. See
  /// _LifecycleWrapper in main.dart, which calls [showIfEnabledAndPermitted]
  /// on the transition that used to happen here.
  ///
  /// Callers should pair this with an explicit [hide] first — this method
  /// only seeds the in-memory flag, it does not touch whatever the overlay
  /// window is currently doing. A bubble left over from a previous session
  /// (app force-killed while backgrounded) would otherwise keep floating on
  /// cold start, since [enabledNotifier] being false here doesn't retract a
  /// window that's already on screen.
  static Future<void> restoreIfEnabled() async {
    if (kIsWeb) return;
    try {
      enabledNotifier.value = await isEnabled();
    } catch (e) {
      debugPrint('⚠️ OverlayService.restoreIfEnabled: $e');
    }
  }
}
