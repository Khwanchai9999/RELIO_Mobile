import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:relio_mobile/core/location/packaged_map_service.dart';
import 'package:relio_mobile/core/location/nearby_map_calculations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline preparation is shared and resolves all style resources to local files',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('relio/offline_map'), (
            _,
          ) async {
            calls++;
            return '/data/user/0/com.relio.relio_mobile.test/files/relio_offline_map/20261101-z15-v4';
          });
      final first = PackagedMapService.prepare();
      final second = PackagedMapService.prepare();
      expect(identical(first, second), isTrue);
      final style = await first;
      expect(style, contains('pmtiles://file:///data/user/0/'));
      expect(style, isNot(contains('asset://')));
      expect(calls, 1);
      final decoded = jsonDecode(style) as Map;
      expect(decoded['glyphs'], startsWith('file:///'));
      expect(decoded['sprite'], startsWith('file:///'));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('relio/offline_map'),
            null,
          );
    },
  );
  test('packaged PMTiles header declares the real z0..15 archive', () {
    final file = File('assets/maps/thailand.pmtiles').openSync();
    try {
      final header = file.readSync(127);
      expect(ascii.decode(header.sublist(0, 7)), 'PMTiles');
      expect(header[7], 3);
      expect(header[100], 0);
      expect(header[101], 15);
      final view = ByteData.sublistView(header);
      expect(view.getUint64(72, Endian.little), greaterThan(500000));
    } finally {
      file.closeSync();
    }
  });

  test('representative Thailand z15 vector tiles exist in the package', () {
    final archive = File('assets/maps/thailand.pmtiles').openSync();
    try {
      final header = archive.readSync(127);
      final view = ByteData.sublistView(header);
      final rootOffset = view.getUint64(8, Endian.little);
      final rootLength = view.getUint64(16, Endian.little);
      final leafOffset = view.getUint64(40, Endian.little);
      final root = _readDirectory(archive, rootOffset, rootLength, header[97]);
      final samples = {
        'Bangkok': _z15Tile(13.7563, 100.5018),
        'Chiang Mai': _z15Tile(18.7883, 98.9853),
        'Phuket': _z15Tile(7.8804, 98.3923),
        'Udon Thani': _z15Tile(17.4138, 102.7872),
        'Chiang Rai': _z15Tile(19.9105, 99.8406),
      };

      for (final entry in samples.entries) {
        final tileId = _zxyToId(15, entry.value.$1, entry.value.$2);
        final tile = _findTile(root, tileId);
        expect(tile, isNotNull, reason: '${entry.key} z15 tile is absent');
        if (tile!.runLength == 0) {
          final leaf = _readDirectory(
            archive,
            leafOffset + tile.offset,
            tile.length,
            header[97],
          );
          expect(_findTile(leaf, tileId), isNotNull, reason: entry.key);
        }
      }
    } finally {
      archive.closeSync();
    }
  });

  test(
    'packaged map style keeps all render resources local through source z15',
    () {
      final style =
          jsonDecode(File('assets/maps/style.json').readAsStringSync()) as Map;
      final source = style['sources']['protomaps'] as Map;
      expect(
        source['tiles'][0],
        'pmtiles://asset://flutter_assets/assets/maps/thailand.pmtiles',
      );
      expect(source['maxzoom'], 15);
      expect(source['bounds'], [97, 5.5, 106, 21]);
      expect(source['attribution'], contains('openstreetmap.org/copyright'));
      expect(
        source['attribution'],
        contains('docs.protomaps.com/basemaps/downloads'),
      );
      expect(style['glyphs'], startsWith('asset://'));
      expect(style['sprite'], startsWith('asset://'));
      expect(jsonEncode(style), isNot(contains('Noto Sans ')));
      expect(jsonEncode(style), isNot(contains('https://build.protomaps.com')));
      expect(source.containsKey('url'), isFalse);
      for (var start = 0; start < 65536; start += 256) {
        expect(
          File('assets/maps/fonts/noto/$start-${start + 255}.pbf').lengthSync(),
          greaterThan(0),
        );
      }
      for (final font in [
        'Noto Sans Regular',
        'Noto Sans Medium',
        'Noto Sans Italic',
      ]) {
        expect(
          File('assets/maps/fonts/$font/3584-3839.pbf').lengthSync(),
          greaterThan(0),
        );
        expect(
          File('assets/maps/fonts/$font/0-255.pbf').lengthSync(),
          greaterThan(0),
        );
      }
      expect(
        File('assets/maps/sprites/light.png').lengthSync(),
        greaterThan(0),
      );
    },
  );
  test('shared location copy is factual and retains old timestamps', () {
    final now = DateTime(2026, 11, 1);
    expect(
      NearbyMapCalculations.sharedLocationLabel(
        now.subtract(const Duration(days: 2)),
        now,
      ),
      'แชร์ล่าสุด 2 วันที่แล้ว',
    );
    expect(
      NearbyMapCalculations.sharedLocationLabel(null, now),
      'ยังไม่มีตำแหน่งที่แชร์',
    );
  });
}

class _PmtilesEntry {
  const _PmtilesEntry({
    required this.tileId,
    required this.offset,
    required this.length,
    required this.runLength,
  });

  final int tileId;
  final int offset;
  final int length;
  final int runLength;
}

List<_PmtilesEntry> _readDirectory(
  RandomAccessFile archive,
  int offset,
  int length,
  int compression,
) {
  archive.setPositionSync(offset);
  final bytes = archive.readSync(length);
  final directory = compression == 2 ? gzip.decode(bytes) : bytes;
  var cursor = 0;
  int readVarint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final byte = directory[cursor++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return value;
      shift += 7;
    }
  }

  final count = readVarint();
  final tileIds = <int>[];
  var lastId = 0;
  for (var index = 0; index < count; index++) {
    lastId += readVarint();
    tileIds.add(lastId);
  }
  final runLengths = List<int>.generate(count, (_) => readVarint());
  final lengths = List<int>.generate(count, (_) => readVarint());
  final offsets = <int>[];
  for (var index = 0; index < count; index++) {
    final encodedOffset = readVarint();
    offsets.add(
      index > 0 && encodedOffset == 0
          ? offsets[index - 1] + lengths[index - 1]
          : encodedOffset - 1,
    );
  }
  return [
    for (var index = 0; index < count; index++)
      _PmtilesEntry(
        tileId: tileIds[index],
        offset: offsets[index],
        length: lengths[index],
        runLength: runLengths[index],
      ),
  ];
}

_PmtilesEntry? _findTile(List<_PmtilesEntry> entries, int tileId) {
  var low = 0;
  var high = entries.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final entry = entries[middle];
    if (entry.tileId == tileId) return entry;
    if (entry.tileId < tileId) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  if (high < 0) return null;
  final previous = entries[high];
  return previous.runLength == 0 ||
          tileId - previous.tileId < previous.runLength
      ? previous
      : null;
}

(int, int) _z15Tile(double latitude, double longitude) {
  const zoom = 15;
  final scale = 1 << zoom;
  final radians = latitude * math.pi / 180;
  final x = ((longitude + 180) / 360 * scale).floor();
  final y =
      ((1 - math.log(math.tan(math.pi / 4 + radians / 2)) / math.pi) /
              2 *
              scale)
          .floor();
  return (x, y);
}

int _zxyToId(int zoom, int x, int y) {
  var accumulator = ((1 << (zoom * 2)) - 1) ~/ 3;
  var shift = zoom - 1;
  for (var side = 1 << shift; side > 0; side >>= 1) {
    final rotateX = side & x;
    final rotateY = side & y;
    accumulator += ((3 * rotateX) ^ rotateY) << shift;
    final rotated = _rotate(side, x, y, rotateX, rotateY);
    x = rotated.$1;
    y = rotated.$2;
    shift--;
  }
  return accumulator;
}

(int, int) _rotate(int side, int x, int y, int rotateX, int rotateY) {
  if (rotateY == 0) {
    if (rotateX != 0) {
      x = side - 1 - x;
      y = side - 1 - y;
    }
    return (y, x);
  }
  return (x, y);
}
