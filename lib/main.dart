// Showcase — procedural 3D tree hero.
//
// Every part of this scene is generated at runtime: the branch structure, the
// leaf texture, and the per-leaf shading. Nothing is downloaded, so the whole
// hero costs zero bytes of payload beyond the code itself.
//
// The configuration here is the one measured to be best on real hardware
// (see docs/flutter-scene-web-leak.md):
//
//   20,000 leaves at size 0.5 → 60 fps desktop, 30 fps on an iPhone 11,
//   and visually better than larger leaves, which over-cover the canopy
//   into a solid blob.
//
// Bloom, wind, and the alpha leaf texture were all measured to cost nothing,
// so they are all on.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const ShowcaseApp());

class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'Showcase',
    debugShowCheckedModeBanner: false,
    home: Scaffold(backgroundColor: Color(0xFF07070E), body: TreeHero()),
  );
}

/// One leaf blade, drawn into an RGBA buffer: a pointed ellipse with a soft
/// edge and a darker midrib.
///
/// The alpha cut is what makes a canopy read as foliage rather than a mass of
/// coloured squares — and it is free, because discarded fragments also cut
/// overdraw.
Uint8List _leafPixels(int size) {
  final px = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final nx = (x / (size - 1)) * 2 - 1;
      final ny = (y / (size - 1)) * 2 - 1;

      // Blade half-width: widest a third from the stem, tapering to a point.
      final t = (ny + 1) / 2;
      final width = math.sin(math.pow(t, 0.75).toDouble() * math.pi) * 0.92;

      final d = width <= 0 ? 2.0 : nx.abs() / width;
      var alpha = d >= 1.0 ? 0.0 : (1.0 - ((d - 0.82) / 0.18)).clamp(0.0, 1.0);
      if (t < 0.02 || t > 0.99) alpha = 0;

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

class TreeHero extends StatefulWidget {
  const TreeHero({super.key});

  @override
  State<TreeHero> createState() => _TreeHeroState();
}

class _TreeHeroState extends State<TreeHero>
    with SingleTickerProviderStateMixin {
  static const int _leafCount = 20000;

  /// Measured sweet spot. Larger over-covers the canopy into a blob; smaller
  /// breaks it up into gaps. Cost scales with this roughly linearly.
  static const double _leafScale = 0.5;

  /// Direction the key light comes from. Leaves on the far side of the canopy
  /// from the camera relative to this are lit through — see [_onTick].
  static final vm.Vector3 _lightDir = vm.Vector3(-0.45, 0.75, 0.5)..normalize();

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
      final r = 3.4 * math.pow(u, 0.34).toDouble();
      final theta = rng.nextDouble() * math.pi * 2;
      final phi = math.acos(1 - 2 * rng.nextDouble());

      _restX[i] = r * math.sin(phi) * math.cos(theta);
      _restY[i] = r * math.cos(phi) * 0.70 + 4.3;
      _restZ[i] = r * math.sin(phi) * math.sin(theta);
      _phase[i] = rng.nextDouble() * math.pi * 2;
      _sizeW[i] = (0.17 + rng.nextDouble() * 0.13) * _leafScale;
      _sizeH[i] = _sizeW[i] * (1.5 + rng.nextDouble() * 0.5);
      _rot[i] = rng.nextDouble() * math.pi * 2;
      _depth[i] = 1.0 - (r / 3.4).clamp(0.0, 1.0);

      // Hue sweep across the crown, and much darker toward the interior.
      // Depth falloff is deliberately steep and non-linear: a canopy that is
      // uniformly lit reads as a flat silhouette, and the eye takes the dark
      // interior as the cue that there is volume behind the surface.
      final hue = (_restX[i] / 3.4 + 1) / 2;
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
            ..colorTexture = Texture2D.fromPixels(_leafPixels(64), 64, 64),
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

    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMilliseconds / 1000.0;
        _cameraPos = vm.Vector3(
          math.cos(t * 0.16) * 11.5,
          4.6 + math.sin(t * 0.11) * 1.1,
          math.sin(t * 0.16) * 11.5,
        );
        return PerspectiveCamera(
          position: _cameraPos,
          target: vm.Vector3(0, 3.9, 0),
        );
      },
    );
  }
}
