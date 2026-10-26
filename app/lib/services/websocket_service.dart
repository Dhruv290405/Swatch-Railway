import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  
  WebSocketChannel? _channel;
  var onMessageCallback;
  bool _isConnected = false;
  String? _authToken;
  String? _userId;
  String? _role;

  WebSocketService._internal();

  void initialize(String authToken, String userId, String role) {
    _authToken = authToken;
    _userId = userId;
    _role = role;
  }

  Future<bool> connect(String baseUrl) async {
    try {
      final url = '$baseUrl/ws';
      final token = _authToken;
      if (token != null) {
        _channel = WebSocketChannel.connect(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'X-User-Id': _userId,
            'X-User-Role': _role,
          },
        );
        
        _channel!.stream.listen(
          (data) => _onMessage(data),
          onDone: () => _onDone(),
          onError: (error) => _onError(error),
        );
        
        _isConnected = true;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      if (onMessageCallback != null) {
        onMessageCallback(data);
      }
    } catch (e) {
      debugPrint('WebSocket message parse error: $e');
    }
  }

  void _onDone() {
    _isConnected = false;
    debugPrint('WebSocket disconnected');
  }

  void _onError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _isConnected = false;
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  void sendMessage(String event, Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      final message = jsonEncode({
        'event': event,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _channel!.sink.add(message);
    }
  }

  void onMessage(void Function(dynamic) callback) {
    onMessageCallback = callback;
  }

  bool get isConnected => _isConnected;
}
