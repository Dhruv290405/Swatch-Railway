import 'package:crm_train/model/performance_billing_models.dart';
import 'package:crm_train/model/station_models.dart';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AreaRateConfigScreen extends StatefulWidget {
  final String contractId;
  const AreaRateConfigScreen({super.key, required this.contractId});

  @override
  State<AreaRateConfigScreen> createState() => _AreaRateConfigScreenState();
}

class _AreaRateConfigScreenState extends State<AreaRateConfigScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  BillingConfig? _config;
  final Map<String, TextEditingController> _areaWeightCtrls = {};
  List<StationArea> _areas = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _areaWeightCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await ApiService.getPerformanceBillingConfig(widget.contractId);
      if (!mounted) return;
      setState(() {
        _config = c;
        _loading = false;
      });
      await _loadAreas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadAreas() async {
    final sid = _config?.stationId;
    if (sid == null || sid.isEmpty) return;
    try {
      final areas = await ApiService.getStationAreas(sid);
      if (!mounted) return;
      setState(() {
        _areas = areas.where((a) => a.active && a.basicAreaSqFt != null).toList()
          ..sort((a, b) => (b.basicAreaSqFt ?? 0).compareTo(a.basicAreaSqFt ?? 0));
        for (final a in _areas) {
          final uid = a.uid!;
          final savedW = _config?.areaWeightages[uid] != null && _config!.areaWeightages[uid]! > 0
              ? _config!.areaWeightages[uid]!
              : 0.0;
          _areaWeightCtrls[uid] ??= TextEditingController(
            text: savedW > 0 ? _fmtW(savedW) : '',
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load areas for this station';
      });
    }
  }

  String _fmtW(double v) {
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    return s;
  }

  Map<String, double> _buildAreaWeightages() {
    final m = <String, double>{};
    _areaWeightCtrls.forEach((areaId, ctrl) {
      final v = double.tryParse(ctrl.text.trim());
      if (v != null && v > 0) m[areaId] = v;
    });
    return m;
  }

  double get _weightTotal => _buildAreaWeightages().values.fold<double>(0, (s, v) => s + v);

  double _othersTotal(String uid) {
    double s = 0;
    _areaWeightCtrls.forEach((id, ctrl) {
      if (id == uid) return;
      final v = double.tryParse(ctrl.text.trim());
      if (v != null && v > 0) s += v;
    });
    return s;
  }

  double get _annualContractValue => _config?.annualContractValue ?? 0;

  double get _contractDays => (_config?.contractDays ?? 0) > 0 ? _config!.contractDays.toDouble() : 365;

  double get _dailyContractValue => _annualContractValue / _contractDays;

  double _sqftOf(String uid) {
    for (final a in _areas) {
      if (a.uid == uid) return a.basicAreaSqFt ?? 0;
    }
    return 0;
  }

  String _measureLabel(StationArea a) {
    if (a.measurementType == 'item' || (a.basicAreaSqFt ?? 0) <= 0) return 'Item';
    return '${(a.basicAreaSqFt ?? 0).round()} sq.ft.';
  }

  double _dailyMoney(String uid, double weightage) {
    return (_annualContractValue * weightage / 100) / _contractDays;
  }

  double? _ratePerSqft(String uid, double weightage) {
    final sqft = _sqftOf(uid);
    if (sqft <= 0 || weightage <= 0) return null;
    return _dailyMoney(uid, weightage) / sqft;
  }

  Future<void> _save() async {
    final weightages = _buildAreaWeightages();
    if (weightages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set area weightage per area to allocate the daily contract value'), backgroundColor: kWarningOrange),
      );
      return;
    }
    final total = _weightTotal;
    if (total > 100.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Weightage CANNOT exceed 100% (currently ${total.toStringAsFixed(2)}%) — reduce the excess allocation'), backgroundColor: kErrorRed),
      );
      return;
    }
    if ((total - 100).abs() > 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Weightage must total EXACTLY 100% (currently ${total.toStringAsFixed(2)}%, ${(100 - total).toStringAsFixed(2)}% remaining)'), backgroundColor: kErrorRed),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = _config;
      final overrides = <String, double>{};
      _areaWeightCtrls.forEach((areaId, ctrl) {
        final w = double.tryParse(ctrl.text.trim());
        if (w != null && w > 0) {
          final r = _ratePerSqft(areaId, w);
          if (r != null && r > 0) overrides[areaId] = double.parse(r.toStringAsFixed(4));
        }
      });
      await ApiService.savePerformanceBillingConfig(widget.contractId, {
        'ratePerSqft': null,
        'areaRateOverrides': overrides,
        'areaWeightages': weightages,
        'gstRate': c?.gstRate ?? 18,
        'verifiedStatuses': c != null ? List.of(c.verifiedStatuses) : ['approved'],
        'categories': c != null ? c.categories.map((cat) => cat.toJson()).toList() : [],
        'penaltyRules': c != null ? c.penaltyRules.map((r) => r.toJson()).toList() : [],
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weightage saved — daily money & ₹/sq.ft. auto-derived'), backgroundColor: kSuccessGreen),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: kErrorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Area Weightage Allocation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _config == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: kErrorRed),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kErrorRed)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildSummaryCard(),
                          const SizedBox(height: 10),
                          _buildWeightageTotal(),
                          const SizedBox(height: 6),
                          _buildAreasList(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          style: ElevatedButton.styleFrom(backgroundColor: kSuccessGreen, foregroundColor: Colors.white),
                          label: Text(_saving ? 'Saving…' : 'Save Weightage'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSummaryCard() {
    final acv = _annualContractValue;
    final daily = _dailyContractValue;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 18, color: kRailwayBlue),
                const SizedBox(width: 6),
                const Text('Contract Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _stat(
                    'Annual (ACV)',
                    acv > 0 ? '₹${_inr(acv)}' : 'Not set',
                    acv > 0,
                  ),
                ),
                Container(width: 1, height: 34, color: Colors.grey[300]),
                const SizedBox(width: 10),
                Expanded(
                  child: _stat(
                    'Daily value',
                    daily > 0 ? '₹${_inr(daily)}' : '—',
                    daily > 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Weightage % allocates the daily value to each area. No rate entry needed — '
              '₹/sq.ft. and daily money are derived automatically.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, bool ok) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ok ? kRailwayBlue : Colors.grey[400],
          ),
        ),
      ],
    );
  }

  String _inr(double v) {
    return v.toStringAsFixed(2);
  }

  Widget _buildWeightageTotal() {
    final total = _weightTotal;
    final hasAny = total > 0;
    final exceeds = total > 100.0001;
    final ok = hasAny && (total - 100).abs() <= 0.0001;
    final Color color;
    final String caption;
    if (exceeds) {
      color = kErrorRed;
      caption = 'EXCEEDS 100% — reduce allocation';
    } else if (ok) {
      color = kSuccessGreen;
      caption = 'Fully allocated — totals 100%';
    } else if (hasAny) {
      color = kErrorRed;
      caption = 'Must total EXACTLY 100%';
    } else {
      color = Colors.grey[500]!;
      caption = 'Enter % per area to allocate the daily value';
    }
    final remaining = 100 - total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(exceeds
              ? Icons.error_outline
              : ok
                  ? Icons.check_circle_outline
                  : hasAny
                      ? Icons.adjust
                      : Icons.percent, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Allocated: ${total.toStringAsFixed(2)}%${hasAny && !ok ? '  •  ${remaining.toStringAsFixed(2)}% ${exceeds ? 'over' : 'left'}' : ''}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Text(
            caption,
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildAreasList() {
    if (_areas.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error != null ? _error! : 'No active areas found for this station.',
            style: TextStyle(fontSize: 12, color: _error != null ? kErrorRed : Colors.grey[500]),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6, top: 2),
          child: Text('AREAS (${_areas.length})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.grey[600])),
        ),
        for (final a in _areas) _areaTile(a),
      ],
    );
  }

  Widget _areaTile(StationArea a) {
    final uid = a.uid!;
    final weightCtrl = _areaWeightCtrls[uid]!;
    final wt = double.tryParse(weightCtrl.text.trim());
    final daily = wt != null && wt > 0 ? _dailyMoney(uid, wt) : 0.0;
    final rate = _ratePerSqft(uid, wt ?? 0);
    final hasWt = wt != null && wt > 0;
    final others = _othersTotal(uid);
    final exceeds = hasWt && wt! > (100 - others) + 0.0001;
    final overSingle = hasWt && (wt! > 100 || exceeds);
    final maxAllowed = 100 - others;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${_measureLabel(a)} • ${a.cleaningFrequency ?? a.frequencyType ?? ''}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _derivedChip(icon: Icons.currency_rupee, label: '${rate != null ? rate.toStringAsFixed(4) : '—'} /sq.ft.', color: kRailwayBlue, enabled: rate != null),
                      _derivedChip(icon: Icons.calendar_today, label: '₹${daily.toStringAsFixed(2)} /day', color: kSuccessGreen, enabled: hasWt),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 118,
              child: TextField(
                controller: weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}(\.\d{0,2})?')),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: 'Weightage',
                  suffixText: wt != null ? '%' : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderSide: overSingle
                        ? const BorderSide(color: kErrorRed, width: 1.4)
                        : BorderSide.none,
                  ),
                  errorText: exceeds
                      ? 'Max ${maxAllowed.toStringAsFixed(1)}%'
                      : null,
                ),
                onChanged: (_) {
                  final parsed = double.tryParse(weightCtrl.text.trim());
                  if (parsed != null && parsed > 0) {
                    final clamp = 100 - _othersTotal(uid);
                    if (clamp < 0) {
                      setState(() {
                        weightCtrl.text = '';
                      });
                    } else if (parsed > clamp) {
                      final v = clamp.toStringAsFixed(clamp == clamp.roundToDouble() ? 0 : 2);
                      setState(() {
                        weightCtrl.text = v;
                      });
                    }
                  }
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _derivedChip({required IconData icon, required String label, required Color color, required bool enabled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: enabled ? color.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: enabled ? color : Colors.grey[400]),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: enabled ? color : Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}