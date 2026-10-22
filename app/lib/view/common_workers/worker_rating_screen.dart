import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../controllers/worker_controller.dart';
import '../../repositories/worker_repo.dart';
import '../../repositories/obhs_repository.dart';
import '../../model/railway_worker_model.dart';
import '../../services/api_services.dart';
import '../../services/passenger_service.dart';
import '../../utills/app_colors.dart';

// ─── Model ───────────────────────────────────────────────────────────────────

class RatingModel {
  final String ratingId;
  final String coachId;
  final String raterType; // 'Passenger' | 'Official'
  final double overallRating;
  final Map<String, double> parameterRatings;
  final String? remarks;
  final bool hasPhoto;
  final bool isRandomInspection;
  final DateTime submittedAt;
  final String? inspectorName;
  final String? passengerName;
  final String? pnrNumber;
  final String? mobileNumber;

  RatingModel({
    required this.ratingId,
    required this.coachId,
    required this.raterType,
    required this.overallRating,
    required this.parameterRatings,
    this.remarks,
    this.hasPhoto = false,
    this.isRandomInspection = false,
    required this.submittedAt,
    this.inspectorName,
    this.passengerName,
    this.pnrNumber,
    this.mobileNumber,
  });

  factory RatingModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawRatings = json['ratings'] ?? {};
    final Map<String, double> parsedRatings = {};
    rawRatings.forEach((k, v) => parsedRatings[k] = (v as num).toDouble());

    double overall = 0;
    if (parsedRatings.isNotEmpty) {
      overall = parsedRatings.values.reduce((a, b) => a + b) / parsedRatings.length;
    }

    return RatingModel(
      ratingId: json['feedbackId']?.toString() ?? json['_id']?.toString() ?? json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      coachId: json['coachNo']?.toString() ?? 'Unknown',
      raterType: json['raterType']?.toString() ?? (json['passengerName'] != null ? 'Passenger' : 'Official'),
      overallRating: json['overallRating'] != null ? (json['overallRating'] as num).toDouble() : overall,
      parameterRatings: parsedRatings,
      remarks: json['remarks']?.toString(),
      hasPhoto: json['photoUrl'] != null && json['photoUrl'].toString().isNotEmpty,
      isRandomInspection: json['isRandomInspection'] == true,
      submittedAt: DateTime.tryParse(json['createdAt']?.toString() ?? json['date']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      inspectorName: json['inspectorName']?.toString(),
      passengerName: json['passengerName']?.toString(),
      pnrNumber: json['pnrNumber']?.toString(),
      mobileNumber: json['mobileNumber']?.toString(),
    );
  }
}

// ─── Configurable rating parameters ──────────────────────────────────────────

const List<Map<String, dynamic>> kRatingParameters = [
  {'key': 'cleanliness', 'label': 'Cleanliness', 'icon': Icons.cleaning_services},
  {'key': 'toiletHygiene', 'label': 'Toilet Hygiene', 'icon': Icons.bathroom},
  {'key': 'linenQuality', 'label': 'Linen Quality', 'icon': Icons.local_laundry_service},
  {'key': 'security', 'label': 'Security', 'icon': Icons.security},
  {'key': 'staffBehaviour', 'label': 'Staff Behaviour', 'icon': Icons.person},
];

// ─── Main Screen ─────────────────────────────────────────────────────────────

class WorkerRatingScreen extends StatefulWidget {
  /// Pass true when this screen is opened for an Official (role-gated).
  final bool isOfficialMode;

  const WorkerRatingScreen({super.key, this.isOfficialMode = false});

  @override
  State<WorkerRatingScreen> createState() => _WorkerRatingScreenState();
}

class _WorkerRatingScreenState extends State<WorkerRatingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<RatingModel> _ratings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.isOfficialMode ? 6 : 3, vsync: this);
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final controller = Get.find<WorkerController>();
      final runInstanceId = await controller.resolveRunInstanceId();
      if (runInstanceId == null || runInstanceId.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final res = await WorkerRepository.getFeedbackSummary(runInstanceId: runInstanceId);
      final rawData = res['recentFeedbacks'] ?? res['data'] ?? [];
      final List<RatingModel> loaded = [];
      for (var item in rawData) {
        loaded.add(RatingModel.fromJson(item));
      }
      
      if (mounted) {
        setState(() {
          _ratings = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ratings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<RatingModel> get _passengerRatings =>
      _ratings.where((r) => r.raterType == 'Passenger').toList();

  List<RatingModel> get _officialRatings =>
      _ratings.where((r) => r.raterType == 'Official').toList();

  List<RatingModel> get _tteRatings =>
      _ratings.where((r) => r.raterType == 'TTE').toList();

  List<RatingModel> get _psmeRatings =>
      _ratings.where((r) => r.raterType == 'PSME').toList();

  List<RatingModel> get _supervisorRatings =>
      _ratings.where((r) => r.raterType == 'Supervisor/Admin').toList();


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Ratings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: kRailwayBlue,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          isScrollable: widget.isOfficialMode,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Summary'),
            Tab(text: 'Passenger (${_passengerRatings.length})'),
            Tab(text: 'Official (${_officialRatings.length})'),
            if (widget.isOfficialMode) ...[
              Tab(text: 'TTE (${_tteRatings.length})'),
              Tab(text: 'PSME (${_psmeRatings.length})'),
              Tab(text: 'Supervisor/Admin (${_supervisorRatings.length})'),
            ],
          ],
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : TabBarView(
          controller: _tabController,
          children: [
            _buildSummaryTab(),
            _buildRatingList(_passengerRatings, 'Passenger'),
            _buildRatingList(_officialRatings, 'Official'),
            if (widget.isOfficialMode) ...[
              _buildRatingList(_tteRatings, 'TTE'),
              _buildRatingList(_psmeRatings, 'PSME'),
              _buildRatingList(_supervisorRatings, 'Supervisor/Admin'),
            ],
          ],
        ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SubmitRatingScreen(isOfficialMode: widget.isOfficialMode),
            ),
          ).then((result) {
            if (result is RatingModel) {
              setState(() => _ratings.insert(0, result));
            }
          });
        },
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.star_outline, color: Colors.white),
        label: Text(
          widget.isOfficialMode ? 'Inspect Coach' : 'Rate Coach',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Summary tab ─────────────────────────────────────────────────────────────

  double _avgForType(List<RatingModel> list) {
    if (list.isEmpty) return 0;
    return list.map((r) => r.overallRating).reduce((a, b) => a + b) / list.length;
  }

  double get _weightedAggregatedScore {
    // Weighted aggregation: Passenger(40%) + Official(25%) + Supervisor/Admin(20%) + TTE(10%) + PSME(5%)
    final pasAvg  = _avgForType(_passengerRatings);
    final offAvg  = _avgForType(_officialRatings);
    final supAvg  = _avgForType(_supervisorRatings);
    final tteAvg  = _avgForType(_tteRatings);
    final psmeAvg = _avgForType(_psmeRatings);

    final hasAny = _passengerRatings.isNotEmpty ||
        _officialRatings.isNotEmpty ||
        _supervisorRatings.isNotEmpty ||
        _tteRatings.isNotEmpty ||
        _psmeRatings.isNotEmpty;
    if (!hasAny) return 0;

    // Proportional weight: only count non-empty groups
    double totalWeight = 0;
    double totalScore = 0;
    if (_passengerRatings.isNotEmpty)  { totalScore += pasAvg  * 0.40; totalWeight += 0.40; }
    if (_officialRatings.isNotEmpty)   { totalScore += offAvg  * 0.25; totalWeight += 0.25; }
    if (_supervisorRatings.isNotEmpty) { totalScore += supAvg  * 0.20; totalWeight += 0.20; }
    if (_tteRatings.isNotEmpty)        { totalScore += tteAvg  * 0.10; totalWeight += 0.10; }
    if (_psmeRatings.isNotEmpty)       { totalScore += psmeAvg * 0.05; totalWeight += 0.05; }
    return totalWeight > 0 ? totalScore / totalWeight : 0;
  }

  Widget _buildSummaryTab() {
    final supervisorAvg = _avgForType(_supervisorRatings);
    final officialAvg = _avgForType(_officialRatings);
    final tteAvg = _avgForType(_tteRatings);
    final psmeAvg = _avgForType(_psmeRatings);
    final passengerAvg = _avgForType(_passengerRatings);
    final weighted = _weightedAggregatedScore;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Weighted Aggregation Score Card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xff1f4e78), Color(0xff2e75b6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0,4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Weighted Aggregated Score', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(weighted.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('/5', style: TextStyle(color: Colors.white70, fontSize: 18))),
                  ],
                ),
                _buildStarRow(weighted, size: 18, color: Colors.amber),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Parameter breakdown
          const Text(
            'Parameter Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: kRatingParameters.map((param) {
                final avg = _computeParamAvg(param['key'] as String);
                return _buildParameterRow(param, avg);
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // Recent ratings
          const Text(
            'Recent Ratings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          ..._ratings.take(3).map((r) => _buildRatingCard(r)),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  double _computeParamAvg(String key) {
    final vals = _ratings
        .where((r) => r.parameterRatings.containsKey(key))
        .map((r) => r.parameterRatings[key]!)
        .toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  Widget _buildRaterScoreCard(String label, double avg, Color color, int count, String weight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Center(
              child: Text(
                avg.toStringAsFixed(1),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                Text('$count reviews · weight $weight', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: avg / 5,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterRow(Map<String, dynamic> param, double avg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              param['icon'] as IconData,
              size: 16,
              color: kRailwayBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      param['label'] as String,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      avg.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: avg / 5,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      avg >= 4
                          ? kSuccessGreen
                          : avg >= 3
                          ? kWarningOrange
                          : kErrorRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rating list tab ──────────────────────────────────────────────────────────

  Widget _buildRatingList(List<RatingModel> list, String type) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No $type ratings yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: list.length,
      itemBuilder: (_, i) => _buildRatingCard(list[i]),
    );
  }

  Widget _buildRatingCard(RatingModel rating) {
    return GestureDetector(
      onTap: () => _showRatingDetail(rating),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Rating circle
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _ratingColor(
                      rating.overallRating,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      rating.overallRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _ratingColor(rating.overallRating),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildRatingBadge(rating.raterType),
                          if (rating.isRandomInspection) ...[
                            const SizedBox(width: 6),
                            _buildBadge('Random', Colors.purple),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildStarRow(rating.overallRating, size: 14),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.train_rounded,
                          size: 13,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Coach ${rating.coachId}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('hh:mm a').format(rating.submittedAt),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
            if (rating.remarks != null && rating.remarks!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.format_quote, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rating.remarks!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (rating.hasPhoto) _buildBadge('Photo', Colors.blue),
                if (rating.inspectorName != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.badge, size: 13, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    rating.inspectorName!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                if (rating.passengerName != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.person, size: 13, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      rating.passengerName!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Icon(Icons.chevron_right, size: 16, color: Colors.grey[400]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _ratingColor(double rating) {
    if (rating >= 4) return kSuccessGreen;
    if (rating >= 3) return kWarningOrange;
    return kErrorRed;
  }

  Widget _buildRatingBadge(String type) {
    final Color badgeColor;
    switch (type) {
      case 'Official':       badgeColor = Colors.purple;     break;
      case 'TTE':            badgeColor = Colors.teal;       break;
      case 'PSME':           badgeColor = Colors.orange;     break;
      case 'Supervisor/Admin': badgeColor = Colors.deepPurple; break;
      default:               badgeColor = Colors.blue;       break; // Passenger
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        type,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: badgeColor),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStarRow(
    double rating, {
    double size = 16,
    Color color = Colors.amber,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.floor();
        final half = !filled && (rating - i) >= 0.5;
        return Icon(
          filled
              ? Icons.star_rounded
              : half
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          size: size,
          color: color,
        );
      }),
    );
  }

  void _showRatingDetail(RatingModel rating) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RatingDetailSheet(rating: rating),
    );
  }
}

// ─── Detail Bottom Sheet ──────────────────────────────────────────────────────

class _RatingDetailSheet extends StatelessWidget {
  final RatingModel rating;
  const _RatingDetailSheet({required this.rating});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        padding: const EdgeInsets.all(24),
        child: ListView(
          controller: controller,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coach ${rating.coachId}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat(
                          'dd MMM yyyy, hh:mm a',
                        ).format(rating.submittedAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Badges row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _badge(
                  rating.raterType,
                  rating.raterType == 'Official' ? Colors.purple
                    : rating.raterType == 'TTE' ? Colors.teal
                    : rating.raterType == 'PSME' ? Colors.orange
                    : rating.raterType == 'Supervisor/Admin' ? Colors.deepPurple
                    : Colors.blue,
                ),
                if (rating.isRandomInspection)
                  _badge('Random Inspection', Colors.orange),
                if (rating.hasPhoto) _badge('Photo Attached', Colors.teal),
              ],
            ),

            const SizedBox(height: 20),

            // Big rating
            Center(
              child: Column(
                children: [
                  Text(
                    rating.overallRating.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: _color(rating.overallRating),
                    ),
                  ),
                  _stars(rating.overallRating),
                  const SizedBox(height: 4),
                  Text(
                    'Overall Rating',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Parameter Wise',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            ...kRatingParameters.map((p) {
              final val = rating.parameterRatings[p['key']] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      p['icon'] as IconData,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p['label'] as String,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    _stars(val.toDouble(), size: 14),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 24,
                      child: Text(
                        val.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            if (rating.remarks != null && rating.remarks!.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                'Remarks',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                rating.remarks!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ],

            if (rating.inspectorName != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Inspector: ${rating.inspectorName}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ],

            if (rating.passengerName != null ||
                rating.pnrNumber != null ||
                rating.mobileNumber != null) ...[
              const Divider(height: 24),
              const Text(
                'Passenger Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              if (rating.passengerName != null)
                _detailRow(Icons.person, 'Name', rating.passengerName!),
              if (rating.pnrNumber != null)
                _detailRow(Icons.confirmation_number, 'PNR', rating.pnrNumber!),
              if (rating.mobileNumber != null)
                _detailRow(Icons.phone_android, 'Mobile', rating.mobileNumber!),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Color _color(double r) => r >= 4
      ? kSuccessGreen
      : r >= 3
      ? kWarningOrange
      : kErrorRed;

  Widget _stars(double r, {double size = 20}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < r.floor();
        final half = !filled && (r - i) >= 0.5;
        return Icon(
          filled
              ? Icons.star_rounded
              : half
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          size: size,
          color: Colors.amber,
        );
      }),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

// ─── Submit Rating Screen ─────────────────────────────────────────────────────

class SubmitRatingScreen extends StatefulWidget {
  final bool isOfficialMode;

  const SubmitRatingScreen({super.key, this.isOfficialMode = false});

  @override
  State<SubmitRatingScreen> createState() => _SubmitRatingScreenState();
}

class _SubmitRatingScreenState extends State<SubmitRatingScreen> {
  // Train + coach selection (passenger mode)
  final TextEditingController _trainNoController = TextEditingController();
  final FocusNode _trainFocusNode = FocusNode();
  List<String> _availableCoaches = [];
  bool _isFetchingCoaches = false;

  String? _selectedCoach;
  double _overallRating = 0;
  final Map<String, double> _paramRatings = {};
  final TextEditingController _remarksController = TextEditingController();
  File? _photoFile;
  bool _isRandomInspection = false;
  bool _isSubmitting = false;
  String _selectedRaterType = 'Official'; // For official mode
  final TextEditingController _inspectorController = TextEditingController();
  final TextEditingController _passengerNameController =
      TextEditingController();

  List<RailwayWorkerModel> _workers = [];
  String? _selectedWorkerId;
  bool _isLoadingWorkers = false;

  List<String> _officialCoaches = [];
  bool _isFetchingOfficialCoaches = false;

  @override
  void initState() {
    super.initState();
    if (widget.isOfficialMode) {
      _fetchWorkers();
    } else {
      _trainFocusNode.addListener(_onTrainFocusChange);
    }
  }

  void _onTrainFocusChange() async {
    if (!_trainFocusNode.hasFocus && _trainNoController.text.trim().isNotEmpty) {
      setState(() {
        _isFetchingCoaches = true;
        _selectedCoach = null;
        _availableCoaches = [];
      });
      try {
        final coaches = await PassengerService.fetchCoachesForTrain(
            _trainNoController.text.trim());
        if (mounted) {
          setState(() {
            _availableCoaches = coaches;
          });
        }
      } catch (e) {
        debugPrint('Failed to fetch coaches: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not fetch coaches: try again.'),
              backgroundColor: kErrorRed,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isFetchingCoaches = false);
      }
    }
  }

  Future<void> _fetchOfficialCoachesForWorker(String workerId) async {
    if (workerId.isEmpty) return;
    if (mounted) {
      setState(() {
        _isFetchingOfficialCoaches = true;
        _officialCoaches = [];
        _selectedCoach = null;
      });
    }

    try {
      final assignment = await WorkerRepository.getRunAssignmentForWorker(workerId);
      final rawCoaches = assignment['coaches'] as List? ?? [];
      final attached = <String>{};
      for (final raw in rawCoaches) {
        if (raw is! Map) continue;
        final coach = Map<String, dynamic>.from(raw);
        final janitorId = (coach['janitorId'] ?? coach['workerId'])?.toString();
        final attendantId = coach['attendantId']?.toString();
        if (janitorId != workerId && attendantId != workerId) continue;

        final label = (coach['coachPosition'] ?? coach['coachNo'] ?? coach['coachType'])
            ?.toString()
            .trim();
        if (label != null && label.isNotEmpty) attached.add(label);
      }

      if (mounted && _selectedWorkerId == workerId) {
        final coaches = attached.toList()..sort();
        setState(() {
          _officialCoaches = coaches;
          if (coaches.length == 1) _selectedCoach = coaches.first;
        });
      }
    } catch (e) {
      debugPrint('Could not load coaches assigned to $workerId: $e');
    } finally {
      if (mounted && _selectedWorkerId == workerId) {
        setState(() => _isFetchingOfficialCoaches = false);
      }
    }
  }

  Future<void> _fetchWorkers() async {
    setState(() => _isLoadingWorkers = true);
    try {
      final workers = await OBHSRepository.getRailwayWorkers();
      if (mounted) {
        setState(() {
          _workers = workers;

          // Pre-select the logged-in worker
          if (Get.isRegistered<WorkerController>()) {
            final controller = Get.find<WorkerController>();
            final loggedInUid = controller.workerProfile.value?.uid ?? controller.currentUser.value?.uid;
            if (loggedInUid != null && loggedInUid.isNotEmpty) {
              final hasWorker = workers.any((w) => w.uid == loggedInUid);
              if (hasWorker) {
                _selectedWorkerId = loggedInUid;
              } else {
                final name = controller.workerName;
                final email = controller.workerEmail;
                final mobile = controller.workerPhone;
                final role = controller.workerRole;
                final status = controller.workerStatus;
                final userType = controller.currentUser.value?.userType ?? 'worker';
                final me = RailwayWorkerModel(
                  uid: loggedInUid,
                  email: email,
                  fullName: name.isNotEmpty ? name : 'Worker',
                  mobile: mobile,
                  role: role,
                  status: status,
                  userType: userType,
                );
                _workers.add(me);
                _selectedWorkerId = loggedInUid;
              }

              // Also pre-select inspector name with logged-in user name if empty
              if (_inspectorController.text.trim().isEmpty) {
                _inspectorController.text = controller.workerName.isNotEmpty ? controller.workerName : 'Worker';
              }

            }
          }
        });
        if (_selectedWorkerId != null) {
          await _fetchOfficialCoachesForWorker(_selectedWorkerId!);
        }
      }
    } catch (e) {
      debugPrint('Error fetching workers: $e');
    } finally {
      if (mounted) setState(() => _isLoadingWorkers = false);
    }
  }


  @override
  void dispose() {
    _trainFocusNode.removeListener(_onTrainFocusChange);
    _trainFocusNode.dispose();
    _trainNoController.dispose();
    _remarksController.dispose();
    _inspectorController.dispose();
    _passengerNameController.dispose();
    super.dispose();
  }

  bool _canSubmit() {
    if (_selectedCoach == null) return false;
    if (_overallRating == 0) return false;
    if (widget.isOfficialMode) {
      if (_inspectorController.text.trim().isEmpty) return false;
      if (_selectedWorkerId == null) return false;
    } else {
      if (_passengerNameController.text.trim().isEmpty) return false;
      if (_trainNoController.text.trim().isEmpty) return false;
    }
    return true;
  }

  void _computeAutoOverall() {
    if (_paramRatings.length == kRatingParameters.length) {
      final avg =
          _paramRatings.values.reduce((a, b) => a + b) / _paramRatings.length;
      setState(() => _overallRating = double.parse(avg.toStringAsFixed(1)));
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (picked != null) {
        setState(() => _photoFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error capturing photo: $e');
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      String? runInstanceId;
      if (Get.isRegistered<WorkerController>()) {
        final controller = Get.find<WorkerController>();
        runInstanceId = await controller.resolveRunInstanceId();
      }

      if (!widget.isOfficialMode && (runInstanceId == null || runInstanceId.isEmpty)) {
        throw Exception('No active run instance.');
      }

      String? photoUrl;
      if (_photoFile != null) {
        photoUrl = await WorkerRepository.uploadMedia(_photoFile!.path);
      }

      final Map<String, int> intRatings = {};
      _paramRatings.forEach((k, v) => intRatings[k] = v.toInt());

      Map<String, dynamic> res;
      if (widget.isOfficialMode) {
        final worker = _workers.firstWhere((w) => w.uid == _selectedWorkerId);
        res = await WorkerRepository.submitOfficialFeedback(
          inspectorName: _inspectorController.text.trim(),
          isRandomInspection: _isRandomInspection,
          workerId: _selectedWorkerId!,
          workerName: worker.fullName,
          coachNo: _selectedCoach!,
          raterType: _selectedRaterType,
          ratings: intRatings,
          remarks: _remarksController.text.trim(),
          photoUrl: photoUrl,
          runInstanceId: runInstanceId,
        );
      } else {
        res = await WorkerRepository.submitPassengerFeedback(
          passengerName: _passengerNameController.text.trim(),
          coachNo: _selectedCoach!,
          ratings: intRatings,
          remarks: _remarksController.text.trim(),
          photoUrl: photoUrl,
          runInstanceId: runInstanceId!,
          workerId: _selectedWorkerId,
        );
      }

      final rating = RatingModel.fromJson(res['data'] ?? res);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating submitted successfully!'),
          backgroundColor: kSuccessGreen,
        ),
      );
      Navigator.pop(context, rating);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: kErrorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.isOfficialMode ? 'Coach Inspection' : 'Rate Coach',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: kRailwayBlue,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Official mode: Random Inspection toggle
            if (widget.isOfficialMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _isRandomInspection
                      ? Colors.purple.shade50
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isRandomInspection
                        ? Colors.purple.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shuffle,
                      color: _isRandomInspection
                          ? Colors.purple
                          : Colors.grey[600],
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Random Inspection',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'Mark this as an unannounced check',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isRandomInspection,
                      onChanged: (v) => setState(() => _isRandomInspection = v),
                      activeThumbColor: Colors.purple,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Rater Type Dropdown
              _sectionTitle('Rater Type'),
              const SizedBox(height: 8),
              _inputContainer(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRaterType != null && ['Official', 'TTE', 'PSME', 'Supervisor/Admin'].contains(_selectedRaterType) ? _selectedRaterType : null,
                    isExpanded: true,
                    items: ['Official', 'TTE', 'PSME', 'Supervisor/Admin']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedRaterType = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Inspector name
              _sectionTitle('Inspector Name'),
              const SizedBox(height: 8),
              _inputContainer(
                child: TextField(
                  controller: _inspectorController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Enter your name / TTE ID',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Select Worker Dropdown
              _sectionTitle('Select Worker'),
              const SizedBox(height: 8),
              _inputContainer(
                child: _isLoadingWorkers 
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Loading workers...', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedWorkerId != null && _workers.any((w) => w.uid == _selectedWorkerId) ? _selectedWorkerId : null,
                    hint: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Choose worker'),
                    ),
                    items: _workers.map((w) {
                      return DropdownMenuItem<String>(
                        value: w.uid,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('${w.fullName} (${w.userType})'),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedWorkerId = val;
                        _selectedCoach = null;
                        _officialCoaches = [];
                        _overallRating = 0;
                        _paramRatings.clear();
                      });
                      if (val != null) _fetchOfficialCoachesForWorker(val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (!widget.isOfficialMode) ...[
              _sectionTitle('Passenger Details'),
              const SizedBox(height: 8),
              _inputContainer(
                child: TextField(
                  controller: _passengerNameController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Passenger name',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Train number (triggers coach fetch on focus-out) ──
              _sectionTitle('Train Number'),
              const SizedBox(height: 8),
              _inputContainer(
                child: TextField(
                  controller: _trainNoController,
                  focusNode: _trainFocusNode,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. 12345',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                    prefixIcon: const Icon(Icons.train),
                    suffixIcon: _isFetchingCoaches
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Coach selection
            _sectionTitle('Select Coach'),
            const SizedBox(height: 8),
            // Passenger: dynamic list from train API; Official: free-text or fixed list
            if (!widget.isOfficialMode)
              _inputContainer(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCoach != null && _availableCoaches.contains(_selectedCoach) ? _selectedCoach : null,
                    hint: Text(
                      _trainNoController.text.trim().isEmpty
                          ? 'Enter train number first'
                          : _availableCoaches.isEmpty && !_isFetchingCoaches
                              ? 'No coaches found – check train number'
                              : 'Choose a coach',
                    ),
                    isExpanded: true,
                    items: _availableCoaches
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: _availableCoaches.isEmpty
                        ? null
                        : (v) => setState(() => _selectedCoach = v),
                  ),
                ),
              )
            else
              _inputContainer(
                child: _isFetchingOfficialCoaches
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Loading coaches...', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCoach != null && _officialCoaches.contains(_selectedCoach) ? _selectedCoach : null,
                          hint: Text(
                            _selectedWorkerId == null
                                ? 'Select a worker first'
                                : _officialCoaches.isEmpty && !_isFetchingOfficialCoaches
                                    ? 'No coaches attached to this worker'
                                    : 'Choose an assigned coach',
                          ),
                          isExpanded: true,
                          items: _officialCoaches
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedCoach = v),
                        ),
                      ),
              ),

            const SizedBox(height: 20),

            // Parameter ratings
            _sectionTitle('Rate Each Parameter'),
            const SizedBox(height: 4),
            Text(
              'Overall rating auto-fills when all parameters are rated.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: kRatingParameters.map((param) {
                  return _buildParamRater(param);
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // Overall rating
            _sectionTitle('Overall Rating'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      return GestureDetector(
                        onTap: () {
                          setState(() => _overallRating = (i + 1).toDouble());
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            i < _overallRating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 40,
                            color: Colors.amber,
                          ),
                        ),
                      );
                    }),
                  ),
                  if (_overallRating > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      _overallRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _ratingColor(_overallRating),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Remarks
            _sectionTitle('Remarks (optional • Hinglish allowed)'),
            const SizedBox(height: 8),
            _inputContainer(
              child: TextField(
                controller: _remarksController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Add any additional remarks...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Photo
            _sectionTitle(
              widget.isOfficialMode
                  ? 'Proof Photo (mandatory)'
                  : 'Attach Photo (optional)',
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _capturePhoto,
              child: Container(
                width: double.infinity,
                height: 130,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _photoFile != null
                        ? Colors.green.shade300
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: _photoFile != null ? Colors.green.shade50 : Colors.grey[50],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _photoFile != null ? Icons.check_circle : Icons.add_a_photo,
                      size: 40,
                      color: _photoFile != null
                          ? Colors.green.shade600
                          : Colors.grey[500],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _photoFile != null ? 'Photo captured' : 'Tap to capture',
                      style: TextStyle(
                        fontSize: 13,
                        color: _photoFile != null
                            ? Colors.green.shade600
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting || !_canSubmit() ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kRailwayBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Rating',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildParamRater(Map<String, dynamic> param) {
    final key = param['key'] as String;
    final currentVal = _paramRatings[key] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(param['icon'] as IconData, size: 18, color: kRailwayBlue),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: Text(
              param['label'] as String,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: List.generate(5, (i) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _paramRatings[key] = (i + 1).toDouble();
                    });
                    _computeAutoOverall();
                  },
                  child: Icon(
                    i < currentVal
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 26,
                    color: Colors.amber,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Color _ratingColor(double r) => r >= 4
      ? kSuccessGreen
      : r >= 3
      ? kWarningOrange
      : kErrorRed;

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 14,
      color: Colors.black87,
    ),
  );

  Widget _inputContainer({required Widget child}) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: child,
  );
}
