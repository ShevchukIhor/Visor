import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/gabor/gabor_patch.dart';

/// Widget that renders a [GaborPatch] as an image.
///
/// [size] is the render resolution (e.g. 128). The decoded [ui.Image] is
/// cached per unique patch identity so the grid repaints cheaply.
class GaborView extends StatefulWidget {
  final GaborPatch patch;
  final int size;
  final int background;

  const GaborView({
    super.key,
    required this.patch,
    this.size = 128,
    this.background = 0xFF1A1A1D,
  });

  @override
  State<GaborView> createState() => _GaborViewState();
}

class _GaborViewState extends State<GaborView> {
  ui.Image? _image;
  int _lastSignature = -1;

  void _load() {
    final sig = Object.hash(
        widget.patch.theta,
        widget.patch.frequency,
        widget.patch.phase,
        widget.patch.curvature,
        widget.patch.contrast,
        widget.size,
        widget.background);
    if (_image != null && _lastSignature == sig) return;
    _lastSignature = sig;
    final rgba = widget.patch.renderRgba(widget.size, bg: widget.background);
    ui.decodeImageFromPixels(
      rgba,
      widget.size,
      widget.size,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted) return;
        final old = _image;
        _image = img;
        old?.dispose();
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
    _image?.dispose();
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