class AppValidators {
  static final RegExp _emailRegex = RegExp(r'^[\w\.-]+@[\w-]+(\.[\w-]+)+$');
  static final RegExp _mobileRegex = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _aadhaarRegex = RegExp(r'^\d{12}$');

  static final RegExp _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final RegExp _gstinRegex =
      RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

  /// PAN: 5 letters + 4 digits + 1 letter (e.g. ABCDE1234F). Case-insensitive input.
  static String? pan(String? value, {bool required = true}) {
    final v = value?.trim().toUpperCase() ?? '';
    if (v.isEmpty) return required ? 'PAN is required' : null;
    if (!_panRegex.hasMatch(v)) return 'Enter valid PAN (e.g. ABCDE1234F)';
    return null;
  }

  /// GSTIN: standard 15-character format (e.g. 22ABCDE1234F1Z5).
  static String? gstin(String? value, {bool required = true}) {
    final v = value?.trim().toUpperCase() ?? '';
    if (v.isEmpty) return required ? 'GSTIN is required' : null;
    if (!_gstinRegex.hasMatch(v)) return 'Enter valid 15-character GSTIN (e.g. 22ABCDE1234F1Z5)';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(v)) return 'Enter valid email';
    return null;
  }

  static String? mobile(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Mobile number is required' : null;
    if (!_mobileRegex.hasMatch(v)) return 'Please enter a valid 10-digit Indian mobile number';
    return null;
  }

  static String? aadhaar(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Aadhaar number is required' : null;
    if (!_aadhaarRegex.hasMatch(v)) return 'Enter valid 12-digit Aadhaar number';
    return null;
  }
}