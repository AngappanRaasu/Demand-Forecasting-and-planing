import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

// ── Layout constants ───────────────────────────────────────────────────────
const double _wSNo  = 52.0;
const double _wCat  = 130.0;
const double _wItem = 130.0;
const double _wMon  = 100.0;
const double _wAcc  = 90.0;
const double _wLeft = _wSNo + _wCat + _wItem; // 312

const double _kRowH  = 48.0;
const double _kHdr1H = 36.0; // "Month / Year" row
const double _kHdr2H = 36.0; // individual month-name row

const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kHeaderBg    = Color(0xFFF1F5F9);

const TextStyle _kHdrStyle = TextStyle(
  fontWeight: FontWeight.w700,
  fontSize: 12,
  color: Color(0xFF475569),
);

// ─────────────────────────────────────────────────────────────────────────────

class PreviewPage extends StatefulWidget {
  final String jobId;
  const PreviewPage({super.key, required this.jobId});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  Map<String, dynamic>? _job;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    try {
      final res = await ApiService().getJobPreview(widget.jobId);
      if (res['success'] == true) {
        setState(() {
          _job = Map<String, dynamic>.from(res['job'] ?? {});
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['message'] ?? 'Unknown error';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Forecast Preview',
                style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(widget.jobId,
                style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: _kBorderColor, height: 1.0),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadResults, child: const Text('Retry')),
        ]),
      );

  Widget _buildContent() {
    final job         = _job!;
    final model       = job['model']    ?? '';
    final jobName     = job['jobName']  ?? '';
    final lookback    = job['lookback'] ?? '';
    final period      = job['period']   ?? '';
    final rawResults  = (job['results'] as List?) ?? [];

    final Set<String> monthSet = {};
    final List<Map<String, dynamic>> rows = [];
    int si = 0;

    for (var r in rawResults) {
      final rawBd = r['monthlyBreakdown'];
      List<dynamic> bd = [];
      try {
        if (rawBd is List)                             bd = rawBd;
        else if (rawBd is String && rawBd.isNotEmpty) bd = jsonDecode(rawBd);
      } catch (_) {}

      final Map<String, double> mv = {};
      for (var b in bd) {
        final m = b['month']?.toString() ?? '';
        final q = (b['quantity'] as num?)?.toDouble() ?? 0.0;
        if (m.isNotEmpty) {
          monthSet.add(m);
          mv[m] = q;
        }
      }
      rows.add({...Map<String, dynamic>.from(r), '_mv': mv, '_si': si++});
    }

    rows.sort((a, b) {
      final c = (a['categoryId'] ?? '')
          .toString()
          .compareTo((b['categoryId'] ?? '').toString());
      return c != 0 ? c : (a['_si'] as int).compareTo(b['_si'] as int);
    });

    final List<String> months = monthSet.toList();
    final bool   hScroll   = months.length > 12;
    final double monBandW  = months.length * _wMon;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoBar(jobName, model, lookback, period, rows.length),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left:   BorderSide(color: _kBorderColor),
                  right:  BorderSide(color: _kBorderColor),
                  bottom: BorderSide(color: _kBorderColor),
                ),
              ),
              child: rows.isEmpty
                  ? const Center(
                      child: Text('No results available for this job.',
                          style: TextStyle(
                              color: Color(0xFF64748B), fontSize: 14)))
                  : _ForecastTable(
                      rows: rows,
                      months: months,
                      monBandW: monBandW,
                      hScroll: hScroll,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBar(String jobName, String model, String lookback,
      String period, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8), topRight: Radius.circular(8)),
        border: Border.all(color: _kBorderColor),
      ),
      child: Wrap(spacing: 20, runSpacing: 10, children: [
        _infoBadge('JobID',         jobName),
        _infoBadge('Model',         model),
        _infoBadge('Lookback',      lookback),
        _infoBadge('Period',        period),
        _infoBadge('Total Results', '$total'),
      ]),
    );
  }

  Widget _infoBadge(String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: _kBorderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(value.isEmpty ? 'N/A' : value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B))),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ForecastTable
// ─────────────────────────────────────────────────────────────────────────────

class _ForecastTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<String> months;
  final double monBandW;
  final bool hScroll;

  const _ForecastTable({
    required this.rows,
    required this.months,
    required this.monBandW,
    required this.hScroll,
  });

  @override
  State<_ForecastTable> createState() => _ForecastTableState();
}

class _ForecastTableState extends State<_ForecastTable> {
  // ── Vertical controllers ──────────────────────────────────────────────────
  // Primary vertical scroll (centre month body ListView).
  final ScrollController _vertCtrl      = ScrollController();
  // Mirrors for the left and right fixed-column ListViews.
  final ScrollController _vertLeftCtrl  = ScrollController();
  final ScrollController _vertRightCtrl = ScrollController();

  // ── Horizontal controllers ────────────────────────────────────────────────
  // Each attached to EXACTLY ONE ScrollView – synced via listeners.
  final ScrollController _horzBodyCtrl = ScrollController(); // body month band
  final ScrollController _horzHdrCtrl  = ScrollController(); // header row-2

  bool _syncingH = false; // re-entry guard

  @override
  void initState() {
    super.initState();
    _vertCtrl.addListener(_syncVert);
    _vertLeftCtrl.addListener(_syncFromLeft);
    _vertRightCtrl.addListener(_syncFromRight);
    _horzBodyCtrl.addListener(_syncHorzFromBody);
    _horzHdrCtrl.addListener(_syncHorzFromHdr);
  }

  // ── Horizontal sync ───────────────────────────────────────────────────────

  void _syncHorzFromBody() {
    if (_syncingH) return;
    if (!_horzHdrCtrl.hasClients) return;
    final offset = _horzBodyCtrl.offset;
    if ((_horzHdrCtrl.offset - offset).abs() > 0.5) {
      _syncingH = true;
      _horzHdrCtrl.jumpTo(
          offset.clamp(0.0, _horzHdrCtrl.position.maxScrollExtent));
      _syncingH = false;
    }
  }

  void _syncHorzFromHdr() {
    if (_syncingH) return;
    if (!_horzBodyCtrl.hasClients) return;
    final offset = _horzHdrCtrl.offset;
    if ((_horzBodyCtrl.offset - offset).abs() > 0.5) {
      _syncingH = true;
      _horzBodyCtrl.jumpTo(
          offset.clamp(0.0, _horzBodyCtrl.position.maxScrollExtent));
      _syncingH = false;
    }
  }

  // ── Vertical sync ─────────────────────────────────────────────────────────

  void _syncVert() {
    final o = _vertCtrl.offset;
    if (_vertLeftCtrl.hasClients && (_vertLeftCtrl.offset - o).abs() > 0.5) {
      _vertLeftCtrl.jumpTo(o.clamp(0, _vertLeftCtrl.position.maxScrollExtent));
    }
    if (_vertRightCtrl.hasClients && (_vertRightCtrl.offset - o).abs() > 0.5) {
      _vertRightCtrl.jumpTo(o.clamp(0, _vertRightCtrl.position.maxScrollExtent));
    }
  }

  void _syncFromLeft() {
    final o = _vertLeftCtrl.offset;
    if (_vertCtrl.hasClients && (_vertCtrl.offset - o).abs() > 0.5) {
      _vertCtrl.jumpTo(o.clamp(0, _vertCtrl.position.maxScrollExtent));
    }
    if (_vertRightCtrl.hasClients && (_vertRightCtrl.offset - o).abs() > 0.5) {
      _vertRightCtrl.jumpTo(o.clamp(0, _vertRightCtrl.position.maxScrollExtent));
    }
  }

  void _syncFromRight() {
    final o = _vertRightCtrl.offset;
    if (_vertCtrl.hasClients && (_vertCtrl.offset - o).abs() > 0.5) {
      _vertCtrl.jumpTo(o.clamp(0, _vertCtrl.position.maxScrollExtent));
    }
    if (_vertLeftCtrl.hasClients && (_vertLeftCtrl.offset - o).abs() > 0.5) {
      _vertLeftCtrl.jumpTo(o.clamp(0, _vertLeftCtrl.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    _vertCtrl.removeListener(_syncVert);
    _vertLeftCtrl.removeListener(_syncFromLeft);
    _vertRightCtrl.removeListener(_syncFromRight);
    _horzBodyCtrl.removeListener(_syncHorzFromBody);
    _horzHdrCtrl.removeListener(_syncHorzFromHdr);
    _vertCtrl.dispose();
    _vertLeftCtrl.dispose();
    _vertRightCtrl.dispose();
    _horzBodyCtrl.dispose();
    _horzHdrCtrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Available width for the month band (full width minus fixed left & right)
      final double bandW = constraints.maxWidth - _wLeft - _wAcc;
      // Dynamic per-column width:
      //   • hScroll (≥2 yrs): fixed 100 px, band scrolls horizontally
      //   • no hScroll (1 yr): divide available space evenly across months
      final double monColW = widget.hScroll
          ? _wMon
          : (widget.months.isEmpty ? _wMon : (bandW / widget.months.length));
      final double monBandW = widget.hScroll ? widget.monBandW : bandW;

      return Column(children: [
        _buildHeader(monColW),
        Expanded(child: _buildBody(monColW, monBandW)),
      ]);
    });
  }

  // ── Header (two rows) ────────────────────────────────────────────────────

  Widget _buildHeader(double monColW) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Left fixed – spans both header rows
        _hdrCellTall('S.No',     _wSNo,  rightBorder: true),
        _hdrCellTall('Category', _wCat,  rightBorder: true),
        _hdrCellTall('Item ID',  _wItem, rightBorder: true),

        // Month band – two stacked rows
        Expanded(
          child: Column(children: [
            // Row 1: "Month / Year" spanning label
            Container(
              height: _kHdr1H,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _kHeaderBg,
                border: Border(bottom: BorderSide(color: _kBorderColor)),
              ),
              child: const Text('Month / Year', style: _kHdrStyle),
            ),
            // Row 2: individual month names
            SizedBox(
              height: _kHdr2H,
              child: widget.hScroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _horzHdrCtrl,
                      physics: const ClampingScrollPhysics(),
                      child: _monthNameRow(monColW),
                    )
                  // 1-year: no scroll, columns already sized to fill width exactly
                  : _monthNameRow(monColW),
            ),
          ]),
        ),

        // Right fixed – spans both header rows
        _hdrCellTall('Accuracy %', _wAcc, leftBorder: true, center: true),
      ]),
    );
  }

  Widget _monthNameRow(double monColW) => Row(
        children: widget.months
            .map((m) => _hdrCellShort(m, monColW, rightBorder: true))
            .toList(),
      );

  // ── Body ─────────────────────────────────────────────────────────────────

  Widget _buildBody(double monColW, double monBandW) {
    final rows   = widget.rows;
    final months = widget.months;

    // Left fixed column
    final leftCol = ListView.builder(
      controller: _vertLeftCtrl,
      physics: const ClampingScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final curCat  = (r['categoryId'] ?? '').toString();
        final curItem = (r['itemId']     ?? '').toString();
        var dispCat  = curCat;
        var dispItem = curItem;
        if (i > 0) {
          final prev = rows[i - 1];
          if (curCat == (prev['categoryId'] ?? '').toString()) {
            dispCat = '';
            if (curItem == (prev['itemId'] ?? '').toString()) dispItem = '';
          }
        }
        final bg = i % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA);
        return SizedBox(
          height: _kRowH,
          child: Row(children: [
            _bodyCell('${i + 1}', _wSNo,  bg, rightBorder: true),
            _bodyCell(dispCat,    _wCat,  bg, rightBorder: true),
            _bodyCell(dispItem,   _wItem, bg, rightBorder: true),
          ]),
        );
      },
    );

    // Right fixed column
    final rightCol = ListView.builder(
      controller: _vertRightCtrl,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final acc = (rows[i]['accuracyPercent'] as num?)?.toDouble() ?? 0.0;
        final bg  = i % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA);
        return Container(
          height: _kRowH,
          width: _wAcc,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: const Border(
              left:   BorderSide(color: _kBorderColor),
              bottom: BorderSide(color: _kBorderColor),
            ),
          ),
          child: _accBadge(acc),
        );
      },
    );

    // Centre month band.
    // monBandW = exact available width (1 yr) OR fixed total (≥2 yr, scrollable)
    final centreCol = Scrollbar(
      controller: _horzBodyCtrl,
      thumbVisibility: widget.hScroll,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _horzBodyCtrl,
        physics: widget.hScroll
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: monBandW,
          child: ListView.builder(
            controller: _vertCtrl,
            physics: const ClampingScrollPhysics(),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final Map<String, double> mv =
                  (rows[i]['_mv'] as Map?)?.cast<String, double>() ?? {};
              final bg = i % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA);
              return SizedBox(
                height: _kRowH,
                child: Row(
                  // Use dynamic monColW so 1-yr columns fill space evenly
                  children: months.map((m) => Container(
                    width: monColW,
                    height: _kRowH,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      border: const Border(
                        right:  BorderSide(color: _kBorderColor),
                        bottom: BorderSide(color: _kBorderColor),
                      ),
                    ),
                    child: _qtyBadge(mv[m] ?? 0.0),
                  )).toList(),
                ),
              );
            },
          ),
        ),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _wLeft, child: leftCol),
        Expanded(child: centreCol),
        SizedBox(width: _wAcc,  child: rightCol),
      ],
    );
  }

  // ── Cell helpers ─────────────────────────────────────────────────────────

  Widget _hdrCellTall(String text, double width,
      {bool rightBorder = false, bool leftBorder = false, bool center = false}) {
    return Container(
      width: width,
      height: _kHdr1H + _kHdr2H,
      alignment: center ? Alignment.center : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _kHeaderBg,
        border: Border(
          right:  rightBorder ? const BorderSide(color: _kBorderColor) : BorderSide.none,
          left:   leftBorder  ? const BorderSide(color: _kBorderColor) : BorderSide.none,
          bottom: const BorderSide(color: _kBorderColor),
        ),
      ),
      child: Text(text, style: _kHdrStyle, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _hdrCellShort(String text, double width, {bool rightBorder = false}) {
    return Container(
      width: width,   // dynamic: evenly-split (1 yr) or fixed 100 px (≥2 yr)
      height: _kHdr2H,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _kHeaderBg,
        border: Border(
          right:  rightBorder ? const BorderSide(color: _kBorderColor) : BorderSide.none,
          bottom: const BorderSide(color: _kBorderColor),
        ),
      ),
      child: Text(text, style: _kHdrStyle, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _bodyCell(String text, double width, Color bg,
      {bool rightBorder = false}) {
    return Container(
      width: width,
      height: _kRowH,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right:  rightBorder ? const BorderSide(color: _kBorderColor) : BorderSide.none,
          bottom: const BorderSide(color: _kBorderColor),
        ),
      ),
      child: Text(text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
    );
  }

  Widget _qtyBadge(double qty) {
    final raw = qty.round().toString();
    final fmt = raw.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(6)),
      child: Text(fmt,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: Color(0xFF047857))),
    );
  }

  Widget _accBadge(double acc) {
    final isGood = acc >= 80;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGood ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('${acc.toStringAsFixed(1)}%',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: isGood ? const Color(0xFF059669) : const Color(0xFFD97706))),
    );
  }
}
