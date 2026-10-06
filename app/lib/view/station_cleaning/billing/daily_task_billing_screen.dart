import 'dart:io';
import 'package:crm_train/model/task_billing_models.dart';
import 'package:crm_train/providers/auth_provider.dart';
import 'package:crm_train/repositories/task_billing_repository.dart';
import 'package:crm_train/services/pdf_report_service.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'area_rate_config_screen.dart';

class DailyTaskBillingScreen extends StatefulWidget {
  final String contractId;
  final String stationId;
  final String stationName;
  final String? initialDate;
  const DailyTaskBillingScreen({
    super.key,
    required this.contractId,
    required this.stationId,
    required this.stationName,
    this.initialDate,
  });

  @override
  State<DailyTaskBillingScreen> createState() => _DailyTaskBillingScreenState();
}

class _DailyTaskBillingScreenState extends State<DailyTaskBillingScreen> {
  late final TextEditingController _dateCtrl;
  final _fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  DailyTaskBillingResponse? _bill;
  DailyBillingMonth _monthData = DailyBillingMonth();
  bool _loading = false;

  DailyBillingMonth _cart = DailyBillingMonth();
  bool _cartLoading = false;

  bool _rangeMode = false;
  String _fromDate = _today();
  String _toDate = _today();
  DailyBillingMonth? _rangeData;
  bool _rangeReportLoading = false;

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool _can(String action) {
    final role = (Provider.of<AuthProvider>(context, listen: false).currentUser?.role ?? '').toUpperCase().replaceAll(' ', '_');
    const perms = {
      'SUPER_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE'},
      'COMPANY_MASTER': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE'},
      'RAILWAY_MASTER': {'VIEW'},
      'ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE'},
      'RAILWAY_ADMIN': {'VIEW', 'GENERATE', 'MANAGE', 'CONFIGURE'},
      'CONTRACTOR_MASTER': {'VIEW', 'CONFIGURE'},
      'CONTRACTOR_ADMIN': {'VIEW', 'GENERATE', 'MANAGE'},
      'CONTRACTOR_SUPERVISOR': {'VIEW'},
    };
    return (perms[role] ?? <String>{}).contains(action);
  }

  bool get _canGenerate => _can('GENERATE');
  bool get _isReadOnly => !_canGenerate;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate;
    final parsed = init == null ? null : DateTime.tryParse(init);
    if (parsed != null) {
      _dateCtrl = TextEditingController(text: init);
      _month = parsed.month;
      _year = parsed.year;
    } else {
      _dateCtrl = TextEditingController(text: _today());
    }
    _loadBills();
    _loadCart();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCart() async {
    if (mounted) setState(() => _cartLoading = true);
    try {
      final cart = await TaskBillingRepository.list(
        widget.contractId,
        widget.stationId,
        _month,
        _year,
        startDate: '2018-01-01',
        endDate: _today(),
      );
      if (!mounted) return;
      setState(() {
        _cart = cart;
        _cartLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cartLoading = false);
      _showStatus('Report cart unavailable: $e', isError: true);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadBills(), _loadCart()]);
  }

  Future<void> _loadBills() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final month = await TaskBillingRepository.list(widget.contractId, widget.stationId, _month, _year);
      if (!mounted) return;
      setState(() {
        _monthData = month;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showStatus('Bills unavailable: $e', isError: true);
    }
  }

  Future<void> _shiftDate(int days) async {
    final parsed = DateTime.tryParse(_dateCtrl.text.trim());
    final base = parsed ?? DateTime.now();
    final shifted = base.add(Duration(days: days));
    _dateCtrl.text = '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}-${shifted.day.toString().padLeft(2, '0')}';
    setState(() {});
    await _preview();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_dateCtrl.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2023, 1, 1),
      lastDate: now.add(const Duration(days: 1)),
      helpText: 'Pick a billing date (past days close automatically)',
    );
    if (picked == null || !mounted) return;
    _dateCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {});
    final bill = await TaskBillingRepository.getByDate(widget.contractId, widget.stationId, _dateCtrl.text.trim());
    if (!mounted) return;
    if (bill != null) {
      setState(() => _bill = bill);
    } else {
      await _preview();
    }
  }

  void _showStatus(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? kErrorRed : kSuccessGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _preview() async {
    setState(() => _loading = true);
    try {
      final bill = await TaskBillingRepository.preview(widget.contractId, widget.stationId, _dateCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _bill = bill;
        _loading = false;
      });
      if (bill.areaRows.isEmpty) {
        _showStatus('No cleaning tasks found for this date.', isError: true);
      } else {
        _showStatus('Preview loaded for ${bill.date}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showStatus(e.toString(), isError: true);
    }
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final bill = await TaskBillingRepository.generate(widget.contractId, widget.stationId, _dateCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _bill = bill;
        _loading = false;
      });
      _showStatus(bill.status == 'generated' ? 'Daily bill generated (immutable).' : 'Existing bill reused.');
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showStatus(e.toString(), isError: true);
    }
  }

  Future<void> _openAreaRates() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AreaRateConfigScreen(contractId: widget.contractId)));
    if (!mounted) return;
    if (_bill != null) await _preview();
  }

  Future<void> _openBill(DailyTaskBillingResponse b) async {
    setState(() => _loading = true);
    try {
      final bill = await TaskBillingRepository.getByDate(widget.contractId, widget.stationId, b.date);
      if (!mounted) return;
      setState(() {
        _bill = bill ?? b;
        _dateCtrl.text = b.date;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bill = b;
        _dateCtrl.text = b.date;
        _loading = false;
      });
    }
  }

  // ── Date range billing ──────────────────────────────────────────────────────
  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_fromDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2023, 1, 1),
      lastDate: now,
      helpText: 'Pick range FROM date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fromDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      if (_fromDate.compareTo(_toDate) > 0) _toDate = _fromDate;
    });
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_toDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2023, 1, 1),
      lastDate: now,
      helpText: 'Pick range TO date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _toDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      if (_toDate.compareTo(_fromDate) < 0) _fromDate = _toDate;
    });
  }

  Future<void> _previewRange() async {
    setState(() {
      _rangeReportLoading = true;
      _rangeData = null;
    });
    try {
      final data = await TaskBillingRepository.previewRange(widget.contractId, widget.stationId, _fromDate, _toDate);
      if (!mounted) return;
      setState(() {
        _rangeData = data;
        _rangeReportLoading = false;
      });
      if (data.bills.isEmpty) {
        _showStatus('No cleaning tasks found in the selected range.', isError: true);
      } else {
        _showStatus('Range report ready: ${data.count} day(s) previewed.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _rangeReportLoading = false);
      _showStatus(e.toString(), isError: true);
    }
  }

  Future<void> _generateRange() async {
    setState(() => _loading = true);
    try {
      final result = await TaskBillingRepository.generateRange(widget.contractId, widget.stationId, _fromDate, _toDate);
      if (!mounted) return;
      setState(() => _loading = false);
      final generated = (result['generated'] as List?)?.length ?? 0;
      final reused = (result['reused'] as List?)?.length ?? 0;
      final failed = (result['failed'] as List?)?.length ?? 0;
      _showStatus('Range: $generated generated, $reused reused, $failed failed — no duplicates.');
      await _loadCart();
      await _loadRangeStored();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showStatus(e.toString(), isError: true);
    }
  }

  Future<void> _loadRangeStored() async {
    try {
      final data = await TaskBillingRepository.list(widget.contractId, widget.stationId, _month, _year,
          startDate: _fromDate, endDate: _toDate);
      if (!mounted) return;
      setState(() => _rangeData = data);
    } catch (_) {
      /* keep previous range report visible */
    }
    await _loadBills();
  }

  Future<void> _openRangeDay(DailyTaskBillingResponse day) async {
    setState(() => _rangeMode = false);
    _dateCtrl.text = day.date;
    await _openBill(day);
  }

  Future<void> _downloadRangePdf() async {
    final data = _rangeData;
    if (data == null || data.bills.isEmpty) return;
    setState(() => _loading = true);
    try {
      final bytes = await PDFReportService.generateDailyTaskBillingMonthPdf(
        {
          'stationName': widget.stationName,
          'contractNumber': _bill?.contractNumber ?? data.bills.first.contractNumber,
          'contractStartDate': _bill?.contractStartDate ?? data.bills.first.contractStartDate,
          'contractEndDate': _bill?.contractEndDate ?? data.bills.first.contractEndDate,
          'ratePerSqft': _bill?.ratePerSqft ?? data.bills.first.ratePerSqft,
          'monthLabel': '$_fromDate  to  $_toDate',
          'periodLabel': 'DATE RANGE',
          'reportTitle': 'DAILY TASK BILLING\nRANGE REPORT',
        },
        data,
      );
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/daily_billing_${widget.stationName}_${_fromDate}_$_toDate.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('PDF saved: ${file.path}');
        await Share.shareXFiles([XFile(file.path)], text: 'Daily Task Billing (Range) PDF - ${widget.stationName} - $_fromDate to $_toDate');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('Error generating PDF: $e', isError: true);
      }
    }
  }

  // ── Range report card (the report you see on the cart) ─────────────────────
  Widget _buildRangeReportCard() {
    final data = _rangeData;
    if (data == null || data.bills.isEmpty) return const SizedBox.shrink();
    Widget cell(String t, {bool bold = false, Color? color, MainAxisAlignment align = MainAxisAlignment.center}) => Expanded(
          flex: 1,
          child: Text(
            t,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black87),
          ),
        );

    return _sectionCard(
      icon: Icons.summarize,
      title: 'Range Report',
      subtitle: '$_fromDate  to  $_toDate · ${data.count} day(s) · no duplicates',
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: kRailwayBannerGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NET PAYABLE (${data.count} days)', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(_money(data.totalNetAmount), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _downloadRangePdf,
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download Range PDF',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _kvRow('Expected work value', _money(data.totalExpectedWorkValue)),
        _kvRow('Actual executed value', _money(data.totalActualExecutionValue), bold: true, valueColor: kSuccessGreen),
        _kvRow('Total deduction', _money(data.totalDeduction), valueColor: kErrorRed),
        if (data.avgFinalScore != null)
          _kvRow('Avg final score', '${data.avgFinalScore!.toStringAsFixed(1)}%',
              valueColor: _scoreColor(data.avgFinalScore!)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text('DAY', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: kRailwayBlue)),
            ),
            cell('Expected', bold: true),
            cell('Actual', bold: true),
            cell('Final %', bold: true),
            cell('Net ₹', bold: true),
          ],
        ),
        const Divider(height: 8),
        for (final d in data.bills)
          InkWell(
            onTap: () => _openRangeDay(d),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(d.date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  cell(_money(d.expectedWorkValue)),
                  cell(_money(d.actualExecutionValue)),
                  cell('${d.overallScore.toStringAsFixed(1)}%'),
                  cell(_money(d.netAmount), bold: true, color: kSuccessGreen),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _downloadPdf() async {
    final b = _bill;
    if (b == null) return;
    setState(() => _loading = true);
    try {
      final bytes = await PDFReportService.generateDailyTaskBillingPdf(b);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/daily_billing_${widget.stationName}_${b.date}.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('PDF saved: ${file.path}');
        await Share.shareXFiles([XFile(file.path)], text: 'Daily Task Billing PDF - ${widget.stationName} - ${b.date}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('Error generating PDF: $e', isError: true);
      }
    }
  }

  Future<void> _downloadMonthPdf() async {
    setState(() => _loading = true);
    try {
      final bytes = await PDFReportService.generateDailyTaskBillingMonthPdf(
        {
          'stationName': widget.stationName,
          'contractNumber': _bill?.contractNumber ?? '',
          'contractStartDate': _bill?.contractStartDate ?? '',
          'contractEndDate': _bill?.contractEndDate ?? '',
          'ratePerSqft': _bill?.ratePerSqft ?? 0,
          'monthLabel': '$_month / $_year',
        },
        _monthData,
      );
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/daily_billing_${widget.stationName}_$_month-$_year.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('PDF saved: ${file.path}');
        await Share.shareXFiles([XFile(file.path)], text: 'Daily Task Billing (Monthly) PDF - ${widget.stationName} - $_month/$_year');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('Error generating PDF: $e', isError: true);
      }
    }
  }

  Future<void> _downloadDayPdf(DailyTaskBillingResponse b) async {
    setState(() => _loading = true);
    try {
      final bytes = await PDFReportService.generateDailyTaskBillingPdf(b);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/daily_billing_${widget.stationName}_${b.date}.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('PDF saved: ${file.path}');
        await Share.shareXFiles([XFile(file.path)], text: 'Daily Task Billing PDF - ${widget.stationName} - ${b.date}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showStatus('Error generating PDF: $e', isError: true);
      }
    }
  }

  Future<void> _openCartDay(DailyTaskBillingResponse b) async {
    setState(() => _rangeMode = false);
    _dateCtrl.text = b.date;
    await _openBill(b);
  }

  // ── Formatting helpers ──────────────────────────────────────────────────────
  String _money(double v) => _fmt.format(v);

  bool _isWeightageMode(DailyTaskBillingResponse b) =>
      (b.ratePerSqft <= 0) &&
      (b.areaRows.any((r) => (((r['weightage'] as num?) ?? 0)).toDouble() > 0));

  String _billingBasis(DailyTaskBillingResponse b) {
    final days = b.contractDays > 0 ? b.contractDays : 365;
    if (_isWeightageMode(b)) {
      return 'Weightage basis: contract ACV ÷ $days contract days × area Wt% — counts APPROVED shift summaries';
    }
    if (b.ratePerSqft > 0) {
      return 'Rate basis: area sq.ft. × ₹${b.ratePerSqft.toStringAsFixed(2)} — counts APPROVED shift summaries';
    }
    return 'No active rate or weightage configured — values are zero';
  }
  String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';
  Color _scoreColor(double v) => v >= 90 ? kSuccessGreen : v >= 70 ? kWarningOrange : kErrorRed;

  @override
  Widget build(BuildContext context) {
    final b = _bill;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily Task Billing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.stationName, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading && _bill == null && _monthData.bills.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 14),
                  if (b == null)
                    _buildHowItWorks()
                  else ...[
                    _buildHero(b),
                    const SizedBox(height: 14),
                    _buildAmountCard(b),
                    const SizedBox(height: 14),
                    _buildPerformanceCard(b),
                    const SizedBox(height: 14),
                    _buildAreaTableCard(b),
                  ],
                  const SizedBox(height: 14),
                  if (_can('CONFIGURE')) ...[
                    _buildAreaRatesRow(),
                    const SizedBox(height: 14),
                  ],
                  _buildReportCartCard(),
                  const SizedBox(height: 14),
                  if (_rangeMode && _rangeData != null && _rangeData!.bills.isNotEmpty) ...[
                    if (_rangeReportLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      _buildRangeReportCard(),
                      const SizedBox(height: 14),
                    ],
                  ],
                  _buildMonthBillsCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: kRailwayBannerGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Daily Billing',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Value = Area × Rate × Executions',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _buildModeToggle(),
          const SizedBox(height: 12),
          if (_rangeMode)
            _buildRangeFields()
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _loading ? null : () => _shiftDate(-1),
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    tooltip: 'Previous day',
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _dateCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'YYYY-MM-DD',
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _preview(),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _pickDate,
                    icon: const Icon(Icons.calendar_month, color: Colors.white70, size: 20),
                    tooltip: 'Pick date',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: _loading ? null : () => _shiftDate(1),
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    tooltip: 'Next day',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (_rangeMode)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _previewRange,
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Preview Range'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (_canGenerate) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _generateRange,
                      icon: Icon(_loading ? Icons.hourglass_empty : Icons.date_range, size: 18),
                      label: Text(_loading ? 'Working…' : 'Generate All'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentYellow,
                        foregroundColor: kTextPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _preview,
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Preview / View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (_canGenerate) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _generate,
                      icon: Icon(_loading ? Icons.hourglass_empty : Icons.check_circle_outline, size: 18),
                      label: Text(_loading ? 'Working…' : 'Generate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAccentYellow,
                        foregroundColor: kTextPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          if (_isReadOnly) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.white70, size: 13),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'View-only access. You can check all billed dates — bill generation is done by contractor admin / railway.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Mode toggle (single day / date range) ──────────────────────────────────
  Widget _buildModeToggle() {
    Widget chip(bool selected, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? kAccentYellow : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? kTextPrimary : Colors.white,
                ),
              ),
            ),
          ),
        );
    return Row(
      children: [
        chip(!_rangeMode, 'Single Day', () => setState(() => _rangeMode = false)),
        const SizedBox(width: 8),
        chip(_rangeMode, 'Date Range', () => setState(() => _rangeMode = true)),
      ],
    );
  }

  Widget _buildDateField(String label, String value, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: _loading ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Icon(Icons.calendar_month, color: Colors.white70, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeFields() {
    return Row(
      children: [
        _buildDateField('FROM', _fromDate, _pickFromDate),
        const SizedBox(width: 8),
        _buildDateField('TO', _toDate, _pickToDate),
      ],
    );
  }

  // ── How it works (no bill loaded) ───────────────────────────────────────────
  Widget _buildHowItWorks() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tips_and_updates, size: 18, color: kRailwayBlue),
                SizedBox(width: 8),
                Text('How daily billing works', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),
            _stepRow('1', 'Pick a date above', 'Choose the day you want to bill for this station.'),
            _stepRow('2', 'Tap Preview / View', 'See the computed value for every cleaning area.'),
            _stepRow('3', 'Generate (contract admin)', 'Freezes the bill for that date — it becomes permanent.'),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(String n, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: kRailwayBlue, shape: BoxShape.circle),
            child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero summary ────────────────────────────────────────────────────────────
  Widget _buildHero(DailyTaskBillingResponse b) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: kRailwayBannerGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Bill for ${b.date}',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              _statusChip(b.status, onDark: true),
              const SizedBox(width: 2),
              IconButton(
                onPressed: _loading ? null : _downloadPdf,
                icon: const Icon(Icons.download, color: Colors.white, size: 20),
                tooltip: 'Download PDF',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net Payable', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      _money(b.netAmount),
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${b.overallScore.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('Grade ${b.grade}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniStat('Executed', _money(b.actualExecutionValue)),
              _miniStat('Expected', _money(b.expectedWorkValue)),
              _miniStat('Deducted', b.deduction > 0 ? _money(b.deduction) : '₹0'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status, {bool onDark = false}) {
    final color = status == 'generated' ? kSuccessGreen : kRailwayBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? (status == 'generated' ? const Color(0xFF43A047) : Colors.white24) : color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: onDark ? Colors.white : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _sectionCard({required IconData icon, required String title, String? subtitle, required List<Widget> children}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: kRailwayBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (subtitle != null)
                        Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _groupLabel(String t) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        t,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: kTextSecondary),
      ),
    );
  }

  // ── Amount breakdown ────────────────────────────────────────────────────────
  Widget _buildAmountCard(DailyTaskBillingResponse b) {
    return _sectionCard(
      icon: Icons.receipt,
      title: 'Amount Breakdown',
      subtitle: '${b.contractNumber} · ${b.contractStartDate} → ${b.contractEndDate} (${b.contractDays} days)',
      children: [
        _kvRow('Valuation basis', b.ratePerSqft > 0
            ? '₹${b.ratePerSqft.toStringAsFixed(2)} per sq.ft.'
            : 'Area weightage % (ACV ÷ ${b.contractDays > 0 ? b.contractDays : 365} contract days)', bold: true, valueColor: kRailwayBlue),
        const SizedBox(height: 4),
        _groupLabel('WORK VALUE'),
        _kvRow('Expected work value', _money(b.expectedWorkValue)),
        _kvRow('Actual executed value', _money(b.actualExecutionValue), bold: true, valueColor: kSuccessGreen),
        _kvRow('Gross eligible value', _money(b.grossEligibleWorkValue), bold: true, valueColor: kSuccessGreen),
        _kvRow('Sq.ft. executed / expected', '${b.executedSqFt.toStringAsFixed(0)} / ${b.expectedSqFt.toStringAsFixed(0)}'),
        if (b.taskExecutionScore != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Task execution', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (b.taskExecutionScore ?? 0) / 100,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    color: _scoreColor(b.taskExecutionScore ?? 0),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${b.taskExecutionScore!.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _scoreColor(b.taskExecutionScore!)),
              ),
            ],
          ),
        ],
        const Divider(height: 22),
        _groupLabel('PENALTY & DEDUCTIONS'),
        if (b.performancePenaltyAmount > 0)
          _kvRow('Performance penalty (score ${b.overallScore.toStringAsFixed(1)}%)', _money(b.performancePenaltyAmount), valueColor: kErrorRed)
        else
          _kvRow('Performance penalty (score ${b.overallScore.toStringAsFixed(1)}%)', 'Nil'),
        if (b.incompleteExecutionPenaltyAmount > 0)
          _kvRow('Task execution < 100% — incomplete penalty', _money(b.incompleteExecutionPenaltyAmount), valueColor: kErrorRed),
        if (b.otherDeductions > 0)
          _kvRow('Other contractual deductions', _money(b.otherDeductions), valueColor: kErrorRed),
        _kvRow('Total deduction', _money(b.deduction), valueColor: kErrorRed, bold: true),
        const Divider(height: 22),
        _groupLabel('PAYABLE'),
        _kvRow('Net payable', _money(b.netAmount), bold: true, valueColor: kSuccessGreen),
        if (b.gstRate > 0) _kvRow('GST (${b.gstRate.toStringAsFixed(0)}%)', _money(b.gstAmount)),
        if (b.gstRate > 0) _kvRow('Total payable', _money(b.totalPayable), bold: true, valueColor: kRailwayBlue),
        const SizedBox(height: 6),
        Text(
          'The final score ${b.overallScore.toStringAsFixed(1)}% is used ONLY to select the configured penalty/deduction rule — it is never multiplied into the work value.',
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _kvRow(String label, String value, {bool bold = false, Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, color: bold ? kRailwayBlue : Colors.black87)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor ?? Colors.black87)),
          ],
        ),
      );

  // ── Performance summary (50 / 20 / 30) ─────────────────────────────────────
  Widget _buildPerformanceCard(DailyTaskBillingResponse b) {
    Widget row(String name, int weight, double? score, double? marks) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    score == null ? 'No data (counts as full)' : 'Achievement ${score.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 11, color: score == null ? Colors.grey[500] : Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Text('$weight%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kRailwayBlue)),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: Text(
                marks == null ? '—' : '${marks.toStringAsFixed(1)} / $weight',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ),
          ],
        ),
      );
    }

    final cats = b.categories;
    final Map<String, Map<String, dynamic>> bySrc = {};
    for (final c in cats) {
      bySrc[c['dataSource']] = c;
    }
    final exec = bySrc['execution'];
    final insp = bySrc['inspection'];
    final fb = bySrc['feedback'];
    final scoreColor = _scoreColor(b.overallScore);

    return _sectionCard(
      icon: Icons.speed,
      title: 'Performance Summary',
      subtitle: 'Weights: Task Execution 50 · Railway Inspection 20 · Passenger Feedback 30',
      children: [
        row('Task Execution', 50, exec?['achievement'] as double?, (exec?['marks'] as num?)?.toDouble()),
        row('Railway Inspection', 20, insp?['achievement'] as double?, (insp?['marks'] as num?)?.toDouble()),
        row('Passenger Feedback', 30, fb?['achievement'] as double?, (fb?['marks'] as num?)?.toDouble()),
        const Divider(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Final Performance Score', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: scoreColor, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${b.overallScore.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 6),
                  Text('Grade ${b.grade}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Area-wise execution table ──────────────────────────────────────────────
  Widget _buildAreaTableCard(DailyTaskBillingResponse b) {
    const colW = {'area': 128.0, 'sqft': 60.0, 'rate': 72.0, 'wt': 58.0, 'req': 44.0, 'done': 44.0, 'exp': 94.0, 'act': 94.0};
    final weightageMode = _isWeightageMode(b);
    Widget cell(Object? text, double w, {TextAlign align = TextAlign.right, bool bold = false, Color? color}) {
      return SizedBox(
        width: w,
        child: Text(
          text == null ? '—' : text.toString(),
          textAlign: align,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black87),
        ),
      );
    }

    double? totalAct, totalExp, totalReq, totalDone;
    double totalWt = 0;
    for (final r in b.areaRows) {
      totalAct = (totalAct ?? 0) + ((r['actualExecutionValue'] as num?) ?? 0).toDouble();
      totalExp = (totalExp ?? 0) + ((r['expectedValue'] as num?) ?? 0).toDouble();
      totalReq = (totalReq ?? 0) + ((r['required'] as num?) ?? 0).toDouble();
      totalDone = (totalDone ?? 0) + ((r['completed'] as num?) ?? 0).toDouble();
      totalWt += ((r['weightage'] as num?) ?? 0).toDouble();
    }

    return _sectionCard(
      icon: Icons.table_chart,
      title: 'Area-wise Execution',
      subtitle: _billingBasis(b),
      children: [
        Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      cell('Area', colW['area']!, align: TextAlign.left, bold: true, color: kRailwayBlue),
                      cell('SQFT', colW['sqft']!, bold: true, color: kRailwayBlue),
                      cell('Rate', colW['rate']!, bold: true, color: kRailwayBlue),
                      cell('Wt%', colW['wt']!, bold: true, color: kRailwayBlue),
                      cell('Req', colW['req']!, bold: true, color: kRailwayBlue),
                      cell('Done', colW['done']!, bold: true, color: kRailwayBlue),
                      cell('Expected₹', colW['exp']!, bold: true, color: kRailwayBlue),
                      cell('Actual₹', colW['act']!, bold: true, color: kRailwayBlue),
                    ],
                  ),
                ),
                for (var i = 0; i < b.areaRows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    color: i.isEven ? Colors.grey[50] : Colors.white,
                    child: Row(
                      children: [
                        cell(b.areaRows[i]['areaName'] ?? '—', colW['area']!, align: TextAlign.left),
                        cell((b.areaRows[i]['areaSqft'] as num?)?.toDouble().toStringAsFixed(0) ?? '0', colW['sqft']!),
                        cell(weightageMode
                            ? '—'
                            : '₹${((b.areaRows[i]['ratePerSqft'] as num?) ?? 0).toStringAsFixed(2)}', colW['rate']!),
                        cell(b.areaRows[i]['weightage'] == null
                            ? '—'
                            : '${((b.areaRows[i]['weightage'] as num?) ?? 0).toStringAsFixed(1)}', colW['wt']!),
                        cell('${b.areaRows[i]['required'] ?? 0}', colW['req']!),
                        cell('${b.areaRows[i]['completed'] ?? 0}', colW['done']!),
                        cell(_money(((b.areaRows[i]['expectedValue'] as num?) ?? 0).toDouble()), colW['exp']!, bold: true),
                        cell(_money(((b.areaRows[i]['actualExecutionValue'] as num?) ?? 0).toDouble()), colW['act']!, bold: true, color: kSuccessGreen),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      cell('TOTAL', colW['area']!, align: TextAlign.left, bold: true, color: kRailwayBlue),
                      cell('', colW['sqft']!),
                      cell('', colW['rate']!),
                      cell(totalWt > 0 ? totalWt.toStringAsFixed(1) : '', colW['wt']!, bold: true, color: kRailwayBlue),
                      cell((totalReq ?? 0).toStringAsFixed(0), colW['req']!, bold: true),
                      cell((totalDone ?? 0).toStringAsFixed(0), colW['done']!, bold: true),
                      cell(_money(totalExp ?? 0), colW['exp']!, bold: true),
                      cell(_money(totalAct ?? 0), colW['act']!, bold: true, color: kSuccessGreen),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Area rates shortcut ─────────────────────────────────────────────────────
  Widget _buildAreaRatesRow() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.currency_rupee, color: kRailwayBlue, size: 20),
        ),
        title: const Text('Area Rates', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('Review the ₹/sq.ft. used for each area', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, color: kRailwayBlue),
        onTap: _openAreaRates,
      ),
    );
  }

  // ── Monthly bills ───────────────────────────────────────────────────────────
  // ── Daily Billing Reports cart ──────────────────────────────────────────────
  Widget _buildReportCartCard() {
    final items = _cart.bills;
    Widget scoreChip(String label, double? v) {
      final s = v;
      final color = s == null
          ? Colors.grey
          : s >= 90
              ? kSuccessGreen
              : s >= 70
                  ? kWarningOrange
                  : kErrorRed;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Text(s == null ? '—' : '${s.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return _sectionCard(
      icon: Icons.receipt_long,
      title: 'Daily Billing Reports (Cart)',
      subtitle: items.isEmpty
          ? null
          : '${items.length} report${items.length != 1 ? 's' : ''} · Net ${_money(_cart.totalNetAmount)} · newest first',
      children: [
        if (_cartLoading && items.isEmpty)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Loading reports\u2026', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 16, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No daily bills yet. Pick any date above (including past days) and tap Generate to add a report here.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('DATE', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: kRailwayBlue)),
              ),
              Text('NET \u20B9', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: kRailwayBlue)),
              const SizedBox(width: 34),
            ],
          ),
          const Divider(height: 8),
          for (final b in items)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: kRailwayBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: _loading ? null : () => _openCartDay(b),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              b.date,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (b.deduction > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text('− ${_money(b.deduction)}', style: const TextStyle(fontSize: 10, color: kErrorRed)),
                            ),
                          Text(_money(b.netAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kSuccessGreen)),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: _loading ? null : () => _downloadDayPdf(b),
                            icon: const Icon(Icons.download, size: 17),
                            color: kRailwayBlue,
                            tooltip: 'Download ${b.date} PDF',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          scoreChip('TASK', b.taskExecutionScore),
                          const SizedBox(width: 6),
                          scoreChip('INSP', b.inspectionScore),
                          const SizedBox(width: 6),
                          scoreChip('FEED', b.feedbackScore),
                          const SizedBox(width: 6),
                          scoreChip('FINAL', b.overallScore),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Divider(height: 4),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('TOTAL (${items.length} days)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kRailwayBlue)),
              ),
              Text(_money(_cart.totalNetAmount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kSuccessGreen)),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              scoreChip('TASK', _cart.avgTaskExecutionScore),
              const SizedBox(width: 6),
              scoreChip('INSP', _cart.avgInspectionScore),
              const SizedBox(width: 6),
              scoreChip('FEED', _cart.avgFeedbackScore),
              const SizedBox(width: 6),
              scoreChip('FINAL', _cart.avgFinalScore),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Scores from the billing logic: TASK (execution) · INSP (inspection) · FEED (feedback) · FINAL (weighted). Tap a row to open that day\u2019s report.',
            style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  Widget _buildMonthBillsCard() {
    Widget h(String t, double w) => SizedBox(
          width: w,
          child: Text(t, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: kRailwayBlue)),
        );
    Widget c(String t, double w, {bool bold = false, Color? color}) => SizedBox(
          width: w,
          child: Text(t, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black87)),
        );

    final month = _monthData;
    return _sectionCard(
      icon: Icons.date_range,
      title: 'Monthly Bills',
      subtitle: month.bills.isEmpty ? null : '${month.count} bill${month.count != 1 ? 's' : ''} in $_month / $_year',
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              color: kRailwayBlue,
              onPressed: () {
                setState(() { _month--; if (_month < 1) { _month = 12; _year--; } });
                _loadBills();
              },
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
                child: Text('$_month / $_year', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kRailwayBlue)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              color: kRailwayBlue,
              onPressed: () {
                setState(() { _month++; if (_month > 12) { _month = 1; _year++; } });
                _loadBills();
              },
            ),
            if (month.bills.isNotEmpty)
              IconButton(
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download, size: 20),
                color: kRailwayBlue,
                tooltip: 'Download Monthly PDF',
                onPressed: _loading ? null : _downloadMonthPdf,
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (month.bills.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No bills generated for $_month/$_year. Browse other months, or pick a date above to view/preview any day.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: kSuccessGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Text('Net ${_money(month.totalNetAmount)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kSuccessGreen)),
                const SizedBox(width: 8),
                if (month.totalDeduction > 0)
                  Text('· Deduction ${_money(month.totalDeduction)}', style: const TextStyle(fontSize: 11, color: kErrorRed)),
                const Spacer(),
                Text('Expected ${_money(month.totalExpectedWorkValue)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      h('Date', 84),
                      h('Expected ₹', 96),
                      h('Actual ₹', 96),
                      h('Final %', 64),
                      h('Deduct ₹', 90),
                      h('Net ₹', 96),
                    ]),
                  ),
                  for (final bill in month.bills)
                    InkWell(
                      onTap: _loading ? null : () => _openBill(bill),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          color: kSuccessGreen.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          c(bill.date, 84),
                          c(_money(bill.expectedWorkValue), 96),
                          c(_money(bill.actualExecutionValue), 96),
                          c(bill.overallScore.toStringAsFixed(1), 64, color: _scoreColor(bill.overallScore)),
                          c(_money(bill.deduction), 90, color: bill.deduction > 0 ? kErrorRed : Colors.grey),
                          c(_money(bill.netAmount), 96, bold: true, color: kSuccessGreen),
                        ]),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(color: kRailwayBlue.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      c('TOTAL', 84, bold: true, color: kRailwayBlue),
                      c(_money(month.totalExpectedWorkValue), 96, bold: true),
                      c(_money(month.totalActualExecutionValue), 96, bold: true),
                      c(_pct(month.avgFinalScore), 64, bold: true),
                      c(_money(month.totalDeduction), 90, bold: true),
                      c(_money(month.totalNetAmount), 96, bold: true, color: kSuccessGreen),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap any row to open that day\u2019s bill.',
            style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }
}