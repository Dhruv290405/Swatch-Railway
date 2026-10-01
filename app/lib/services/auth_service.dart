import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'api_services.dart';

class AuthService {
  String baseUrl = ApiService.baseUrl;

  static const Duration connectionTimeout = Duration(seconds: 60);
  static const Duration receiveTimeout = Duration(seconds: 60);

  Future<AuthResponse> _makeRequest({
    required String endpoint,
    required Map<String, dynamic> body,
    bool retryOnTimeout = false,
  }) async {
    final int maxAttempts = retryOnTimeout ? 2 : 1;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final AuthResponse result = await _post(endpoint, body);
      if (result.errorType != ErrorType.timeout || attempt == maxAttempts - 1) {
        return result;
      }
    }

    return AuthResponse(
      success: false,
      message: 'Connection timeout. Please check your internet connection and try again.',
      statusCode: 0,
      errorType: ErrorType.timeout,
    );
  }

  Future<AuthResponse> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
          .timeout(
        connectionTimeout,
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      return AuthResponse.fromJson(responseData, response.statusCode);

    } on SocketException catch (e) {
      return AuthResponse(
        success: false,
        message: 'No internet connection. Please check your network and try again.',
        statusCode: 0,
        errorType: ErrorType.noInternet,
      );
    } on TimeoutException catch (e) {
      return AuthResponse(
        success: false,
        message: 'Connection timeout. Please check your internet connection and try again.',
        statusCode: 0,
        errorType: ErrorType.timeout,
      );
    } on HttpException catch (e) {
      return AuthResponse(
        success: false,
        message: 'Unable to connect to server. Please try again later.',
        statusCode: 0,
        errorType: ErrorType.serverError,
      );
    } on FormatException catch (e) {
      return AuthResponse(
        success: false,
        message: 'Received invalid response from server. Please try again.',
        statusCode: 0,
        errorType: ErrorType.invalidResponse,
      );
    } catch (e) {
      return AuthResponse(
        success: false,
        message: 'Something went wrong. Please try again later.',
        statusCode: 500,
        errorType: ErrorType.unknown,
      );
    }
  }

  Future<AuthResponse> loginWithOtpEmail(String email) async {
    if (email.isEmpty || !_isValidEmail(email)) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid email address.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/send-email-otp',
      body: {'email': email},
    );
  }

  Future<AuthResponse> verifyOtpEmail(String email, String otp) async {
    if (email.isEmpty || otp.isEmpty) {
      return AuthResponse(
        success: false,
        message: 'Email and OTP are required.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    if (otp.length != 6) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 6-digit OTP.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/verify-email-otp',
      body: {'email': email, 'otp': otp},
      retryOnTimeout: true,
    );
  }

  Future<AuthResponse> loginWithOtp(String phone) async {
    if (phone.isEmpty || !_isValidPhone(phone)) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 10-digit mobile number.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/send-otp',
      body: {'phone': phone},
    );
  }

  Future<AuthResponse> verifyOtp(String otp, String phone) async {
    if (phone.isEmpty || otp.isEmpty) {
      return AuthResponse(
        success: false,
        message: 'Phone and OTP are required.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    if (otp.length != 6) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 6-digit OTP.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/verify-otp',
      body: {'phone': phone, 'otp': otp},
      retryOnTimeout: true,
    );
  }

  Future<AuthResponse> loginWithPassword(String email, String password) async {
    if (email.isEmpty || !_isValidEmail(email)) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid email address.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }


    return await _makeRequest(
      endpoint: '/api/auth/login',
      body: {'email': email, 'password': password},
      retryOnTimeout: true,
    );
  }

  Future<AuthResponse> mobileWithPassword(String mobile, String password) async {
    if (mobile.isEmpty || !_isValidPhone(mobile)) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 10-digit mobile number.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }


    return await _makeRequest(
      endpoint: '/api/auth/loginWithMobile',
      body: {'mobile': mobile, 'password': password},
      retryOnTimeout: true,
    );
  }

  Future<AuthResponse> forgotPasswordSendOtpMobile(String phone) async {
    if (phone.isEmpty || !_isValidPhone(phone)) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 10-digit mobile number.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/forgot-password/send-otp',
      body: {'mobile': phone},
    );
  }

  Future<AuthResponse> forgotPasswordVerifyOtpMobile(String otp, String mobile) async {
    if (mobile.isEmpty || otp.isEmpty) {
      return AuthResponse(
        success: false,
        message: 'Mobile and OTP are required.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    if (otp.length != 6) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 6-digit OTP.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/forgot-password/verify-otp',
      body: {'mobile': mobile, 'otp': otp},
      retryOnTimeout: true,
    );
  }

  Future<AuthResponse> forgotPasswordSendOtpEmail(String email) async {
    if (email.isEmpty || !_isValidEmail(email)) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid email address.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/forgot-password/email/send-otp',
      body: {'email': email},
    );
  }

  Future<AuthResponse> forgotPasswordVerifyOtpEmail(String email, String otp) async {
    if (email.isEmpty || otp.isEmpty) {
      return AuthResponse(
        success: false,
        message: 'Email and OTP are required.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    if (otp.length != 6) {
      return AuthResponse(
        success: false,
        message: 'Please enter a valid 6-digit OTP.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/forgot-password/email/verify-otp',
      body: {'email': email, 'otp': otp},
      retryOnTimeout: true,
    );
  }

  Future<AuthResponse> changePassword(String currentPassword, String newPassword) async {
    final token = await ApiService.getToken();
    if (token == null) {
      return AuthResponse(
        success: false,
        message: 'You must be logged in to change password.',
        statusCode: 401,
        errorType: ErrorType.validation,
      );
    }
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/auth/change-password'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
          }),
        ).timeout(connectionTimeout, onTimeout: () => throw TimeoutException('Request timeout'));
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        return AuthResponse.fromJson(responseData, response.statusCode);
      } on SocketException catch (e) {
        return AuthResponse(
          success: false,
          message: 'No internet connection.',
          statusCode: 0,
          errorType: ErrorType.noInternet,
        );
      } on TimeoutException catch (e) {
        if (attempt == 0) continue;
        return AuthResponse(
          success: false,
          message: 'Connection timeout.',
          statusCode: 0,
          errorType: ErrorType.timeout,
        );
      } catch (e) {
        return AuthResponse(
          success: false,
          message: 'Something went wrong: $e',
          statusCode: 500,
          errorType: ErrorType.unknown,
        );
      }
    }
    return AuthResponse(
      success: false,
      message: 'Connection timeout.',
      statusCode: 0,
      errorType: ErrorType.timeout,
    );
  }

  Future<AuthResponse> resetPassword(String newPassword, String resetToken) async {
    if (newPassword.isEmpty || newPassword.length < 6) {
      return AuthResponse(
        success: false,
        message: 'Password must be at least 6 characters long.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    if (resetToken.isEmpty) {
      return AuthResponse(
        success: false,
        message: 'Invalid reset token. Please try again.',
        statusCode: 400,
        errorType: ErrorType.validation,
      );
    }

    return await _makeRequest(
      endpoint: '/api/auth/forgot-password/reset',
      body: {'newPassword': newPassword, 'resetToken': resetToken},
      retryOnTimeout: true,
    );
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^[6-9]\d{9}$');
    return phoneRegex.hasMatch(phone);
  }
}

enum ErrorType {
  noInternet,
  timeout,
  serverError,
  invalidResponse,
  validation,
  unknown,
}

class AuthResponse {
  final bool success;
  final String message;
  final int statusCode;
  final String? token;
  final String? resetToken;
  final Map<String, dynamic>? userData;
  final ErrorType? errorType;

  AuthResponse({
    required this.success,
    required this.message,
    required this.statusCode,
    this.token,
    this.resetToken,
    this.userData,
    this.errorType,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json, int statusCode) {
    ErrorType? errorType;
    if (statusCode >= 400 && statusCode < 500) {
      errorType = ErrorType.validation;
    } else if (statusCode >= 500) {
      errorType = ErrorType.serverError;
    }

    String message = _getUserFriendlyMessage(json, statusCode);

    return AuthResponse(
      success: statusCode >= 200 && statusCode < 300,
      message: message,
      statusCode: statusCode,
      token: json['token'],
      resetToken: json['resetToken'],
      userData: json['user'] ?? json['data'],
      errorType: errorType,
    );
  }

  static String _getUserFriendlyMessage(Map<String, dynamic> json, int statusCode) {
    String? serverMessage = json['message'] ?? json['error'];

    if (statusCode == 200 || statusCode == 201) {
      return serverMessage ?? 'Success';
    } else if (statusCode == 400) {
      return serverMessage ?? 'Invalid request. Please check your input.';
    } else if (statusCode == 401) {
      return serverMessage ?? 'Invalid credentials. Please try again.';
    } else if (statusCode == 403) {
      return serverMessage ?? 'Access denied. Please contact support.';
    } else if (statusCode == 404) {
      return serverMessage ?? 'User not found. Please check your details.';
    } else if (statusCode == 429) {
      return 'Too many attempts. Please try again after some time.';
    } else if (statusCode >= 500) {
      return 'Server error. Please try again later.';
    }

    return serverMessage ?? 'Something went wrong. Please try again.';
  }

  bool get isRetryable {
    return errorType == ErrorType.noInternet ||
        errorType == ErrorType.timeout ||
        errorType == ErrorType.serverError;
  }
}