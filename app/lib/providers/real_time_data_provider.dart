import 'dart:async';
import 'package:crm_train/services/api_services.dart';

/// Provider class for handling real-time data from WebSockets and other real-time sources.
/// Handles events like taskStatusChanged, complaintCreated, and other real-time updates.
class RealTimeDataProvider {
  // TODO: Define ApiServices or remove this field
// final ApiServices _apiServices = ApiServices();

  /// Stream controller for task status changes
  final _taskStatusController = StreamController<String>.broadcast();
  Stream<String> get taskStatusStream => _taskStatusController.stream;

  /// Stream controller for complaint creation events
  final _complaintCreatedController = StreamController<String>.broadcast();
  Stream<String> get complaintCreatedStream => _complaintCreatedController.stream;

  /// Initialize the provider and set up listeners
  initilazeListeners() {
    // Set up WebSocket listeners or other real-time connections here
  }

  /// Call when a task status changes
  void onTaskStatusChanged(String taskId, String newStatus) {
    _taskStatusController.sink.add('$taskId:$newStatus');
    // Additional logic can be added here
  }

  /// Call when a new complaint is created
  void onComplaintCreated(String complaintId) {
    _complaintCreatedController.sink.add(complaintId);
    // Additional logic can be added here
  }

  /// Dispose of controllers when done
  dispose() {
    _taskStatusController.close();
    _complaintCreatedController.close();
  }
}