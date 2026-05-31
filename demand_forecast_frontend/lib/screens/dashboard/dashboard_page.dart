import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../main_layout.dart';
import 'preview_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().getJobs();
      final List<dynamic> rawJobs = res['jobs'] ?? [];
      if (!mounted) return;
      setState(() {
        _jobs = rawJobs.map((j) => Map<String, dynamic>.from(j)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _downloadExcel(String jobId, String jobName) async {
    try {
      final response = await ApiService().downloadJobExcel(jobId);
      if (response.statusCode == 200) {
        final filename = 'Forecast_${jobId}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        final path = await ApiService.saveExcelToDownloads(response.bodyBytes, filename);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(path != null
                ? 'Downloaded: $filename ✓'
                : 'Download done but could not save automatically.'),
            backgroundColor: path != null ? const Color(0xFF059669) : null,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed (${response.statusCode})'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Summary counts ────────────────────────────────────────────────────────
  int get _totalJobs       => _jobs.length;
  int get _pendingJobs     => _jobs.where((j) => j['status'] == 'Pending').length;
  int get _processingJobs  => _jobs.where((j) => j['status'] == 'Processing').length;
  int get _completedJobs   => _jobs.where((j) => j['status'] == 'Completed').length;
  int get _failedJobs      => _jobs.where((j) => j['status'] == 'Failed').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildTopBar(context),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsRow(),
                        const SizedBox(height: 24),
                        _buildTable(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Top Bar ──────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Real-time tracking of forecasting accuracy and engine status across all models.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _loadJobs,
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Sync Data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => MainLayoutScope.of(context).switchPage(1),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Forecast'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StatCard(label: 'Total Forecasts',  subLabel: '',                       value: '$_totalJobs',      icon: Icons.analytics,       color: const Color(0xFF2563EB))),
          const SizedBox(width: 14),
          Expanded(child: _StatCard(label: 'Pending Jobs',     subLabel: 'Tasks in queue for run', value: '$_pendingJobs',    icon: Icons.hourglass_empty, color: const Color(0xFFF59E0B))),
          const SizedBox(width: 14),
          Expanded(child: _StatCard(label: 'Active Jobs',      subLabel: 'Live currently running',  value: '$_processingJobs', icon: Icons.run_circle,      color: const Color(0xFF6366F1))),
          const SizedBox(width: 14),
          Expanded(child: _StatCard(label: 'Completed Jobs',   subLabel: 'Successfully finished',   value: '$_completedJobs',  icon: Icons.check_circle,    color: const Color(0xFF059669))),
          const SizedBox(width: 14),
          Expanded(child: _StatCard(label: 'Failed Jobs',      subLabel: '',                        value: '$_failedJobs',     icon: Icons.error_outline,   color: const Color(0xFFEF4444))),
        ],
      ),
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                const Text(
                  'Forecast Jobs',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildTableHeader(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          _buildTableBody(),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: const Row(
        children: [
          Expanded(flex: 2, child: Text('JOB ID',        style: style)),
          Expanded(flex: 3, child: Text('JOB NAME',      style: style)),
          Expanded(flex: 2, child: Text('MODEL',         style: style)),
          Expanded(flex: 2, child: Text('YEAR',          style: style)),
          Expanded(flex: 3, child: Text('STARTED TIME',  style: style)),
          Expanded(flex: 2, child: Text('STATUS',        style: style)),
          Expanded(flex: 2, child: Text('PREVIEW',       style: style)),
          Expanded(flex: 2, child: Text('DOWNLOAD',      style: style)),
        ],
      ),
    );
  }

  Widget _buildTableBody() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
              const SizedBox(height: 8),
              Text('Could not connect to backend.\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            ],
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, color: Colors.grey.shade300, size: 56),
              const SizedBox(height: 12),
              const Text('No forecast jobs yet.', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
              const SizedBox(height: 6),
              const Text('Click "New Forecast" to get started.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: (_jobs.length * 56.0).clamp(200.0, 520.0),
      child: ListView.separated(
        itemCount: _jobs.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (_, i) {
          final job   = _jobs[i];
          final jobId = job['jobId'] ?? '';
          final status = job['status'] ?? '';
          final isCompleted = status == 'Completed';

          // Format started time
          final createdAt = job['createdAt'] != null
              ? DateTime.tryParse(job['createdAt'].toString())?.toLocal()
              : null;
          final timeStr = createdAt != null
              ? '${createdAt.year}-${_pad(createdAt.month)}-${_pad(createdAt.day)} '
                '${_pad(createdAt.hour)}:${_pad(createdAt.minute)}'
              : '';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: i % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA),
            child: Row(
              children: [
                // JOB ID
                Expanded(flex: 2, child: _jobIdBadge(jobId)),
                // JOB NAME
                Expanded(flex: 3, child: _cell(job['jobName'] ?? '')),
                // MODEL
                Expanded(flex: 2, child: _cell(job['model'] ?? '')),
                // YEAR
                Expanded(flex: 2, child: _cell(job['period'] ?? '')),
                // STARTED TIME
                Expanded(flex: 3, child: _cell(timeStr)),
                // STATUS
                Expanded(flex: 2, child: _statusBadge(status)),
                // PREVIEW
                Expanded(
                  flex: 2,
                  child: isCompleted
                      ? TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PreviewPage(jobId: jobId),
                            ),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 15, color: Color(0xFF2563EB)),
                          label: const Text('Preview', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB))),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : const Text('—', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
                ),
                // DOWNLOAD
                Expanded(
                  flex: 2,
                  child: isCompleted
                      ? TextButton.icon(
                          onPressed: () => _downloadExcel(jobId, job['jobName'] ?? ''),
                          icon: const Icon(Icons.download_outlined, size: 15, color: Color(0xFF059669)),
                          label: const Text('Download', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669))),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : const Text('—', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _pad(int n) => n.toString().padLeft(2, '0');

  Widget _cell(String text) => Text(
    text,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
  );

  Widget _jobIdBadge(String jobId) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        jobId,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
      ),
    ),
  );

  Widget _statusBadge(String status) {
    Color bg, fg;
    switch (status) {
      case 'Completed':
        bg = const Color(0xFFDCFCE7); fg = const Color(0xFF059669);
      case 'Failed':
        bg = const Color(0xFFFEE2E2); fg = const Color(0xFFDC2626);
      case 'Processing':
        bg = const Color(0xFFEDE9FE); fg = const Color(0xFF7C3AED);
      default: // Pending
        bg = const Color(0xFFFEF3C7); fg = const Color(0xFFD97706);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.subLabel,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label, subLabel, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value.padLeft(2, '0'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          if (subLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF059669)),
            ),
          ],
        ],
      ),
    );
  }
}
