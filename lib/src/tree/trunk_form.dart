/// The trunk's shape, as a handful of meaningful numbers.
///
/// ## Why parameters and not control points
///
/// The trunk's centre line is a spline through seven points — twenty-one
/// coordinates. Editing those directly is miserable: most combinations are
/// broken shapes, and there is no way to say "lean it further" without moving
/// several points in agreement. So the points are *computed* from the numbers
/// below, and every setting of those numbers is a valid trunk.
///
/// That is also what makes a control panel worth having: sliders on this class
/// are sliders on the shape's vocabulary, not on raw geometry.
///
/// Coordinates: **+Y up**, **+X to the viewer's right**, **+Z toward the
/// camera**, ground at `y = 0`.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Smootherstep between [a] and [b] — Perlin's quintic, `6u^5 - 15u^4 + 10u^3`.
///
/// The cubic smoothstep would be the obvious choice and it is not good enough
/// here. Its *second* derivative is non-zero at the ends, which puts a spike of
/// curvature exactly where each shaping term starts — and at the bottom of the
/// trunk that is precisely where the root flare makes the trunk fattest, so the
/// sweep had to shove the surface sideways to avoid folding and the base came
/// out as a flared skirt. The quintic is flat to the second derivative at both
/// ends, so curvature builds and fades smoothly and there is nothing to
/// compensate for.
double _smootherstep(double a, double b, double x) {
  if (b <= a) return x >= b ? 1 : 0;
  final u = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return u * u * u * (u * (u * 6 - 15) + 10);
}

/// Everything that decides the trunk's shape.
class TrunkForm {
  const TrunkForm({
    this.height = 1.8,
    this.baseDiameter = 1.1,
    this.topDiameter = 0.72,
    this.lean = 0.42,
    this.leanHeight = 0.42,
    this.counterLean = 0.24,
    this.depthTurn = 0.30,
    this.flareWidth = 0.55,
    this.flareHeight = 0.30,
    this.squash = 0.75,
  });

  /// Ground to the top of the section.
  final double height;

  /// Thickness at the bottom of the trunk proper, above the root flare.
  final double baseDiameter;

  /// Thickness where the section ends. The difference between this and
  /// [baseDiameter] is most of what separates a massive tree from a post.
  final double topDiameter;

  /// How far the trunk leans out, in world units.
  final double lean;

  /// Where the lean has finished developing, as a fraction of [height]. Low
  /// values read as old and gnarled; high values as young and whippy.
  final double leanHeight;

  /// How far it comes back above [leanHeight]. Zero gives a bow; a value near
  /// [lean] gives a full S.
  final double counterLean;

  /// How far the trunk swings toward the camera and back on its way up.
  /// Without it the trunk is a shape cut from cardboard, which a fixed camera
  /// has no way to disguise.
  final double depthTurn;

  /// How much wider the very bottom is than [baseDiameter], as a fraction —
  /// the root flare.
  final double flareWidth;

  /// The height, in world units, over which the flare dies away. Small values
  /// keep it hugging the ground, which is what makes it read as roots
  /// spreading rather than as a cone.
  final double flareHeight;

  /// How much the cross-section flattens on the inside of a bend, from 0 to 1.
  ///
  /// **This is what lets a thick trunk bend at all.** Drag a rigid circle along
  /// a curve that bends tighter than the circle's own radius and the surface
  /// passes through itself — the trunk comes out as a folded shell. A real
  /// trunk does not do that because it is not rigid: it compresses on the
  /// inside of the bend. Modelling that compression removes the limit, and it
  /// is also simply what a bent trunk looks like.
  final double squash;

  TrunkForm copyWith({
    double? height,
    double? baseDiameter,
    double? topDiameter,
    double? lean,
    double? leanHeight,
    double? counterLean,
    double? depthTurn,
    double? flareWidth,
    double? flareHeight,
    double? squash,
  }) => TrunkForm(
    height: height ?? this.height,
    baseDiameter: baseDiameter ?? this.baseDiameter,
    topDiameter: topDiameter ?? this.topDiameter,
    lean: lean ?? this.lean,
    leanHeight: leanHeight ?? this.leanHeight,
    counterLean: counterLean ?? this.counterLean,
    depthTurn: depthTurn ?? this.depthTurn,
    flareWidth: flareWidth ?? this.flareWidth,
    flareHeight: flareHeight ?? this.flareHeight,
    squash: squash ?? this.squash,
  );

  /// Height against thickness — the number that actually decides whether this
  /// reads as a massive tree, since a camera that reframes makes absolute size
  /// invisible.
  double get slenderness => baseDiameter <= 0 ? 0 : height / baseDiameter;

  /// The centre line, as a point at `t` in `0..1`.
  vm.Vector3 axisAt(double t) {
    final u = t.clamp(0.0, 1.0);
    // Lean out, then come back. Both terms are flat at t = 0, so the trunk
    // leaves the ground vertically whatever the sliders say.
    final out = _smootherstep(0, leanHeight.clamp(0.05, 0.95), u);
    final back = _smootherstep(leanHeight.clamp(0.05, 0.95), 1, u);
    // Out and back, built from the same quintic so the depth swing adds no
    // curvature spike of its own at the base.
    final depth = _smootherstep(0, 0.5, u) - _smootherstep(0.5, 1, u);
    return vm.Vector3(
      -lean * out + counterLean * back,
      height * u,
      depthTurn * depth,
    );
  }

  /// The trunk's radius at `t`, including the root flare.
  double radiusAt(double t) {
    final u = t.clamp(0.0, 1.0);
    final trunk = (baseDiameter + (topDiameter - baseDiameter) * u) / 2;
    final falloff = flareHeight <= 0
        ? 0.0
        : math.exp(-(u * height) / flareHeight);
    return trunk * (1 + flareWidth * falloff);
  }

  /// The centre line as a curve the renderer can sweep along, relaxed so a
  /// trunk of this thickness can actually follow it.
  ///
  /// ## Why the curve gets relaxed
  ///
  /// A surface swept along a curve folds through itself wherever the curve
  /// bends tighter than the surface is wide. That is not a bug to code around,
  /// it is what "too tight to bend" means — and a real trunk obeys it too: a
  /// thick trunk cannot kink, it can only sweep.
  ///
  /// So rather than let the sliders produce a shape that cannot exist, the
  /// requested curve is relaxed until every bend is wide enough for the trunk's
  /// own radius there. Ask for an impossible kink and you get the tightest bend
  /// that thickness allows, which is exactly what a real tree would give you.
  /// Thin the trunk and the same slider bends further.
  ///
  /// Endpoints are pinned, so the trunk's height and where it finishes never
  /// move.
  ScenePath toPath({int samples = 65}) =>
      CatmullRomPath(relaxedAxis(samples: samples));

  /// The centre line's sample points, after curvature relaxation.
  List<vm.Vector3> relaxedAxis({int samples = 65, int iterations = 400}) {
    final points = <vm.Vector3>[
      for (var i = 0; i < samples; i++) axisAt(i / (samples - 1)),
    ];
    final radii = <double>[
      for (var i = 0; i < samples; i++) radiusAt(i / (samples - 1)),
    ];

    // A bend is legal while `curvature * radius` stays under this. Below 1 the
    // surface is strictly safe; the margin keeps the tightest bends looking
    // clean rather than merely non-degenerate.
    const limit = 0.72;
    // How far a violating point moves toward its neighbours each pass. Small,
    // so the relaxation spreads a tight bend along the curve instead of
    // denting it locally.
    const strength = 0.22;

    for (var pass = 0; pass < iterations; pass++) {
      var worst = 0.0;
      for (var i = 1; i < points.length - 1; i++) {
        final a = points[i - 1];
        final b = points[i];
        final c = points[i + 1];
        final ab = (b - a).length;
        final bc = (c - b).length;
        final ca = (a - c).length;
        if (ab < 1e-9 || bc < 1e-9 || ca < 1e-9) continue;
        // Menger curvature: 1 / the radius of the circle through the three
        // points. Stable in float32, unlike anything built on the angle
        // between nearly-parallel tangents.
        final area = (b - a).cross(c - a).length / 2;
        final curvature = 4 * area / (ab * bc * ca);
        final load = curvature * radii[i];
        if (load <= limit) continue;
        worst = math.max(worst, load);
        // Toward the midpoint of its neighbours: the straighter this point
        // sits between them, the wider the bend.
        final target = (a + c).scaled(0.5);
        points[i] = b + (target - b).scaled(strength);
      }
      if (worst == 0) break;
    }
    return points;
  }

  /// The current values, as Dart source that can be pasted straight back in.
  String toDartSource() =>
      'const TrunkForm(\n'
      '  height: ${height.toStringAsFixed(3)},\n'
      '  baseDiameter: ${baseDiameter.toStringAsFixed(3)},\n'
      '  topDiameter: ${topDiameter.toStringAsFixed(3)},\n'
      '  lean: ${lean.toStringAsFixed(3)},\n'
      '  leanHeight: ${leanHeight.toStringAsFixed(3)},\n'
      '  counterLean: ${counterLean.toStringAsFixed(3)},\n'
      '  depthTurn: ${depthTurn.toStringAsFixed(3)},\n'
      '  flareWidth: ${flareWidth.toStringAsFixed(3)},\n'
      '  flareHeight: ${flareHeight.toStringAsFixed(3)},\n'
      '  squash: ${squash.toStringAsFixed(3)},\n'
      ')';
}
