abstract final class RegisterValidation {
  static String normalizeEmail(String value) => value.trim();

  static String? emailError(String? value) {
    final email = normalizeEmail(value ?? '');
    if (email.isEmpty) return 'กรุณากรอกอีเมล';
    return isValidEmail(email) ? null : 'รูปแบบอีเมลไม่ถูกต้อง';
  }

  static bool isValidEmail(String email) {
    if (email.length > 254 || email.contains(RegExp(r'\s'))) return false;
    final parts = email.split('@');
    if (parts.length != 2) return false;

    final local = parts.first;
    final domain = parts.last;
    if (local.isEmpty || local.length > 64 || domain.isEmpty) return false;
    if (local.startsWith('.') || local.endsWith('.') || local.contains('..')) {
      return false;
    }
    if (!RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local)) {
      return false;
    }

    final labels = domain.split('.');
    if (labels.length < 2) return false;
    final labelPattern = RegExp(
      r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
    );
    return labels.every(
      (label) => label.length <= 63 && labelPattern.hasMatch(label),
    );
  }

  static bool hasMinimumLength(String password) => password.length >= 8;
  static bool hasUppercase(String password) =>
      RegExp(r'[A-Z]').hasMatch(password);
  static bool hasLowercase(String password) =>
      RegExp(r'[a-z]').hasMatch(password);
  static bool hasNumber(String password) => RegExp(r'[0-9]').hasMatch(password);
  static bool hasSpecialCharacter(String password) =>
      RegExp(r'[^A-Za-z0-9\s]').hasMatch(password);

  static bool isPasswordValid(String password) =>
      hasMinimumLength(password) &&
      hasUppercase(password) &&
      hasLowercase(password) &&
      hasNumber(password) &&
      hasSpecialCharacter(password);

  static String? passwordError(String password) =>
      isPasswordValid(password) ? null : 'รหัสผ่านยังไม่ตรงตามเงื่อนไข';

  static String? confirmationError(String password, String confirmation) {
    if (confirmation.isEmpty) return 'กรุณายืนยันรหัสผ่าน';
    return confirmation == password
        ? null
        : 'รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน';
  }
}
