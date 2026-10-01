import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/nearby_retry_backoff.dart';

void main() {
  test('retry delays grow exponentially and remain bounded', () {
    final retry = NearbyRetryBackoff();

    expect(retry.registerFailure(), const Duration(seconds: 10));
    expect(retry.registerFailure(), const Duration(seconds: 20));
    expect(retry.registerFailure(), const Duration(seconds: 40));
    expect(retry.registerFailure(), const Duration(seconds: 80));
    expect(retry.registerFailure(), const Duration(seconds: 160));
    expect(retry.registerFailure(), const Duration(seconds: 300));
    expect(retry.registerFailure(), const Duration(seconds: 300));
  });

  test('successful start resets retry delay to the initial interval', () {
    final retry = NearbyRetryBackoff();
    retry.registerFailure();
    retry.registerFailure();

    retry.reset();

    expect(retry.attempt, 0);
    expect(retry.registerFailure(), const Duration(seconds: 10));
  });
}
