import 'package:flutter_test/flutter_test.dart';
import 'package:showcase/src/leaf_texture.dart';

/// Alpha byte of the pixel at (x, y) in a `size`-square RGBA buffer.
int alphaAt(List<int> px, int size, int x, int y) => px[(y * size + x) * 4 + 3];

void main() {
  const size = 64;
  final px = leafPixels(size);

  test('produces a full RGBA buffer', () {
    expect(px.length, size * size * 4);
  });

  test('corners are fully transparent', () {
    // A leaf inscribed in a square must not fill the square, or the canopy
    // renders as overlapping opaque cards instead of foliage.
    const last = size - 1;
    for (final (x, y) in [(0, 0), (last, 0), (0, last), (last, last)]) {
      expect(alphaAt(px, size, x, y), 0, reason: 'corner ($x, $y) is opaque');
    }
  });

  test('the blade is opaque along the centre line', () {
    // Sample inside the body, away from the tip and stem cutoffs.
    for (var y = (size * 0.25).round(); y < (size * 0.75).round(); y++) {
      expect(
        alphaAt(px, size, size ~/ 2, y),
        255,
        reason: 'centre of the blade should be solid at y=$y',
      );
    }
  });

  test('is horizontally symmetric', () {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size ~/ 2; x++) {
        expect(
          alphaAt(px, size, x, y),
          alphaAt(px, size, size - 1 - x, y),
          reason: 'asymmetry at ($x, $y)',
        );
      }
    }
  });

  test('covers a sensible fraction of the quad', () {
    // Too little and the canopy needs far more instances to look dense; too
    // much and the alpha cut is not buying back any overdraw.
    var opaque = 0;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] > 127) opaque++;
    }
    final fraction = opaque / (size * size);
    expect(fraction, greaterThan(0.25));
    expect(fraction, lessThan(0.75));
  });

  test('has a visible midrib', () {
    // The rib is a darker vertical vein; without it leaves read as flat blobs.
    const mid = size ~/ 2;
    const y = size ~/ 2;
    final ribLuma = px[(y * size + mid) * 4];
    final bladeLuma = px[(y * size + mid + 12) * 4];
    expect(ribLuma, lessThan(bladeLuma));
  });
}
