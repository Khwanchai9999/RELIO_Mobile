import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Fits media within a bubble without changing its source aspect ratio.
Size fitMediaPreviewSize(Size source, Size bounds) {
  if (source.width <= 0 ||
      source.height <= 0 ||
      bounds.width <= 0 ||
      bounds.height <= 0) {
    return Size.zero;
  }
  final scale = math.min(
    1.0,
    math.min(bounds.width / source.width, bounds.height / source.height),
  );
  return Size(source.width * scale, source.height * scale);
}
