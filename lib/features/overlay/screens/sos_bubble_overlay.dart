// lib/features/overlay/screens/sos_bubble_overlay.dart
//
// LifeGuard360 — Floating SOS Bubble (system overlay / "chathead")
//
// This widget is the root of a SEPARATE Flutter engine hosted inside an
// Android system overlay window (TYPE_APPLICATION_OVERLAY), so it stays
// visible and interactive while the user is in ANY other app.
//
// ── Behaviour ────────────────────────────────────────────────────────────────
//   • Drag the bubble anywhere on screen. On release it glides to rest
//     against the nearest edge (left or right) — the same feel as iOS
//     AssistiveTouch — while keeping the y position it was dropped at.
//   • Drag it toward the bottom-centre of the screen, Messenger-chathead
//     style, and a red X target fades in. Drop the bubble on it and the
//     overlay closes instead of snapping back — see OverlayService.java's
//     showCloseTarget()/performCloseFromDrag() for the native half of this.
//   • Tap the bubble to arm it. The first tap starts a single kArmWindow
//     (10s) countdown for the whole sequence and fills one of 5 segments in
//     the ring; each further tap fills another segment but does NOT restart
//     the countdown.
//   • Land all 5 taps before kArmWindow runs out → emergency SOS to all
//     family members (the same path as the Shake SOS: /Families/{code}/SOS,
//     .../FamilyReports, /UserEmergencyReports + FCM push).
//   • Only manage 1-4 taps before kArmWindow runs out and it cancels — the
//     counter clears and nothing is sent — so a stray pocket tap (or two)
//     can never fire an alert on its own.
//   • Capped at kMaxSendsPerWindow (3) successful sends per kRateLimitWindow
//     (2h), tracked per-userId in SharedPreferences. A first tap that would
//     exceed the cap shows a distinct "limited" state instead of arming, so
//     repeated bubble taps can't spam the family with alerts.
//
// ── Positioning is handled ENTIRELY by Android ───────────────────────────────
// OverlayService.show() passes:
//
//     enableDrag: true                       // native drag
//     alignment: OverlayAlignment.topLeft    // x/y measured from top-left
//     positionGravity: PositionGravity.auto  // glide to nearest edge on release
//
// This file contains NO positioning code whatsoever — no moveOverlay calls,
// no position polling, no timers. That is deliberate, and worth preserving:
// calling moveOverlay() during a drag forces a FlutterView re-layout on every
// frame (visible in logcat as a flood of "Sending viewport metrics to the
// engine"), which made the overlay window thrash and disappear.
//
// `alignment: topLeft` matters as much as `positionGravity: auto` here — the
// native edge-snap animation always assumes x is an offset from the screen's
// left edge. Any other alignment (e.g. the default `center`) puts x in a
// different coordinate system and the bubble ends up snapping to the wrong
// place. See the comment in OverlayService.show() for the full story.
//
// Letting the native layer own placement avoids both problems.
//
// Launched from OverlayService.show(); engine entry point is `overlayMain()`
// in lib/main.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/emergency_report_service.dart';

/// Number of taps required to fire the SOS.
const int kRequiredTaps = 5;

/// How long the user has, from their FIRST tap, to land all kRequiredTaps —
/// this does not restart on each subsequent tap. Landing only 1-4 taps
/// before it elapses cancels the alert and clears the counter.
const Duration kArmWindow = Duration(seconds: 10);

/// How long the success / failure state stays on screen before resetting.
///
/// Long enough that the user cannot miss the confirmation — the earlier
/// 4-second window meant a slow send could finish and reset almost
/// immediately after the tick appeared.
const Duration kResultDuration = Duration(seconds: 6);

/// Hard ceiling on the send. GPS, reverse geocoding and three Firebase writes
/// all have their own timeouts, but this guarantees the bubble always resolves
/// to a success or failure state instead of spinning forever.
const Duration kSendTimeout = Duration(seconds: 25);

/// Anti-spam cap: at most this many SUCCESSFUL sends per [kRateLimitWindow],
/// tracked per-userId. Only counts sends that actually went through — a
/// failed attempt didn't reach anyone, so it shouldn't cost the user one of
/// their 3.
const int kMaxSendsPerWindow = 20;

/// Rolling window [kMaxSendsPerWindow] applies over.
const Duration kRateLimitWindow = Duration(seconds: 5);

enum _BubbleState { idle, arming, sending, sent, failed, limited }

class SosBubbleOverlay extends StatefulWidget {
  const SosBubbleOverlay({super.key});

  @override
  State<SosBubbleOverlay> createState() => _SosBubbleOverlayState();
}

class _SosBubbleOverlayState extends State<SosBubbleOverlay>
    with TickerProviderStateMixin {
  _BubbleState _state = _BubbleState.idle;
  int _tapCount = 0;

  /// When the oldest of the current rate-limit window's sends ages out and
  /// frees up a slot. Only meaningful while [_state] is [_BubbleState.limited];
  /// shown to the user as "try again in Xh Ym".
  DateTime? _nextAvailableAt;

  Timer? _resetTimer;
  Timer? _resultTimer;

  // ── Session, pushed from the main app ──────────────────────────────────────
  //
  // OverlayService.pushSession() sends these over as soon as the bubble
  // starts, and again whenever the session changes. Holding them here means an
  // SOS never depends on SharedPreferences working inside the overlay engine.
  StreamSubscription<dynamic>? _dataSub;
  String? _userId;
  String? _userName;
  String? _familyCode;

  late final AnimationController _pulseController;
  late final AnimationController _tapController;
  late final Animation<double> _tapScale;

  @override
  void initState() {
    super.initState();

    // Slow ambient pulse so the bubble reads as "live" but stays unobtrusive.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Quick squash-and-stretch feedback on every tap.
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _tapScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeOut),
    );

    _listenForSession();
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _resultTimer?.cancel();
    _dataSub?.cancel();
    _pulseController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  /// Receives session pushes from the main app.
  void _listenForSession() {
    try {
      _dataSub = FlutterOverlayWindow.overlayListener.listen((event) {
        if (event is! Map) return;
        if (event['event']?.toString() != 'session') return;

        _userId = event['userId']?.toString();
        _userName = event['userName']?.toString();
        _familyCode = event['familyCode']?.toString();

        debugPrint('Bubble received session: userId=$_userId '
            'familyCode=$_familyCode');
      });
    } catch (e) {
      debugPrint('Bubble could not attach overlay listener: $e');
    }
  }

  // ── Rate limiting ──────────────────────────────────────────────────────────

  String get _rateLimitPrefsKey =>
      'bubbleSosSendTimestamps_${(_userId == null || _userId!.isEmpty) ? 'unknown' : _userId}';

  /// Timestamps of successful sends still inside [kRateLimitWindow], oldest
  /// entries pruned as a side effect.
  ///
  /// Fails OPEN (returns an empty list, i.e. "not limited") if
  /// SharedPreferences can't be read — this plugin isn't guaranteed to be
  /// registered in the overlay's own Flutter engine on every device (see the
  /// fallback note on saveOverlaySosReport below), and wrongly refusing a
  /// real emergency because of that would be far worse than occasionally
  /// letting a 4th send through.
  Future<List<DateTime>> _recentSendTimestamps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_rateLimitPrefsKey) ?? const [];
      final cutoff = DateTime.now().subtract(kRateLimitWindow);
      final recent = raw
          .map((s) => DateTime.tryParse(s))
          .whereType<DateTime>()
          .where((t) => t.isAfter(cutoff))
          .toList();

      if (recent.length != raw.length) {
        await prefs.setStringList(
          _rateLimitPrefsKey,
          recent.map((t) => t.toIso8601String()).toList(),
        );
      }
      return recent;
    } catch (e) {
      debugPrint('Bubble rate-limit read failed (failing open): $e');
      return const [];
    }
  }

  Future<void> _recordSendForRateLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = [..._sendTimestampsCache, DateTime.now()];
      await prefs.setStringList(
        _rateLimitPrefsKey,
        updated.map((t) => t.toIso8601String()).toList(),
      );
    } catch (e) {
      debugPrint('Bubble rate-limit write failed: $e');
    }
  }

  /// Snapshot of the last [_recentSendTimestamps] read, so
  /// [_recordSendForRateLimit] doesn't need to re-read prefs right after
  /// [_handleTap] already did.
  List<DateTime> _sendTimestampsCache = const [];

  // ── Tap handling ───────────────────────────────────────────────────────────

  Future<void> _handleTap() async {
    // Ignore taps while a send is in flight or a result is being displayed.
    if (_state == _BubbleState.sending) return;

    if (_state == _BubbleState.sent ||
        _state == _BubbleState.failed ||
        _state == _BubbleState.limited) {
      _resultTimer?.cancel();
      setState(() {
        _state = _BubbleState.idle;
        _tapCount = 0;
      });
      return;
    }

    final isFirstTap = _state == _BubbleState.idle;

    if (isFirstTap) {
      _sendTimestampsCache = await _recentSendTimestamps();
      if (!mounted) return;

      if (_sendTimestampsCache.length >= kMaxSendsPerWindow) {
        // The window frees a slot the moment its OLDEST send ages out, not
        // when all of them do — so it's the earliest timestamp, not the
        // latest, that determines when the user can send again.
        final oldest = _sendTimestampsCache.reduce(
          (a, b) => a.isBefore(b) ? a : b,
        );

        _tapController.forward().then((_) => _tapController.reverse());
        HapticFeedback.heavyImpact();
        setState(() {
          _state = _BubbleState.limited;
          _nextAvailableAt = oldest.add(kRateLimitWindow);
        });
        _resultTimer?.cancel();
        _resultTimer = Timer(kResultDuration, () {
          if (!mounted) return;
          setState(() => _state = _BubbleState.idle);
        });
        return;
      }
    }

    _tapController.forward().then((_) => _tapController.reverse());
    HapticFeedback.selectionClick();

    final next = _tapCount + 1;

    setState(() {
      _tapCount = next;
      _state = _BubbleState.arming;
    });

    if (next >= kRequiredTaps) {
      _resetTimer?.cancel();
      _sendSos();
      return;
    }

    if (isFirstTap) {
      // Starts the single kArmWindow countdown for the whole sequence.
      // Taps 2-4 land inside this same window WITHOUT restarting it, so
      // landing only 1-4 taps before it elapses cancels the alert.
      _resetTimer?.cancel();
      _resetTimer = Timer(kArmWindow, () {
        if (!mounted) return;
        setState(() {
          _tapCount = 0;
          _state = _BubbleState.idle;
        });
      });
    }
  }

  // ── Send the emergency signal ──────────────────────────────────────────────

  Future<void> _sendSos() async {
    setState(() => _state = _BubbleState.sending);

    HapticFeedback.heavyImpact();

    final started = DateTime.now();
    debugPrint('=== BUBBLE SOS: 5 taps reached, sending ===');

    Map<String, dynamic> result;
    try {
      // Hard ceiling on the whole operation.
      //
      // saveReport does a GPS fix (up to 10s) followed by three sequential
      // HTTP writes (10s + 15s + 10s timeouts), so a bad network could leave
      // the bubble spinning for the best part of a minute with no feedback.
      // This guarantees the user always gets an answer.
      if (_userId != null && _userId!.isNotEmpty) {
        // Preferred path — session was pushed from the main app, so nothing
        // here depends on SharedPreferences working in the overlay engine.
        debugPrint('BUBBLE SOS: using pushed session (userId=$_userId)');
        result = await EmergencyReportService.saveBubbleSosReport(
          userId: _userId!,
          userName: (_userName == null || _userName!.isEmpty)
              ? 'Unknown'
              : _userName!,
          familyCode: _familyCode ?? '',
        ).timeout(kSendTimeout);
      } else {
        // Fallback — no session was pushed, so read it ourselves. This throws
        // on devices where SharedPreferences is not registered in the overlay
        // engine, which the catch below reports.
        debugPrint('BUBBLE SOS: no pushed session, reading prefs directly');
        result = await EmergencyReportService.saveOverlaySosReport()
            .timeout(kSendTimeout);
      }
    } on TimeoutException {
      // The write may still land — the report is sent to Firebase before the
      // slower steps run — but we cannot confirm it, so say so honestly
      // rather than showing a green tick we cannot stand behind.
      debugPrint('BUBBLE SOS TIMED OUT after ${kSendTimeout.inSeconds}s');
      result = {
        'success': false,
        'error': 'Timed out after ${kSendTimeout.inSeconds}s — check signal',
      };
    } catch (e) {
      debugPrint('BUBBLE SOS FAILED: $e');
      result = {'success': false, 'error': e.toString()};
    }

    if (!mounted) return;

    final success = result['success'] == true;
    final elapsed = DateTime.now().difference(started).inMilliseconds;

    debugPrint(success
        ? 'BUBBLE SOS SENT in ${elapsed}ms -> reportId: ${result['reportId']}'
        : 'BUBBLE SOS FAILED in ${elapsed}ms -> ${result['error']}');

    // Tell the main app what happened, so it can refresh its notification
    // list / show a confirmation the next time it is brought to the front.
    try {
      await FlutterOverlayWindow.shareData({
        'event': success ? 'overlay_sos_sent' : 'overlay_sos_failed',
        'reportId': result['reportId']?.toString() ?? '',
        'error': result['error']?.toString() ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Overlay shareData failed: $e');
    }

    if (success) {
      HapticFeedback.vibrate();
      await _recordSendForRateLimit();
    }

    if (!mounted) return;

    setState(() {
      _state = success ? _BubbleState.sent : _BubbleState.failed;
      _tapCount = success ? kRequiredTaps : 0;
    });

    _resultTimer?.cancel();
    _resultTimer = Timer(kResultDuration, () {
      if (!mounted) return;
      setState(() {
        _state = _BubbleState.idle;
        _tapCount = 0;
      });
    });
  }

  // ── Appearance per state ───────────────────────────────────────────────────

  Color get _bubbleColor {
    switch (_state) {
      case _BubbleState.idle:
        return const Color(0xFFCC0000);
      case _BubbleState.arming:
        return Color.lerp(
          const Color(0xFFCC0000),
          const Color(0xFFFF3B30),
          _tapCount / kRequiredTaps,
        )!;
      case _BubbleState.sending:
        return const Color(0xFFFF6B00);
      case _BubbleState.sent:
        return const Color(0xFF28A745);
      case _BubbleState.failed:
        return const Color(0xFF555555);
      case _BubbleState.limited:
        return const Color(0xFFFF9800);
    }
  }

  IconData get _bubbleIcon {
    switch (_state) {
      case _BubbleState.idle:
      case _BubbleState.arming:
        return Icons.sos_rounded;
      case _BubbleState.sending:
        return Icons.wifi_tethering;
      case _BubbleState.sent:
        return Icons.check_rounded;
      case _BubbleState.failed:
        return Icons.priority_high_rounded;
      case _BubbleState.limited:
        return Icons.timer_off_rounded;
    }
  }

  /// "Try again in ~Xh Ym" text for the limited state, e.g. "1h 24m" or
  /// "45m". Always shows at least 1m, so it never reads "0m" in the instant
  /// right after the cap is hit.
  String get _rateLimitCountdownText {
    final until = _nextAvailableAt;
    if (until == null) return '';

    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative) return '';

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes < 1 ? 1 : minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The overlay window is sized in device pixels, so derive every
              // dimension from the actual constraints. This keeps the bubble
              // correctly proportioned on any screen density.
              final canvas = constraints.biggest.shortestSide;
              final ringSize = canvas * 0.92;
              final bubbleSize = ringSize * 0.72;

              return SizedBox(
                width: ringSize,
                height: ringSize,
                // Only onTap is handled here. Drag gestures are intentionally
                // NOT captured — they must fall through to the native layer,
                // which owns dragging and placement.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_pulseController, _tapController]),
                    builder: (context, child) {
                      final pulse = _state == _BubbleState.idle
                          ? 1.0 + (_pulseController.value * 0.05)
                          : 1.0;

                      return Transform.scale(
                        scale: _tapScale.value * pulse,
                        child: child,
                      );
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Progress ring — one segment per required tap.
                        SizedBox(
                          width: ringSize,
                          height: ringSize,
                          child: CustomPaint(
                            painter: _TapRingPainter(
                              filled: _tapCount,
                              total: kRequiredTaps,
                              color: _bubbleColor,
                              strokeWidth: ringSize * 0.075,
                            ),
                          ),
                        ),

                        // The bubble itself.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: bubbleSize,
                          height: bubbleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Color.lerp(_bubbleColor, Colors.white, 0.18)!,
                                _bubbleColor,
                              ],
                              center: const Alignment(-0.3, -0.4),
                              radius: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _bubbleColor.withOpacity(0.45),
                                blurRadius: bubbleSize * 0.22,
                                spreadRadius: bubbleSize * 0.02,
                                offset: Offset(0, bubbleSize * 0.06),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.28),
                                blurRadius: bubbleSize * 0.14,
                                offset: Offset(0, bubbleSize * 0.04),
                              ),
                            ],
                            border: Border.all(
                              color: Colors.white.withOpacity(0.85),
                              width: bubbleSize * 0.035,
                            ),
                          ),
                          child: Center(
                            child: _state == _BubbleState.sending
                                ? SizedBox(
                                    width: bubbleSize * 0.42,
                                    height: bubbleSize * 0.42,
                                    child: CircularProgressIndicator(
                                      strokeWidth: bubbleSize * 0.06,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _bubbleIcon,
                                        color: Colors.white,
                                        size: bubbleSize * 0.40,
                                      ),
                                      if (_state == _BubbleState.arming) ...[
                                        SizedBox(height: bubbleSize * 0.02),
                                        Text(
                                          '${kRequiredTaps - _tapCount}',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: bubbleSize * 0.22,
                                            fontWeight: FontWeight.w800,
                                            height: 1.0,
                                          ),
                                        ),
                                      ],
                                      if (_state == _BubbleState.limited) ...[
                                        SizedBox(height: bubbleSize * 0.03),
                                        Text(
                                          _rateLimitCountdownText,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: bubbleSize * 0.15,
                                            fontWeight: FontWeight.w800,
                                            height: 1.0,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Tap progress ring ────────────────────────────────────────────────────────
//
// Draws [total] arc segments around the bubble, filling one per registered tap
// so the user gets unambiguous feedback on how many taps remain.

class _TapRingPainter extends CustomPainter {
  final int filled;
  final int total;
  final Color color;
  final double strokeWidth;

  _TapRingPainter({
    required this.filled,
    required this.total,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Gap between segments, in radians.
    const gap = 0.16;
    final sweep = (2 * 3.141592653589793 / total) - gap;
    const start = -3.141592653589793 / 2; // 12 o'clock

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.35);

    final fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    for (int i = 0; i < total; i++) {
      final segStart = start + i * (sweep + gap) + gap / 2;
      canvas.drawArc(
        rect,
        segStart,
        sweep,
        false,
        i < filled ? fillPaint : basePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TapRingPainter old) {
    return old.filled != filled ||
        old.total != total ||
        old.color != color ||
        old.strokeWidth != strokeWidth;
  }
}
