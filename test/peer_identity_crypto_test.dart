import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:relio_mobile/core/nearby/peer_identity_crypto.dart';

void main() {
  test(
    'test identity remains stable and returns only public identity data',
    () async {
      final crypto = MockPeerIdentityCrypto('device-a');
      final first = await crypto.getPublicIdentity();
      final second = await crypto.getPublicIdentity();

      expect(second.publicKey, first.publicKey);
      expect(second.fingerprint, first.fingerprint);
      expect(first.fingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(first.publicKey, isNotEmpty);
      expect(first.toString(), isNot(contains('privateKey')));
    },
  );

  test(
    'test proof rejects tampered payload and a different peer key',
    () async {
      final signer = MockPeerIdentityCrypto('device-a');
      final otherPeer = MockPeerIdentityCrypto('device-b');
      final identity = await signer.getPublicIdentity();
      final message = identityChallengeMessage(
        challengeId: 'challenge-1',
        nonce: base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', ''),
        challengerDeviceId: 'device-b',
        responderDeviceId: 'device-a',
      );
      final signature = await signer.sign(message);

      expect(
        await signer.verify(
          publicKey: identity.publicKey,
          message: message,
          signature: signature,
        ),
        isTrue,
      );
      expect(
        await signer.verify(
          publicKey: identity.publicKey,
          message: utf8.encode('tampered'),
          signature: signature,
        ),
        isFalse,
      );
      final otherIdentity = await otherPeer.getPublicIdentity();
      expect(
        await otherPeer.verify(
          publicKey: identity.publicKey,
          message: message,
          signature: signature,
        ),
        isFalse,
      );
      expect(otherIdentity.fingerprint, isNot(identity.fingerprint));
    },
  );
}
