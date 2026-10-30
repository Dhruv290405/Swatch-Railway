import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../../controllers/worker_controller.dart';
import '../../repositories/worker_repo.dart';
import '../../utills/app_colors.dart';

class WorkerTaskModel {
  final String taskId;
  final String taskName;
  final String category;
  final String coachId;
  final String frequencyIndex;
  final String originalTaskType;
  final DateTime? dueTime;
  final String status;
  final bool requiresPhoto;
  final bool requiresComment;
  final String taskSource;

  WorkerTaskModel({
    required this.taskId,
    required this.taskName,
    required this.category,
    required this.coachId,
    required this.frequencyIndex,
    required this.originalTaskType,
    this.dueTime,
    required this.status,
    required this.requiresPhoto,
    required this.requiresComment,
    this.taskSource = 'SCHEDULED',
  });

  factory WorkerTaskModel.fromJson(Map<String, dynamic> json) {
    final taskType = (json['taskType'] ?? json['taskName'] ?? json['name'] ?? 'Task').toString();
    final coachNo = (json['coachNo'] ?? json['coachId'] ?? json['coachType'] ?? '').toString();
    final frequency = (json['frequencyIndex'] ?? json['frequency'] ?? json['slot'] ?? 'Hour 1').toString();

    return WorkerTaskModel(
      taskId: (json['uid'] ?? json['taskId'] ?? json['id'] ?? "$coachNo-$taskType-$frequency").toString(),
      taskName: coachNo.isEmpty ? taskType : "$taskType - Coach $coachNo",
      category: _categoryFromTaskType(taskType),
      coachId: coachNo,
      frequencyIndex: frequency,
      originalTaskType: taskType,
      dueTime: _parseDueTime(json['dueTime'] ?? json['dueAt'] ?? json['scheduledStartTime'] ?? json['scheduledTime'] ?? json['startTime'] ?? json['createdAt'] ?? json['timestamp']),
      status: _normalizeStatus(json),
      requiresPhoto: json['requiresPhoto'] as bool? ?? true,
      requiresComment: json['requiresComment'] as bool? ?? true,
      taskSource: (json['taskSource'] ?? json['source'] ?? 'SCHEDULED').toString().toUpperCase(),
    );
  }

  static String _categoryFromTaskType(String taskType) {
    final lower = taskType.toLowerCase();
    if (lower.contains('toilet')) return 'Toilet';
    if (lower.contains('garbage')) return 'Garbage';
    if (lower.contains('linen')) return 'Linen';
    if (lower.contains('security')) return 'Security';
    if (lower.contains('water')) return 'Water';
    return taskType;
  }

  static DateTime? _parseDueTime(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }
    if (value is int) {
      if (value < 10000000000) return DateTime.fromMillisecondsSinceEpoch(value * 1000).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }
    return null;
  }

  static String _normalizeStatus(Map<String, dynamic> json) {
    final raw = (json['status'] ?? json['state'] ?? '').toString().toLowerCase();
    final completed = json['completed'] == true || json['isCompleted'] == true || json['submitted'] == true || json['isSubmitted'] == true || json['taskStatus']?.toString().toLowerCase() == 'completed';
    if (completed || raw.contains('complete') || raw.contains('done')) return 'Completed';
    if (raw.contains('overdue') || json['isOverdue'] == true) return 'Overdue';
    if (raw.contains('upcoming')) return 'Upcoming';
    final dueAt = _parseDueTime(json['dueTime'] ?? json['dueAt']);
    if (dueAt != null && dueAt.isBefore(DateTime.now())) return 'Overdue';
    return 'Due';
  }
}

class WorkerTaskScreen extends StatefulWidget {
  const WorkerTaskScreen({super.key});

  @override
  State<WorkerTaskScreen> createState() => _WorkerTaskScreenState();
}

class _WorkerTaskScreenState extends State<WorkerTaskScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<WorkerTaskModel> tasks = [];
  bool isLoadingTasks = false;
  bool hasLoadedTasks = false;
  String? tasksError;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<WorkerTaskModel> get dueTasks =>
      tasks.where((t) => t.status == 'Due').toList();
  List<WorkerTaskModel> get overdueTasks =>
      tasks.where((t) => t.status == 'Overdue').toList();
  List<WorkerTaskModel> get completedTasks =>
      tasks.where((t) => t.status == 'Completed').toList();
  List<WorkerTaskModel> get upcomingTasks =>
      tasks.where((t) => t.status == 'Upcoming').toList();
  List<WorkerTaskModel> get allTasks => tasks;

  Future<void> _loadTasksBoard(WorkerController controller) async {
    if (isLoadingTasks) return;

    try {
      setState(() {
        isLoadingTasks = true;
        tasksError = null;
      });

      final runInstanceId = await controller.resolveRunInstanceId();
      if (runInstanceId == null || runInstanceId.trim().isEmpty) {
        throw Exception('No run instance assigned for tasks.');
      }

      final response = await WorkerRepository.getObhsTasksBoard(
        runInstanceId: runInstanceId,
      );
      final parsedTasks = _parseTasksBoard(response);

      // Add passenger and emergency tasks
      for (final t in controller.complaintTasks) {
        try { parsedTasks.add(WorkerTaskModel.fromJson(t)); } catch (_) {}
      }
      for (final t in controller.emergencyTasks) {
        try { parsedTasks.add(WorkerTaskModel.fromJson(t)); } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        tasks = parsedTasks;
        hasLoadedTasks = true;
      });
      controller.syncTaskBoardCounts(
        due: dueTasks.length,
        overdue: overdueTasks.length,
        completed: completedTasks.length,
        upcoming: upcomingTasks.length,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        tasksError = e.toString().replaceAll('Exception: ', '');
        hasLoadedTasks = true;
      });
    } finally {
      if (mounted) {
        setState(() => isLoadingTasks = false);
      }
    }
  }

  List<WorkerTaskModel> _parseTasksBoard(Map<String, dynamic> response) {
    final rawTasks = <Map<String, dynamic>>[];

    void collect(dynamic value) {
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        final looksLikeTask =
            map.containsKey('taskType') ||
            map.containsKey('taskName') ||
            map.containsKey('coachNo') ||
            map.containsKey('frequencyIndex');
        if (looksLikeTask) {
          rawTasks.add(map);
          return;
        }
        for (final nested in map.values) {
          collect(nested);
        }
      }
    }

    collect(
      response['tasks'] ?? response['data'] ?? response['board'] ?? response,
    );
    
    final uniqueTasks = <String, WorkerTaskModel>{};
    for (final raw in rawTasks) {
      try {
        final task = WorkerTaskModel.fromJson(raw);
        // If there's already a task with this ID, prefer the one that is completed or more updated if possible,
        // but simply overwriting is usually fine because the completed status will be the same.
        // Actually, if one is 'Completed' and the other is 'Due', prefer 'Completed'.
        if (uniqueTasks.containsKey(task.taskId)) {
          final existing = uniqueTasks[task.taskId]!;
          if (task.status == 'Completed' && existing.status != 'Completed') {
            uniqueTasks[task.taskId] = task;
          } else if (task.status == 'Overdue' && existing.status == 'Due') {
            uniqueTasks[task.taskId] = task;
          }
        } else {
          uniqueTasks[task.taskId] = task;
        }
      } catch (e) {
        debugPrint('Error parsing task: $e');
      }
    }
    
    return uniqueTasks.values.toList();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Overdue':
        return kErrorRed;
      case 'Due':
        return kWarningOrange;
      case 'Upcoming':
        return Colors.blue;
      case 'Completed':
        return kSuccessGreen;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Security':
        return Icons.security;
      case 'Toilet':
        return Icons.bathroom;
      case 'Garbage':
        return Icons.delete_rounded;
      case 'Linen':
        return Icons.local_laundry_service;
      case 'Water':
        return Icons.water_drop;
      default:
        return Icons.task_alt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WorkerController>();

    return Obx(() {
      if (!controller.startAttendance.value) {
        return const _StartAttendanceRequiredScreen(title: 'Work To Do');
      }

      if (!hasLoadedTasks && !isLoadingTasks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadTasksBoard(controller);
        });
      }

      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'Work To Do',
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
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Due (${dueTasks.length})'),
              Tab(text: 'Overdue (${overdueTasks.length})'),
              Tab(text: 'All (${allTasks.length})'),
            ],
          ),
        ),
        body: _buildTasksBody(controller),
      );
    });
  }

  Widget _buildTasksBody(WorkerController controller) {
    if (isLoadingTasks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tasksError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
              const SizedBox(height: 12),
              Text(
                tasksError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadTasksBoard(controller),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: kRailwayBlue,
      onRefresh: () => _loadTasksBoard(controller),
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(dueTasks, 'Due'),
          _buildTaskList(overdueTasks, 'Overdue'),
          _buildTaskList(allTasks, 'All'),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<WorkerTaskModel> taskList, String type) {
    if (taskList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_alt, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No $type tasks',
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
      padding: const EdgeInsets.all(12),
      itemCount: taskList.length,
      itemBuilder: (context, index) {
        final task = taskList[index];
        return _buildTaskCard(task);
      },
    );
  }

  Widget _buildTaskCard(WorkerTaskModel task) {
    final isCompleted = task.status == 'Completed';
    final isOverdue = task.status == 'Overdue';

    return GestureDetector(
      onTap: isCompleted
          ? null
          : () {
              _showTaskDetailDialog(task);
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOverdue
                ? kErrorRed.withValues(alpha: 0.3)
                : Colors.grey[300]!,
            width: isOverdue ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getStatusColor(task.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getCategoryIcon(task.category),
                    color: _getStatusColor(task.status),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.taskSource == 'PASSENGER' || task.taskSource == 'CTS')
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: task.taskSource == 'PASSENGER' ? Colors.orange.shade100 : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.taskSource == 'PASSENGER' ? 'Passenger Request' : 'Emergency Task',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: task.taskSource == 'PASSENGER' ? Colors.orange.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ),
                      Text(
                        task.taskName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.category,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(task.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _getStatusColor(task.status),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    task.status,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: _getStatusColor(task.status),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Details Row
            Row(
              children: [
                Icon(Icons.train_rounded, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Coach ${task.coachId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (task.dueTime != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('hh:mm a').format(task.dueTime!),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 10),

            // Evidence Requirements
            if (task.requiresPhoto || task.requiresComment) ...[
              Row(
                children: [
                  if (task.requiresPhoto)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue[300]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.photo_camera,
                              size: 13,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Photo',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (task.requiresPhoto && task.requiresComment)
                    const SizedBox(width: 8),
                  if (task.requiresComment)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.purple[300]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.comment,
                              size: 13,
                              color: Colors.purple[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Comment',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Action Button
            if (!isCompleted)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _showTaskDetailDialog(task);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kRailwayBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Start Task',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: kSuccessGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: kSuccessGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: kSuccessGreen, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Completed',
                      style: TextStyle(
                        color: kSuccessGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showTaskDetailDialog(WorkerTaskModel task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return TaskExecutionBottomSheet(task: task);
      },
    ).then((submitted) {
      if (submitted == true && mounted) {
        _loadTasksBoard(Get.find<WorkerController>());
      }
    });
  }
}

class _StartAttendanceRequiredScreen extends StatelessWidget {
  final String title;

  const _StartAttendanceRequiredScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: kRailwayBlue,
        elevation: 0.5,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_clock, color: Colors.orange.shade700, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Start attendance required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mark Start Attendance from Home to view your assigned tasks.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskExecutionBottomSheet extends StatefulWidget {
  final WorkerTaskModel task;

  const TaskExecutionBottomSheet({super.key, required this.task});

  @override
  State<TaskExecutionBottomSheet> createState() =>
      _TaskExecutionBottomSheetState();
}

class _TaskExecutionBottomSheetState extends State<TaskExecutionBottomSheet> {
  int currentStep =
      0; // 0: Before Photo, 1: Comments, 2: After Photo, 3: Submit

  TextEditingController commentController = TextEditingController();
  XFile? beforePhoto;
  XFile? afterPhoto;
  bool isSubmitting = false;
  final ScrollController _scrollController = ScrollController();
  final FocusNode _commentFocusNode = FocusNode();

  @override
  void dispose() {
    commentController.dispose();
    _scrollController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: SingleChildScrollView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.task.taskName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Coach ${widget.task.coachId}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
            const SizedBox(height: 20),
            // Progress Indicator
            _buildProgressIndicator(),
            const SizedBox(height: 20),
            // Content
            if (currentStep == 0)
              _buildBeforePhotoStep()
            else if (currentStep == 1)
              _buildCommentStep()
            else if (currentStep == 2)
              _buildAfterPhotoStep()
            else
              _buildSummaryStep(),
            const SizedBox(height: 20),
            // Action Buttons
            Row(
              children: [
                if (currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => currentStep--);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.grey),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                if (currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canProceed() && !isSubmitting
                        ? () {
                            FocusScope.of(context).unfocus();
                            if (currentStep < 3) {
                              setState(() => currentStep++);
                            } else {
                              _submitTask();
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kRailwayBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      isSubmitting
                          ? 'Submitting...'
                          : currentStep == 3
                          ? 'Submit Task'
                          : 'Next',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final steps = ['Before Photo', 'Comments', 'After Photo', 'Submit'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${currentStep + 1} of ${steps.length}',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(
            steps.length,
            (index) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(
                  right: index < steps.length - 1 ? 8 : 0,
                ),
                decoration: BoxDecoration(
                  color: index <= currentStep ? kRailwayBlue : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBeforePhotoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Capture Before Photo',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        if (beforePhoto != null)
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: FileImage(File(beforePhoto!.path)),
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () => _captureTaskPhoto(isBefore: true),
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to take photo',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCommentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add Comments',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: commentController,
          focusNode: _commentFocusNode,
          minLines: 3,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Enter your comments here (Hinglish allowed)...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(12),
          ),
          onTap: () => WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }),
        ),
        const SizedBox(height: 12),
        Text(
          'Character count: ${commentController.text.length}',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildAfterPhotoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Capture After Photo',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        if (afterPhoto != null)
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: FileImage(File(afterPhoto!.path)),
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () => _captureTaskPhoto(isBefore: false),
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to take photo',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Review & Submit',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: kSuccessGreen, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Task Summary',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: kSuccessGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _summaryItem('Task', widget.task.taskName),
              _summaryItem('Coach', widget.task.coachId),
              _summaryItem('Before Photo', 'Captured ✓'),
              _summaryItem(
                'Comments',
                commentController.text.isEmpty
                    ? 'Pending'
                    : commentController.text,
              ),
              _summaryItem('After Photo', 'Captured ✓'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    if (currentStep == 0) return beforePhoto != null;
    if (currentStep == 1) return commentController.text.isNotEmpty;
    if (currentStep == 2) return afterPhoto != null;
    return true;
  }

  Future<void> _captureTaskPhoto({required bool isBefore}) async {
    FocusScope.of(context).unfocus();
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1280,
    );

    if (photo == null) return;

    setState(() {
      if (isBefore) {
        beforePhoto = photo;
      } else {
        afterPhoto = photo;
      }
    });
  }

  Future<void> _submitTask() async {
    try {
      setState(() => isSubmitting = true);

      final controller = Get.find<WorkerController>();
      final runInstanceId = await controller.resolveRunInstanceId();
      if (runInstanceId == null || runInstanceId.trim().isEmpty) {
        throw Exception('No run instance assigned for task submit.');
      }
      final beforeUrl = await WorkerRepository.uploadMedia(beforePhoto!.path);
      final afterUrl = await WorkerRepository.uploadMedia(afterPhoto!.path);

      // Fetch GPS for evidence
      double? lat;
      double? lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (gpsErr) {
        debugPrint('GPS Fetch ignored for task: $gpsErr');
      }

      final response = await WorkerRepository.submitObhsTask(
        runInstanceId: runInstanceId,
        taskId: widget.task.taskId,
        taskType: widget.task.originalTaskType,
        coachNo: widget.task.coachId,
        frequencyIndex: widget.task.frequencyIndex,
        beforePhoto: beforeUrl,
        afterPhoto: afterUrl,
        comment: commentController.text.trim(),
        gpsLatitude: lat,
        gpsLongitude: lng,
      );

      if (response['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task submitted successfully!'),
            backgroundColor: kSuccessGreen,
          ),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception(response['message'] ?? 'Task submit failed.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: kErrorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }
}
