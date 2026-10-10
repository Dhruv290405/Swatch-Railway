import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../repositories/worker_repo.dart';
import '../../../utills/app_colors.dart';
import '../../common_workers/worker_rating_screen.dart' show RatingModel, kRatingParameters, SubmitRatingScreen;

class AdminRatingsScreen extends StatefulWidget {
  const AdminRatingsScreen({super.key});

  @override
  State<AdminRatingsScreen> createState() => _AdminRatingsScreenState();
}

class _AdminRatingsScreenState extends State<AdminRatingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<RatingModel> _ratings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Calls the same endpoint but without runInstanceId to fetch all summary data
      final res = await WorkerRepository.getFeedbackSummary();
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
      debugPrint('Error loading ratings for Admin: $e');
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

  // Include ratings from both 'Supervisor' and 'Admin' types, as well as combined label.
  List<RatingModel> get _supervisorRatings =>
      _ratings.where((r) =>
          r.raterType == 'Supervisor' ||
          r.raterType == 'Admin' ||
          r.raterType == 'Supervisor/Admin').toList();

  double get _avgOverall {
    if (_ratings.isEmpty) return 0;
    return _ratings.map((r) => r.overallRating).reduce((a, b) => a + b) /
        _ratings.length;
  }

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
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRatings,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Summary'),
            Tab(text: 'Passenger (${_passengerRatings.length})'),
            Tab(text: 'Official (${_officialRatings.length})'),
            Tab(text: 'Supervisor/Admin (${_supervisorRatings.length})'),
            Tab(text: 'TTE (${_tteRatings.length})'),
            Tab(text: 'PSME (${_psmeRatings.length})'),
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
            _buildRatingList(_supervisorRatings, 'Supervisor/Admin'),
            _buildRatingList(_tteRatings, 'TTE'),
            _buildRatingList(_psmeRatings, 'PSME'),
          ],
        ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SubmitRatingScreen(isOfficialMode: true),
            ),
          ).then((result) {
            if (result != null) {
              _loadRatings(); // Refresh if a rating was somehow submitted
            }
          });
        },
        backgroundColor: kRailwayBlue,
        icon: const Icon(Icons.star_outline, color: Colors.white),
        label: const Text(
          'Rate Coach',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Summary tab ─────────────────────────────────────────────────────────────

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall score card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kRailwayBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Rating',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _avgOverall.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildStarRow(_avgOverall, size: 16),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Parameter Breakdown
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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: kRatingParameters.map((param) {
                final key = param['key'] as String;
                final label = param['label'] as String;
                final icon = param['icon'] as IconData;

                // Calculate average for this specific parameter
                double sum = 0;
                int count = 0;
                for (final r in _ratings) {
                  if (r.parameterRatings.containsKey(key)) {
                    sum += r.parameterRatings[key]!;
                    count++;
                  }
                }
                final avg = count > 0 ? sum / count : 0.0;

                return _buildParameterBar(label, icon, avg);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarRow(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        IconData iconData;
        if (index < rating.floor()) {
          iconData = Icons.star;
        } else if (index == rating.floor() && rating % 1 > 0) {
          iconData = Icons.star_half;
        } else {
          iconData = Icons.star_border;
        }
        return Icon(
          iconData,
          color: Colors.amber,
          size: size,
        );
      }),
    );
  }

  Widget _buildParameterBar(String label, IconData icon, double avg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: kRailwayBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
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
              color: Colors.black.withOpacity(0.04),
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
                    ).withOpacity(0.12),
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
    final isPassenger = type == 'Passenger';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPassenger ? Colors.blue[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isPassenger ? Colors.blue[200]! : Colors.orange[200]!,
        ),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isPassenger ? Colors.blue[700] : Colors.orange[700],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color[200]!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color[700],
        ),
      ),
    );
  }

  // ── Rating Detail Bottom Sheet ──────────────────────────────────────────────

  void _showRatingDetail(RatingModel rating) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RatingDetailSheet(rating: rating),
    );
  }
}

class _RatingDetailSheet extends StatelessWidget {
  final RatingModel rating;

  const _RatingDetailSheet({required this.rating});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rating Details',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              
              // Key Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _detailItem('Coach', rating.coachId, Icons.train),
                  _detailItem('Source', rating.raterType, Icons.person),
                  _detailItem(
                    'Date',
                    DateFormat('dd MMM yyyy').format(rating.submittedAt),
                    Icons.calendar_today,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Overall Score
              Center(
                child: Column(
                  children: [
                    Text(
                      rating.overallRating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    _buildStarRow(rating.overallRating, size: 28),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Parameter Breakdown
              const Text(
                'Parameter Ratings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              ...kRatingParameters.map((param) {
                final key = param['key'] as String;
                final label = param['label'] as String;
                final icon = param['icon'] as IconData;
                final val = rating.parameterRatings[key] ?? 0.0;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(icon, size: 18, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      _buildStarRow(val, size: 14),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text(
                          val.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),

              // Remarks
              if (rating.remarks != null && rating.remarks!.isNotEmpty) ...[
                const Text(
                  'Remarks',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    rating.remarks!,
                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _detailItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildStarRow(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        IconData iconData;
        if (index < rating.floor()) {
          iconData = Icons.star;
        } else if (index == rating.floor() && rating % 1 > 0) {
          iconData = Icons.star_half;
        } else {
          iconData = Icons.star_border;
        }
        return Icon(iconData, color: Colors.amber, size: size);
      }),
    );
  }
}
