import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/gabor/gabor_patch.dart';

/// Bounded cache of decoded Gabor images, shared by every [GaborView].
///
/// Two consumers make it worthwhile: a trial renders its target patch in the
/// target slot AND in the matching grid cell (one decode, two views), and the
/// game prewarms the next trial during the feedback delay so its grid swaps
/// in already-decoded instead of flashing spinners.
///
/// Entries are owned by the cache, never by a widget: a [GaborView] that
/// unmounts keeps its image cached for the next view of the same patch. The
/// bound keeps a long session from accumulating gigabytes — at 96 px an entry
/// is 36 KB, so [maxEntries] caps the cache near 3.5 MB.
class GaborImageCache {
  GaborImageCache._();

  static const int maxEntries = 96;

  /// Insertion order doubles as age order: the first key is the oldest.
  static final Map<int, ui.Image> _images = {};

  static ui.Image? lookup(int signature) => _images[signature];

  static void put(int signature, ui.Image image) {
    if (!_images.containsKey(signature) && _images.length >= maxEntries) {
      _images.remove(_images.keys.first)?.dispose();
    }
    _images[signature] = image;
  }

  /// Test hook: drop every entry and its image.
  static void clear() {
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
  }
}

int gaborSignature(GaborPatch patch, int size, int background) => Object.hash(
    patch.theta, patch.frequency, patch.phase, patch.curvature,
    patch.contrast, size, background);

/// Widget that renders a [GaborPatch] as an image.
///
/// [size] is the render resolution (e.g. 128). Decoded [ui.Image]s live in
/// [GaborImageCache], so a patch that several views need is decoded once.
class GaborView extends StatefulWidget {
  final GaborPatch patch;
  final int size;

  /// Colour of the surrounding surface. Used both for the pre-decode
  /// placeholder and as the dark end of the patch's luminance ramp, so the
  /// darkest stripes meet the page instead of banding against it.
  final int background;

  const GaborView({
    super.key,
    required this.patch,
    this.size = 128,
    this.background = 0xFF1A1A1D,
  });

  /// Decodes [patch] into [GaborImageCache] without rendering it. The game
  /// calls this for the whole next trial during the 650 ms feedback delay,
  /// so the grid swap lands on cached images.
  static void prewarm(
    GaborPatch patch, {
    int size = 128,
    int background = 0xFF1A1A1D,
  }) {
    final sig = gaborSignature(patch, size, background);
    if (GaborImageCache.lookup(sig) != null) return;
    final rgba = patch.renderRgba(size, darkLevel: background);
    ui.decodeImageFromPixels(
      rgba,
      size,
      size,
      ui.PixelFormat.rgba8888,
      (img) => GaborImageCache.put(sig, img),
    );
  }

  @override
  State<GaborView> createState() => _GaborViewState();
}

class _GaborViewState extends State<GaborView> {
  ui.Image? _image;
  int _lastSignature = -1;

  void _load() {
    final sig =
        gaborSignature(widget.patch, widget.size, widget.background);
    if (_image != null && _lastSignature == sig) return;
    _lastSignature = sig;
    final cached = GaborImageCache.lookup(sig);
    if (cached != null) {
      _image = cached;
      return;
    }
    final rgba =
        widget.patch.renderRgba(widget.size, darkLevel: widget.background);
    ui.decodeImageFromPixels(
      rgba,
      widget.size,
      widget.size,
      ui.PixelFormat.rgba8888,
      (img) {
        GaborImageCache.put(sig, img);
        if (!mounted || _lastSignature != sig) return;
        _image = img;
        setState(() {});
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GaborView old) {
    super.didUpdateWidget(old);
    if (old.patch != widget.patch ||
        old.size != widget.size ||
        old.background != widget.background) {
      _load();
    }
  }

  @override
  void dispose() {
    // The image belongs to GaborImageCache, which owns its lifetime.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) {
      return Container(
        color: Color(widget.background),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return CustomPaint(
      painter: _ImagePainter(img),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) => old.image != image;
}