class NearbyRetryBackoff {
  int attempt = 0;

  Duration registerFailure() {
    attempt++;
    // เพิ่มช่วงรอแบบ exponential แต่จำกัดเพดานไว้เพื่อไม่ให้ retry ถี่เกินไป
    final exponent = (attempt - 1).clamp(0, 5);
    final seconds = (10 * (1 << exponent)).clamp(10, 300);
    return Duration(seconds: seconds);
  }

  void reset() => attempt = 0;
}
