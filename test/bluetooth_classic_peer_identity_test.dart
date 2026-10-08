import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/bluetooth_classic_transport.dart';

void main() {
  test('Classic peer label uses only the address suffix', () {
    expect(
      bluetoothClassicAddressSuffix('classic:12:34:56:78:9a:bc'),
      '...:9A:BC',
    );
  });

  test('non-Classic or malformed identifiers are not exposed', () {
    expect(bluetoothClassicAddressSuffix('endpoint-123'), isNull);
    expect(bluetoothClassicAddressSuffix('classic:not-an-address'), isNull);
  });
}
