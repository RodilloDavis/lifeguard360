import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/animated_refresh_button.dart';
import '../../../services/emergency_report_service.dart';
import '../../../services/offline_report_queue_service.dart';

// Values arrive from the DB as raw slugs ("fire-report", "family-bubble-sos")
// — turn them into readable text before they reach the UI.
const _acronyms = {'sos', 'id', 'gps'};

// Google Open Location Code token, e.g. "8M6G+MFG" — meaningless to users,
// so it's stripped out of any address before display.
final _plusCodeRe = RegExp(
    r'\b[23456789A-CF-HJ-NP-TV-Z]{4,8}\+[23456789A-CF-HJ-NP-TV-Z]{2,3}\b',
    caseSensitive: false);

String _stripPlusCode(String s) {
  var out = s.replaceAll(_plusCodeRe, '');
  out = out.replaceAll(RegExp(r',\s*,'), ','); // collapse the gap it leaves
  out = out.replaceAll(RegExp(r'^[,\s]+'), '');
  out = out.replaceAll(RegExp(r'[,\s]+$'), '');
  return out.trim();
}

// `Location.Address` is a plus-code reverse-geocode (e.g. "8M6G+MFG, Panabo,
// Davao Region") with no barangay info, while `Barangay` is stored as a
// separate field entirely — the two are never combined anywhere they're
// displayed, so the barangay a report happened in was invisible. This joins
// them into one readable string, skipping placeholder values.
String _formatLocation(String? address, String? barangay) {
  final addr = _stripPlusCode((address ?? '').trim());
  final brgy = (barangay ?? '').trim();
  final hasAddr = addr.isNotEmpty &&
      addr.toLowerCase() != 'location unavailable' &&
      addr.toLowerCase() != 'see map for exact location';
  final hasBrgy = brgy.isNotEmpty && brgy.toLowerCase() != 'unknown barangay';

  if (hasBrgy && hasAddr) {
    // Don't double up if the address already names the barangay.
    return addr.toLowerCase().contains(brgy.toLowerCase())
        ? addr
        : 'Brgy. $brgy, $addr';
  }
  if (hasBrgy) return 'Brgy. $brgy';
  if (hasAddr) return addr;
  return 'Location unavailable';
}

String _humanize(String raw) {
  final words = raw.replaceAll('-', ' ').replaceAll('_', ' ').trim().split(' ');
  return words
      .where((w) => w.isNotEmpty)
      .map((w) => _acronyms.contains(w.toLowerCase())
          ? w.toUpperCase()
          : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// "Active" is a live, ongoing SOS — a different lifecycle than the
// Pending → In Progress → Resolved review pipeline. Forcing it through that
// timeline used to render it identically to a freshly-submitted, unreviewed
// report, so both the list card and the detail sheet swap it for this instead.
Widget _liveSosBanner() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.danger.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        const _PulsingDot(),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Ongoing — responders have been alerted',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
        ),
      ],
    ),
  );
}

// Delegates to the shared mapping so every screen that shows a status badge
// agrees on the same vocabulary (see EmergencyReportService.displayStatus).
String _displayStatus(String raw) => EmergencyReportService.displayStatus(raw);

// A cheap fingerprint of a report list's user-visible content (id + status +
// dispatcher message — the fields that ever change on an existing report).
// Comparing this against the previous poll's fingerprint lets a silent
// refresh skip setState entirely when nothing actually changed, instead of
// replacing the list (and re-running every item's build) every 12 seconds
// even when every report on screen is identical to what's already shown.
String _reportsFingerprint(List<Map<String, dynamic>> reports) {
  final buffer = StringBuffer();
  for (final r in reports) {
    buffer
      ..write(r['ReportId'])
      ..write('|')
      ..write(r['Status'])
      ..write('|')
      ..write(r['DispatcherMessage'])
      ..write(';');
  }
  return buffer.toString();
}

// Shown while one or more reports made offline are still sitting on this
// device waiting for a connection — separate from _offlineBanner, which is
// about a stale READ, not a report that hasn't actually reached the server
// yet. Distinguished with an orange/pending look rather than the neutral
// grey used for "showing cached data", since this is closer to "action
// still pending" than "data might be old".
Widget _queuedReportsBanner(int count) {
  final label = count == 1
      ? '1 report saved on this device — will send automatically once online'
      : '$count reports saved on this device — will send automatically once online';
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.orange.withOpacity(0.35)),
    ),
    child: Row(
      children: [
        const Icon(Icons.schedule_send, size: 16, color: Colors.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.orange,
            ),
          ),
        ),
      ],
    ),
  );
}

// Shown in place of an error screen when a fetch fails but we already have
// reports loaded — losing connectivity shouldn't blank out data the user
// already has; it should just tell them it might be stale.
Widget _offlineBanner() {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.grey.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.grey.withOpacity(0.3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.wifi_off, size: 16, color: AppColors.textLight),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'No internet connection — showing previously loaded reports',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textLight,
            ),
          ),
        ),
      ],
    ),
  );
}

// Puts every unresolved report (Pending, In Progress, Active — anything the
// user might still need to act on or follow up on) ahead of resolved ones,
// so the reports that actually need attention aren't buried under closed-out
// history. Both services already return newest-first by CreatedAt; this
// partitions rather than re-sorts so that relative recency order survives
// within each group instead of being reshuffled.
List<Map<String, dynamic>> _unresolvedFirst(List<Map<String, dynamic>> reports) {
  final unresolved = <Map<String, dynamic>>[];
  final resolved = <Map<String, dynamic>>[];
  for (final r in reports) {
    (EmergencyReportService.isResolvedStatus(r['Status']?.toString())
            ? resolved
            : unresolved)
        .add(r);
  }
  return [...unresolved, ...resolved];
}

// A message the dispatcher sent when acknowledging this report.
Widget _dispatcherMessageBanner(String message) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primary.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.local_police, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Message from dispatcher',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// MyReportsScreen
//
// Shows the current user's emergency reports fetched from:
//   /UserEmergencyReports/{userId}
//
// For each report the user sees:
//   • Report label badge  (e.g. "crime-report")
//   • Status badge        (Pending / In Progress / Resolved)
//   • Date & GPS location
//   • Progress timeline   (3 steps)
//   • Tap → full details bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════

class MyReportsScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String familyCode;

  const MyReportsScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.familyCode = '',
  });

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoadingMy = true;
  bool _isLoadingFamily = true;
  List<Map<String, dynamic>> _myReports = [];
  List<Map<String, dynamic>> _familyReports = [];
  String? _myError;
  String? _familyError;
  String _myFingerprint = '';
  String _familyFingerprint = '';

  // True once the most recent fetch (either tab) failed. Drives the offline
  // banner rather than replacing the list with an error screen — the whole
  // point is that already-loaded reports stay visible while this is true.
  bool _isOffline = false;

  // Number of reports made on this device that are still queued locally
  // (see OfflineReportQueueService) waiting for connectivity to actually
  // reach the server — separate from _isOffline, which is about a stale
  // read of reports that already made it through.
  int _queuedCount = 0;
  StreamSubscription<int>? _queuedCountSub;

  // A report's status can move Pending → In Progress → Resolved on the
  // dispatcher's side at any moment while this screen just sits open — a
  // one-shot load only ever reflects whatever was true when the screen
  // opened. Without a poll here, a report acknowledged or resolved while the
  // user is actually looking at this list would keep showing its old status
  // until they thought to pull down and refresh by hand.
  Timer? _autoRefreshTimer;

  // Scoped to the specific user/family so switching accounts on the same
  // device (or a shared/demo device) never shows one person's cached
  // reports to another.
  String get _myCacheKey => 'cached_reports_my_v1_${widget.userId}';
  String get _familyCacheKey =>
      'cached_reports_family_v1_${widget.familyCode}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) HapticFeedback.selectionClick();
    });
    _initReports();
    _autoRefreshTimer = Timer.periodic(
        const Duration(seconds: 12), (_) => _refreshAll(silent: true));
    _queuedCountSub = OfflineReportQueueService.pendingCountStream.listen((count) {
      if (mounted) setState(() => _queuedCount = count);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _autoRefreshTimer?.cancel();
    _queuedCountSub?.cancel();
    super.dispose();
  }

  // Paints instantly from whatever was saved to disk last session — before
  // any network round-trip — so opening this screen (even offline, even on
  // a cold app start with no connection yet) shows reports immediately
  // instead of a spinner. The network fetch right after this is what keeps
  // it current; if THAT fails, having cache already on screen is exactly
  // what lets it fail silently into the offline banner instead of an error
  // screen.
  Future<void> _initReports() async {
    await _loadCachedReports();
    await Future.wait([
      _loadMyReports(silent: _myReports.isNotEmpty),
      _loadFamilyReports(silent: _familyReports.isNotEmpty),
    ]);
  }

  Future<void> _loadCachedReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final myJson = prefs.getString(_myCacheKey);
      final familyJson = prefs.getString(_familyCacheKey);
      if (!mounted) return;
      setState(() {
        final my = _decodeCachedReports(myJson);
        if (my != null) {
          _myReports = my;
          _myFingerprint = _reportsFingerprint(my);
          _isLoadingMy = false;
        }
        final family = _decodeCachedReports(familyJson);
        if (family != null) {
          _familyReports = family;
          _familyFingerprint = _reportsFingerprint(family);
          _isLoadingFamily = false;
        }
      });
    } catch (_) {
      // No cache yet (first run) or a corrupt entry — the network load
      // right after this covers both cases the normal way.
    }
  }

  List<Map<String, dynamic>>? _decodeCachedReports(String? raw) {
    if (raw == null) return null;
    try {
      return (json.decode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveReportsCache(String key, List<Map<String, dynamic>> reports) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, json.encode(reports));
    } catch (_) {
      // Disk cache is a nice-to-have for offline viewing — a write failure
      // here shouldn't disrupt the screen the user is already looking at.
    }
  }

  Future<void> _loadMyReports({bool silent = false}) async {
    if (!mounted) return;
    // A silent background poll must never flash the full-list loading
    // spinner over a list that's already on screen, and a transient failure
    // on one of these polls shouldn't replace good, already-loaded data
    // with an error screen — only an explicit load/refresh does that.
    if (!silent) {
      setState(() {
        _isLoadingMy = true;
        _myError = null;
      });
    }
    try {
      final list = _unresolvedFirst(await EmergencyReportService.getUserReports(
          widget.userId,
          throwOnError: true));
      if (!mounted) return;
      final fp = _reportsFingerprint(list);
      final contentChanged = fp != _myFingerprint;
      // Skip the rebuild entirely when this poll changed nothing — no new
      // report, no status change, nothing for the list to show differently.
      if (contentChanged || _isLoadingMy || _isOffline) {
        setState(() {
          if (contentChanged) {
            _myReports = list;
            _myFingerprint = fp;
          }
          _isLoadingMy = false;
          _isOffline = false;
        });
        if (contentChanged) unawaited(_saveReportsCache(_myCacheKey, list));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMy = false;
          _isOffline = true;
          // Only replace the list with a full error screen when there's
          // nothing cached to fall back to — otherwise the offline banner
          // covers it and whatever was already loaded stays on screen.
          if (!silent && _myReports.isEmpty) _myError = 'Failed to load: $e';
        });
      }
    }
  }

  Future<void> _loadFamilyReports({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoadingFamily = true;
        _familyError = null;
      });
    }
    try {
      final list = _unresolvedFirst(await EmergencyReportService.getFamilyReports(
          widget.familyCode,
          throwOnError: true));
      if (!mounted) return;
      final fp = _reportsFingerprint(list);
      final contentChanged = fp != _familyFingerprint;
      if (contentChanged || _isLoadingFamily || _isOffline) {
        setState(() {
          if (contentChanged) {
            _familyReports = list;
            _familyFingerprint = fp;
          }
          _isLoadingFamily = false;
          _isOffline = false;
        });
        if (contentChanged) {
          unawaited(_saveReportsCache(_familyCacheKey, list));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingFamily = false;
          _isOffline = true;
          if (!silent && _familyReports.isEmpty) {
            _familyError = 'Failed to load: $e';
          }
        });
      }
    }
  }

  Future<void> _refreshAll({bool silent = false}) async {
    await Future.wait(
        [_loadMyReports(silent: silent), _loadFamilyReports(silent: silent)]);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Reports',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: AnimatedRefreshButton(
              onRefresh: _refreshAll,
              color: AppColors.primary,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.grey,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 6),
                  const Text('My Reports',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_myReports.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_myReports.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.groups_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('Family',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  if (_familyReports.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_familyReports.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_queuedCount > 0) _queuedReportsBanner(_queuedCount),
          if (_isOffline) _offlineBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildReportsList(
                  isLoading: _isLoadingMy,
                  error: _myError,
                  reports: _myReports,
                  onRefresh: _loadMyReports,
                  emptyMessage:
                      'Your submitted emergency reports will appear here.',
                  showReporterBadge: false,
                ),
                _buildReportsList(
                  isLoading: _isLoadingFamily,
                  error: _familyError,
                  reports: _familyReports,
                  onRefresh: _loadFamilyReports,
                  emptyMessage: 'No family emergency reports yet.',
                  showReporterBadge: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsList({
    required bool isLoading,
    required String? error,
    required List<Map<String, dynamic>> reports,
    required Future<void> Function() onRefresh,
    required String emptyMessage,
    required bool showReporterBadge,
  }) {
    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 64, color: AppColors.danger),
              const SizedBox(height: 16),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textLight)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_outlined,
                    size: 64, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              const Text('No Reports Yet',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary)),
              const SizedBox(height: 8),
              Text(emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textLight)),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        // Each card paints a shadow and a progress timeline; isolating them
        // as their own layers keeps a repaint in one card from re-rasterizing
        // the whole visible list. Matters most here because the 12-second
        // status poll rebuilds this list underneath the user as they scroll.
        // Keyed by ReportId (rather than position) so Flutter can match a
        // report to the same element across rebuilds — needed now that a
        // silent poll only replaces the list when its fingerprint actually
        // changes, instead of a fresh List every 12 seconds regardless.
        itemBuilder: (context, index) => RepaintBoundary(
          key: ValueKey(reports[index]['ReportId']?.toString() ?? index),
          child: _buildReportCard(reports[index],
              showReporterBadge: showReporterBadge),
        ),
      ),
    );
  }

  // ── Report card ────────────────────────────────────────────────────────────

  Widget _buildReportCard(Map<String, dynamic> report,
      {bool showReporterBadge = false}) {
    final reportId = report['ReportId']?.toString() ?? '';
    final label = report['ReportLabel']?.toString() ?? 'other-report';
    final type = report['EmergencyType']?.toString() ?? 'other';
    final status = _displayStatus(report['Status']?.toString() ?? 'Pending');
    final createdAt = report['CreatedAt']?.toString() ?? '';
    final location = report['Location'] as Map<String, dynamic>?;
    final displayLocation =
        _formatLocation(location?['Address']?.toString(), report['Barangay']?.toString());
    final reporterName = report['UserName']?.toString() ?? '';
    final isOwnReport = report['UserId']?.toString() == widget.userId;
    final dispatcherMessage = report['DispatcherMessage']?.toString() ?? '';

    final isActive = status == 'Active';
    final labelColor = isActive ? AppColors.danger : _labelColor(type);
    final statusColor = _statusColor(status);
    final emoji = _typeEmoji(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          if (isActive)
            BoxShadow(
              color: AppColors.danger.withOpacity(0.15),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
        ],
        border: Border.all(
          color: labelColor.withOpacity(isActive ? 0.4 : 0.2),
          width: isActive ? 1.6 : 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            _showReportDetails(report);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ───────────────────────────────────────
                Row(
                  children: [
                    // Emoji icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: labelColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                          child: Text(emoji,
                              style: const TextStyle(fontSize: 24))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Reporter badge (Family tab only)
                          if (showReporterBadge && reporterName.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOwnReport
                                    ? AppColors.primary.withOpacity(0.1)
                                    : AppColors.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: isOwnReport
                                        ? AppColors.primary.withOpacity(0.4)
                                        : AppColors.danger.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isOwnReport ? Icons.person : Icons.people,
                                    size: 11,
                                    color: isOwnReport
                                        ? AppColors.primary
                                        : AppColors.danger,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOwnReport ? 'You' : reporterName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isOwnReport
                                          ? AppColors.primary
                                          : AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Label badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: labelColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: labelColor.withOpacity(0.4)),
                            ),
                            child: Text(
                              _humanize(label),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: labelColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Short report ID
                          Text(
                            _shortId(reportId),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textLight,
                                fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    _buildStatusBadge(status, statusColor),
                  ],
                ),

                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.lightGrey),
                const SizedBox(height: 12),

                // ── Date & location ──────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: AppColors.grey),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        createdAt,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textLight),
                      ),
                    ),
                  ],
                ),
                if (displayLocation != 'Location unavailable') ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          displayLocation,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textLight),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // ── Progress timeline ────────────────────────────────
                // "Active" (a live, ongoing SOS — e.g. the floating bubble)
                // used to hide the Pending/In Progress/Resolved timeline
                // entirely in favor of just this banner, so a bubble SOS
                // gave no indication of where it stood in the dispatcher's
                // review — only that it was "ongoing". The banner still
                // carries the urgency framing an SOS needs, but now sits
                // ABOVE the timeline rather than replacing it: an
                // unreconciled 'Active' status isn't in the three known
                // steps, so it renders at the Pending step (nobody has
                // acted on it yet) and naturally advances to In Progress /
                // Resolved once the dispatcher does — same reconciled
                // Status every other screen reads, see
                // EmergencyReportService.reconcileStatuses.
                if (isActive) ...[
                  _liveSosBanner(),
                  const SizedBox(height: 12),
                ],
                _buildProgressTimeline(status),

                if (dispatcherMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _dispatcherMessageBanner(dispatcherMessage),
                ],

                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Tap to view details',
                        style: TextStyle(
                            fontSize: 11,
                            color: labelColor,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 10, color: labelColor),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Progress timeline widget ───────────────────────────────────────────────

  Widget _buildProgressTimeline(String status) {
    const steps = ['Pending', 'In Progress', 'Resolved'];
    final current = steps.indexOf(status).clamp(0, 2);

    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIndex = i ~/ 2;
          final isDone = current > stepIndex;
          return Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: isDone ? AppColors.success : AppColors.lightGrey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }

        final stepIndex = i ~/ 2;
        final isDone = current > stepIndex; // strictly past = completed
        final isActive = current == stepIndex; // currently here
        final stepLabel = steps[stepIndex];

        // Completed steps → green, Active/current step → primary blue, Future → grey
        final dotColor = isDone
            ? AppColors.success
            : isActive
                ? AppColors.primary
                : AppColors.lightGrey;
        final iconColor = (isDone || isActive) ? Colors.white : AppColors.grey;
        final labelColor = isDone
            ? AppColors.success
            : isActive
                ? AppColors.primary
                : AppColors.grey;

        return Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                border: isActive
                    ? Border.all(color: AppColors.primary, width: 2.5)
                    : null,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Icon(
                (isDone || isActive) ? Icons.check : _stepIcon(stepIndex),
                size: 14,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              stepLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
                color: labelColor,
              ),
            ),
          ],
        );
      }),
    );
  }

  IconData _stepIcon(int index) {
    switch (index) {
      case 0:
        return Icons.pending_outlined;
      case 1:
        return Icons.sync;
      case 2:
        return Icons.check_circle_outline;
      default:
        return Icons.circle;
    }
  }

  // ── Status badge ───────────────────────────────────────────────────────────

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Full details bottom sheet ──────────────────────────────────────────────

  void _showReportDetails(Map<String, dynamic> indexEntry) async {
    // Show a loading indicator while we fetch the full report
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReportDetailSheet(
        indexEntry: indexEntry,
        userId: widget.userId,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _shortId(String id) {
    if (id.length <= 22) return id;
    // e.g. "CRM-1740000000000-ABCDEF" → "CRM-…ABCDEF"
    return '${id.substring(0, 7)}…${id.substring(id.length - 6)}';
  }

  Color _labelColor(String type) {
    switch (type) {
      case 'crime':
        return AppColors.secondary;
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.deepOrange;
      case 'flood':
        return Colors.blue;
      case 'accident':
        return Colors.orange;
      case 'other':
        return AppColors.grey;
      default:
        return AppColors.primary;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'In Progress':
        return AppColors.primary;
      case 'Resolved':
        return AppColors.success;
      case 'Active':
        return AppColors.danger;
      default:
        return AppColors.grey;
    }
  }

  String _typeEmoji(String type) {
    switch (type) {
      case 'crime':
        return '👮';
      case 'medical':
        return '🏥';
      case 'fire':
        return '🔥';
      case 'flood':
        return '💧';
      case 'accident':
        return '🚗';
      case 'other':
        return '⚠️';
      default:
        return '🚨';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _ReportDetailSheet — expands full report fetched from labeled collection
// ═══════════════════════════════════════════════════════════════════════════════

class _ReportDetailSheet extends StatefulWidget {
  final Map<String, dynamic> indexEntry;
  final String userId;

  const _ReportDetailSheet({
    required this.indexEntry,
    required this.userId,
  });

  @override
  State<_ReportDetailSheet> createState() => _ReportDetailSheetState();
}

class _ReportDetailSheetState extends State<_ReportDetailSheet> {
  bool _isLoading = true;
  Map<String, dynamic>? _fullReport;

  // Keeps this sheet's status current while it's open — a responder can
  // acknowledge or resolve the report at any point during that, and without
  // a poll the sheet would keep showing whatever it fetched on open until
  // the user closed and reopened it.
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchFullReport();
    _autoRefreshTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _fetchFullReport());
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchFullReport() async {
    final full =
        await EmergencyReportService.getReportFromIndex(widget.indexEntry);
    // _isLoading only ever starts true and this only ever sets it false, so
    // repeat calls from the poll above never re-show the initial loader —
    // the fetched fields just update in place once they land.
    if (mounted) {
      setState(() {
        _fullReport = full;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // The index entry already has label, status, date, and location —
            // no need to block all of that behind a spinner while we fetch
            // the fuller record. Only the "Emergency Details" section below
            // depends on that fetch, so it carries its own small loader.
            Expanded(child: _buildContent(controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScrollController controller) {
    // The canonical record fetched here can lag behind the index entry
    // passed in — the dispatcher side doesn't always patch both in lockstep
    // — so this merges rather than blindly trusting whichever one loaded
    // last. Otherwise a report already showing Resolved in every list on
    // this screen could flash back to Pending the moment its detail sheet's
    // fetch resolves. See EmergencyReportService.mergeReportSources.
    final report = EmergencyReportService.mergeReportSources(
        widget.indexEntry, _fullReport);

    final label = report['ReportLabel']?.toString() ?? 'other-report';
    final type = report['EmergencyType']?.toString() ?? 'other';
    final status = _displayStatus(report['Status']?.toString() ?? 'Pending');
    final createdAt = report['CreatedAt']?.toString() ?? '';
    final reportId = report['ReportId']?.toString() ?? '';
    final userName = report['UserName']?.toString() ?? '';
    final location = report['Location'] as Map<String, dynamic>?;
    final details = report['Details'] as Map<String, dynamic>?;
    final dispatcherMessage = report['DispatcherMessage']?.toString() ?? '';

    final isActive = status == 'Active';
    final labelColor = isActive ? AppColors.danger : _labelColor(type);
    final statusColor = _statusColor(status);
    final emoji = _typeEmoji(type);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        // ── Title row ──────────────────────────────────────────────────────
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _humanize(label),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: labelColor),
                  ),
                  Text(
                    reportId,
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textLight,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            _buildStatusBadge(status, statusColor),
          ],
        ),

        const SizedBox(height: 20),

        // ── Progress timeline ─────────────────────────────────────────────
        // See the matching comment in _buildReportCard: the "Active" banner
        // now sits above the timeline instead of hiding it, so a live SOS
        // still shows where it stands in the dispatcher's Pending → In
        // Progress → Resolved review — it just also flags that it's
        // urgent/ongoing while that review hasn't happened yet.
        if (isActive) ...[
          _liveSosBanner(),
          const SizedBox(height: 14),
        ],
        _buildTimeline(status, labelColor),

        if (dispatcherMessage.isNotEmpty) ...[
          const SizedBox(height: 14),
          _dispatcherMessageBanner(dispatcherMessage),
        ],

        const SizedBox(height: 20),

        // ── Info section ──────────────────────────────────────────────────
        _buildInfoCard(
          title: 'Report Info',
          icon: Icons.info_outline,
          color: labelColor,
          children: [
            _buildInfoRow('Date Submitted', createdAt),
            if (userName.isNotEmpty) _buildInfoRow('Reported By', userName),
            _buildInfoRow('Status', status),
          ],
        ),

        const SizedBox(height: 12),

        // ── Location section ──────────────────────────────────────────────
        if (location != null)
          _buildInfoCard(
            title: 'Incident Location',
            icon: Icons.location_on,
            color: Colors.green,
            children: [
              _buildInfoRow(
                  'Address',
                  _formatLocation(location['Address']?.toString(),
                      report['Barangay']?.toString())),
              if (location['LastUpdated'] != null)
                _buildInfoRow(
                    'Captured At', location['LastUpdated']?.toString() ?? ''),
            ],
          ),

        if (location != null) const SizedBox(height: 12),

        // ── Details section ───────────────────────────────────────────────
        // Only this section depends on the full-report fetch — while it's
        // in flight, show a small loader here instead of blocking everything
        // above (label, status, location) that the index entry already has.
        if (_isLoading && _fullReport == null)
          _buildInfoCard(
            title: 'Emergency Details',
            icon: Icons.assignment_outlined,
            color: labelColor,
            children: const [
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
              ),
            ],
          )
        else if (details != null && details.isNotEmpty)
          _buildInfoCard(
            title: 'Emergency Details',
            icon: Icons.assignment_outlined,
            color: labelColor,
            children: _buildDetailRows(type, details),
          ),
      ],
    );
  }

  // ── Detail rows by type ────────────────────────────────────────────────────

  List<Widget> _buildDetailRows(String type, Map<String, dynamic> details) {
    switch (type) {
      case 'fire':
        return [
          _buildInfoRow('Fire Type', _fireLabel(details['fireType'])),
          _buildInfoRow(
              'People Trapped',
              details['peopleTrapped'] == true
                  ? 'Yes — ${details['numberOfPeople']} person(s)'
                  : 'No'),
          _buildInfoRow('Spreading Fast',
              details['spreadingFast'] == true ? 'Yes' : 'No'),
          if (_nonEmpty(details['additionalInfo']))
            _buildInfoRow(
                'Additional Info', details['additionalInfo']?.toString() ?? ''),
        ];

      case 'medical':
        return [
          _buildInfoRow('Condition', _medLabel(details['condition'])),
          _buildInfoRow(
              'Conscious', details['isConscious'] == true ? 'Yes' : 'No'),
          _buildInfoRow('Needs Ambulance',
              details['needsAmbulance'] == true ? 'Yes' : 'No'),
          if (_nonEmpty(details['additionalInfo']))
            _buildInfoRow('Info', details['additionalInfo']?.toString() ?? ''),
        ];

      case 'crime':
        return [
          _buildInfoRow('Crime Type', _crimeLabel(details['crimeType'])),
          _buildInfoRow('Ongoing', details['isOngoing'] == true ? 'Yes' : 'No'),
          _buildInfoRow(
              'Needs Police', details['needsPolice'] == true ? 'Yes' : 'No'),
          if (_nonEmpty(details['additionalInfo']))
            _buildInfoRow('Info', details['additionalInfo']?.toString() ?? ''),
        ];

      case 'flood':
        return [
          _buildInfoRow('Water Level', _waterLabel(details['waterLevel'])),
          _buildInfoRow(
              'People Trapped',
              details['peopleTrapped'] == true
                  ? 'Yes — ${details['numberOfPeople']} person(s)'
                  : 'No'),
          _buildInfoRow('Needs Evacuation',
              details['needsEvacuation'] == true ? 'Yes' : 'No'),
        ];

      case 'accident':
        return [
          _buildInfoRow(
              'Accident Type', _accidentLabel(details['accidentType'])),
          _buildInfoRow(
              'Injuries',
              details['hasInjuries'] == true
                  ? 'Yes — ${_injuryLabel(details['injurySeverity'])}'
                  : 'No'),
          _buildInfoRow('Blocking Traffic',
              details['blockingTraffic'] == true ? 'Yes' : 'No'),
        ];

      case 'other':
        return [
          _buildInfoRow('Category', _otherCatLabel(details['category'])),
          _buildInfoRow('Urgent', details['isUrgent'] == true ? 'Yes' : 'No'),
          _buildInfoRow('Immediate Help',
              details['needsImmediateHelp'] == true ? 'Yes' : 'No'),
          if (_nonEmpty(details['description']))
            _buildInfoRow(
                'Description', details['description']?.toString() ?? ''),
        ];

      default:
        return details.entries
            .where((e) => e.key != 'type' && e.value != null)
            .map((e) => _buildInfoRow(
                  _capitalise(e.key),
                  e.value.toString(),
                ))
            .toList();
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.lightGrey),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.grey,
                  fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(String status, Color accentColor) {
    const steps = ['Pending', 'In Progress', 'Resolved'];
    const icons = [
      Icons.pending_outlined,
      Icons.sync,
      Icons.check_circle_outline,
    ];
    final current = steps.indexOf(status).clamp(0, 2);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.splashBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final done = current > i ~/ 2;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 22),
                decoration: BoxDecoration(
                  color: done ? AppColors.success : AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }
          final idx = i ~/ 2;
          final isDone = current > idx; // strictly past = completed
          final isNow = current == idx; // currently active step

          final dotColor = isDone
              ? AppColors.success
              : isNow
                  ? AppColors.primary
                  : Colors.white;
          final iconColor = (isDone || isNow) ? Colors.white : AppColors.grey;
          final borderColor = isDone
              ? AppColors.success
              : isNow
                  ? AppColors.primary
                  : AppColors.lightGrey;
          final labelColor = isDone
              ? AppColors.success
              : isNow
                  ? AppColors.primary
                  : AppColors.grey;

          return Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  border: Border.all(
                    color: borderColor,
                    width: isNow ? 3 : 2,
                  ),
                  boxShadow: isNow
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  icons[idx],
                  size: 18,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                steps[idx],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isNow ? FontWeight.bold : FontWeight.w400,
                  color: labelColor,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  // ── Label helpers ──────────────────────────────────────────────────────────

  bool _nonEmpty(dynamic v) => v != null && v.toString().isNotEmpty;

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Color _labelColor(String type) {
    switch (type) {
      case 'crime':
        return AppColors.secondary;
      case 'medical':
        return Colors.red;
      case 'fire':
        return Colors.deepOrange;
      case 'flood':
        return Colors.blue;
      case 'accident':
        return Colors.orange;
      default:
        return AppColors.grey;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'In Progress':
        return AppColors.primary;
      case 'Resolved':
        return AppColors.success;
      case 'Active':
        return AppColors.danger;
      default:
        return AppColors.grey;
    }
  }

  String _typeEmoji(String type) {
    switch (type) {
      case 'crime':
        return '👮';
      case 'medical':
        return '🏥';
      case 'fire':
        return '🔥';
      case 'flood':
        return '💧';
      case 'accident':
        return '🚗';
      default:
        return '⚠️';
    }
  }

  String _fireLabel(dynamic v) =>
      const {
        'residential': 'Residential Fire',
        'industrial': 'Industrial Fire',
        'forest': 'Forest Fire',
        'vehicle': 'Vehicle Fire',
        'electrical': 'Electrical Fire',
        'chemical': 'Chemical Fire',
      }[v?.toString()] ??
      'Unknown';

  String _medLabel(dynamic v) =>
      const {
        'heart_attack': 'Heart Attack',
        'stroke': 'Stroke',
        'breathing': 'Breathing Problem',
        'injury': 'Severe Injury',
        'seizure': 'Seizure',
        'allergic': 'Allergic Reaction',
        'poisoning': 'Poisoning',
        'other': 'Other Medical',
      }[v?.toString()] ??
      'Unknown';

  String _crimeLabel(dynamic v) =>
      const {
        'theft': 'Theft/Robbery',
        'assault': 'Assault',
        'burglary': 'Burglary',
        'vandalism': 'Vandalism',
        'suspicious': 'Suspicious Activity',
        'other': 'Other Crime',
      }[v?.toString()] ??
      'Unknown';

  String _waterLabel(dynamic v) =>
      const {
        'ankle': 'Ankle Deep',
        'knee': 'Knee Deep',
        'waist': 'Waist Deep',
        'chest': 'Chest Deep+',
      }[v?.toString()] ??
      'Unknown';

  String _accidentLabel(dynamic v) =>
      const {
        'vehicle': 'Vehicle Collision',
        'motorcycle': 'Motorcycle Accident',
        'pedestrian': 'Pedestrian Hit',
        'bicycle': 'Bicycle Accident',
        'workplace': 'Workplace Accident',
        'other': 'Other Accident',
      }[v?.toString()] ??
      'Unknown';

  String _injuryLabel(dynamic v) =>
      const {
        'minor': 'Minor',
        'moderate': 'Moderate',
        'severe': 'Severe',
      }[v?.toString()] ??
      'Unknown';

  String _otherCatLabel(dynamic v) =>
      const {
        'gas_leak': 'Gas Leak',
        'power_outage': 'Power Outage',
        'animal': 'Animal Emergency',
        'missing_person': 'Missing Person',
        'chemical': 'Chemical Spill',
        'structural': 'Structural Damage',
        'other': 'Other',
      }[v?.toString()] ??
      'Unknown';
}

// ── Small pulsing dot used to signal a live/ongoing SOS ─────────────────────
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  // Built once rather than allocating a fresh Tween + CurvedAnimation on
  // every build().
  late final Animation<double> _opacity = Tween(begin: 0.35, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // This dot animates continuously, so it repaints every frame — and it
    // lives inside a report card that also paints a shadow and a progress
    // timeline. Without its own boundary, each of those frames dirties the
    // whole card and re-rasterizes all of it just to fade a 9px dot. The
    // boundary confines the per-frame repaint to the dot itself.
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
