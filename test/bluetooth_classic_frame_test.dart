import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/bluetooth_classic_frame.dart';

void main() {
  test('round trips partial and multiple frames', () {
    final first = BluetoothClassicFrame(
      type: 1,
      payload: Uint8List.fromList([1, 2, 3]),
    ).encode();
    final second = BluetoothClassicFrame(
      type: 2,
      payload: Uint8List.fromList([4, 5]),
    ).encode();
    final decoder = BluetoothClassicFrameDecoder();

    expect(decoder.add(first.sublist(0, 5)), isEmpty);
    final frames = decoder.add(
      Uint8List.fromList([...first.sublist(5), ...second]),
    );

    expect(frames.map((frame) => frame.type), [1, 2]);
    expect(frames.first.payload, [1, 2, 3]);
    expect(frames.last.payload, [4, 5]);
  });

  test('rejects malformed, oversized, and checksum-corrupt frames', () {
    final decoder = BluetoothClassicFrameDecoder();
    expect(
      () => decoder.add(
        Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
      ),
      returnsNormally,
    );
    final frame = BluetoothClassicFrame(
      type: 1,
      payload: Uint8List.fromList([9]),
    ).encode();
    frame[frame.length - 1] ^= 0xff;
    expect(() => decoder.add(frame), throwsFormatException);
  });
}
