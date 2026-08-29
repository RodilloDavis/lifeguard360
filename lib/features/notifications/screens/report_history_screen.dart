// lib/features/notifications/screens/report_history_screen.dart
//
// Calendar drill-down history of every report submitted by anyone in the
// family circle (including the current user's own): pick a Year, then a
// Month within it, then a Date within that month, to see everything
// reported that day. Only years/months/dates that actually have at least
// one report are ever shown as options — this is a browser over real data,
// not a full calendar grid with empty cells.
//
// Deliberately separate from the alert-style Notifications screen (which
// excludes the user's own reports and carries read/unread/delete state)
// — this is read-only browsing, nothing more.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/emergency_report_service.dart';
import '../../../services/report_history_cache_service.dart';

// ── Shared date parsing ─────────────────────────────────────────────────────
// Parses the app's custom "M/d/yyyy HH:mm:ss" format (month/day are NOT
// zero-padded) — same format EmergencyReportService writes CreatedAt in.
DateTime? _parseCreatedAt(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final parts = s.split(' ');
    if (parts.length != 2) return null;
    final dateParts = parts[0].split('/');
    final timeParts = parts[1].split(':');
    if (dateParts.length != 3 || timeParts.length != 3) return null;
    return DateTime(
      int.parse(dateParts[2]),
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
      int.parse(timeParts[2]),
    );
  } catch (_) {
    return null;
  }
}

// ── Shared report card look ─────────────────────────────────────────────────

String _humanizeLabel(String raw) {
  final words = raw.replaceAll('-', ' ').replaceAll('_', ' ').trim().split(' ');
  return words
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
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
    case 'shake':
    case 'bubble':
      return AppColors.danger;
    default:
      return AppColors.grey;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'Pending':
      return Colors.orange;
    case 'In Progress':
    case 'Acknowledged':
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
    case 'shake':
    case 'bubble':
      return '🚨';
    default:
      return '⚠️';
  }
}

Widget _buildReportCard(Map<String, dynamic> report) {
  final label = report['ReportLabel']?.toString() ?? 'other-report';
  final type = report['EmergencyType']?.toString() ?? 'other';
  final status = EmergencyReportService.displayStatus(report['Status']?.toString());
  final createdAt = report['CreatedAt']?.toString() ?? '';
  final reporterName = report['UserName']?.toString() ?? 'Unknown';
  final barangay = report['Barangay']?.toString() ?? '';
  final labelColor = _labelColor(type);
  final statusColor = _statusColor(status);

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: labelColor.withOpacity(0.2)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: labelColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(_typeEmoji(type), style: const TextStyle(fontSize: 20)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _humanizeLabel(label),
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.bold, color: labelColor),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                reporterName,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.secondary),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 12, color: AppColors.grey),
                  const SizedBox(width: 4),
                  Text(createdAt,
                      style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                  if (barangay.isNotEmpty && barangay != 'Unknown Barangay') ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on, size: 12, color: AppColors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        barangay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.textLight),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── A row used at every drill-down level (year / month / date) ─────────────

Widget _pickerRow({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.secondary),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.textLight),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.grey),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _emptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
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
            child: Icon(icon, size: 56, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.secondary)),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textLight),
          ),
        ],
      ),
    ),
  );
}

PreferredSizeWidget _historyAppBar(String title, {List<Widget>? actions}) {
  return AppBar(
    backgroundColor: AppColors.canvas,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    title: Text(title,
        style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
    actions: actions,
  );
}

// ═════════════════════════════════════════════════════════════════════════
// Level 1 — Years
// ═════════════════════════════════════════════════════════════════════════

class ReportHistoryScreen extends StatefulWidget {
  final String familyCode;

  const ReportHistoryScreen({super.key, required this.familyCode});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  bool _isLoading = true;
  String? _error;

  // year -> month(1-12) -> day(1-31) -> reports
  final Map<int, Map<int, Map<int, List<Map<String, dynamic>>>>> _byDate = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads Report History with the cache doing the heavy lifting: whatever
  /// is already on-device paints immediately (so a slow connection never
  /// blocks the screen), then a sync in the background pulls in only new
  /// or status-updated reports — see ReportHistoryCacheService for why a
  /// full re-download is only ever needed on the very first visit.
  ///
  /// [forceFull] re-checks every unresolved report's status regardless of
  /// age, not just recent ones — used for an explicit user-initiated
  /// refresh (button / pull-to-refresh), where taking a bit longer to
  /// double-check everything is the point. The initial automatic load on
  /// opening the screen never sets this, keeping that path fast and light.
  Future<void> _load({bool forceFull = false}) async {
    if (!mounted) return;

    final cached =
        await ReportHistoryCacheService.getCachedReports(widget.familyCode);
    if (cached != null) {
      if (!mounted) return;
      _applyReports(cached);
      setState(() {
        _isLoading = false;
        _error = null;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final synced = await ReportHistoryCacheService.syncAndGetReports(
        widget.familyCode,
        forceFullReconcile: forceFull,
      );
      if (!mounted) return;
      _applyReports(synced);
      setState(() {
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (cached == null) {
        // Nothing to fall back on — this is a genuine load failure.
        setState(() {
          _error = 'Failed to load report history: $e';
          _isLoading = false;
        });
      }
      // Otherwise keep quietly showing the cached data; the sync will be
      // retried the next time this screen is opened or refreshed.
    }
  }

  void _applyReports(List<Map<String, dynamic>> reports) {
    _byDate.clear();
    for (final report in reports) {
      final dt = _parseCreatedAt(report['CreatedAt']?.toString());
      if (dt == null) continue;
      _byDate
          .putIfAbsent(dt.year, () => {})
          .putIfAbsent(dt.month, () => {})
          .putIfAbsent(dt.day, () => [])
          .add(report);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _historyAppBar('Report History', actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: AppColors.secondary),
          onPressed: _isLoading ? null : () => _load(forceFull: true),
          tooltip: 'Refresh',
        ),
      ]),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.danger),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textLight)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (_byDate.isEmpty) {
      return _emptyState(
        icon: Icons.calendar_today_outlined,
        title: 'No Reports Yet',
        subtitle:
            'Reports submitted by you or your family will show up here, organized by year.',
      );
    }

    final years = _byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: () => _load(forceFull: true),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          for (final year in years)
            _pickerRow(
              context: context,
              icon: Icons.calendar_today,
              title: '$year',
              subtitle: '${_countForYear(year)} reports',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _MonthListScreen(
                    year: year,
                    monthData: _byDate[year]!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _countForYear(int year) {
    var total = 0;
    for (final days in _byDate[year]!.values) {
      for (final reports in days.values) {
        total += reports.length;
      }
    }
    return total;
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Level 2 — Months within a year
// ═════════════════════════════════════════════════════════════════════════

class _MonthListScreen extends StatelessWidget {
  final int year;
  final Map<int, Map<int, List<Map<String, dynamic>>>> monthData;

  const _MonthListScreen({required this.year, required this.monthData});

  int _countForMonth(int month) {
    var total = 0;
    for (final reports in monthData[month]!.values) {
      total += reports.length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final months = monthData.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _historyAppBar('$year'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            for (final month in months)
              _pickerRow(
                context: context,
                icon: Icons.date_range,
                title: DateFormat('MMMM').format(DateTime(year, month)),
                subtitle: '${_countForMonth(month)} reports',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DateListScreen(
                      year: year,
                      month: month,
                      dayData: monthData[month]!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Level 3 — Dates within a month
// ═════════════════════════════════════════════════════════════════════════

class _DateListScreen extends StatelessWidget {
  final int year;
  final int month;
  final Map<int, List<Map<String, dynamic>>> dayData;

  const _DateListScreen({
    required this.year,
    required this.month,
    required this.dayData,
  });

  @override
  Widget build(BuildContext context) {
    final days = dayData.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _historyAppBar(DateFormat('MMMM yyyy').format(DateTime(year, month))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            for (final day in days)
              _pickerRow(
                context: context,
                icon: Icons.today,
                title: DateFormat('EEEE, MMM d').format(DateTime(year, month, day)),
                subtitle: '${dayData[day]!.length} reports',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DayReportsScreen(
                      date: DateTime(year, month, day),
                      reports: dayData[day]!,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Level 4 — Reports for a specific date
// ═════════════════════════════════════════════════════════════════════════

class _DayReportsScreen extends StatelessWidget {
  final DateTime date;
  final List<Map<String, dynamic>> reports;

  const _DayReportsScreen({required this.date, required this.reports});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _historyAppBar(DateFormat('EEEE, MMM d, yyyy').format(date)),
      body: SafeArea(
        child: reports.isEmpty
            ? _emptyState(
                icon: Icons.assignment_outlined,
                title: 'No Reports',
                subtitle: 'No reports were submitted on this date.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  for (final report in reports) _buildReportCard(report),
                ],
              ),
      ),
    );
  }
}
