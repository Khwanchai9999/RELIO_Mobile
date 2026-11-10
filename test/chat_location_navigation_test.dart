import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/data/models/prototype_models.dart';
import 'package:relio_mobile/features/chat/chat_location_navigation.dart';

void main() {
  test('chat map target preserves saved coordinates and sharing time', () {
    final sharedAt = DateTime.utc(2026, 11, 3, 11, 56);
    final message = RelioMessage(
      id: 'location-1',
      text: 'ตำแหน่งที่แชร์',
      time: '18:56',
      outgoing: false,
      type: MessageType.location,
      latitude: 14.041375,
      longitude: 100.739633,
      createdAt: sharedAt,
    );
    final target = chatSharedLocationUri(message)!;
    expect(target.path, '/nearby');
    expect(target.queryParameters['lat'], '14.041375');
    expect(target.queryParameters['lon'], '100.739633');
    expect(target.queryParameters['shared'], '1');
    expect(
      target.queryParameters['capturedAt'],
      '${sharedAt.millisecondsSinceEpoch}',
    );
  });

  test('missing and invalid saved locations do not create map targets', () {
    final missing = RelioMessage(
      id: 'location-missing',
      text: '',
      time: '',
      outgoing: true,
      type: MessageType.location,
    );
    final invalid = RelioMessage(
      id: 'location-invalid',
      text: '',
      time: '',
      outgoing: true,
      type: MessageType.location,
      latitude: 0,
      longitude: 181,
    );
    expect(chatSharedLocationUri(missing), isNull);
    expect(chatSharedLocationUri(invalid), isNull);
  });
}
