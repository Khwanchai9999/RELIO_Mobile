import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

import '../../app/theme/relio_colors.dart';
import 'peer_connection_presence.dart';

abstract final class AvatarAppearanceResolver {
  // สร้างสีคงที่จาก identity เดิม เพื่อไม่ให้สี avatar เปลี่ยนทุกครั้งที่ Widget rebuild
  static Color colorFor(String identityKey) {
    final key = identityKey.trim().toLowerCase();
    if (key.isEmpty) return RelioColors.muted;
    final digest = sha256.convert(utf8.encode(key)).bytes;
    final hueBits = (digest[0] << 8) | digest[1];
    final hue = hueBits / 0xffff * 360;
    final saturation = 0.58 + digest[2] / 255 * 0.16;
    final lightness = 0.39 + digest[3] / 255 * 0.09;
    return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
  }

  static Color displayColor(Color base, PeerConnectionPresence presence) {
    if (presence == PeerConnectionPresence.online) return base;
    final saturation = presence == PeerConnectionPresence.offline ? 0.16 : 0.08;
    return HSLColor.fromColor(base).withSaturation(saturation).toColor();
  }
}
