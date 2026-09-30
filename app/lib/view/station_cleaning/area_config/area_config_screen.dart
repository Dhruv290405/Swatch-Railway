import 'package:flutter/material.dart';
import 'package:crm_train/model/platform_model.dart';
import 'package:crm_train/model/boq_data.dart';
import 'package:crm_train/repositories/platform_repository.dart';
import 'package:crm_train/repositories/station_cleaning_repository.dart';
import 'package:crm_train/helper/api_error_handler.dart';
import 'package:crm_train/utills/app_colors.dart';
import 'package:crm_train/view/common_railways/station_management/area_form_screen.dart';

double _calcTendered(double basicAreaSqFt, String frequencyType, int boqTimesPerPeriod) {
  final area = basicAreaSqFt;
  final times = boqTimesPerPeriod;
  switch (frequencyType.toLowerCase()) {
    case 'monthly':
      return (area * times) / 30;
    case 'weekly':
      return (area * times) / 7;
    case 'daily':
    default:
      return area * times;
  }
}

String _num(dynamic v) {
  if (v == null) return '-';
  final n = (v is num) ? v : double.tryParse(v.toString()) ?? 0;
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n.toStringAsFixed(1);
}

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

class AreaConfigScreen extends StatefulWidget {
  final String stationId;
  final String stationName;
  final String? platformId;

  const AreaConfigScreen({
    super.key,
    required this.stationId,
    required this.stationName,
    this.platformId,
  });

  @override
  State<AreaConfigScreen> createState() => _AreaConfigScreenState();
}

class _AreaConfigScreenState extends State<AreaConfigScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _areas = [];
  List<Platform> _platforms = [];
  Platform? _selectedPlatform;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlatforms();
  }

  Future<void> _loadPlatforms() async {
    try {
      final platforms = await PlatformRepository.getByStation(widget.stationId);
      Platform? preSelected;
      if (widget.platformId != null) {
        preSelected = platforms.where((p) => p.uid == widget.platformId).firstOrNull;
      }
      if (mounted) {
        setState(() {
          _platforms = platforms;
          _selectedPlatform = preSelected;
        });
      }
    } catch (_) {}
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    try {
      final result = await StationCleaningRepository.listAreas(widget.stationId);
      final list = (result['areas'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      List<Map<String, dynamic>> filtered = list;
      if (_selectedPlatform?.uid != null) {
        filtered = filtered.where((a) => a['platformId'] == _selectedPlatform!.uid).toList();
      } else if (widget.platformId != null) {
        filtered = filtered.where((a) => a['platformId'] == widget.platformId).toList();
      }
      if (mounted) {
        setState(() {
          _areas = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('AUTH_ERROR') ? 'Session expired' : ApiErrorHandler.getErrorMessage(e, null);
          _isLoading = false;
        });
      }
    }
  }

  List<String> get _existingMainAreas {
    final set = <String>{};
    for (final a in _areas) {
      final m = a['mainArea'] as String?;
      if (m != null && m.isNotEmpty) set.add(m);
    }
    final sorted = set.toList()..sort();
    return sorted;
  }

  Map<String, List<Map<String, dynamic>>> get _groupedAreas {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final area in _areas) {
      final main = (area['mainArea'] as String?)?.isNotEmpty == true ? area['mainArea'] as String : 'Uncategorized';
      grouped.putIfAbsent(main, () => []);
      grouped[main]!.add(area);
    }
    final keys = grouped.keys.toList()..sort((a, b) {
      if (a == 'Uncategorized') return 1;
      if (b == 'Uncategorized') return -1;
      return a.compareTo(b);
    });
    final sortedGrouped = <String, List<Map<String, dynamic>>>{};
    for (final k in keys) {
      sortedGrouped[k] = grouped[k]!;
    }
    return sortedGrouped;
  }

  double get _totalBasicArea {
    double total = 0;
    for (final a in _areas) {
      total += (a['basicAreaSqFt'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  double get _totalTenderedArea {
    double total = 0;
    for (final a in _areas) {
      total += (a['tenderedAreaPerDay'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  void _showBoqPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kRailwayBlue,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('BOQ - MSH Station Cleaning', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(8),
                children: [
                  for (final main in _boqMainAreas) ...[
                    _BoqSectionTile(
                      mainArea: main,
                      items: _boqGrouped[main]!,
                      onSelect: (item) {
                        Navigator.pop(ctx);
                        Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AreaFormScreen(
                              stationId: widget.stationId,
                              boqPrefill: [{'mainArea': item.mainArea, 'subArea': item.subArea}],
                            ),
                          ),
                        ).then((_) => _loadAreas());
                      },
                      onSelectAll: (items) async {
                        Navigator.pop(ctx);
                        int created = 0;
                        final errors = <String>[];
                        for (final item in items) {
                          try {
                            await StationCleaningRepository.createArea({
                              'areaName': item.subArea,
                              'stationId': widget.stationId,
                              'platformId': _selectedPlatform?.uid ?? widget.platformId,
                              'mainArea': item.mainArea,
                              'basicAreaSqFt': item.basicAreaSqFt,
                              'frequencyType': item.frequencyType,
                              'boqTimesPerPeriod': item.boqTimesPerPeriod,
                              'tenderedAreaPerDay': item.tenderedAreaPerDay,
                            });
                            created++;
                          } catch (e) {
                            errors.add('${item.subArea}: $e');
                          }
                        }
                        _loadAreas();
                        if (context.mounted) {
                          final msg = 'Created $created area${created == 1 ? '' : 's'}';
                          if (errors.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg), backgroundColor: kSuccessGreen),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$msg, ${errors.length} failed'), backgroundColor: Colors.orange),
                            );
                          }
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showConfigDialog({Map<String, dynamic>? area, BoqItem? prefill}) async {
    final isEditing = area != null;
    final areaId = area?['uid'] ?? area?['id'] ?? '';

    String selectedMainArea = prefill?.mainArea ?? area?['mainArea'] as String? ?? '';
    String selectedSubArea = prefill?.subArea ?? area?['areaName'] as String? ?? '';
    double basicAreaSqFt = prefill?.basicAreaSqFt ?? (area?['basicAreaSqFt'] as num?)?.toDouble() ?? 0;
    String frequencyType = prefill?.frequencyType ?? area?['frequencyType'] as String? ?? 'daily';
    int boqTimesPerPeriod = prefill?.boqTimesPerPeriod ?? ((area?['boqTimesPerPeriod'] as num?)?.toInt() ?? 1);
    double tenderedAreaPerDay = prefill?.tenderedAreaPerDay ?? (area?['tenderedAreaPerDay'] as num?)?.toDouble() ?? 0;
    String dialogMeasurementType = (area?['measurementType'] as String?) == 'item' ? 'item' : 'area';

    final basicCtrl = TextEditingController(text: basicAreaSqFt > 0 && dialogMeasurementType != 'item' ? basicAreaSqFt.toString() : '');
    final timesCtrl = TextEditingController(text: boqTimesPerPeriod.toString());

    bool useCustomMain = false;
    final customMainCtrl = TextEditingController(text: '');
    bool useCustomSub = false;
    final customSubCtrl = TextEditingController(text: '');

    if (selectedMainArea.isNotEmpty && !_boqMainAreas.contains(selectedMainArea)) {
      useCustomMain = true;
      customMainCtrl.text = selectedMainArea;
    }
    if (selectedSubArea.isNotEmpty && selectedMainArea.isNotEmpty && _boqGrouped[selectedMainArea]?.any((i) => i.subArea == selectedSubArea) != true) {
      useCustomSub = true;
      customSubCtrl.text = selectedSubArea;
    }

    Platform? dialogPlatform = area != null
        ? _platforms.where((p) => p.uid == (area['platformId'])).firstOrNull
        : _selectedPlatform;

    double calcTendered() {
      final basic = double.tryParse(basicCtrl.text) ?? 0;
      final times = int.tryParse(timesCtrl.text) ?? 1;
      return _calcTendered(basic, frequencyType, times);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final tendered = calcTendered();

          return AlertDialog(
            title: Text(isEditing ? 'Edit Area' : 'Add Area'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_platforms.isNotEmpty) ...[
                    DropdownButtonFormField<Platform>(
                      value: dialogPlatform,
                      decoration: const InputDecoration(
                        labelText: 'Platform',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.view_quilt),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('No Platform')),
                        ..._platforms.map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p.displayName, overflow: TextOverflow.ellipsis),
                        )),
                      ],
                      onChanged: (v) => setDialogState(() => dialogPlatform = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!useCustomMain)
                    DropdownButtonFormField<String>(
                      value: selectedMainArea.isNotEmpty && _boqMainAreas.contains(selectedMainArea) ? selectedMainArea : null,
                      decoration: const InputDecoration(
                        labelText: 'Main Area (from BOQ)',
                        border: OutlineInputBorder(),
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
                          setDialogState(() {
                            useCustomMain = true;
                            selectedMainArea = '';
                            selectedSubArea = '';
                          });
                        } else {
                          setDialogState(() {
                            selectedMainArea = v!;
                            selectedSubArea = '';
                            basicCtrl.clear();
                            timesCtrl.text = '1';
                            frequencyType = 'daily';
                          });
                        }
                      },
                    ),
                  if (useCustomMain)
                    TextField(
                      controller: customMainCtrl,
                      decoration: InputDecoration(
                        labelText: 'Main Area (custom)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.category),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setDialogState(() {
                            useCustomMain = false;
                            customMainCtrl.clear();
                            selectedMainArea = _boqMainAreas.isNotEmpty ? _boqMainAreas.first : '';
                          }),
                        ),
                      ),
                      onChanged: (v) => selectedMainArea = v,
                    ),
                  const SizedBox(height: 12),
                  if (selectedMainArea.isNotEmpty && _boqGrouped.containsKey(selectedMainArea) && !useCustomMain && !useCustomSub)
                    DropdownButtonFormField<String>(
                      value: selectedSubArea.isNotEmpty && _boqGrouped[selectedMainArea]!.any((i) => i.subArea == selectedSubArea) ? selectedSubArea : null,
                      decoration: const InputDecoration(
                        labelText: 'Sub-area',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.place),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: [
                        ..._boqGrouped[selectedMainArea]!.map((i) => DropdownMenuItem(value: i.subArea, child: Text(i.subArea, overflow: TextOverflow.ellipsis))),
                        const DropdownMenuItem(value: '__custom_sub__', child: Text('+ Custom', style: TextStyle(color: Colors.blue))),
                      ],
                      onChanged: (v) {
                        if (v == '__custom_sub__') {
                          setDialogState(() => useCustomSub = true);
                        } else {
                          final item = _boqGrouped[selectedMainArea]!.firstWhere((i) => i.subArea == v);
                          setDialogState(() {
                            selectedSubArea = v!;
                            basicCtrl.text = item.basicAreaSqFt.toString();
                            timesCtrl.text = item.boqTimesPerPeriod.toString();
                            frequencyType = item.frequencyType;
                          });
                        }
                      },
                    ),
                  if (useCustomSub || (selectedMainArea.isNotEmpty && !_boqGrouped.containsKey(selectedMainArea)))
                    TextField(
                      controller: customSubCtrl,
                      decoration: InputDecoration(
                        labelText: 'Sub-area Name',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.place),
                      ),
                      onChanged: (v) => selectedSubArea = v,
                    ),
                  if (!useCustomSub && !useCustomMain && selectedMainArea.isNotEmpty && _boqGrouped.containsKey(selectedMainArea) && selectedSubArea.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(_boqGrouped[selectedMainArea]!.firstWhere((i) => i.subArea == selectedSubArea).frequencyDescription,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: dialogMeasurementType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'area', child: Text('Area (sq.ft.)')),
                      DropdownMenuItem(value: 'item', child: Text('Item (no area size)')),
                    ],
                    onChanged: (v) => setDialogState(() {
                      dialogMeasurementType = v!;
                      if (v == 'item') basicCtrl.clear();
                    }),
                  ),
                  if (dialogMeasurementType == 'item') ...[
                    const SizedBox(height: 12),
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
                          Expanded(child: Text('No area size. This item is billed by the weightage % you assign in Daily Billing → Area Weightage.', style: TextStyle(fontSize: 11, color: Colors.black54))),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: basicCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Basic Area (sq.ft.)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.square_foot),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: frequencyType,
                    decoration: const InputDecoration(
                      labelText: 'Frequency Type',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repeat),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    ],
                    onChanged: (v) => setDialogState(() => frequencyType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: timesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Times per Period',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.format_list_numbered),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kRailwayBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: kRailwayBlue.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate, color: kRailwayBlue),
                        const SizedBox(width: 8),
                        Text(
                          'Tendered Area/day: ${_num(tendered)} sq.ft.',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final mainArea = useCustomMain ? customMainCtrl.text : selectedMainArea;
                  final subArea = useCustomSub ? customSubCtrl.text : selectedSubArea;
                  if (subArea.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sub-area name is required')));
                    return;
                  }
                  if (mainArea.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select or enter a main area')));
                    return;
                  }

                  final data = {
                    'areaName': subArea.trim(),
                    'stationId': widget.stationId,
                    'platformId': dialogPlatform?.uid,
                    'mainArea': mainArea,
                    'measurementType': dialogMeasurementType == 'item' ? 'item' : null,
                    'basicAreaSqFt': dialogMeasurementType == 'item' ? 0 : (double.tryParse(basicCtrl.text) ?? 0),
                    'frequencyType': frequencyType,
                    'boqTimesPerPeriod': int.tryParse(timesCtrl.text) ?? 1,
                  };

                  try {
                    if (isEditing) {
                      await StationCleaningRepository.updateArea(areaId, data);
                    } else {
                      await StationCleaningRepository.createArea(data);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadAreas();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
                      );
                    }
                  }
                },
                child: Text(isEditing ? 'Update' : 'Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedAreas;
    final totalBasic = _totalBasicArea;
    final totalTendered = _totalTenderedArea;

    return Scaffold(
      appBar: AppBar(
        title: Text('Areas - ${widget.stationName}'),
        actions: [
          TextButton.icon(
            onPressed: _showBoqPicker,
            icon: const Icon(Icons.description, color: Colors.white),
            label: const Text('BOQ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => AreaFormScreen(stationId: widget.stationId),
            ),
          );
          if (result == true) _loadAreas();
        },
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  children: [
                    if (_platforms.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: Colors.white,
                        child: DropdownButtonFormField<Platform>(
                          value: _selectedPlatform,
                          decoration: const InputDecoration(
                            labelText: 'Platform',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.view_quilt),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            isDense: true,
                          ),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Platforms')),
                            ..._platforms.map((p) => DropdownMenuItem(
                              value: p,
                              child: Text(p.displayName, overflow: TextOverflow.ellipsis),
                            )),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedPlatform = v);
                            _loadAreas();
                          },
                        ),
                      ),
                    Expanded(
                      child: _areas.isEmpty
                          ? const Center(child: Text('No areas configured'))
                          : RefreshIndicator(
                              onRefresh: _loadAreas,
                              child: ListView(
                                children: [
                                  for (final entry in grouped.entries)
                                    _AreaGroupTile(
                                      mainArea: entry.key,
                                      areas: entry.value,
                                      onEdit: (a) => _showConfigDialog(area: a),
                                    ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                    ),
                    if (_areas.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kRailwayBlue.withOpacity(0.08),
                          border: Border(top: BorderSide(color: kRailwayBlue.withOpacity(0.3))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${_areas.length} areas', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Basic area: ${_num(totalBasic)} sq.ft.'),
                                  Text('Tendered/day: ${_num(totalTendered)} sq.ft.', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _loadAreas,
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _AreaGroupTile extends StatelessWidget {
  final String mainArea;
  final List<Map<String, dynamic>> areas;
  final void Function(Map<String, dynamic> area) onEdit;

  const _AreaGroupTile({
    required this.mainArea,
    required this.areas,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: mainArea != 'Uncategorized',
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(mainArea, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${areas.length} area${areas.length == 1 ? '' : 's'}'),
        children: areas.map((area) {
          final basic = area['basicAreaSqFt'] as num?;
          final freqType = area['frequencyType'] as String?;
          final boqTimes = area['boqTimesPerPeriod'] as num?;
          final tendered = area['tenderedAreaPerDay'] as num?;
          final isItem = (area['measurementType'] as String?) == 'item';
          final hasBoq = basic != null || freqType != null;

          String freqLabel;
          if (freqType != null && boqTimes != null) {
            freqLabel = '$freqType ${boqTimes}x';
          } else {
            freqLabel = area['cleaningFrequency'] as String? ?? '-';
          }

          return ListTile(
            dense: true,
            title: Text(area['areaName'] ?? 'Unnamed'),
            subtitle: isItem
                ? Text('Item (no size) | Freq: $freqLabel | Billed by weightage')
                : hasBoq
                    ? Text('Basic: ${_num(basic)} sq.ft. | Freq: $freqLabel | Tendered: ${_num(tendered)}/day')
                    : Text('Freq: $freqLabel | Code: ${area['areaCode'] ?? '-'}'),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => onEdit(area),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BoqSectionTile extends StatelessWidget {
  final String mainArea;
  final List<BoqItem> items;
  final void Function(BoqItem item) onSelect;
  final void Function(List<BoqItem> items) onSelectAll;

  const _BoqSectionTile({
    required this.mainArea,
    required this.items,
    required this.onSelect,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    double totalBasic = 0;
    double totalTendered = 0;
    for (final i in items) {
      totalBasic += i.basicAreaSqFt;
      totalTendered += i.tenderedAreaPerDay;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text('$mainArea (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('Basic: ${_num(totalBasic)} sq.ft. | Tendered/day: ${_num(totalTendered)} sq.ft.'),
        children: [
          ...items.map((item) => ListTile(
            dense: true,
            title: Text(item.subArea, style: const TextStyle(fontSize: 13)),
            subtitle: Text('Basic: ${_num(item.basicAreaSqFt)} sq.ft. | Freq: ${item.frequencyType} ${item.boqTimesPerPeriod}x | Tendered: ${_num(item.tenderedAreaPerDay)}/day',
                style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20, color: kRailwayBlue),
              tooltip: 'Add this area',
              onPressed: () => onSelect(item),
            ),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onSelectAll(items),
                icon: const Icon(Icons.add_circle, size: 16),
                label: Text('Add All (${items.length})'),
                style: OutlinedButton.styleFrom(foregroundColor: kRailwayBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
