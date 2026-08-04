import 'dart:math' as math;
import 'dart:typed_data';

/// Generates one leaf blade as RGBA8888 pixels: a pointed ellipse with a soft
/// edge and a darker midrib, on transparent background.
///
/// Generated rather than shipped, so the canopy costs nothing to download.
///
/// The alpha cut is what makes a canopy read as foliage instead of a mass of
/// coloured squares — and it is free, because discarded fragments also cut
/// overdraw.
Uint8List leafPixels(int size) {
  assert(size > 1, 'size must be at least 2');
  final px = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // Normalised to [-1, 1]; y runs tip (-1) to stem (+1).
      final nx = (x / (size - 1)) * 2 - 1;
      final ny = (y / (size - 1)) * 2 - 1;

      // Blade half-width: widest a third from the stem, tapering to a point.
      final t = (ny + 1) / 2;
      final width = math.sin(math.pow(t, 0.75).toDouble() * math.pi) * 0.92;

      final d = width <= 0 ? 2.0 : nx.abs() / width;
      // Soft edge over the outer 18% of the blade.
      var alpha = d >= 1.0 ? 0.0 : (1.0 - ((d - 0.82) / 0.18)).clamp(0.0, 1.0);
      if (t < 0.02 || t > 0.99) alpha = 0;

      // Midrib: a thin darker vein down the centre.
      final rib = (1.0 - (nx.abs() / 0.06)).clamp(0.0, 1.0);
      final shade = 1.0 - rib * 0.32;

      final o = (y * size + x) * 4;
      px[o] = (255 * shade).round();
      px[o + 1] = (255 * shade).round();
      px[o + 2] = (255 * shade).round();
      px[o + 3] = (alpha * 255).round();
    }
  }
  return px;
}
