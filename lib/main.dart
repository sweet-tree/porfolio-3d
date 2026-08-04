// Showcase — procedural 3D tree hero.
//
// Every part of this scene is generated at runtime: the branch structure, the
// leaf texture, and the per-leaf shading. Nothing is downloaded, so the whole
// hero costs zero bytes of payload beyond the code itself.
//
// Every number here came from measuring on real hardware rather than from
// reasoning — see docs/flutter-scene-web-leak.md for the workings.
//
// The dominant cost is fill rate: how many leaf-pixels get drawn, which is why
// the same scene runs at 57 fps when the tree is small in frame and 27 when it
// fills it. Leaf count barely matters by comparison. Bloom, wind and the alpha
// leaf texture were each measured to cost nothing, so all three are on.
//
// Density is tunable from the URL (?leaves=&size=) so it can be adjusted
// against a real phone rather than guessed at here.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:showcase/src/leaf_texture.dart';
import 'package:showcase/src/query_params.dart';
import 'package:showcase/src/stats_overlay.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const ShowcaseApp());

class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Showcase',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF07070E),
      body: Stack(
        children: [
          const TreeHero(),
          // Opt-in via ?stats=1 — the only way to get honest numbers is to
          // read them off the real device hitting the real deployment.
          if (statsRequested) const StatsOverlay(),
        ],
      ),
    ),
  );
}

class TreeHero extends StatefulWidget {
  const TreeHero({super.key});

  @override
  State<TreeHero> createState() => _TreeHeroState();
}

class _TreeHeroState extends State<TreeHero>
    with SingleTickerProviderStateMixin {
  // ── Canopy density ───────────────────────────────────────────────────────
  //
  // Two quantities, related but NOT interchangeable:
  //
  //   cost     ∝ count × size      (measured: halving size halves the cost)
  //   coverage ∝ count × size²
  //
  // So for a fixed visual density, FEWER LARGER leaves are cheaper. Holding
  // coverage constant while halving size needs 4× the leaves and doubles the
  // work. 20,000 @ 0.5 and 8,000 @ 0.8 cover the same canopy, but the second
  // costs about a third less:
  //
  //   20000 × 0.5  = 10000 cost, 20000 × 0.25 = 5000 coverage
  //    8000 × 0.8  =  6400 cost,  8000 × 0.64 = 5120 coverage
  //
  // Overridable from the URL (?leaves=8000&size=0.8) so this can be tuned on a
  // real device without a deploy cycle — the numbers that matter come from the
  // phone, not from here.
  static final int _leafCount = qInt('leaves', 8000);
  static final double _leafScale = qDouble('size', 0.8);

  // ── Tree extents, shared by the generator and the camera ────────────────
  // The camera derives its framing from these, so changing the tree's shape
  // cannot silently leave the framing wrong.

  /// Horizontal radius of the crown.
  static const double _crownRadius = 3.4;

  /// Height of the crown's centre above the ground.
  static const double _crownCentreY = 4.3;

  /// Vertical squash: the crown is wider than it is tall.
  static const double _crownSquash = 0.70;

  /// Vertical field of view. The horizontal one is derived from this and the
  /// viewport's aspect ratio at render time.
  static const double _fovY = 50 * math.pi / 180;

  /// Padding around the tree, as a multiple of the fitted distance.
  static const double _framingMargin = 1.06;

  /// Direction the key light comes from. Leaves on the far side of the canopy
  /// from the camera relative to this are lit through — see [_onTick].
  static final vm.Vector3 _lightDir = vm.Vector3(-0.45, 0.75, 0.5)..normalize();

  /// Highest point of the tree: the top of the crown.
  static const double _treeTop = _crownCentreY + _crownRadius * _crownSquash;

  /// Point the camera looks at — the middle of the tree's full height, so the
  /// trunk and the crown are framed together rather than the crown alone.
  static final vm.Vector3 _treeCentre = vm.Vector3(0, _treeTop / 2, 0);

  /// Radius of the sphere enclosing the whole tree, measured from
  /// [_treeCentre]. The widest points are the crown's edge, so this is the
  /// distance from the centre out to the crown rim.
  static final double _treeRadius = math.sqrt(
    _crownRadius * _crownRadius +
        math.pow(_crownCentreY - _treeTop / 2, 2).toDouble(),
  );

  /// Distance the camera must sit at for the whole tree to fit a viewport of
  /// the given [aspect] ratio.
  ///
  /// The vertical field of view is fixed; the horizontal one follows from it
  /// and the aspect ratio. In portrait the horizontal field is the NARROWER
  /// of the two, so fitting only vertically — which is what
  /// `PerspectiveCamera.framing` does, by its own documentation — crops the
  /// crown left and right. Fitting whichever axis is tighter is the fix.
  static double _framingDistance(double aspect) {
    final fovX = 2 * math.atan(math.tan(_fovY / 2) * aspect);
    final limiting = math.min(_fovY, fovX);
    return _treeRadius / math.sin(limiting / 2) * _framingMargin;
  }

  final Scene scene = Scene();
  bool _ready = false;
  String? _error;

  BillboardGeometry? _canopy;
  Ticker? _ticker;

  // Per-leaf rest state. Kept in flat typed arrays rather than objects: at
  // 20k leaves the object overhead is what would actually hurt.
  final Float32List _restX = Float32List(_leafCount);
  final Float32List _restY = Float32List(_leafCount);
  final Float32List _restZ = Float32List(_leafCount);
  final Float32List _phase = Float32List(_leafCount);
  final Float32List _sizeW = Float32List(_leafCount);
  final Float32List _sizeH = Float32List(_leafCount);
  final Float32List _rot = Float32List(_leafCount);
  // Base colour per leaf, flat RGB. Alpha is always 1.
  final Float32List _baseRGB = Float32List(_leafCount * 3);
  // How deep inside the crown each leaf sits, 0 (outside) .. 1 (centre).
  final Float32List _depth = Float32List(_leafCount);

  vm.Vector3 _cameraPos = vm.Vector3(0, 4, 12);

  @override
  void initState() {
    super.initState();
    unawaited(_build());
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    try {
      await Scene.initializeStaticResources();
      _buildTrunk();
      _buildCanopy();

      // Bloom is built into flutter_scene and measured free — it is what makes
      // the bright outer leaves glow rather than just being pale.
      // Bloom threshold sits high on purpose: only the brightest backlit rim
      // should glow. A low threshold blooms the whole canopy into a pale mass
      // and destroys the depth the shading below works to create.
      scene.environmentSettings = EnvironmentSettings(
        bloomEnabled: true,
        bloomThreshold: 0.92,
        bloomIntensity: 0.55,
      );

      // start() returns a TickerFuture that only completes if the ticker is
      // stopped; this one runs for the lifetime of the widget.
      _ticker = createTicker(_onTick);
      unawaited(_ticker!.start());
      if (mounted) setState(() => _ready = true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Recursive branching, every segment an instance of one cylinder so the
  /// whole trunk is a single draw call. Measured free (~300 instances).
  void _buildTrunk() {
    final mesh = InstancedMesh(
      geometry: CylinderGeometry(bottomRadius: 1, radialSegments: 8),
      material: UnlitMaterial()
        ..baseColorFactor = vm.Vector4(0.30, 0.17, 0.24, 1),
    );
    final rng = math.Random(11);

    void branch(
      vm.Vector3 from,
      vm.Vector3 dir,
      double length,
      double radius,
      int depth,
    ) {
      if (depth == 0 || radius < 0.012) return;
      final to = from + dir.scaled(length);

      // Orient a unit-Y cylinder along `dir`, then scale to length/radius.
      final up = vm.Vector3(0, 1, 0);
      final axis = up.cross(dir);
      final angle = math.acos(up.dot(dir.normalized()).clamp(-1.0, 1.0));
      final rot = axis.length2 < 1e-9
          ? vm.Matrix4.identity()
          : vm.Matrix4.compose(
              vm.Vector3.zero(),
              vm.Quaternion.axisAngle(axis.normalized(), angle),
              vm.Vector3.all(1),
            );

      final mid = (from + to).scaled(0.5);
      mesh.addInstance(
        vm.Matrix4.translation(mid)
          ..multiply(rot)
          ..multiply(vm.Matrix4.diagonal3(vm.Vector3(radius, length, radius))),
      );

      final children = depth > 3 ? 2 : 2 + (rng.nextDouble() < 0.35 ? 1 : 0);
      for (var i = 0; i < children; i++) {
        final yaw = rng.nextDouble() * math.pi * 2;
        final pitch = 0.38 + rng.nextDouble() * 0.42;
        final child = vm.Vector3(
          math.sin(pitch) * math.cos(yaw),
          math.cos(pitch),
          math.sin(pitch) * math.sin(yaw),
        );
        // Blend toward the parent direction so branches keep flowing upward.
        final blended = (dir.normalized().scaled(0.55) + child.scaled(0.45))
          ..normalize();
        branch(
          to,
          blended,
          length * (0.66 + rng.nextDouble() * 0.12),
          radius * 0.68,
          depth - 1,
        );
      }
    }

    branch(vm.Vector3.zero(), vm.Vector3(0, 1, 0), 1.5, 0.30, 7);
    scene.add(Node(name: 'trunk')..addComponent(InstancedMeshComponent(mesh)));
  }

  void _buildCanopy() {
    final rng = math.Random(7);
    final canopy = BillboardGeometry(capacity: _leafCount)
      ..facing = BillboardFacing.spherical;

    for (var i = 0; i < _leafCount; i++) {
      // Crown shape: a squashed sphere, denser toward the outside, which is
      // roughly how real foliage distributes.
      final u = rng.nextDouble();
      final r = _crownRadius * math.pow(u, 0.34).toDouble();
      final theta = rng.nextDouble() * math.pi * 2;
      final phi = math.acos(1 - 2 * rng.nextDouble());

      _restX[i] = r * math.sin(phi) * math.cos(theta);
      _restY[i] = r * math.cos(phi) * _crownSquash + _crownCentreY;
      _restZ[i] = r * math.sin(phi) * math.sin(theta);
      _phase[i] = rng.nextDouble() * math.pi * 2;
      _sizeW[i] = (0.17 + rng.nextDouble() * 0.13) * _leafScale;
      _sizeH[i] = _sizeW[i] * (1.5 + rng.nextDouble() * 0.5);
      _rot[i] = rng.nextDouble() * math.pi * 2;
      _depth[i] = 1.0 - (r / _crownRadius).clamp(0.0, 1.0);

      // Hue sweep across the crown, and much darker toward the interior.
      // Depth falloff is deliberately steep and non-linear: a canopy that is
      // uniformly lit reads as a flat silhouette, and the eye takes the dark
      // interior as the cue that there is volume behind the surface.
      final hue = (_restX[i] / _crownRadius + 1) / 2;
      final shade = 0.10 + 0.90 * math.pow(1 - _depth[i], 2.2).toDouble();
      _baseRGB[i * 3] = (0.30 + 0.85 * hue) * shade;
      _baseRGB[i * 3 + 1] = (0.22 + 0.40 * (1 - hue)) * shade;
      _baseRGB[i * 3 + 2] = (0.60 + 0.40 * (1 - hue * 0.6)) * shade;
    }
    canopy.commit(_leafCount);
    _canopy = canopy;

    scene.add(
      Node(
        name: 'canopy',
        mesh: Mesh(
          canopy,
          SpriteMaterial()
            ..colorTexture = Texture2D.fromPixels(leafPixels(64), 64, 64),
        ),
      ),
    );
  }

  /// Per-frame: wind sway, plus a translucency pass.
  ///
  /// The translucency is Filament's `subsurfaceColor` idea done cheaply — real
  /// leaves are thin enough to transmit light, so a leaf between the viewer and
  /// the light glows warm rather than falling into shadow. Approximated per
  /// leaf on the CPU: measured at 0.26 ms per frame for 4,000 leaves, so even
  /// at 20,000 it stays well inside budget.
  void _onTick(Duration elapsed) {
    final canopy = _canopy;
    if (canopy == null) return;
    final t = elapsed.inMicroseconds / 1e6;

    // View direction, used to decide which leaves are backlit.
    final view = (vm.Vector3.zero() - _cameraPos)..normalize();
    // How much the light opposes the view: 1 when we look into the light.
    final backlight = (-view.dot(_lightDir)).clamp(0.0, 1.0);

    for (var i = 0; i < _leafCount; i++) {
      final ph = _phase[i];
      // Height-weighted sway: leaves higher in the crown move more.
      final weight = ((_restY[i] - 2.0) / 4.0).clamp(0.0, 1.0);
      final sway = math.sin(t * 1.6 + ph) * 0.16 * weight;
      final bob = math.sin(t * 2.3 + ph * 1.7) * 0.06 * weight;

      // Transmission is strongest for outer leaves (thin, unshadowed) and when
      // we are looking into the light. Kept modest — pushed too far it just
      // saturates everything to white and flattens the crown again.
      final transmit =
          backlight * math.pow(1 - _depth[i], 3).toDouble() * 0.40;

      canopy.setInstance(
        i,
        center: vm.Vector3(
          _restX[i] + sway,
          _restY[i] + bob,
          _restZ[i] + sway * 0.6,
        ),
        width: _sizeW[i],
        height: _sizeH[i],
        rotation: _rot[i] + sway * 0.8,
        // Warm-biased transmission: light through a leaf loses blue first,
        // which is why backlit foliage reads amber rather than pale.
        color: vm.Vector4(
          _baseRGB[i * 3] + transmit,
          _baseRGB[i * 3 + 1] + transmit * 0.55,
          _baseRGB[i * 3 + 2] + transmit * 0.18,
          1,
        ),
      );
    }
    canopy.commit(_leafCount);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Scene failed to initialise:\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 15),
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());

    // The viewport drives the framing, so the camera has to know its size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = constraints.maxHeight <= 0
            ? 1.0
            : constraints.maxWidth / constraints.maxHeight;
        final distance = _framingDistance(aspect);

        return SceneView(
          scene,
          cameraBuilder: (elapsed) {
            final t = elapsed.inMilliseconds / 1000.0;
            // Orbit at the fitted distance, with a gentle vertical drift kept
            // proportional so it never pushes the crown out of frame.
            _cameraPos = vm.Vector3(
              math.cos(t * 0.16) * distance,
              _treeCentre.y + distance * 0.06 * math.sin(t * 0.11),
              math.sin(t * 0.16) * distance,
            );
            return PerspectiveCamera(
              fovRadiansY: _fovY,
              position: _cameraPos,
              target: _treeCentre,
            );
          },
        );
      },
    );
  }
}
