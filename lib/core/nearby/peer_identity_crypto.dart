import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class PeerPublicIdentity {
  const PeerPublicIdentity({
    required this.publicKey,
    required this.fingerprint,
  });

  final String publicKey;
  final String fingerprint;
}

abstract interface class PeerIdentityCrypto {
  Future<PeerPublicIdentity> getPublicIdentity();
  Future<String> sign(Uint8List message);
  Future<String> fingerprint(String publicKey);
  Future<bool> verify({
    required String publicKey,
    required Uint8List message,
    required String signature,
  });
}

class AndroidPeerIdentityCrypto implements PeerIdentityCrypto {
  AndroidPeerIdentityCrypto({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('relio/device_identity');

  final MethodChannel _channel;

  @override
  Future<PeerPublicIdentity> getPublicIdentity() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getPublicIdentity',
    );
    final key = result?['publicKey'];
    final fingerprint = result?['fingerprint'];
    if (key is! String ||
        fingerprint is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
      throw StateError('Android device identity is unavailable.');
    }
    return PeerPublicIdentity(publicKey: key, fingerprint: fingerprint);
  }

  @override
  Future<String> sign(Uint8List message) async {
    final signature = await _channel.invokeMethod<String>('sign', {
      'message': base64Url.encode(message).replaceAll('=', ''),
    });
    if (signature == null || signature.isEmpty) {
      throw StateError('Android device signing failed.');
    }
    return signature;
  }

  @override
  Future<String> fingerprint(String publicKey) async {
    final result = await _channel.invokeMethod<String>('fingerprint', {
      'publicKey': publicKey,
    });
    if (result == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(result)) {
      throw FormatException('Invalid peer public-key fingerprint.');
    }
    return result;
  }

  @override
  Future<bool> verify({
    required String publicKey,
    required Uint8List message,
    required String signature,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('verify', {
            'publicKey': publicKey,
            'message': base64Url.encode(message).replaceAll('=', ''),
            'signature': signature,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}

/// Deliberately non-cryptographic identity provider for MockNearbyTransport tests.
class MockPeerIdentityCrypto implements PeerIdentityCrypto {
  MockPeerIdentityCrypto(this.deviceId)
    : _publicKey = base64Url.encode(utf8.encode('test-only:$deviceId')),
      _fingerprint = _testFingerprint(deviceId);

  final String deviceId;
  final String _publicKey;
  final String _fingerprint;

  static String _testFingerprint(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  @override
  Future<PeerPublicIdentity> getPublicIdentity() async =>
      PeerPublicIdentity(publicKey: _publicKey, fingerprint: _fingerprint);

  @override
  Future<String> sign(Uint8List message) async =>
      '$_publicKey.${base64Url.encode(message)}';

  @override
  Future<String> fingerprint(String publicKey) async {
    if (publicKey != _publicKey) {
      throw const FormatException('Unknown test key.');
    }
    return _fingerprint;
  }

  @override
  Future<bool> verify({
    required String publicKey,
    required Uint8List message,
    required String signature,
  }) async =>
      publicKey == _publicKey &&
      signature == '$_publicKey.${base64Url.encode(message)}';
}

Uint8List identityChallengeMessage({
  required String challengeId,
  required String nonce,
  required String challengerDeviceId,
  required String responderDeviceId,
}) {
  if ([
    challengeId,
    nonce,
    challengerDeviceId,
    responderDeviceId,
  ].any((value) => value.isEmpty || value.contains('\n'))) {
    throw ArgumentError('Invalid identity challenge fields.');
  }
  return Uint8List.fromList(
    utf8.encode(
      'RELIO_PEER_AUTH_V1\n$challengeId\n$nonce\n'
      '$challengerDeviceId\n$responderDeviceId',
    ),
  );
}
