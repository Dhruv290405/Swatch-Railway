import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import '../providers/auth_provider.dart';

class RealTimeIndicator extends StatelessWidget {
  final String? eventType;
  final Widget child;

  const RealTimeIndicator({
    super.key,
    this.eventType,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<RealTimeDataProvider, AuthProvider>(
      builder: (context, realTime, auth, child) {
        final isConnected = realTime.isRealTimeConnected;
        final isLoggedIn = auth.isLoggedIn;
        final connectionColor = isConnected ? Colors.green : Colors.red;
        
        return Stack(
          children: [
            child!,
            if (!isConnected && isLoggedIn)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.cloud_off,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            if (isConnected && eventType != null)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: connectionColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  constraints: const BoxConstraints(minWidth: 60, minHeight: 20),
                  child: Text(
                    'LIVE',
                    style: TextStyle(
                      fontSize: 10,
                      color: connectionColor == Colors.green ? Colors.white : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class RealTimeDataProvider extends ChangeNotifier {
  bool _isRealTimeConnected = false;
  bool get isRealTimeConnected => _isRealTimeConnected;

  Map<String, dynamic> _lastUpdate = {};
  Map<String, dynamic> get lastUpdate => _lastUpdate;

  final Map<String, List<Function>> _subscribers = {};

  void subscribe(String event, Function callback) {
    if (!_subscribers.containsKey(event)) {
      _subscribers[event] = [];
    }
    _subscribers[event]!.add(callback);
    notifyListeners();
  }

  void unsubscribe(String event, Function callback) {
    if (_subscribers.containsKey(event)) {
      _subscribers[event]!.remove(callback);
    }
  }

  void handleMessage(dynamic message) {
    try {
      final data = message;
      if (data['event'] != null) {
        final event = data['event'];
        
        if (_subscribers.containsKey(event)) {
          for (final callback in _subscribers[event]!) {
            try {
              callback(data);
            } catch (e) {
              debugPrint('Subscriber error for $event: $e');
            }
          }
        }
        
        _lastUpdate = {
          'event': event,
          'timestamp': data['timestamp'],
          'data': data['data'],
        };
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error handling message: $e');
    }
  }

  void disconnect() {
    _isRealTimeConnected = false;
    _subscribers.clear();
    notifyListeners();
  }
}
