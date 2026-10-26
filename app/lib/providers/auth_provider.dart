import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_services.dart';
import '../services/websocket_service.dart';
import '../services/real_time_data_service.dart';


import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../model/user_model.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _token;
  String? get token => _token;

  Map<String, dynamic>? _userData;
  Map<String, dynamic>? get userData => _userData;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  RealTimeDataProvider? _realTimeDataProvider;
  WebSocketService? _webSocketService;
  WebSocketChannel? _webSocketChannel;
  bool _isWebSocketConnected = false;
  bool get isWebSocketConnected => _isWebSocketConnected;

  final Map<String, Function> _eventHandlers = {};

  void setRealTimeProvider(RealTimeDataProvider provider) {
    _realTimeDataProvider = provider;
  }

  void onEvent(String event, Function handler) {
    _eventHandlers[event] = handler;
    if (_realTimeDataProvider != null) {
      _realTimeDataProvider!.subscribe(event, (data) {
        handler(data);
      });
    }
  }

  Map<String, dynamic>? get entityDetails => _currentUser?.entityDetails;


  Future<bool> sendOtp(String phone) async {
    _setLoading(true);
    _errorMessage = null;

    final response = await _authService.loginWithOtp(phone);

    _setLoading(false);

    if (response.success) {
      notifyListeners();
      return true;
    } else {
      _errorMessage = response.message;
      notifyListeners();
      return false;
    }
  }


  Future<bool> sendEmailOtp(String email) async {
    _setLoading(true);
    _errorMessage = null;

    final response = await _authService.loginWithOtpEmail(email);

    _setLoading(false);

    if (response.success) {
      notifyListeners();
      return true;
    } else {
      _errorMessage = response.message;
      notifyListeners();
      return false;
    }
  }


  Future<bool> verifyEmailOtp(String email, String otp) async {
    _setLoading(true);
    _errorMessage = null;

    final response = await _authService.verifyOtpEmail(email, otp);

    _setLoading(false);

    if (response.success) {
      _token = response.token;
      _userData = response.userData;


      if (_userData != null) {
        try {
          _currentUser = UserModel.fromApiResponse(_userData!);
          debugPrint('\n======= EMAIL OTP LOGIN SUCCESS =======');
          debugPrint('Token: $_token\n');
          debugPrint('Raw User Data: ${jsonEncode(_userData)}\n');
          debugPrint('Parsed User Model: ${jsonEncode(_currentUser!.toJson())}');
          debugPrint('========================================\n');
        } catch (e) {
          _errorMessage = 'Failed to parse user data: $e';
          notifyListeners();
          return false;
        }
      }

      notifyListeners();
      return true;
    } else {
      _errorMessage = response.message;
      notifyListeners();
      return false;
    }
  }


  Future<bool> verifyOtp(String phone, String otp) async {
    _setLoading(true);
    _errorMessage = null;

    final response = await _authService.verifyOtp(otp, phone);

    _setLoading(false);

    if (response.success) {
      _token = response.token;
      _userData = response.userData;


      if (_userData != null) {
        try {
          _currentUser = UserModel.fromApiResponse(_userData!);
          debugPrint('\n======= OTP LOGIN SUCCESS =======');
          debugPrint('Token: $_token\n');
          debugPrint('Raw User Data: ${jsonEncode(_userData)}\n');
          debugPrint('Parsed User Model: ${jsonEncode(_currentUser!.toJson())}');
          debugPrint('=================================\n');
        } catch (e) {
          _errorMessage = 'Failed to parse user data: $e';
          notifyListeners();
          return false;
        }
      }

      notifyListeners();
      return true;
    } else {
      _errorMessage = response.message;
      notifyListeners();
      return false;
    }
  }


  Future<bool> loginWithPassword(String email, String password) async {
    _setLoading(true);
    _errorMessage = null;

    final response = await _authService.loginWithPassword(email, password);

    _setLoading(false);

    if (response.success) {
      _token = response.token;
      _userData = response.userData;


      if (_userData != null) {
        try {
          _currentUser = UserModel.fromApiResponse(_userData!);
        } catch (e) {
          _errorMessage = 'Failed to parse user data: $e';
          notifyListeners();
          return false;
        }
      }

      notifyListeners();
      return true;
    } else {
      _errorMessage = response.message;
      notifyListeners();
      return false;
    }
  }


  Future<bool> loginWithMobile(String mobile, String password) async {
    _setLoading(true);
    _errorMessage = null;

    final response = await _authService.mobileWithPassword(mobile, password);

    _setLoading(false);

    if (response.success) {
      _token = response.token;
      _userData = response.userData;


      if (_userData != null) {
        try {
          _currentUser = UserModel.fromApiResponse(_userData!);
        } catch (e) {
          _errorMessage = 'Failed to parse user data: $e';
          notifyListeners();
          return false;
        }
      }

      notifyListeners();
      return true;
    } else {
      _errorMessage = response.message;
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> saveUserSession({bool rememberMe = false}) async {
    final prefs = await SharedPreferences.getInstance();

    if (_token != null) {
      await prefs.setString('token', _token!);
      await prefs.setString('auth_token', _token!);
    }

    if (_userData != null) {
      await prefs.setString('userData', jsonEncode(_userData));
    }

    if (_currentUser != null) {
      await prefs.setString('currentUser', jsonEncode(_currentUser!.toJson()));
    }

    await prefs.setBool('rememberMe', rememberMe);
  }

  Future<void> loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();

    _token = prefs.getString('token') ?? prefs.getString('auth_token');

    final userDataStr = prefs.getString('userData');
    if (userDataStr != null) {
      _userData = jsonDecode(userDataStr);
    }

    final currentUserStr = prefs.getString('currentUser');
    if (currentUserStr != null) {
      try {
        _currentUser = UserModel.fromJson(jsonDecode(currentUserStr));
      } catch (e) {
        debugPrint('Error loading user from session: $e');
      }
    }

    notifyListeners();
  }


  bool get isLoggedIn => _token != null && _currentUser != null;

  // Check if Remember Me was enabled
  Future<bool> getRememberMeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('rememberMe') ?? false;
  }

  Future<void> checkAndClearSessionIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('rememberMe') ?? false;

    if (!rememberMe) {
      // Clear all session data if remember me was not checked
      await prefs.clear();
      _token = null;
      _userData = null;
      _currentUser = null;
      _errorMessage = null;
      notifyListeners();
      debugPrint('Session cleared - Remember Me was not enabled');
    }
  }

  Future<void> logout() async {
    _token = null;
    _userData = null;
    _currentUser = null;
    _errorMessage = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }

  void disconnectWebSocket() {
    _webSocketService?.disconnect();
    _webSocketChannel?.sink.close();
    _webSocketChannel = null;
    _isWebSocketConnected = false;
    _webSocketService = null;
    notifyListeners();
  }

  Future<void> initializeWebSocket() async {
    if (_webSocketService != null && _isWebSocketConnected) return;

    try {
      _webSocketService = WebSocketService();
      _webSocketService!.initialize(
        _token ?? '',
        _currentUser?.uid ?? '',
        _currentUser?.role ?? '',
      );

      final connected = await _webSocketService!.connect(
        ApiService.baseUrl,
      );

      _isWebSocketConnected = connected;
      notifyListeners();

      if (connected) {
        _webSocketChannel = _webSocketService!.channel;

        _webSocketChannel!.stream.listen(
          (data) {
            _onWebSocketMessage(data);
            if (_realTimeDataProvider != null) {
              _realTimeDataProvider!.handleMessage(data);
            }
          },
          onDone: () {
            _isWebSocketConnected = false;
            notifyListeners();
            _attemptReconnection();
          },
          onError: (error) {
            debugPrint('WebSocket error: $error');
            _isWebSocketConnected = false;
            notifyListeners();
            _attemptReconnection();
          },
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize WebSocket: $e');
      _isWebSocketConnected = false;
      notifyListeners();
    }
  }

  void _onWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      final event = data['event'];

      if (_eventHandlers.containsKey(event)) {
        _eventHandlers[event]!(data['data']);
      }

      if (_realTimeDataProvider != null) {
        _realTimeDataProvider!.handleMessage(data);
      }
    } catch (e) {
      debugPrint('WebSocket message parse error: $e');
    }
  }

  void _attemptReconnection() {
    Future.delayed(const Duration(seconds: 3), () {
      if (_token != null && _currentUser != null) {
        initializeWebSocket();
      }
    });
  }
}
}