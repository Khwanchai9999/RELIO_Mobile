import 'dart:typed_data';

/// Deterministic RFCOMM framing shared by the Dart contract tests and the
/// Android BluetoothClassicChannels implementation.
final class BluetoothClassicFrame {
  const BluetoothClassicFrame({required this.type, required this.payload});

  static const magic = 0x524c; // RL
  static const version = 1;
  static const headerLength = 12;
  static const maxPayloadLength = 2 * 1024 * 1024;

  final int type;
  final Uint8List payload;

  Uint8List encode() {
    if (type < 0 || type > 255) {
      throw ArgumentError.value(type, 'type');
    }
    if (payload.length > maxPayloadLength) {
      throw const FormatException('Bluetooth frame payload is too large.');
    }
    final output = ByteData(headerLength + payload.length);
    output.setUint16(0, magic);
    output.setUint8(2, version);
    output.setUint8(3, type);
    output.setUint32(4, payload.length);
    output.setUint32(8, crc32(payload));
    final bytes = output.buffer.asUint8List();
    bytes.setRange(headerLength, bytes.length, payload);
    return bytes;
  }

  // CRC32 ใช้ตรวจความเสียหายของ frame ไม่ใช่หลักฐานยืนยันตัวตนของ peer
  static int crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }
}

final class BluetoothClassicFrameDecoder {
  final List<int> _buffer = <int>[];

  List<BluetoothClassicFrame> add(Uint8List bytes) {
    _buffer.addAll(bytes);
    final frames = <BluetoothClassicFrame>[];
    while (true) {
      if (_buffer.length < BluetoothClassicFrame.headerLength) return frames;
      final view = ByteData.sublistView(Uint8List.fromList(_buffer));
      final magic = view.getUint16(0);
      if (magic != BluetoothClassicFrame.magic) {
        // ข้าม byte ที่ไม่ใช่หัว frame เพื่อหาจุดเริ่มข้อมูลที่ถูกต้องอีกครั้ง
        _buffer.removeAt(0);
        continue;
      }
      if (view.getUint8(2) != BluetoothClassicFrame.version) {
        throw const FormatException('Unsupported Bluetooth frame version.');
      }
      final length = view.getUint32(4);
      if (length > BluetoothClassicFrame.maxPayloadLength) {
        throw const FormatException('Bluetooth frame payload is too large.');
      }
      final frameLength = BluetoothClassicFrame.headerLength + length;
      if (_buffer.length < frameLength) return frames;
      final payload = Uint8List.fromList(_buffer.sublist(12, frameLength));
      if (view.getUint32(8) != BluetoothClassicFrame.crc32(payload)) {
        _buffer.removeRange(0, frameLength);
        throw const FormatException('Bluetooth frame checksum mismatch.');
      }
      frames.add(
        BluetoothClassicFrame(type: view.getUint8(3), payload: payload),
      );
      _buffer.removeRange(0, frameLength);
    }
  }
}
