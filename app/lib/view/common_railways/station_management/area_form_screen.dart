import 'package:flutter/material.dart';
import 'package:crm_train/model/boq_data.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';

final _boqMainAreas = (() {
  final set = <String>{};
  for (final item in boqData) {
    set.add(item.mainArea);
  }
  final list = set.toList()..sort((a, b) {
    final sa = int.tryParse(a.split(' ').first) ?? 99;
    final sb = int.tryParse(b.split(' ').first) ?? 99;
    return sa.compareTo(sb);
  });
  return list;
})();

Map<String, List<BoqItem>> get _boqGrouped {
  final map = <String, List<BoqItem>>{};
  for (final item in boqData) {
    map.putIfAbsent(item.mainArea, () => []);
    map[item.mainArea]!.add(item);
  }
  return map;
}

class _MainAreaSelection {
  String mainArea;
  final String subArea;
  final double? sqft;
  final String? frequency;
  final int? times;
  final double? tendered;
  final String? measurementType;
  _MainAreaSelection({
    required this.mainArea,
    required this.subArea,
    this.sqft,
    this.frequency,
    this.times,
    this.tendered,
    this.measurementType,
  });
}

const _detailFrequencyOptions = <MapEntry<String, String>>[
  MapEntry('Once per day', 'daily'),
  MapEntry('Twice per day', 'twice_daily'),
  MapEntry('Three times per day', 'three_times_daily'),
  MapEntry('Four times per day', 'four_times_daily'),
  MapEntry('Once per week', 'weekly'),
  MapEntry('Once per month', 'monthly'),
];

int _timesForFrequency(String freq) {
  switch (freq) {
    case 'twice_daily':
    case 'two_times_daily':
      return 2;
    case 'three_times_daily':
    case 'shift_wise':
      return 3;
    case 'four_times_daily':
      return 4;
    case 'weekly':
    case 'monthly':
    case 'daily':
      return 1;
    default:
      return 1;
  }
}

double _tenderedFor(double sqft, String freq, int times) {
  switch (freq.toLowerCase()) {
    case 'monthly':
      return (sqft * times) / 30;
    case 'weekly':
      return (sqft * times) / 7;
    default:
      return sqft * times;
  }
}

class AreaFormScreen extends StatefulWidget {
  final String stationId;
  final Map<String, dynamic>? existingArea;
  final List<Map<String, String>>? boqPrefill;
  const AreaFormScreen({super.key, required this.stationId, this.existingArea, this.boqPrefill});

  @override
  State<AreaFormScreen> createState() => _AreaFormScreenState();
}

class _AreaFormScreenState extends State<AreaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  final List<_MainAreaSelection> _selections = [];

  bool _loadingExisting = true;
  Set<String> _existingKeys = {};
  List<Map<String, dynamic>> _existingAreas = [];

  String _pendingMainArea = '';
  final _pendingSubAreas = <String>{};
  bool _useCustomMain = false;
  final _customMainCtrl = TextEditingController();
  final _customSubCtrl = TextEditingController();
  final _customSqftCtrl = TextEditingController();
  final _customTimesCtrl = TextEditingController(text: '1');
  final _descCtrl = TextEditingController();
  final _orderCtrl = TextEditingController(text: '0');
  String _customFrequency = 'daily';
  int _customTimes = 1;
  String _customMeasurementType = 'area';
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existingArea;
    if (e != null) {
      final ma = e['mainArea'] as String? ?? '';
      final sa = e['areaName'] as String? ?? e['name'] as String? ?? '';
      if (ma.isNotEmpty) {
        final qty = (e['quantity'] as num?)?.toDouble();
        final sqft = (e['basicAreaSqFt'] as num?)?.toDouble();
        final freq = (e['frequencyType'] as String?)?.isNotEmpty == true
            ? e['frequencyType'] as String
            : e['cleaningFrequency'] as String? ?? 'daily';
        final times = (e['boqTimesPerPeriod'] as num?)?.toInt() ?? _timesForFrequency(freq);
        final tendered = (e['tenderedAreaPerDay'] as num?)?.toDouble();
        _selections.add(_MainAreaSelection(
          mainArea: ma,
          subArea: sa,
          sqft: (qty != null && qty > 0) ? qty : (sqft ?? 0),
          frequency: freq,
          times: times,
          tendered: tendered,
          measurementType: e['measurementType'] as String?,
        ));
      }
      _descCtrl.text = e['description'] ?? '';
      _orderCtrl.text = '${e['order'] ?? 0}';
      _active = e['active'] ?? true;
    }
    final pref = widget.boqPrefill;
    if (pref != null) {
      for (final p in pref) {
        final ma = p['mainArea'] ?? '';
        final sa = p['subArea'] ?? '';
        if (ma.isNotEmpty && sa.isNotEmpty) {
          final item = _boqGrouped.containsKey(ma)
              ? _boqGrouped[ma]!.where((i) => i.subArea == sa).firstOrNull
              : null;
          _selections.add(_MainAreaSelection(
            mainArea: ma,
            subArea: sa,
            sqft: item?.basicAreaSqFt,
            frequency: item?.frequencyType ?? 'daily',
            times: item?.boqTimesPerPeriod ?? 1,
            tendered: item?.tenderedAreaPerDay,
          ));
        }
      }
    }
    _loadExistingAreas();
  }

  Future<void> _loadExistingAreas() async {
    try {
      final result = await StationCleaningRepository.listAreas(widget.stationId);
      final rawList = (result['areas'] as List<dynamic>?) ?? [];
      final keys = <String>{};
      final areas = <Map<String, dynamic>>[];
      for (final a in rawList) {
        final map = (a is Map) ? Map<String, dynamic>.from(a) : <String, dynamic>{};
        final ma = map['mainArea'] as String? ?? '';
        final sa = map['areaName'] as String? ?? map['name'] as String? ?? '';
        if (ma.isNotEmpty && sa.isNotEmpty) {
          keys.add('$ma||$sa');
        }
        areas.add(map);
      }
      if (mounted) {
        setState(() {
          _existingKeys = keys;
          _existingAreas = areas;
          _loadingExisting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingExisting = false);
      }
    }
  }

  @override
  void dispose() {
    _customMainCtrl.dispose();
    _customSubCtrl.dispose();
    _customSqftCtrl.dispose();
    _customTimesCtrl.dispose();
    _descCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  bool get _hasBoqSubItems => _pendingMainArea.isNotEmpty && _boqGrouped.containsKey(_pendingMainArea) && _boqGrouped[_pendingMainArea]!.isNotEmpty;

  Set<String> get _alreadyAddedSubAreas {
    if (_pendingMainArea.isEmpty) return {};
    final fromSelections = _selections
        .where((s) => s.mainArea == _pendingMainArea)
        .map((s) => s.subArea)
        .toSet();
    final fromExisting = _existingAreas
        .where((a) => (a['mainArea'] as String? ?? '') == _pendingMainArea)
        .map((a) => a['areaName'] as String? ?? a['name'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toSet();
    return fromSelections.union(fromExisting);
  }

  void _addPendingToSelections() {
    final mainArea = _useCustomMain ? _customMainCtrl.text.trim() : _pendingMainArea;
    if (mainArea.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select or enter a main area'), backgroundColor: kErrorRed));
      return;
    }

    final useBoq = _hasBoqSubItems && !_useCustomMain;
    final selected = useBoq ? _pendingSubAreas.toSet() : {_customSubCtrl.text.trim()};
    selected.removeWhere((s) => s.isEmpty);

    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one sub-area'), backgroundColor: kErrorRed));
      return;
    }

    int skipped = 0;
    final isItem = _customMeasurementType == 'item';
    final customSqft = isItem ? 0.0 : (double.tryParse(_customSqftCtrl.text.trim()) ?? 0.0);
    setState(() {
      for (final sa in selected) {
        final key = '$mainArea||$sa';
        if (_existingKeys.contains(key)) {
          skipped++;
          continue;
        }
        if (!_selections.any((s) => s.mainArea == mainArea && s.subArea == sa)) {
          if (useBoq) {
            final item = _boqGrouped[mainArea]!.where((i) => i.subArea == sa).firstOrNull;
            _selections.add(_MainAreaSelection(
              mainArea: mainArea,
              subArea: sa,
              sqft: item?.basicAreaSqFt ?? 0,
              frequency: item?.frequencyType ?? 'daily',
              times: item?.boqTimesPerPeriod ?? 1,
              tendered: item?.tenderedAreaPerDay,
              measurementType: 'sq_ft',
            ));
          } else {
            _selections.add(_MainAreaSelection(
              mainArea: mainArea,
              subArea: sa,
              sqft: customSqft,
              frequency: _customFrequency,
              times: _customTimes,
              tendered: _tenderedFor(customSqft, _customFrequency, _customTimes),
              measurementType: isItem ? 'item' : (customSqft > 0 ? 'sq_ft' : 'as_available'),
            ));
          }
        }
      }
      _pendingMainArea = '';
      _pendingSubAreas.clear();
      _useCustomMain = false;
      _customMainCtrl.clear();
      _customSubCtrl.clear();
      _customSqftCtrl.clear();
      _customFrequency = 'daily';
      _customTimes = 1;
      _customTimesCtrl.text = '1';
      _customMeasurementType = 'area';
    });
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$skipped area${skipped == 1 ? '' : 's'} already exist in backend — skipped'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  void _showMultiSubAreaPicker(List<BoqItem> items) {
    final alreadyAdded = _alreadyAddedSubAreas;
    final tempSelected = Set<String>.from(_pendingSubAreas);
    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchCtrl.text.toLowerCase();
            final filtered = items.where((i) {
              if (alreadyAdded.contains(i.subArea)) return false;
              if (query.isNotEmpty && !i.subArea.toLowerCase().contains(query)) return false;
              return true;
            }).toList();

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Expanded(child: Text('Select Sub-areas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700]))),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _pendingSubAreas
                                ..clear()
                                ..addAll(tempSelected);
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  if (alreadyAdded.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('${alreadyAdded.length} already added — hidden below', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search sub-areas...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  SizedBox(
                    height: (filtered.length * 60).clamp(100, 400).toDouble(),
                    child: filtered.isEmpty
                        ? Center(child: Text(query.isEmpty ? 'No more sub-areas to select' : 'No matches', style: TextStyle(color: Colors.grey[500])))
                        : ListView(
                            children: filtered.map((item) {
                              final isChecked = tempSelected.contains(item.subArea);
                              return CheckboxListTile(
                                value: isChecked,
                                dense: true,
                                title: Text(item.subArea, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: Text('${_num(item.basicAreaSqFt)} sq.ft.  ${item.frequencyType} ${item.boqTimesPerPeriod}x  Tendered/day: ${_num(item.tenderedAreaPerDay)} sq.ft.',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                controlAffinity: ListTileControlAffinity.leading,
                                onChanged: (v) {
                                  setSheetState(() {
                                    if (v == true) {
                                      tempSelected.add(item.subArea);
                                    } else {
                                      tempSelected.remove(item.subArea);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  if (tempSelected.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('${tempSelected.length} selected', style: TextStyle(color: kRailwayBlue, fontWeight: FontWeight.w500)),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    if (_selections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one main area with sub-areas'), backgroundColor: kErrorRed));
      return;
    }

    setState(() => _isSaving = true);
    int created = 0;
    int skipped = 0;
    final errorList = <String>[];

    for (final sel in _selections) {
      final key = '${sel.mainArea}||${sel.subArea}';
      if (widget.existingArea == null && _existingKeys.contains(key)) {
        skipped++;
        continue;
      }

      final data = _payloadFor(sel);

      if (widget.existingArea != null) {
        try {
          final uid = widget.existingArea!['uid'] ?? widget.existingArea!['id'];
          await StationCleaningRepository.updateArea(uid, data);
          created++;
        } catch (e) {
          errorList.add('${sel.mainArea}/${sel.subArea}: $e');
        }
        break;
      } else {
        try {
          await StationCleaningRepository.createArea(data);
          created++;
          _existingKeys.add(key);
        } catch (e) {
          errorList.add('${sel.mainArea}/${sel.subArea}: $e');
        }
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (widget.existingArea != null) {
        if (errorList.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Area updated'), backgroundColor: kSuccessGreen));
          Navigator.pop(context, true);
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Update Error', style: TextStyle(color: kErrorRed)),
              content: SingleChildScrollView(child: SelectableText(errorList.join('\n'))),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
        }
      } else {
        final parts = <String>['Created $created area${created == 1 ? '' : 's'}'];
        if (skipped > 0) parts.add('Skipped $skipped duplicate${skipped == 1 ? '' : 's'}');
        if (errorList.isNotEmpty) parts.add('${errorList.length} error${errorList.length == 1 ? '' : 's'}');
        final msg = parts.join(', ');
        if (errorList.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: kSuccessGreen));
          Navigator.pop(context, true);
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Creation Summary', style: TextStyle(color: errorList.isEmpty ? kSuccessGreen : Colors.orange)),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (errorList.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold, color: kErrorRed)),
                      const SizedBox(height: 4),
                      ...errorList.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(e, style: const TextStyle(fontSize: 13)),
                      )),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    if (created > 0) Navigator.pop(context, true);
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Map<String, dynamic> _payloadFor(_MainAreaSelection sel) {
    final sqft = sel.sqft ?? 0.0;
    final freq = sel.frequency ?? 'daily';
    final times = sel.times ?? _timesForFrequency(freq);
    return {
      'stationId': widget.stationId,
      'areaName': sel.subArea,
      'name': sel.subArea,
      'mainArea': sel.mainArea,
      'subArea': sel.subArea,
      'basicAreaSqFt': sqft,
      'quantity': sqft,
      'measurementType': sel.measurementType ?? (sqft > 0 ? 'sq_ft' : 'as_available'),
      'frequencyType': freq,
      'boqTimesPerPeriod': times,
      'tenderedAreaPerDay': sel.tendered ?? _tenderedFor(sqft, freq, times),
      'cleaningFrequency': _boqTimesToFrequency(times),
      'description': _descCtrl.text.trim(),
      'order': int.tryParse(_orderCtrl.text) ?? 0,
      'active': _active,
    };
  }

  Future<void> _showEditSelection(int index) async {
    final sel = _selections[index];
    final isItem = sel.measurementType == 'item';
    final nameCtrl = TextEditingController(text: sel.subArea);
    final sqftCtrl = TextEditingController(text: (sel.sqft ?? 0) > 0 && !isItem ? _num(sel.sqft) : '');
    final timesCtrl = TextEditingController(text: '${sel.times ?? _timesForFrequency(sel.frequency ?? 'daily')}');
    String frequency = sel.frequency ?? 'daily';
    String measurementType = isItem ? 'item' : 'area';

    final freqOptions = [
      ..._detailFrequencyOptions,
      if (!_detailFrequencyOptions.any((o) => o.value == frequency))
        MapEntry(_frequencyLabel(frequency), frequency),
    ];

    final edited = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => AlertDialog(
          title: const Text('Edit Area Details', style: TextStyle(fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Area name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: measurementType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'area', child: Text('Area (sq.ft.)')),
                    DropdownMenuItem(value: 'item', child: Text('Item (no area size)')),
                  ],
                  onChanged: (v) => setSheetState(() {
                    measurementType = v!;
                    if (v == 'item') sqftCtrl.clear();
                  }),
                ),
                if (measurementType == 'item') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kRailwayBlue.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kRailwayBlue.withOpacity(0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.tips_and_updates_outlined, size: 16, color: kRailwayBlue),
                        SizedBox(width: 6),
                        Expanded(child: Text('No area size. This item is billed by the weightage % you assign.', style: TextStyle(fontSize: 11, color: Colors.black54))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: sqftCtrl,
                    decoration: const InputDecoration(labelText: 'Area size (sq.ft.)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.square_foot)),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  value: frequency,
                  decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
                  items: freqOptions.map((o) => DropdownMenuItem(value: o.value, child: Text(o.key))).toList(),
                  onChanged: (v) => setSheetState(() {
                    frequency = v!;
                    final t = _timesForFrequency(v);
                    timesCtrl.text = '$t';
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timesCtrl,
                  decoration: const InputDecoration(labelText: 'Times per period', border: OutlineInputBorder(), prefixIcon: Icon(Icons.repeat)),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (edited != true) return;
    final name = nameCtrl.text.trim();
    final isItemSave = measurementType == 'item';
    final sqft = isItemSave ? 0.0 : (double.tryParse(sqftCtrl.text.trim()) ?? sel.sqft ?? 0.0);
    final times = int.tryParse(timesCtrl.text.trim()) ?? sel.times ?? _timesForFrequency(frequency);
    final resolvedSqft = sqft;
    setState(() {
      _selections[index] = _MainAreaSelection(
        mainArea: sel.mainArea,
        subArea: name.isEmpty ? sel.subArea : name,
        sqft: resolvedSqft,
        frequency: frequency,
        times: times,
        tendered: _tenderedFor(resolvedSqft, frequency, times),
        measurementType: isItemSave ? 'item' : (resolvedSqft > 0 ? 'sq_ft' : 'as_available'),
      );
    });
  }

  Widget _customDetailFields() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: kRailwayBlue.withOpacity(0.03),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: kRailwayBlue.withOpacity(0.15))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: kRailwayBlue),
                const SizedBox(width: 6),
                Text('Details (custom area)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _customMeasurementType,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: const [
                DropdownMenuItem(value: 'area', child: Text('Area (sq.ft.)')),
                DropdownMenuItem(value: 'item', child: Text('Item (no area size)')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _customMeasurementType = v;
                  if (v == 'item') _customSqftCtrl.clear();
                });
              },
            ),
            if (_customMeasurementType == 'item') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kRailwayBlue.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kRailwayBlue.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, size: 16, color: kRailwayBlue),
                    SizedBox(width: 6),
                    Expanded(child: Text('No area size needed. This item is billed by the weightage % you assign in Daily Billing → Area Weightage.', style: TextStyle(fontSize: 11, color: Colors.black54))),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customSqftCtrl,
                decoration: const InputDecoration(labelText: 'Area size (sq.ft.)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.square_foot)),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _customFrequency,
              decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
              items: _detailFrequencyOptions.map((o) => DropdownMenuItem(value: o.value, child: Text(o.key))).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _customFrequency = v;
                  _customTimes = _timesForFrequency(v);
                  _customTimesCtrl.text = '$_customTimes';
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customTimesCtrl,
              decoration: const InputDecoration(labelText: 'Times per period', border: OutlineInputBorder(), prefixIcon: Icon(Icons.repeat)),
              keyboardType: TextInputType.number,
              onChanged: (v) => _customTimes = int.tryParse(v) ?? _customTimes,
            ),
          ],
        ),
      ),
    );
  }

  double _rowSqft(_MainAreaSelection sel) {
    if (sel.sqft != null && sel.sqft! > 0) return sel.sqft!;
    final matched = _boqGrouped[sel.mainArea]?.where((i) => i.subArea == sel.subArea).firstOrNull;
    return matched?.basicAreaSqFt ?? 0;
  }

  String _rowDetail(_MainAreaSelection sel) {
    final parts = <String>[];
    final sqft = _rowSqft(sel);
    if (sel.measurementType == 'item' ||
        ((sel.measurementType == null || sel.measurementType == 'as_available') &&
            (sel.sqft ?? 0) <= 0 && sel.mainArea.isNotEmpty && !_boqGrouped.containsKey(sel.mainArea))) {
      parts.add('Item (no size)');
    } else if (sqft > 0) {
      parts.add('${_num(sqft)} sq.ft.');
    }
    final f = sel.frequency ?? _boqGrouped[sel.mainArea]?.where((i) => i.subArea == sel.subArea).firstOrNull?.frequencyType;
    final t = sel.times ?? _boqGrouped[sel.mainArea]?.where((i) => i.subArea == sel.subArea).firstOrNull?.boqTimesPerPeriod;
    if (f != null && f.isNotEmpty) parts.add('${_frequencyLabel(f)}${(t ?? 0) > 1 ? ' x$t' : ''}');
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingArea != null;
    final subItems = _pendingMainArea.isNotEmpty && _boqGrouped.containsKey(_pendingMainArea)
        ? _boqGrouped[_pendingMainArea]!
        : <BoqItem>[];
    final useBoq = _hasBoqSubItems && !_useCustomMain;
    final canAdd = useBoq ? _pendingSubAreas.isNotEmpty : _customSubCtrl.text.trim().isNotEmpty;
    final availableCount = subItems.where((i) => !_alreadyAddedSubAreas.contains(i.subArea)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${isEdit ? 'Edit' : 'Add'} Area', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: kRailwayBlue,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isEdit ? 'Edit Area Details' : 'Add Areas', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (!isEdit && _existingKeys.isNotEmpty)
                    Text('${_existingKeys.length} area${_existingKeys.length == 1 ? '' : 's'} already exist for this station',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),

                  // ── Step 1: Selected Areas List ──
                  if (_selections.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kRailwayBlue.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kRailwayBlue.withOpacity(0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.checklist, size: 18, color: kRailwayBlue),
                              const SizedBox(width: 6),
                              Text('Selected Areas (${_selections.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kRailwayBlue)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (int i = 0; i < _selections.length; i++) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        RichText(
                                          text: TextSpan(
                                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                                            children: [
                                              TextSpan(text: _selections[i].mainArea, style: const TextStyle(fontWeight: FontWeight.bold, color: kRailwayBlue)),
                                              const TextSpan(text: '  →  '),
                                              TextSpan(text: _selections[i].subArea),
                                            ],
                                          ),
                                        ),
                                        if (_rowDetail(_selections[i]).isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              _rowDetail(_selections[i]),
                                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _showEditSelection(i),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.edit_outlined, size: 16, color: kRailwayBlue),
                                    tooltip: 'Edit name / size / frequency',
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => setState(() => _selections.removeAt(i)),
                                    child: const Icon(Icons.close, size: 16, color: kErrorRed),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Step 2: Add New Main Area ──
                  _sectionHeader(Icons.add_circle_outline, 'Add More Areas'),
                  const SizedBox(height: 10),

                  if (!_useCustomMain)
                    DropdownButtonFormField<String>(
                      value: _pendingMainArea.isNotEmpty && _boqMainAreas.contains(_pendingMainArea) ? _pendingMainArea : null,
                      decoration: const InputDecoration(
                        labelText: 'Main Area', border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: [
                        ..._boqMainAreas.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))),
                        const DropdownMenuItem(value: '__custom__', child: Text('+ Custom', style: TextStyle(color: Colors.blue))),
                      ],
                      onChanged: (v) {
                        if (v == '__custom__') {
                          setState(() {
                            _useCustomMain = true;
                            _pendingMainArea = '';
                            _pendingSubAreas.clear();
                          });
                        } else {
                          setState(() {
                            _pendingMainArea = v!;
                            _pendingSubAreas.clear();
                          });
                        }
                      },
                    ),
                  if (_useCustomMain)
                    TextField(
                      controller: _customMainCtrl,
                      decoration: InputDecoration(
                        labelText: 'Main Area (custom)', border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.category),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _useCustomMain = false;
                            _customMainCtrl.clear();
                            _pendingMainArea = '';
                            _pendingSubAreas.clear();
                          }),
                        ),
                      ),
                      onChanged: (v) => _pendingMainArea = v,
                    ),

                  // ── Step 3: Pick Sub-areas ──
                  if (_pendingMainArea.isNotEmpty && subItems.isNotEmpty && !_useCustomMain) ...[
                    const SizedBox(height: 14),
                    _sectionHeader(Icons.place, 'Pick Sub-areas'),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _showMultiSubAreaPicker(subItems),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Sub-areas ($availableCount available)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.place),
                          suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                        ),
                        child: _pendingSubAreas.isEmpty
                            ? Text('Tap to select sub-areas', style: TextStyle(color: Colors.grey[600], fontSize: 14))
                            : Text('${_pendingSubAreas.length} sub-area${_pendingSubAreas.length == 1 ? '' : 's'} selected', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                    ),
                    if (_pendingSubAreas.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _pendingSubAreas.map((sa) {
                          final item = subItems.where((i) => i.subArea == sa).firstOrNull;
                          return Chip(
                            label: Text(sa, style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(() => _pendingSubAreas.remove(sa)),
                            backgroundColor: kRailwayBlue.withOpacity(0.08),
                            side: BorderSide(color: kRailwayBlue.withOpacity(0.3)),
                            visualDensity: VisualDensity.compact,
                            deleteIconColor: kErrorRed,
                          );
                        }).toList(),
                      ),
                    ],
                  ],

                  // ── Custom Sub-area ──
                  if (_pendingMainArea.isNotEmpty && subItems.isEmpty && !_useCustomMain) ...[
                    const SizedBox(height: 14),
                    _sectionHeader(Icons.add_box, 'Sub-area Name'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customSubCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Sub-area name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.add_box),
                        hintText: 'e.g. Extra Room A',
                      ),
                    ),
                    _customDetailFields(),
                  ],
                  if (_useCustomMain) ...[
                    const SizedBox(height: 14),
                    _sectionHeader(Icons.add_box, 'Sub-area Name'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customSubCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Sub-area name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.add_box),
                        hintText: 'e.g. Extra Room A',
                      ),
                    ),
                    _customDetailFields(),
                  ],
                  const SizedBox(height: 12),

                  // ── Step 4: Add Button ──
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: canAdd ? _addPendingToSelections : null,
                      icon: const Icon(Icons.add_circle, size: 18),
                      label: Text(useBoq
                          ? 'Add ${_pendingSubAreas.length} sub-area${_pendingSubAreas.length == 1 ? '' : 's'} to List'
                          : 'Add This Main Area'),
                      style: OutlinedButton.styleFrom(foregroundColor: kRailwayBlue),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  _sectionHeader(Icons.tune, 'Common Settings'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder(), prefixIcon: Icon(Icons.description)),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _orderCtrl,
                    decoration: const InputDecoration(labelText: 'Display Order', border: OutlineInputBorder(), prefixIcon: Icon(Icons.sort)),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Active'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    activeColor: kRailwayBlue,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : () {
                        if (_selections.isEmpty && _pendingSubAreas.isNotEmpty && _pendingMainArea.isNotEmpty) {
                          _addPendingToSelections();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_selections.isNotEmpty) _save();
                          });
                          return;
                        }
                        if (_selections.isEmpty) {
                          if (_pendingMainArea.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Select a Main Area from the BOQ list first'),
                              backgroundColor: kErrorRed,
                            ));
                          } else if (_pendingSubAreas.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Tap "Tap to select sub-areas" to pick areas to add'),
                              backgroundColor: kErrorRed,
                            ));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Click "Add to List" button above first, then save'),
                              backgroundColor: kErrorRed,
                            ));
                          }
                          return;
                        }
                        _save();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit
                              ? 'Update Area'
                              : _selections.isEmpty
                                  ? 'Add areas above to save'
                                  : 'Save All Areas (${_selections.length})'),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          if (_loadingExisting)
            Container(
              color: Colors.white.withOpacity(0.85),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  String _boqTimesToFrequency(int times) {
    if (times <= 1) return 'daily';
    if (times == 2) return 'twice_daily';
    if (times == 3) return 'shift_wise';
    if (times == 4) return 'four_times_daily';
    if (times <= 6) return '4hrs';
    return 'hourly';
  }

  String _frequencyLabel(String freq) {
    for (final o in _detailFrequencyOptions) {
      if (o.value == freq) return o.key;
    }
    return freq.replaceAll('_', ' ');
  }

  Widget _sectionHeader(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 18, color: kRailwayBlue),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
      ],
    );
  }
}

String _num(dynamic v) {
  if (v == null) return '-';
  final n = (v is num) ? v : double.tryParse(v.toString()) ?? 0;
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(1);
}
