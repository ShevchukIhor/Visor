import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visor/core/gabor/gabor_patch.dart';
import 'package:visor/widgets/gabor_view.dart';

/// Coverage for the shared Gabor image cache: prewarming must leave a decoded
/// image behind, a prewarmed view must render on its first frame, and the
/// bound must evict the oldest entry.
Future<ui.Image> _onePixel() {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      Uint8List.fromList([0, 0, 0, 255]), 1, 1, ui.PixelFormat.rgba8888,
      done.complete);
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GaborImageCache.clear);

  test('prewarm decodes the patch into the shared cache', () async {
    final patch = const GaborPatch(theta: 0.3, phase: 0.7);
    GaborView.prewarm(patch, size: 64);
    // decodeImageFromPixels delivers on the real event loop.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final sig = gaborSignature(patch, 64, 0xFF1A1A1D);
    expect(GaborImageCache.lookup(sig), isNotNull,
        reason: 'prewarm must leave the decoded image in the cache');
  });

  testWidgets('a prewarmed patch renders without a spinner', (tester) async {
    final patch = const GaborPatch(theta: 1.1, phase: 2.2);
    await tester.runAsync(() async {
      GaborView.prewarm(patch, size: 64);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpWidget(MaterialApp(home: GaborView(patch: patch, size: 64)));
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'the cached image must be ready on the first frame');
  });

  test('the cache evicts the oldest image past its bound', () async {
    GaborImageCache.put(1, await _onePixel());
    for (var i = 2; i <= GaborImageCache.maxEntries + 1; i++) {
      GaborImageCache.put(i, await _onePixel());
    }
    expect(GaborImageCache.lookup(1), isNull,
        reason: 'the oldest entry must be evicted at the bound');
  });
}
