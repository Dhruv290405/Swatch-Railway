import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FCMService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _fcm.getToken();
    debugPrint('FCM Token: $token');
  }

  Future<void> subscribeToTopic(String topic) async {
    await _fcm.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    await _fcm.unsubscribeFromTopic(topic);
  }

  Stream<String?> get onTokenRefresh => _fcm.onTokenRefresh;

  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    // Handle background messages
    debugPrint('Handling background message: ${message.messageId}');
  }

  RemoteNotification? getNotification(RemoteMessage message) {
    return message.notification;
  }

  Map<String, dynamic>? getData(RemoteMessage message) {
    return message.data;
  }
}
