/// Scale helpers for the score-trend chart, kept free of Flutter types so the
/// axis arithmetic can be tested directly.
library;

import 'dart:math' as math;

/// Round a raw max up to a clean ceiling.
///
/// The scale is 0-based on purpose: line height then reads as a share of the
/// real value rather than a position inside a min..max window.
double niceCeil(double v) {
  if (!v.isFinite || v <= 0) return 10;
  final exp = (math.log(v) / math.log(10)).floorToDouble();
  final mag = math.pow(10.0, exp).toDouble();
  final n = v / mag;
  final nice = const [1.0, 2.0, 2.5, 5.0, 10.0]
      .firstWhere((c) => n <= c, orElse: () => 10.0);
  return nice * mag;
}
